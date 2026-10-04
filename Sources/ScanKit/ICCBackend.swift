import Foundation
@preconcurrency import ImageCaptureCore
import UniformTypeIdentifiers

/// ImageCaptureCore backend — drives any scanner macOS supports
/// (local ICA/TWAIN devices and AirScan/eSCL network scanners).
public final class ICCBackend: ScannerBackend {
    /// One browser for the backend's lifetime, and the sole owner of it.
    /// ImageCaptureCore posts blocks to the main thread that outlive a
    /// browse and retain the ICDeviceBrowser when they run, so a per-call
    /// browser that deallocates on return crashes in objc_retain; releasing
    /// it also invalidates the devices it handed out, mid-session.
    private let browser = DeviceBrowser()

    /// The open session, for cancelScan. A cancel can arrive before the
    /// session exists (while browsing), hence the separate flag.
    private let stateLock = NSLock()
    private var activeSession: ScanSession?
    private var cancelRequested = false

    public init() {}

    public func discover(timeout: TimeInterval) async -> [ScannerInfo] {
        await browser.browse(for: timeout).map {
            ScannerInfo(
                id: $0.persistentIDString ?? $0.name ?? UUID().uuidString,
                name: $0.name ?? "Unknown scanner"
            )
        }
    }

    public func capabilities(of scanner: ScannerInfo) async throws -> ScannerCapabilities {
        try await withSession(for: scanner) { session in
            let unit = try await session.selectFlatbed()
            try ScanSession.useInches(unit)
            let inches = unit.physicalSize
            return ScannerCapabilities(
                resolutions: unit.supportedResolutions.sorted(),
                bedSizeMM: CGSize(width: inches.width * 25.4, height: inches.height * 25.4)
            )
        }
    }

    public func scan(
        with scanner: ScannerInfo, config: ScanConfig,
        to directory: URL
    ) async throws -> URL {
        try await withSession(for: scanner) { session in
            _ = try await session.selectFlatbed()
            return try await session.scan(config: config, to: directory)
        }
    }

    /// ICC devices need no USB recovery after a cancel.
    public func cancelScan(scannerName _: String) async -> Bool {
        let session = stateLock.withLock { () -> ScanSession? in
            cancelRequested = true
            return activeSession
        }
        session?.cancel()
        return true
    }

    /// Opens a session on the scanner, runs `body`, and closes the session
    /// however it ends — including when opening failed part-way.
    private func withSession<T>(
        for scanner: ScannerInfo,
        _ body: (ScanSession) async throws -> T
    ) async throws -> T {
        stateLock.withLock { cancelRequested = false }
        // Stopping the browser frees every device not in use
        // (/documentation/imagecapturecore/icdevicebrowser/stop()), the one
        // about to be opened included; keep it running until we are done.
        browser.hold()
        defer { browser.release() }
        @Sendable func isWanted(_ device: ICScannerDevice) -> Bool {
            (device.persistentIDString ?? device.name) == scanner.id || device.name == scanner.name
        }
        let devices = await browser.browse(for: 8) { $0.contains(where: isWanted) }
        guard let device = devices.first(where: isWanted) else { throw ScanError.noDevice }
        let session = ScanSession(device: device)
        let cancelled = stateLock.withLock { () -> Bool in
            activeSession = session
            return cancelRequested
        }
        defer {
            session.close()
            stateLock.withLock { activeSession = nil }
        }
        if cancelled {
            throw ScanError.cancelled
        }
        try await session.open()
        return try await body(session)
    }
}

// MARK: - Device browsing

/// Runs `body` on the main thread: ImageCaptureCore drives its browser and
/// delegates there.
private func onMain(_ body: @escaping @Sendable () -> Void) {
    if Thread.isMainThread {
        body()
    } else {
        DispatchQueue.main.async(execute: body)
    }
}

/// All state is confined to the main thread, so it needs no lock.
private final class DeviceBrowser: NSObject, ICDeviceBrowserDelegate, @unchecked Sendable {
    private struct Waiter {
        let cont: CheckedContinuation<[ICScannerDevice], Never>
        /// Answers the browse early; nil waits for network devices too.
        let isDone: (@Sendable ([ICScannerDevice]) -> Bool)?
    }

    /// Network scanners arrive after local ones and have no "all found"
    /// signal of their own, so an untargeted browse waits this long after
    /// local enumeration ends. A guess: no network scanner was at hand to
    /// measure.
    private static let networkGrace: TimeInterval = 2

    private let browser = ICDeviceBrowser()
    private var waiters: [Int: Waiter] = [:]
    private var nextWaiter = 0
    /// Sessions keeping the browser running between browses.
    private var holds = 0
    private var localDevicesEnumerated = false

    /// The browser outlives every browse, so its delegate and device mask
    /// are one-time setup rather than per-call configuration.
    override init() {
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask(
            rawValue: ICDeviceTypeMask.scanner.rawValue
                | ICDeviceLocationTypeMask.local.rawValue
                | ICDeviceLocationTypeMask.shared.rawValue
                | ICDeviceLocationTypeMask.bonjour.rawValue
        )!
    }

    /// The scanners found within `timeout`. Answers sooner once `isDone`
    /// holds of them or, without one, `networkGrace` after the local devices
    /// are enumerated. `moreComing` is no end signal: it closes one batch,
    /// and network devices come in later ones.
    func browse(
        for timeout: TimeInterval,
        until isDone: (@Sendable ([ICScannerDevice]) -> Bool)? = nil
    ) async -> [ICScannerDevice] {
        await withCheckedContinuation { cont in
            onMain { [self] in
                let id = nextWaiter
                nextWaiter += 1
                waiters[id] = Waiter(cont: cont, isDone: isDone)
                startIfNeeded()
                after(timeout) { $0.answer(id) }
                if isDone == nil, localDevicesEnumerated {
                    after(Self.networkGrace) { $0.answer(id) }
                }
                answerSatisfiedWaiters()
            }
        }
    }

    /// Keeps the browser running until the matching `release()`.
    func hold() {
        onMain { [self] in
            holds += 1
            startIfNeeded()
        }
    }

    func release() {
        onMain { [self] in
            holds -= 1
            stopIfIdle()
        }
    }

    private var scanners: [ICScannerDevice] {
        browser.devices?.compactMap { $0 as? ICScannerDevice } ?? []
    }

    private func startIfNeeded() {
        guard !browser.isBrowsing else { return }
        localDevicesEnumerated = false
        browser.start()
    }

    /// Stopping frees the devices not in use, so it waits until nothing is
    /// browsing or holding.
    private func stopIfIdle() {
        if waiters.isEmpty, holds == 0, browser.isBrowsing {
            browser.stop()
        }
    }

    private func answer(_ id: Int) {
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.cont.resume(returning: scanners)
        stopIfIdle()
    }

    private func answerSatisfiedWaiters() {
        let found = scanners
        for (id, waiter) in waiters where waiter.isDone?(found) == true {
            answer(id)
        }
    }

    private func after(_ delay: TimeInterval, _ body: @escaping @Sendable (DeviceBrowser) -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self.map(body)
        }
    }

    // MARK: ICDeviceBrowserDelegate

    func deviceBrowser(_: ICDeviceBrowser, didAdd _: ICDevice, moreComing _: Bool) {
        onMain { self.answerSatisfiedWaiters() }
    }

    // /documentation/imagecapturecore/icdevicebrowserdelegate/devicebrowserdidenumeratelocaldevices(_:)
    func deviceBrowserDidEnumerateLocalDevices(_: ICDeviceBrowser) {
        onMain { [self] in
            localDevicesEnumerated = true
            for (id, waiter) in waiters where waiter.isDone == nil {
                after(Self.networkGrace) { $0.answer(id) }
            }
        }
    }

    func deviceBrowser(_: ICDeviceBrowser, didRemove _: ICDevice, moreGoing _: Bool) {}
}

// MARK: - Scan session

private final class ScanSession: NSObject, ICScannerDeviceDelegate, @unchecked Sendable {
    private typealias Slot<T> = ReferenceWritableKeyPath<ScanSession, CheckedContinuation<T, Error>?>

    private let device: ICScannerDevice

    /// Guarded by `lock`: delegate callbacks arrive on the main thread,
    /// requests, timeouts and cancels on other threads. Each continuation
    /// is resumed by whichever of them takes it from its slot first.
    private var openCont: CheckedContinuation<Void, Error>?
    private var selectCont: CheckedContinuation<ICScannerFunctionalUnit, Error>?
    private var scanCont: CheckedContinuation<URL, Error>?
    private var scannedURL: URL?
    private var cancelled = false
    private let lock = NSLock()

    init(device: ICScannerDevice) {
        self.device = device
        super.init()
        device.delegate = self
    }

    /// The 60 s backstops outlast ImageCaptureCore's own ~30 s failure
    /// for a dead vendor driver, whose message is the more useful one.
    func open() async throws {
        try await request(\.openCont, timeout: 60, what: "Opening the scanner") {
            self.device.requestOpenSession()
        }
    }

    /// ImageCaptureCore holds its delegate unowned(unsafe)
    /// (/documentation/imagecapturecore/icdevice/delegate) and calls it
    /// after a close is requested, so the completion keeps this session
    /// alive until the close is done, then detaches it on the main thread,
    /// where the callbacks arrive.
    func close() {
        guard device.hasOpenSession else {
            onMain { self.device.delegate = nil }
            return
        }
        device.requestCloseSession(options: nil) { _ in
            onMain { self.device.delegate = nil }
        }
    }

    func selectFlatbed() async throws -> ICScannerFunctionalUnit {
        // /documentation/imagecapturecore/icscannerdevice/availablefunctionalunittypes
        guard
            device.availableFunctionalUnitTypes.contains(where: {
                $0.uintValue == ICScannerFunctionalUnitType.flatbed.rawValue
            })
        else { throw ScanError.sessionFailed("This scanner has no flatbed") }
        if device.selectedFunctionalUnit.type == .flatbed {
            return device.selectedFunctionalUnit
        }
        return try await request(\.selectCont, timeout: 60, what: "Selecting the flatbed") {
            self.device.requestSelect(.flatbed)
        }
    }

    /// Sets the unit to inches, the unit `physicalSize` and `scanArea` are
    /// then in. The unit "will always be one of the supported" ones, so a
    /// device without inches keeps its own; refuse rather than mis-measure.
    static func useInches(_ unit: ICScannerFunctionalUnit) throws {
        unit.measurementUnit = .inches
        guard unit.measurementUnit == .inches else {
            throw ScanError.sessionFailed("The scanner does not measure in inches")
        }
    }

    func scan(config: ScanConfig, to directory: URL) async throws -> URL {
        let unit = device.selectedFunctionalUnit
        // Nearest supported resolution at or above the request.
        let supported = unit.supportedResolutions.sorted()
        let dpi = supported.first(where: { $0 >= config.dpi }) ?? supported.last ?? config.dpi
        unit.resolution = dpi
        unit.pixelDataType =
            switch config.mode {
            case .blackAndWhite: .BW
            case .gray: .gray
            case .color: .RGB
            }
        unit.bitDepth = config.mode == .blackAndWhite ? .depth1Bit : .depth8Bits
        try Self.useInches(unit)
        let bed = unit.physicalSize
        if let mm = config.areaMM {
            unit.scanArea = CGRect(
                x: mm.minX / 25.4, y: mm.minY / 25.4,
                width: mm.width / 25.4, height: mm.height / 25.4
            )
        } else {
            unit.scanArea = CGRect(origin: .zero, size: bed)
        }

        device.transferMode = .fileBased
        device.downloadsDirectory = directory
        device.documentName = "scan-\(Int(Date().timeIntervalSince1970))"
        device.documentUTI = UTType.tiff.identifier

        // As generous as SANE's: slow devices at high dpi take minutes.
        // Weak: the timer outlives the scan by up to 20 minutes.
        return try await request(
            \.scanCont, timeout: 1200, what: "The scan",
            onTimeout: { [weak self] in self?.device.cancelScan() }
        ) {
            self.device.requestScan()
        }
    }

    /// Fails whatever the session is waiting for, stopping a scan in
    /// progress. Once `cancelled` is set nothing new can be parked.
    func cancel() {
        let scanning = lock.withLock {
            cancelled = true
            return scanCont != nil
        }
        if scanning {
            device.cancelScan()
        }
        failAll(ScanError.cancelled)
    }

    private func failAll(_ error: Error) {
        take(\.openCont)?.resume(throwing: error)
        take(\.selectCont)?.resume(throwing: error)
        take(\.scanCont)?.resume(throwing: error)
    }

    /// Parks a continuation in `slot`, then makes the device request. A
    /// device that never answers fails the request after `timeout` rather
    /// than leaving the app scanning forever.
    private func request<T>(
        _ slot: Slot<T>, timeout: TimeInterval, what: String,
        onTimeout: (@Sendable () -> Void)? = nil,
        _ start: () -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { cont in
            let parked = lock.withLock { () -> Bool in
                guard !cancelled else { return false }
                self[keyPath: slot] = cont
                return true
            }
            guard parked else {
                cont.resume(throwing: ScanError.cancelled)
                return
            }
            // An immutable key path; safe to hand to the timer's queue.
            nonisolated(unsafe) let slot = slot
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let cont = self?.take(slot) else { return }
                onTimeout?()
                cont.resume(throwing: ScanError.sessionFailed("\(what) timed out"))
            }
            start()
        }
    }

    private func take<T>(_ slot: Slot<T>) -> CheckedContinuation<T, Error>? {
        lock.withLock {
            defer { self[keyPath: slot] = nil }
            return self[keyPath: slot]
        }
    }

    // MARK: ICDeviceDelegate

    func device(_: ICDevice, didOpenSessionWithError error: Error?) {
        if let error {
            take(\.openCont)?.resume(throwing: ScanError.sessionFailed(error.localizedDescription))
        }
    }

    func deviceDidBecomeReady(_: ICDevice) {
        take(\.openCont)?.resume()
    }

    func device(_: ICDevice, didCloseSessionWithError _: Error?) {}
    func didRemove(_: ICDevice) {
        failAll(ScanError.scanFailed("Scanner disconnected"))
    }

    // Without this a device error left the request to its timeout.
    func device(_: ICDevice, didEncounterError error: Error?) {
        failAll(ScanError.scanFailed(error?.localizedDescription ?? "The scanner reported an error"))
    }

    // MARK: ICScannerDeviceDelegate

    func scannerDevice(
        _: ICScannerDevice,
        didSelect unit: ICScannerFunctionalUnit, error: Error?
    ) {
        // Also sent for the device's default unit just after the session
        // opens; only the flatbed (or a failure) answers the request.
        guard error != nil || unit.type == .flatbed, let cont = take(\.selectCont) else { return }
        if let error {
            cont.resume(throwing: ScanError.sessionFailed(error.localizedDescription))
        } else {
            cont.resume(returning: unit)
        }
    }

    func scannerDevice(_: ICScannerDevice, didScanTo url: URL) {
        lock.withLock { scannedURL = url }
    }

    func scannerDevice(
        _: ICScannerDevice,
        didCompleteScanWithError error: Error?
    ) {
        guard let cont = take(\.scanCont) else { return }
        if let error {
            cont.resume(throwing: ScanError.scanFailed(error.localizedDescription))
        } else if let url = lock.withLock({ scannedURL }) {
            cont.resume(returning: url)
        } else {
            cont.resume(throwing: ScanError.scanFailed("No file produced"))
        }
    }
}
