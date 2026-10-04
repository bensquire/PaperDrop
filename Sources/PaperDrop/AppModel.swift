import ScanKit
import SwiftUI

struct PageItem: Identifiable {
    let id = UUID()
    let thumbnail: NSImage?
    let sizeLabel: String
    let mmSize: String
    /// Builds the PDF page; the flag controls whether OCR runs.
    let build: (_ ocr: Bool) throws -> PDFWriter.Page
}

@MainActor
final class AppModel: ObservableObject {
    @Published var scanners: [ScannerInfo] = []
    @Published var selectedScannerID: String?
    @Published var discovering = false

    @Published var pages: [PageItem] = []
    @Published var scanning = false
    @Published var saving = false
    @Published var statusText = ""
    @Published var errorText: String?
    @Published var docName = ""

    private static let dpiKey = "dpi"
    private static let dpiFallback = 300

    /// Persistent default (Settings); the toolbar picker edits the
    /// session-only `dpi` below so a one-off override doesn't stick.
    @AppStorage(AppModel.dpiKey) var defaultDpi = AppModel.dpiFallback {
        willSet { objectWillChange.send() }
    }
    @Published var dpi: Int

    init() {
        dpi =
            UserDefaults.standard.object(forKey: Self.dpiKey) as? Int
            ?? Self.dpiFallback
        // Scans orphaned by a crash or a failed page; nothing in here
        // outlives a session.
        try? FileManager.default.removeItem(at: workDir)
    }

    // @AppStorage doesn't publish from inside an ObservableObject; each
    // announces its change so dependent views (e.g. Orientation's
    // disabled state) refresh.
    @AppStorage("photoMode") var photoMode = false {
        willSet { objectWillChange.send() }
    }
    @AppStorage("ocr") var ocrEnabled = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("paperSnap") var paperSnap = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("uniformPages") var uniformPages = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("paperChoice") var paperChoice = "auto" {
        willSet { objectWillChange.send() }
    }
    @AppStorage("paperLandscape") var paperLandscape = false {
        willSet { objectWillChange.send() }
    }

    /// Toolbar paper choices, derived from Pipeline's tables so paper
    /// dimensions have exactly one home. Keys are stable for the
    /// persisted "paperChoice" preference ("4×6″" → "4x6").
    static let fixedPapers: [(key: String, label: String, wMM: Double, hMM: Double)] = {
        let all = Pipeline.paperSizesMM + Pipeline.photoSizesMM
        let order = ["A4", "A5", "4×6″", "5×7″", "8×10″", "Letter"]
        return order.compactMap { name in
            all.first { $0.name == name }.map {
                (
                    key: name.lowercased()
                        .replacingOccurrences(of: "×", with: "x")
                        .replacingOccurrences(of: "″", with: ""),
                    label: name, wMM: $0.w, hMM: $0.h
                )
            }
        }
    }()

    /// The forced page size, or nil for auto-detect. Paper tables are
    /// portrait, so landscape is the same pair swapped.
    var fixedPaperMM: (w: Double, h: Double)? {
        Self.fixedPapers.first { $0.key == paperChoice }
            .map { paperLandscape ? ($0.hMM, $0.wMM) : ($0.wMM, $0.hMM) }
    }

    @AppStorage("archivePath") var archivePath =
        NSHomeDirectory() + "/Documents/Scans"
    {
        willSet { objectWillChange.send() }
    }

    let availableDPIs = [150, 200, 300, 400, 600]

    private let iccBackend = ICCBackend()
    private let saneBackend = SANECLIBackend()
    private let workDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("PaperDrop", isDirectory: true)

    var selectedScanner: ScannerInfo? {
        scanners.first { $0.id == selectedScannerID }
    }

    var busy: Bool {
        scanning || saving
    }

    private func backend(for scanner: ScannerInfo) -> ScannerBackend {
        scanner.id.hasPrefix("sane:") ? saneBackend : iccBackend
    }

    // MARK: Discovery

    func discoverScanners() {
        guard !discovering else { return }
        discovering = true
        // The empty state and toolbar picker already show discovery
        // progress; keep the status bar quiet.
        Task {
            // Sequential: an ICC browse launches legacy vendor drivers that
            // grab the USB device, which would break a concurrent SANE probe.
            let saneFound = await saneBackend.discover(timeout: 6)
            let iccFound = await iccBackend.discover(timeout: 6)
            let found = ScannerInfo.merge(sane: saneFound, icc: iccFound)
            let previous = self.selectedScanner
            self.scanners = found
            if self.selectedScanner == nil {
                // Keep the same scanner selected when its ID changed.
                self.selectedScannerID = (previous?.match(in: found) ?? found.first)?.id
            }
            self.discovering = false
        }
    }

    // MARK: Scanning

    func cancelScan() {
        guard scanning, let scanner = selectedScanner else { return }
        statusText = "Cancelling — resetting scanner…"
        Task {
            let reset = await backend(for: scanner)
                .cancelScan(scannerName: scanner.name)
            if !reset {
                self.errorText =
                    "Cancelled. If the next scan looks corrupted, "
                    + "unplug and replug the scanner."
            }
        }
    }

    func scanPage() {
        guard let scanner = selectedScanner, !busy else { return }
        scanning = true
        errorText = nil
        statusText = "Scanning page \(pages.count + 1)…"
        let backend = backend(for: scanner)
        let config = ScanConfig(dpi: dpi, mode: .gray)

        Task {
            do {
                try FileManager.default.createDirectory(
                    at: workDir, withIntermediateDirectories: true
                )
                let url = try await backend.scan(
                    with: scanner, config: config,
                    to: workDir
                )
                // The device may have snapped the request to a resolution
                // it supports; the file says what it delivered.
                let dpi = Pipeline.resolution(of: url) ?? config.dpi
                let item = try await Self.process(
                    url: url, dpi: dpi,
                    photo: photoMode, snap: paperSnap,
                    fixed: fixedPaperMM
                )
                self.pages.append(item)
                self.statusText =
                    "Page \(self.pages.count): \(item.sizeLabel), \(item.mmSize)"
                    + (dpi == config.dpi ? "" : " (scanned at \(dpi) dpi)")
            } catch {
                if case ScanError.cancelled = error {
                    self.statusText = "Scan cancelled"
                } else {
                    self.errorText = error.localizedDescription
                    self.statusText = ""
                }
            }
            self.scanning = false
        }
    }

    nonisolated static func process(
        url: URL, dpi: Int, photo: Bool,
        snap: Bool,
        fixed: (w: Double, h: Double)? = nil
    )
        async throws -> PageItem
    {
        defer { try? FileManager.default.removeItem(at: url) }
        let gray = try Pipeline.loadGray(url)

        if photo {
            let crop = Pipeline.analyze(
                gray, dpi: dpi,
                snapSlackMM: snap ? 25 : 0,
                fixedMM: fixed
            ).crop
            let cropped = gray.cropped(crop)
            guard let cg = cropped.cgImage,
                let jpeg = ImageEncode.jpeg(cg, dpi: dpi)
            else {
                throw ScanError.scanFailed("JPEG encode failed")
            }
            let thumb = thumbnail(cg)
            let (w, h) = (cropped.width, cropped.height)
            let origin = (
                Double(crop.x0) / Double(dpi) * 72,
                Double(crop.y0) / Double(dpi) * 72
            )
            return PageItem(
                thumbnail: thumb,
                sizeLabel: "\(jpeg.count / 1024) KB",
                mmSize: mmLabel(w, h, dpi),
                build: { _ in
                    .init(
                        content: .jpegGray(jpeg, width: w, height: h),
                        dpi: dpi, bedOriginPt: origin
                    )
                }
            )
        }

        let page = Pipeline.processDocument(
            gray, dpi: dpi,
            snapSlackMM: snap ? 25 : 0,
            fixedMM: fixed
        )
        let tiff = try G4.tiff(from: page)
        let stream = try G4.extractStream(fromTIFF: tiff)
        let thumb = page.cgImage.map { thumbnail($0) }
        let capturedPage = page
        return PageItem(
            thumbnail: thumb,
            sizeLabel: "\(stream.data.count / 1024) KB",
            mmSize: mmLabel(page.width, page.height, dpi),
            build: { ocr in
                let words = ocr ? (try? OCR.recognize(capturedPage)) ?? [] : []
                return .init(
                    content: .g4(stream), dpi: dpi, ocrWords: words,
                    bedOriginPt: capturedPage.bedOriginPt
                )
            }
        )
    }

    /// Downscaled preview — full-resolution scans must not live in the view.
    nonisolated static func thumbnail(_ img: CGImage, maxSide: Int = 400) -> NSImage {
        let scale = Double(maxSide) / Double(max(img.width, img.height))
        guard scale < 1,
            let ctx = CGContext(
                data: nil,
                width: Int(Double(img.width) * scale),
                height: Int(Double(img.height) * scale),
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            )
        else { return NSImage(cgImage: img, size: .zero) }
        ctx.interpolationQuality = .high
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: ctx.width, height: ctx.height))
        guard let small = ctx.makeImage() else {
            return NSImage(cgImage: img, size: .zero)
        }
        return NSImage(cgImage: small, size: .zero)
    }

    nonisolated static func mmLabel(_ w: Int, _ h: Int, _ dpi: Int) -> String {
        let mmW = Double(w) / Double(dpi) * 25.4
        let mmH = Double(h) / Double(dpi) * 25.4
        return Pipeline.paperSizeName(widthMM: mmW, heightMM: mmH)
            ?? "\(Int(mmW))×\(Int(mmH)) mm"
    }

    // MARK: Saving

    func savePDF() {
        guard !pages.isEmpty, !busy else { return }
        saving = true
        errorText = nil
        let ocr = ocrEnabled
        statusText = ocr ? "Assembling PDF (OCR)…" : "Assembling PDF…"
        let title = docName
        let dir = URL(fileURLWithPath: archivePath)
        let builders = pages.map(\.build)

        let uniform = uniformPages
        Task.detached { [weak self] in
            do {
                // OCR dominates assembly and pages are independent: build
                // them on three workers, each taking every third page into
                // its own slot. Three because Vision peaks at ~170 MB per
                // 300 dpi page (~450 MB at 600); one per core could spike
                // to gigabytes.
                var built = [Result<PDFWriter.Page, Error>?](
                    repeating: nil, count: builders.count
                )
                built.withUnsafeMutableBufferPointer { buffer in
                    nonisolated(unsafe) let slots = buffer  // disjoint writes
                    DispatchQueue.concurrentPerform(iterations: min(3, builders.count)) { worker in
                        for i in stride(from: worker, to: builders.count, by: 3) {
                            slots[i] = Result { try builders[i](ocr) }
                        }
                    }
                }
                var pdfPages = try built.map { try $0!.get() }
                if uniform, pdfPages.count > 1 {
                    let maxW = pdfPages.map(\.naturalSizePt.w).max()!
                    let maxH = pdfPages.map(\.naturalSizePt.h).max()!
                    for i in pdfPages.indices {
                        pdfPages[i].pageSizePt = (maxW, maxH)
                    }
                }
                let data = PDFWriter.build(pages: pdfPages)
                try FileManager.default.createDirectory(
                    at: dir, withIntermediateDirectories: true
                )
                let dest = Archive.destination(for: title, in: dir)
                try data.write(to: dest, options: .withoutOverwriting)
                await MainActor.run {
                    self?.pages = []
                    self?.docName = ""
                    self?.saving = false
                    self?.statusText =
                        "Saved \(dest.lastPathComponent) (\(data.count / 1024) KB)"
                    NSWorkspace.shared.activateFileViewerSelecting([dest])
                }
            } catch {
                await MainActor.run {
                    self?.saving = false
                    self?.errorText = error.localizedDescription
                }
            }
        }
    }

    func deletePage(_ id: UUID) {
        pages.removeAll { $0.id == id }
    }

    func movePage(id: UUID, before targetID: UUID) {
        guard id != targetID,
            let from = pages.firstIndex(where: { $0.id == id }),
            let to = pages.firstIndex(where: { $0.id == targetID })
        else { return }
        withAnimation(.easeInOut(duration: 0.15)) {
            pages.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: to > from ? to + 1 : to
            )
        }
    }

    func discardAll() {
        pages = []
        docName = ""
        statusText = ""
        errorText = nil
    }
}
