---
title: Fast, but Not Over Accuracy
impact: MEDIUM
impactDescription: A test that is quick because it cannot see the defect is not a test; a slow suite is one nobody runs
tags: [testing, performance, accuracy, fixtures]
paths: ["Tests/**/*.swift"]
---

## Fast, but Not Over Accuracy

**Impact: MEDIUM**

A test is first for what it proves, then as cheap as that allows — never the
other way round. The 35 tests run in about 4.3 s. Speed is bought by not paying
for what the test does not need: synthetic beds are drawn at 50 dpi, because the
pipeline works in millimetres and scales its pixel figures by the dpi; a rule
about one unit is pinned on that unit — `cleanComponents` on a hand-drawn
100 × 100 grid, `PDFWriter.flate` on the word "Wikipedia" — not on a whole page;
scanner and OCR decisions are tested in the functions that make them, with no
device and no Vision request.

Speed is never bought by making the test see less. The paper-snap tests draw a
whole 216.7 × 300 mm bed and take about 0.75 s each, the slowest in the suite,
because a crop is clamped inside the scan and a smaller bed could not hold the
A4 or Letter page they measure. The speck tests set the dpi they are about (150,
300) on their own grids, because at 50 dpi the dust size is its floor of 2 px
and the scaling would go untested. A bed shrunk until the snap cannot show, or a
tolerance loosened so a coarse fixture clears it, is a faster test that no
longer tests.

**Incorrect (fast because it cannot see):**

```swift
let gray = makeGray(bedW: 150, bedH: 200, inkRectsMM: [content])   // smaller than A4: the crop is clamped
XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 100)                // loosened until it passes
```

**Correct (cheap where it costs nothing to be; exact where it counts):**

```swift
private let dpi = 50   // synthetic scans small enough to keep tests fast
let gray = makeGray(bedW: 216.7, bedH: 300, inkRectsMM: [CGRect(x: 15, y: 15, width: 180, height: 265)])
XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 3, "height should snap to A4")
```
