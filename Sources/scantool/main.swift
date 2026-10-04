import Foundation
import ScanKit

// scantool — headless test harness for ScanKit backends.
//   scantool [--sane] list
//   scantool [--sane] caps
//   scantool [--sane] scan <out-dir> [dpi] [bw|gray|color]
//   scantool process <in.tiff> <out.pdf> [dpi] [WxH] [fixed:WxH]
//     dpi        defaults to the resolution recorded in the file
//     WxH        pad the page to WxH mm (e.g. 210x297)
//     fixed:WxH  force the paper size instead of auto-detecting
//   scantool usbreset [name tokens…]
// --sane uses the SANE backend (Homebrew's scanimage outside the app);
// the default is ImageCaptureCore.

var args = CommandLine.arguments
let useSANE = args.contains("--sane")
args.removeAll { $0 == "--sane" }
let command = args.count > 1 ? args[1] : "list"
let backend: ScannerBackend = useSANE ? SANECLIBackend() : ICCBackend()

func firstScanner() async -> ScannerInfo? {
    let devices = await backend.discover(timeout: 8)
    for d in devices {
        print("device: \(d.name) [\(d.id)]")
    }
    return devices.first
}

Task {
    defer { exit(0) }
    switch command {
    case "list":
        _ = await firstScanner()
    case "caps":
        guard let s = await firstScanner() else {
            print("no scanner")
            return
        }
        do {
            let caps = try await backend.capabilities(of: s)
            print("resolutions: \(caps.resolutions)")
            print("bed: \(Int(caps.bedSizeMM.width)) x \(Int(caps.bedSizeMM.height)) mm")
        } catch { print("error: \(error.localizedDescription)") }
    case "scan":
        guard let s = await firstScanner() else {
            print("no scanner")
            return
        }
        let dir = URL(fileURLWithPath: args.count > 2 ? args[2] : ".")
        let dpi = args.count > 3 ? Int(args[3]) ?? 300 : 300
        let mode = args.count > 4 ? ScanMode(rawValue: args[4]) ?? .gray : .gray
        do {
            let t0 = Date()
            let url = try await backend.scan(
                with: s, config: ScanConfig(dpi: dpi, mode: mode), to: dir
            )
            print("scanned to \(url.path) in \(Int(-t0.timeIntervalSinceNow))s")
        } catch { print("error: \(error.localizedDescription)") }
    case "process":
        guard args.count > 3 else {
            print("process <in.tiff> <out.pdf> [dpi] [WxH] [fixed:WxH]")
            return
        }
        let input = URL(fileURLWithPath: args[2])
        // Optional args in any order: a bare number is the dpi, "WxH" pads
        // the page, "fixed:WxH" forces the paper size.
        func mm(_ s: Substring) -> (w: Double, h: Double)? {
            let parts = s.split(separator: "x").compactMap { Double($0) }
            return parts.count == 2 ? (parts[0], parts[1]) : nil
        }
        let options = args.dropFirst(4)
        let dpi =
            options.lazy.compactMap { Int($0) }.first
            ?? Pipeline.resolution(of: input) ?? 300
        let fixed = options.first { $0.hasPrefix("fixed:") }
            .flatMap { mm($0.dropFirst(6)) }
        let pad = options.first { !$0.hasPrefix("fixed:") && $0.contains("x") }
            .flatMap { mm(Substring($0)) }
        do {
            let t0 = Date()
            let gray = try Pipeline.loadGray(input)
            let page = Pipeline.processDocument(gray, dpi: dpi, fixedMM: fixed)
            let tiff = try G4.tiff(from: page)
            let stream = try G4.extractStream(fromTIFF: tiff)
            let words = (try? OCR.recognize(page)) ?? []
            print("ocr: \(words.count) text segments")
            let pageSize = pad.map { ($0.w / 25.4 * 72, $0.h / 25.4 * 72) }
            let pdf = PDFWriter.build(pages: [
                .init(
                    content: .g4(stream), dpi: dpi,
                    ocrWords: words,
                    pageSizePt: pageSize,
                    bedOriginPt: page.bedOriginPt
                )
            ])
            try pdf.write(to: URL(fileURLWithPath: args[3]))
            let mmW = Double(page.width) / Double(dpi) * 25.4
            let mmH = Double(page.height) / Double(dpi) * 25.4
            print(
                "page \(Int(mmW)) x \(Int(mmH)) mm at \(dpi) dpi, pdf \(pdf.count / 1024) KB, "
                    + "\(String(format: "%.2f", -t0.timeIntervalSinceNow))s"
            )
        } catch { print("error: \(error.localizedDescription)") }
    case "usbreset":
        let tokens = args.count > 2 ? Array(args[2...]) : ["canoscan", "lide"]
        print("reset:", USBReset.resetDevice(nameTokens: tokens))
    default:
        print(
            "usage: scantool [--sane] list|caps|scan [dir] [dpi] [mode] | "
                + "process <in> <out> [dpi] [WxH] [fixed:WxH] | usbreset [tokens]"
        )
    }
}

// ImageCaptureCore delivers delegate callbacks via the main run loop —
// blocking the main thread (semaphore) would deadlock discovery.
RunLoop.main.run()
