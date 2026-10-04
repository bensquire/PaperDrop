import Foundation
@preconcurrency import ImageCaptureCore

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
            let res = unit.supportedResolutions.sorted()
            let size = unit.physicalSize  // in current measurement unit
            let mm =
                unit.measurementUnit == .inches
                ? CGSize(width: size.width * 25.4, height: size.height * 25.4)
                : CGSize(width: size.width * 10, height: size.height * 10)
            return ScannerCapabilities(resolutions: res, bedSizeMM: mm)
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
        let devices = await browser.browse(for: 8)
        guard
            let device = devices.first(where: {
                ($0.persistentIDString ?? $0.name) == scanner.id || $0.name == scanner.name
            })
        else { throw ScanError.noDevice }
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

private final class DeviceBrowser: NSObject, ICDeviceBrowserDelegate, @unchecked Sendable {
    private let browser = ICDeviceBrowser()
    private var found: [ICScannerDevice] = []
    private var waiting: [CheckedContinuation<[ICScannerDevice], Never>] = []
    /// Identifies the browse in flight, so a finished browse's timeout
    /// cannot cut short the next one.
    private var generation = 0
    private let lock = NSLock()

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

    /// A caller arriving while a browse is in flight joins it rather than
    /// restarting the shared browser — cancelling the running one would
    /// hand its caller an empty device list. The first caller's timeout
    /// governs; a browse is short and both callers want the same answer.
    func browse(for timeout: TimeInterval) async -> [ICScannerDevice] {
        await withCheckedContinuation { cont in
            let browse = lock.withLock { () -> Int? in
                waiting.append(cont)
                guard waiting.count == 1 else { return nil }
                found.removeAll()
                generation += 1
                return generation
            }
            guard let browse else { return }
            // ImageCaptureCore delivers to the main run loop; drive the
            // browser from there too.
            DispatchQueue.main.async { [self] in
                browser.start()
                DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                    self?.finish(browse: browse)
                }
            }
        }
    }

    /// Both the early-stop and the timeout path call this; whichever claims
    /// the waiters stops the browser and answers them all. A timeout passes
    /// its browse, and is ignored once a later browse has begun. Clearing
    /// `found` here releases the ImageCaptureCore devices rather than
    /// holding them until the next browse.
    private func finish(browse: Int? = nil) {
        let (waiters, devices) = lock.withLock {
            () -> ([CheckedContinuation<[ICScannerDevice], Never>], [ICScannerDevice]) in
            guard browse == nil || browse == generation else { return ([], []) }
            defer {
                waiting.removeAll()
                found.removeAll()
            }
            return (waiting, found)
        }
        guard !waiters.isEmpty else { return }
        browser.stop()
        for cont in waiters {
            cont.resume(returning: devices)
        }
    }

    func deviceBrowser(_: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        if let scanner = device as? ICScannerDevice {
            lock.withLock { found.append(scanner) }
            // Local scanners arrive fast; stop early when the browser says so.
            if !moreComing {
                finish()
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

    func close() {
        device.requestCloseSession()
    }

    func selectFlatbed() async throws -> ICScannerFunctionalUnit {
        try await request(\.selectCont, timeout: 60, what: "Selecting the flatbed") {
            self.device.requestSelect(.flatbed)
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
        unit.measurementUnit = .inches
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
        device.documentUTI = "public.tiff"

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

    // MARK: ICScannerDeviceDelegate

    func scannerDevice(
        _: ICScannerDevice,
        didSelect unit: ICScannerFunctionalUnit, error: Error?
    ) {
        guard let cont = take(\.selectCont) else { return }
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
