---
title: Every Run Gives the Same Answer
impact: HIGH
impactDescription: A flaky test is a test nobody trusts
tags: [testing, determinism, fixtures, hardware]
paths: ["Tests/**/*.swift"]
---

## Every Run Gives the Same Answer

**Impact: HIGH**

Fixtures are drawn in the test — `makeGray` paints ink rectangles on a white
bed, `makePage` packs a 1-bit page — never fetched, and no test needs a
scanner, a network or Vision. No clock: what depends on the date takes it, and
`Archive.defaultTitle(for:)` is handed 2026-10-04 08:45:12. No machine settings:
`OCR.recognitionLanguages` is handed the preferred and supported languages
rather than reading the Mac's. No dependence on another test having run first or
on the order tests run in: a test that writes files makes its own directory
under the temporary directory, named by a fresh UUID, and removes it in a
`defer`. No sleeping for luck.

**Incorrect:**

```swift
XCTAssertTrue(Archive.defaultTitle().hasPrefix("Scan 2026"))     // today's date
let devices = await SANECLIBackend().discover(timeout: 15)         // whatever is plugged in
```

**Correct:**

```swift
XCTAssertEqual(Archive.defaultTitle(for: date), "Scan 2026-10-04 at 08.45.12")
let devices = SANECLIBackend.parseDeviceList(out)   // scanimage's output, written in the test
```
