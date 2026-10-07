import Foundation
import PDFKit
import XCTest

@testable import ScanKit

/// A white 200x100px page with a black bar, packed 1-bit.
private func makePage(
    width: Int = 200, height: Int = 100,
    dpi: Int = 100
) -> Pipeline.ProcessedPage {
    let rowBytes = (width + 7) / 8
    var packed = Data(repeating: 0xFF, count: rowBytes * height)
    for y in 20..<40 {
        for xb in 2..<10 {
            packed[y * rowBytes + xb] = 0x00
        }
    }
    return Pipeline.ProcessedPage(
        width: width, height: height, dpi: dpi,
        originX: 0, originY: 0, packed: packed)
}

/// makePage() as an embeddable G4 stream.
private func makeStream() throws -> G4.Stream {
    try G4.extractStream(fromTIFF: G4.tiff(from: makePage()))
}

/// 2026-10-04 08:45:12, local time.
private func scanDate() throws -> Date {
    var parts = DateComponents()
    (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) =
        (2026, 10, 4, 8, 45, 12)
    return try XCTUnwrap(Calendar.current.date(from: parts), "2026-10-04 08:45:12 should be a date")
}

/// A built PDF as text (its streams are ASCII or binary we don't inspect).
private func pdfText(_ pages: [PDFWriter.Page]) -> String {
    String(decoding: PDFWriter.build(pages: pages), as: UTF8.self)
}

/// The text a PDF reader extracts, decoding streams and fonts.
private func readerText(_ pages: [PDFWriter.Page]) -> String {
    PDFDocument(data: PDFWriter.build(pages: pages))?.string ?? ""
}

/// The first page's content stream, inflated.
private func pageContent(_ pages: [PDFWriter.Page]) -> String {
    let pdf = PDFWriter.build(pages: pages)
    guard let start = pdf.range(of: Data("/Filter/FlateDecode>>\nstream\n".utf8))?.upperBound,
        let end = pdf.range(of: Data("\nendstream".utf8), in: start..<pdf.endIndex)?.lowerBound,
        let raw = try? (pdf[(start + 2)..<(end - 4)] as NSData).decompressed(using: .zlib)
    else { return "" }
    return String(decoding: raw as Data, as: UTF8.self)
}

final class G4Tests: XCTestCase {
    func test_g4Tiff_roundTripPreservesGeometry() throws {
        // Arrange
        let page = makePage()

        // Act
        let tiff = try G4.tiff(from: page)
        let stream = try G4.extractStream(fromTIFF: tiff)

        // Assert
        XCTAssertEqual(stream.width, page.width, "the G4 stream should keep the page's width")
        XCTAssertEqual(stream.height, page.height, "the G4 stream should keep the page's height")
        XCTAssertFalse(stream.data.isEmpty, "the stream should carry the page's data")
        XCTAssertLessThan(
            stream.data.count, page.packed.count,
            "G4 should compress a mostly-white page")
    }

    func test_extractStream_refusesADirectoryOutsideTheData() {
        // Arrange — little-endian TIFF headers whose directory, or whose
        // entries, lie past the end of the data
        let tiffs: [(what: String, data: Data)] = [
            ("a directory offset past the end", Data([0x49, 0x49, 0x2A, 0, 0xFF, 0xFF, 0, 0, 0, 0])),
            ("five entries in two bytes", Data([0x49, 0x49, 0x2A, 0, 0x08, 0, 0, 0, 0x05, 0])),
        ]

        // Act / Assert
        for tiff in tiffs {
            XCTAssertThrowsError(
                try G4.extractStream(fromTIFF: tiff.data),
                "a TIFF with \(tiff.what) should be refused, not read")
        }
    }
}

final class PDFWriterTests: XCTestCase {
    func test_build_producesAWellFormedPDF() throws {
        // Arrange
        let stream = try makeStream()

        // Act
        let text = pdfText([.init(content: .g4(stream), dpi: 100)])

        // Assert
        XCTAssertTrue(text.hasPrefix("%PDF-1.4"), "a PDF should start with its version header")
        XCTAssertTrue(text.contains("/CCITTFaxDecode"), "the page image should be the G4 stream")
        XCTAssertTrue(text.contains("/Count 1"), "the page tree should hold one page")
        XCTAssertTrue(text.hasSuffix("%%EOF"), "a PDF should end with %%EOF")
    }

    func test_build_padsToUniformPageSizeTopAnchored() throws {
        // Arrange — 200x100px at 100dpi = 144x72pt natural
        var pdfPage = try PDFWriter.Page(content: .g4(makeStream()), dpi: 100)
        pdfPage.pageSizePt = (200, 200)

        // Act
        let text = pdfText([pdfPage])

        // Assert — MediaBox is the padded size; image sits at the top
        XCTAssertTrue(
            text.contains("/MediaBox[0 0 200.00 200.00]"),
            "the page should be the padded 200 × 200 pt, not the natural 144 × 72")
        XCTAssertTrue(
            text.contains("0.00 128.00 cm"),
            "image should sit at the page top (200-72=128)")
    }

    func test_build_escapesOCRTextAndMarksItInvisible() throws {
        // Arrange
        let stream = try makeStream()
        let words = [
            OCR.Word(
                text: "with (parens) \\ done",
                box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05))
        ]

        let page = PDFWriter.Page(content: .g4(stream), dpi: 100, ocrWords: words)

        // Act
        let content = pageContent([page])
        let extracted = readerText([page])

        // Assert — escaped in the stream, intact for a reader
        XCTAssertTrue(content.contains("BT 3 Tr"), "OCR text must be invisible")
        XCTAssertTrue(
            content.contains("with \\(parens\\) \\\\ done"),
            "parentheses and the backslash should be escaped in the stream")
        XCTAssertTrue(
            extracted.contains("with (parens) \\ done"),
            "a reader should get the text back as it was recognised")
    }

    func test_build_keepsWinAnsiCharactersInOCRText() throws {
        // Arrange
        let stream = try makeStream()
        let words = [
            OCR.Word(
                text: "£5 café – don’t 漢",
                box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05))
        ]

        let page = PDFWriter.Page(content: .g4(stream), dpi: 100, ocrWords: words)

        // Act
        let text = pdfText([page])
        let content = pageContent([page])
        let extracted = readerText([page])

        // Assert — octal WinAnsi escapes, read back by PDFKit; only the
        // CJK glyph is lost
        XCTAssertTrue(text.contains("/Encoding/WinAnsiEncoding"), "the OCR font should use WinAnsi")
        XCTAssertTrue(
            content.contains("(\\2435 caf\\351 \\226 don\\222t  )"),
            "£, é, – and ’ should be octal WinAnsi escapes, and 漢 a space")
        XCTAssertTrue(extracted.contains("£5 café – don’t"), "a reader should get the Latin text back")
    }

    func test_flate_wrapsDeflateInTheZlibFormat() throws {
        // Arrange — the classic Adler-32 example: "Wikipedia" is 0x11E60398
        let data = Data("Wikipedia".utf8)

        // Act
        let flated = try XCTUnwrap(PDFWriter.flate(data), "flate should compress \"Wikipedia\"")

        // Assert — header, round-trip body, big-endian checksum
        XCTAssertEqual(
            Array(flated.prefix(2)), [0x78, 0x9C],
            "the zlib header should be deflate, default level")
        let body = flated.dropFirst(2).dropLast(4)
        XCTAssertEqual(
            try (Data(body) as NSData).decompressed(using: .zlib) as Data, data,
            "the body should inflate back to the input")
        XCTAssertEqual(
            Array(flated.suffix(4)), [0x11, 0xE6, 0x03, 0x98],
            "the trailer should be the Adler-32 0x11E60398, big-endian")
    }

    func test_build_embedsGrayscaleJPEGPages() throws {
        // Arrange
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

        // Act
        let text = pdfText([.init(content: .jpegGray(jpeg, width: 200, height: 100), dpi: 100)])

        // Assert
        XCTAssertTrue(text.contains("/Width 200/Height 100"), "the image should keep its 200 × 100 px")
        XCTAssertTrue(
            text.contains("/BitsPerComponent 8/Filter/DCTDecode/Length 4"),
            "the JPEG should be embedded as 8-bit DCTDecode, all 4 bytes")
        XCTAssertTrue(
            text.contains("/MediaBox[0 0 144.00 72.00]"),
            "200 × 100 px at 100 dpi should make a 144 × 72 pt page")
    }

    func test_build_clampsBedOriginIntoThePaddedPage() throws {
        // Arrange — 144x72pt content claiming to sit beyond the page
        let pdfPage = try PDFWriter.Page(
            content: .g4(makeStream()), dpi: 100,
            pageSizePt: (200, 200), bedOriginPt: (500, 500))

        // Act
        let text = pdfText([pdfPage])

        // Assert — pushed back to the bottom-right corner, fully on the page
        XCTAssertTrue(
            text.contains("144.00 0 0 72.00 56.00 0.00 cm"),
            "the image should sit in the bottom-right corner (200 − 144 = 56 pt across), on the page")
    }
}

final class ScannerInfoTests: XCTestCase {
    func test_sameModel_toleratesVendorSpellings() {
        // Arrange / Act / Assert
        XCTAssertTrue(
            ScannerInfo.sameModel("Canon LiDE 110 (SANE)", "CanoScan LiDE 110"),
            "Canon's two spellings of the LiDE 110 should be one model")
        XCTAssertFalse(
            ScannerInfo.sameModel("Canon LiDE 110", "EPSON Perfection V600"),
            "a Canon and an Epson should be different models")
    }

    func test_baseName_stripsBackendSuffix() {
        // Arrange
        let info = ScannerInfo(id: "sane:x", name: "Canon LiDE 110 (SANE)")

        // Act / Assert
        XCTAssertEqual(info.baseName, "Canon LiDE 110", "the \" (SANE)\" suffix should be stripped")
    }

    func test_merge_prefersTheSANETwinAndKeepsOtherSuffixes() {
        // Arrange — the LiDE via both backends, plus a SANE-only scanner
        let sane = [
            ScannerInfo(id: "sane:genesys:libusb:002:001", name: "Canon LiDE 110 (SANE)"),
            ScannerInfo(id: "sane:plustek:libusb:001:004", name: "Plustek OpticPro (SANE)"),
        ]
        let icc = [
            ScannerInfo(id: "0210-ABCD", name: "CanoScan LiDE 110"),
            ScannerInfo(id: "airscan-1", name: "Brother MFC-L2710DW"),
        ]

        // Act
        let merged = ScannerInfo.merge(sane: sane, icc: icc)

        // Assert — only the twin loses its suffix; its ICC copy is gone
        XCTAssertEqual(
            merged.map(\.name),
            ["Canon LiDE 110", "Plustek OpticPro (SANE)", "Brother MFC-L2710DW"],
            "one LiDE without its suffix, the SANE-only Plustek with its own, the Brother")
        XCTAssertEqual(
            merged.first?.id, "sane:genesys:libusb:002:001",
            "the LiDE should be the SANE twin, not the ICC copy")
    }
}

final class OCRLanguageTests: XCTestCase {
    func test_recognitionLanguages_matchesByLanguageInTheUsersOrder() {
        // Arrange — a British user who also reads French; Vision has US
        // English and France French
        let preferred = ["en-GB", "fr-CA", "cy-GB"]
        let supported = ["fr-FR", "en-US", "de-DE"]

        // Act
        let picked = OCR.recognitionLanguages(preferred: preferred, supported: supported)

        // Assert — Welsh has no match and is skipped
        XCTAssertEqual(
            picked, ["en-US", "fr-FR"],
            "en-GB should find en-US and fr-CA fr-FR, in the user's order; cy-GB nothing")
    }
}

final class SANEDeviceListTests: XCTestCase {
    func test_parseDeviceList_readsDeviceAndModelPerLine() {
        // Arrange — scanimage -f "%d|%v %m%n" output, with a stray line
        let out = "genesys:libusb:002:001|Canon LiDE 110\nnoise\nnet:host:pixma|Canon MX920\n"

        // Act
        let devices = SANECLIBackend.parseDeviceList(out)

        // Assert
        XCTAssertEqual(
            devices.map(\.id), ["sane:genesys:libusb:002:001", "sane:net:host:pixma"],
            "each device line should give a sane: id; the stray line none")
        XCTAssertEqual(
            devices.map(\.name), ["Canon LiDE 110 (SANE)", "Canon MX920 (SANE)"],
            "each name should be the model with the SANE suffix")
    }
}

final class ArchiveTests: XCTestCase {
    func test_fileName_replacesPathSeparatorsAndLeadingDots() {
        // Arrange / Act / Assert
        for (title, name) in [(" Bills/2026: Q3 ", "Bills-2026- Q3"), ("..hidden", "hidden")] {
            XCTAssertEqual(Archive.fileName(for: title), name, "file name for \"\(title)\"")
        }
    }

    func test_defaultTitle_hasNoColon() throws {
        // Arrange
        let date = try scanDate()

        // Act / Assert
        XCTAssertEqual(
            Archive.defaultTitle(for: date), "Scan 2026-10-04 at 08.45.12",
            "the title should use dots, not the colon Finder shows as a slash")
    }

    func test_destination_neverReusesAnExistingName() throws {
        // Arrange — "Letter.pdf" and "Letter 2.pdf" already exist
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        for name in ["Letter.pdf", "Letter 2.pdf"] {
            try Data().write(to: dir.appendingPathComponent(name))
        }

        // Act
        let dest = Archive.destination(for: "Letter", in: dir, untitledDate: try scanDate())

        // Assert
        XCTAssertEqual(dest.lastPathComponent, "Letter 3.pdf", "the first free name should be \"Letter 3\"")
    }

    func test_destination_namesAnEmptyTitleForTheDate() throws {
        // Arrange — an empty folder, and a title that is empty once made safe
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let date = try scanDate()

        // Act
        let dest = Archive.destination(for: " .. ", in: dir, untitledDate: date)

        // Assert
        XCTAssertEqual(
            dest.lastPathComponent, "Scan 2026-10-04 at 08.45.12.pdf",
            "an empty title should be named for the date handed in")
    }
}
