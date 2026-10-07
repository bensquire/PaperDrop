---
title: Ground Truth Is Where the Page Lands, and the Bar Has Teeth
impact: HIGH
impactDescription: A PDF can be well formed, and its stream can hold the words, while the page is the wrong size and a reader finds nothing
tags: [testing, ground-truth, geometry, pdf, ocr]
paths: ["Tests/**/*.swift"]
---

## Ground Truth Is Where the Page Lands, and the Bar Has Teeth

**Impact: HIGH**

A fixture is a synthetic bed with ink at known millimetre positions
(`makeGray`), so a result is judged in the units the user sees: the crop's
width and height in millimetres, where its origin sits on the bed, which paper
size it snapped to. Text is judged by what a PDF reader extracts (`readerText`,
through PDFKit), not only by what the writer put in the stream. When a test says
a result is good, it also says, where it can, what the alternative would have
measured, so the bar cannot be cleared by accident:
`test_contentCrop_prefersA4OverLetterForShortContent` draws content inside
Letter's slack but not A4's, so a snap that kept the first size within its
slack would measure 279 mm, not 297. A tolerance carries the reason for its
size; at the suite's 50 dpi a pixel is half a millimetre, so the crop tests'
3 mm is six pixels. When a bug is fixed, a test pins it, with the measurement
that showed it: `test_resolution_readsTheDpiTheFileRecords` is the 150 dpi
file a 200 dpi request produced.

**Incorrect (a bar with no teeth — passes on a crop or a text layer that did nothing):**

```swift
XCTAssertNotNil(Pipeline.contentCrop(cleanedBinary(gray), dpi: dpi))
XCTAssertTrue(pdfText([page]).contains("BT"))
```

**Correct (the measured page, and what a reader gets back):**

```swift
let c = try XCTUnwrap(crop)
XCTAssertEqual(mm(c.x1 - c.x0), 210, accuracy: 3, "width should snap to A4")
XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 3, "height should snap to A4")
XCTAssertTrue(readerText([page]).contains("with (parens) \\ done"))
```
