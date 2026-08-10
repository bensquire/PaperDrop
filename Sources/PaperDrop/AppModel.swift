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
    @AppStorage(AppModel.dpiKey) var defaultDpi = AppModel.dpiFallback
    @Published var dpi: Int

    init() {
        dpi =
            UserDefaults.standard.object(forKey: Self.dpiKey) as? Int
            ?? Self.dpiFallback
    }

    @AppStorage("photoMode") var photoMode = false
    @AppStorage("ocr") var ocrEnabled = true
    @AppStorage("paperSnap") var paperSnap = true
    @AppStorage("uniformPages") var uniformPages = true
    @AppStorage("paperChoice") var paperChoice = "auto"
    @AppStorage("paperLandscape") var paperLandscape = false

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
            // The same USB device often appears via both backends with
            // different name spellings ("Canon LiDE 110" vs "CanoScan
            // LiDE 110"). Match on normalized model suffix; when a SANE
            // twin exists, prefer it — ICC cannot open devices whose
            // vendor driver is dead.
            let deduped = iccFound.filter { iccDev in
                !saneFound.contains { ScannerInfo.sameModel($0.name, iccDev.name) }
            }
            let twinRemoved = deduped.count != iccFound.count
            let cleaned = saneFound.map { dev in
                ScannerInfo(id: dev.id, name: twinRemoved ? dev.baseName : dev.name)
            }
            let found = cleaned + deduped
            self.scanners = found
            if self.selectedScanner == nil {
                self.selectedScannerID = found.first?.id
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
                let item = try await Self.process(
                    url: url, dpi: config.dpi,
                    photo: photoMode, snap: paperSnap,
                    fixed: fixedPaperMM
                )
                self.pages.append(item)
                self.statusText = "Page \(self.pages.count): \(item.sizeLabel), \(item.mmSize)"
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
        let gray = try Pipeline.loadGray(url)
        try? FileManager.default.removeItem(at: url)

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
        let name = docName.trimmingCharacters(in: .whitespaces)
        let fileName =
            (name.isEmpty
                ? "Scan " + Date().formatted(date: .abbreviated, time: .shortened)
                : name) + ".pdf"
        let dir = URL(fileURLWithPath: archivePath)
        let builders = pages.map(\.build)

        let uniform = uniformPages
        Task.detached { [weak self] in
            do {
                var pdfPages: [PDFWriter.Page] = []
                for build in builders {
                    try pdfPages.append(build(ocr))
                }
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
                let dest = dir.appendingPathComponent(fileName)
                try data.write(to: dest)
                await MainActor.run {
                    self?.pages = []
                    self?.docName = ""
                    self?.saving = false
                    self?.statusText = "Saved \(fileName) (\(data.count / 1024) KB)"
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
