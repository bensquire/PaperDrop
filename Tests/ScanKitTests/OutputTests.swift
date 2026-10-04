import Foundation
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

/// A built PDF as text (its streams are ASCII or binary we don't inspect).
private func pdfText(_ pages: [PDFWriter.Page]) -> String {
    String(decoding: PDFWriter.build(pages: pages), as: UTF8.self)
}

final class G4Tests: XCTestCase {
    func test_g4Tiff_roundTripPreservesGeometry() throws {
        // Arrange
        let page = makePage()

        // Act
        let tiff = try G4.tiff(from: page)
        let stream = try G4.extractStream(fromTIFF: tiff)

        // Assert
        XCTAssertEqual(stream.width, page.width)
        XCTAssertEqual(stream.height, page.height)
        XCTAssertFalse(stream.data.isEmpty)
        XCTAssertLessThan(
            stream.data.count, page.packed.count,
            "G4 should compress a mostly-white page")
    }
}

final class PDFWriterTests: XCTestCase {
    func test_build_producesAWellFormedPDF() throws {
        // Arrange
        let stream = try makeStream()

        // Act
        let text = pdfText([.init(content: .g4(stream), dpi: 100)])

        // Assert
        XCTAssertTrue(text.hasPrefix("%PDF-1.4"))
        XCTAssertTrue(text.contains("/CCITTFaxDecode"))
        XCTAssertTrue(text.contains("/Count 1"))
        XCTAssertTrue(text.hasSuffix("%%EOF"))
    }

    func test_build_padsToUniformPageSizeTopAnchored() throws {
        // Arrange — 200x100px at 100dpi = 144x72pt natural
        var pdfPage = try PDFWriter.Page(content: .g4(makeStream()), dpi: 100)
        pdfPage.pageSizePt = (200, 200)

        // Act
        let text = pdfText([pdfPage])

        // Assert — MediaBox is the padded size; image sits at the top
        XCTAssertTrue(text.contains("/MediaBox[0 0 200.00 200.00]"))
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

        // Act
        let text = pdfText([.init(content: .g4(stream), dpi: 100, ocrWords: words)])

        // Assert
        XCTAssertTrue(text.contains("BT 3 Tr"), "OCR text must be invisible")
        XCTAssertTrue(text.contains("with \\(parens\\) \\\\ done"))
    }

    func test_build_keepsWinAnsiCharactersInOCRText() throws {
        // Arrange
        let stream = try makeStream()
        let words = [
            OCR.Word(
                text: "£5 café – don’t 漢",
                box: CGRect(x: 0.1, y: 0.1, width: 0.5, height: 0.05))
        ]

        // Act
        let text = pdfText([.init(content: .g4(stream), dpi: 100, ocrWords: words)])

        // Assert — octal WinAnsi escapes; only the CJK glyph is lost
        XCTAssertTrue(text.contains("/Encoding/WinAnsiEncoding"))
        XCTAssertTrue(text.contains("(\\2435 caf\\351 \\226 don\\222t  )"))
    }

    func test_build_embedsGrayscaleJPEGPages() throws {
        // Arrange
        let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])

        // Act
        let text = pdfText([.init(content: .jpegGray(jpeg, width: 200, height: 100), dpi: 100)])

        // Assert
        XCTAssertTrue(text.contains("/Width 200/Height 100"))
        XCTAssertTrue(text.contains("/BitsPerComponent 8/Filter/DCTDecode/Length 4"))
        XCTAssertTrue(text.contains("/MediaBox[0 0 144.00 72.00]"))
    }

    func test_build_clampsBedOriginIntoThePaddedPage() throws {
        // Arrange — 144x72pt content claiming to sit beyond the page
        let pdfPage = try PDFWriter.Page(
            content: .g4(makeStream()), dpi: 100,
            pageSizePt: (200, 200), bedOriginPt: (500, 500))

        // Act
        let text = pdfText([pdfPage])

        // Assert — pushed back to the bottom-right corner, fully on the page
        XCTAssertTrue(text.contains("144.00 0 0 72.00 56.00 0.00 cm"))
    }
}

final class ScannerInfoTests: XCTestCase {
    func test_sameModel_toleratesVendorSpellings() {
        // Arrange / Act / Assert
        XCTAssertTrue(ScannerInfo.sameModel("Canon LiDE 110 (SANE)", "CanoScan LiDE 110"))
        XCTAssertFalse(ScannerInfo.sameModel("Canon LiDE 110", "EPSON Perfection V600"))
    }

    func test_baseName_stripsBackendSuffix() {
        // Arrange
        let info = ScannerInfo(id: "sane:x", name: "Canon LiDE 110 (SANE)")

        // Act / Assert
        XCTAssertEqual(info.baseName, "Canon LiDE 110")
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
            ["Canon LiDE 110", "Plustek OpticPro (SANE)", "Brother MFC-L2710DW"])
        XCTAssertEqual(merged.first?.id, "sane:genesys:libusb:002:001")
    }
}

final class SANEDeviceListTests: XCTestCase {
    func test_parseDeviceList_readsDeviceAndModelPerLine() {
        // Arrange — scanimage -f "%d|%v %m%n" output, with a stray line
        let out = "genesys:libusb:002:001|Canon LiDE 110\nnoise\nnet:host:pixma|Canon MX920\n"

        // Act
        let devices = SANECLIBackend.parseDeviceList(out)

        // Assert
        XCTAssertEqual(devices.map(\.id), ["sane:genesys:libusb:002:001", "sane:net:host:pixma"])
        XCTAssertEqual(devices.map(\.name), ["Canon LiDE 110 (SANE)", "Canon MX920 (SANE)"])
    }
}

final class ArchiveTests: XCTestCase {
    func test_fileName_replacesPathSeparatorsAndLeadingDots() {
        // Arrange / Act / Assert
        XCTAssertEqual(Archive.fileName(for: " Bills/2026: Q3 "), "Bills-2026- Q3")
        XCTAssertEqual(Archive.fileName(for: "..hidden"), "hidden")
    }

    func test_defaultTitle_hasNoColon() {
        // Arrange
        var parts = DateComponents()
        (parts.year, parts.month, parts.day, parts.hour, parts.minute, parts.second) =
            (2026, 10, 4, 8, 45, 12)
        let date = Calendar.current.date(from: parts)!

        // Act / Assert
        XCTAssertEqual(Archive.defaultTitle(for: date), "Scan 2026-10-04 at 08.45.12")
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
        let dest = Archive.destination(for: "Letter", in: dir)

        // Assert
        XCTAssertEqual(dest.lastPathComponent, "Letter 3.pdf")
    }
}
