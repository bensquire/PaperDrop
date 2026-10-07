import CoreGraphics
import XCTest

@testable import ScanKit

/// Synthetic scans small enough to keep tests fast.
private let dpi = 50

/// White bed with black rectangles, dimensions in mm.
private func makeGray(
    bedW: Double, bedH: Double,
    inkRectsMM: [CGRect]
) -> Pipeline.GrayImage {
    let px = { (mm: Double) in Int(mm / 25.4 * Double(dpi)) }
    let w = px(bedW), h = px(bedH)
    var pixels = [UInt8](repeating: 230, count: w * h)
    for rect in inkRectsMM {
        for y in px(rect.minY)..<min(h, px(rect.maxY)) {
            for x in px(rect.minX)..<min(w, px(rect.maxX)) {
                pixels[y * w + x] = 20
            }
        }
    }
    return Pipeline.GrayImage(width: w, height: h, pixels: pixels)
}

private func mm(_ px: Int) -> Double {
    Double(px) / Double(dpi) * 25.4
}

private func cleanedBinary(_ gray: Pipeline.GrayImage) -> Pipeline.BinaryImage {
    var bw = Pipeline.threshold(gray, at: 128)
    Pipeline.cleanComponents(&bw, dpi: dpi)
    return bw
}

final class OtsuTests: XCTestCase {
    func test_otsuThreshold_splitsABimodalHistogram() {
        // Arrange
        let gray = makeGray(
            bedW: 50, bedH: 50,
            inkRectsMM: [CGRect(x: 10, y: 10, width: 20, height: 20)])

        // Act
        let t = Pipeline.otsuThreshold(gray)

        // Assert
        XCTAssertTrue(
            t > 20 && t <= 230,
            "threshold \(t) should fall between the ink (20) and the paper (230)")
    }
}

final class CleanComponentsTests: XCTestCase {
    func test_cleanComponents_removesBorderTouchingInk() {
        // Arrange — one blob touching the top edge, one interior
        let gray = makeGray(
            bedW: 60, bedH: 60,
            inkRectsMM: [
                CGRect(x: 20, y: 0, width: 10, height: 10),
                CGRect(x: 20, y: 30, width: 10, height: 10),
            ])
        var bw = Pipeline.threshold(gray, at: Pipeline.otsuThreshold(gray))

        // Act
        Pipeline.cleanComponents(&bw, dpi: dpi)

        // Assert
        let borderY = Int(5 / 25.4 * Double(dpi))
        let interiorY = Int(35 / 25.4 * Double(dpi))
        let x = Int(25 / 25.4 * Double(dpi))
        XCTAssertFalse(bw[x, borderY], "border blob should be whitened")
        XCTAssertTrue(bw[x, interiorY], "interior blob should survive")
    }

    func test_cleanComponents_removesTinySpecks() {
        // Arrange — a 1px speck and a solid block
        let w = 100, h = 100
        var ink = [Bool](repeating: false, count: w * h)
        ink[50 * w + 50] = true
        for y in 70..<80 {
            for x in 70..<80 {
                ink[y * w + x] = true
            }
        }
        var bw = Pipeline.BinaryImage(width: w, height: h, ink: ink)

        // Act
        Pipeline.cleanComponents(&bw, dpi: 300)

        // Assert
        XCTAssertFalse(bw[50, 50], "1px speck should be removed")
        XCTAssertTrue(bw[75, 75], "solid block should survive")
    }
}

final class SpeckThresholdTests: XCTestCase {
    func test_minSpeck_scalesWithResolutionByArea() {
        // Arrange / Act / Assert — 4 px at 300 dpi, by area, at least 2
        for (resolution, dust) in [(150, 2), (300, 4), (600, 16)] {
            XCTAssertEqual(
                Pipeline.minSpeck(dpi: resolution), dust,
                "dust size at \(resolution) dpi should be \(dust) px")
        }
    }

    func test_cleanComponents_keepsAFullStopAt150dpi() {
        // Arrange — a 2x2 dot (a full stop at 150 dpi) and a lone pixel
        var ink = [Bool](repeating: false, count: 20 * 20)
        for (x, y) in [(5, 5), (6, 5), (5, 6), (6, 6), (14, 14)] {
            ink[y * 20 + x] = true
        }
        var bw = Pipeline.BinaryImage(width: 20, height: 20, ink: ink)

        // Act
        Pipeline.cleanComponents(&bw, dpi: 150)

        // Assert
        XCTAssertTrue(bw[5, 5], "the dot should survive")
        XCTAssertFalse(bw[14, 14], "lone noise should be removed")
    }
}

final class ResolutionTests: XCTestCase {
    func test_resolution_readsTheDpiTheFileRecords() throws {
        // Arrange — a 150 dpi TIFF, as SANE delivers for a 200 dpi request
        let tiff = try G4.tiff(
            from: Pipeline.ProcessedPage(
                width: 8, height: 8, dpi: 150,
                originX: 0, originY: 0, packed: Data(repeating: 0xFF, count: 8)))
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("scan.tiff")
        try tiff.write(to: url)

        // Act
        let dpi = Pipeline.resolution(of: url)

        // Assert
        XCTAssertEqual(
            dpi, 150,
            "the page should be sized by the 150 dpi the file records, not the 200 asked for")
    }
}

final class ContentCropTests: XCTestCase {
    func test_contentCrop_snapsA4ContentToA4() throws {
        // Arrange — content block a little smaller than A4 on a full bed
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 15, y: 15, width: 180, height: 265)
            ])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(mm(c.x1 - c.x0), 210, accuracy: 3, "width should snap to A4")
        XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 3, "height should snap to A4")
    }

    func test_contentCrop_prefersA4OverLetterWhenBothFit() throws {
        // Arrange — 190x260mm content (+8mm margins) fits both A4 and
        // Letter within the snap slack
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 8, y: 8, width: 190, height: 260)
            ])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert — metric A4 must win over Letter
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(
            mm(c.y1 - c.y0), 297, accuracy: 3,
            "height should snap to A4 (297 mm), not Letter (279)")
    }

    func test_contentCrop_prefersA4OverLetterForShortContent() throws {
        // Arrange — a short A4 letter: 190x245mm content (+8mm margins)
        // is within the slack of Letter's height but not of A4's
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 10, y: 10, width: 190, height: 245)
            ])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert — the content fits A4, so A4 wins over Letter
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(
            mm(c.x1 - c.x0), 210, accuracy: 3,
            "width should snap to A4 (210 mm), not Letter (216)")
        XCTAssertEqual(
            mm(c.y1 - c.y0), 297, accuracy: 3,
            "height should snap to A4 (297 mm), not Letter (279)")
    }

    func test_contentCrop_snapsContentWiderThanA4ToLetter() throws {
        // Arrange — 198x245mm content (+8mm margins) is wider than A4
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 10, y: 10, width: 198, height: 245)
            ])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert — only Letter holds it
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(
            mm(c.x1 - c.x0), 216, accuracy: 3,
            "width should snap to Letter (216 mm); A4's 210 is too narrow")
        XCTAssertEqual(mm(c.y1 - c.y0), 279, accuracy: 3, "height should snap to Letter (279 mm)")
    }

    func test_contentCrop_fixedSizeRotatesWhenContentCannotFit() throws {
        // Arrange — content wider than 5x7 portrait (a landscape photo)
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 20, y: 20, width: 160, height: 100)
            ])

        // Act — force 5x7 inch paper, portrait
        let crop = Pipeline.contentCrop(
            cleanedBinary(gray), dpi: dpi,
            fixedMM: (w: 127, h: 177.8))

        // Assert — rotated to landscape, the only way the content fits
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(
            mm(c.x1 - c.x0), 177.8, accuracy: 3,
            "width should be 5×7's long side: it fits only landscape")
        XCTAssertEqual(mm(c.y1 - c.y0), 127, accuracy: 3, "height should be 5×7's short side (127 mm)")
    }

    func test_contentCrop_fixedA4KeepsPortraitForWideInk() throws {
        // Arrange — a portrait A4 sheet whose ink is wider than tall
        // (letterhead plus a paragraph, empty lower half)
        let gray = makeGray(
            bedW: 216, bedH: 297,
            inkRectsMM: [
                CGRect(x: 20, y: 20, width: 170, height: 120)
            ])

        // Act — force A4
        let crop = Pipeline.contentCrop(
            cleanedBinary(gray), dpi: dpi,
            fixedMM: (w: 210, h: 297))

        // Assert — full-height portrait page, not a landscape band that
        // discards the bottom third of the sheet
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(mm(c.x1 - c.x0), 210, accuracy: 3, "width should be portrait A4 (210 mm)")
        XCTAssertEqual(
            mm(c.y1 - c.y0), 297, accuracy: 3,
            "height should be portrait A4 (297 mm), not a 210 mm band")
    }

    func test_contentCrop_fixedSizeHonoursRequestedLandscape() throws {
        // Arrange — ink taller than wide, but small enough to fit either way
        let gray = makeGray(
            bedW: 216, bedH: 297,
            inkRectsMM: [
                CGRect(x: 20, y: 20, width: 100, height: 130)
            ])

        // Act — force A5 landscape
        let crop = Pipeline.contentCrop(
            cleanedBinary(gray), dpi: dpi,
            fixedMM: (w: 210, h: 148))

        // Assert — the requested orientation wins over the ink's shape
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertEqual(mm(c.x1 - c.x0), 210, accuracy: 3, "width should be landscape A5 (210 mm), as asked")
        XCTAssertEqual(mm(c.y1 - c.y0), 148, accuracy: 3, "height should be landscape A5 (148 mm), as asked")
    }

    func test_contentCrop_keepsDistantSparseContent() throws {
        // Arrange — dense block plus a small distant signature-like mark
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 15, y: 15, width: 120, height: 60),
                CGRect(x: 20, y: 200, width: 40, height: 12),
            ])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert — crop must extend past the distant mark's top edge
        let c = try XCTUnwrap(crop, "a page with ink should have a crop")
        XCTAssertGreaterThanOrEqual(mm(c.y1), 208, "distant mark must be inside the crop")
    }

    func test_contentCrop_nilOnBlankPage() {
        // Arrange
        let gray = makeGray(bedW: 60, bedH: 60, inkRectsMM: [])

        // Act
        let crop = Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi)

        // Assert
        XCTAssertNil(crop)
    }
}

final class PaperSizeNameTests: XCTestCase {
    func test_paperSizeName_namesStandardAndPhotoSizes() {
        // Arrange / Act / Assert
        let sizes: [(w: Double, h: Double, name: String?)] = [
            (210, 297, "A4"), (148, 210, "A5"), (101.6, 152.4, "4×6″"),
            (152.4, 101.6, "4×6″ landscape"), (100, 100, nil),
        ]
        for size in sizes {
            XCTAssertEqual(
                Pipeline.paperSizeName(widthMM: size.w, heightMM: size.h), size.name,
                "name for \(size.w) × \(size.h) mm")
        }
    }
}

final class ProcessDocumentTests: XCTestCase {
    func test_processDocument_recordsBedOriginOfCrop() {
        // Arrange — content well away from the bed origin
        let gray = makeGray(
            bedW: 216.7, bedH: 300,
            inkRectsMM: [
                CGRect(x: 50, y: 80, width: 60, height: 40)
            ])

        // Act
        let page = Pipeline.processDocument(gray, dpi: dpi)

        // Assert — origin ≈ content position minus the 8mm margin
        XCTAssertEqual(
            mm(page.originX), 42, accuracy: 3,
            "x origin should be the content's 50 mm less the margin")
        XCTAssertEqual(
            mm(page.originY), 72, accuracy: 3,
            "y origin should be the content's 80 mm less the margin")
    }
}
