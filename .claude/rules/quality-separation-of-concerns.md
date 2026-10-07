---
title: Each Part Does One Job, and Knows Only Its Neighbours
impact: HIGH
impactDescription: ScanKit is testable headlessly and shared with scantool because nothing in it knows about a window
tags: [quality, architecture, separation-of-concerns, layers]
paths: ["Sources/**/*.swift", "Package.swift"]
---

## Each Part Does One Job, and Knows Only Its Neighbours

**Impact: HIGH**

The layers are the targets, and the dependencies run one way. `ScanKit` (the
scanner backends, the pipeline, the encoders, OCR, the PDF writer, file naming)
imports no SwiftUI or AppKit; `PaperDrop` holds the views and `AppModel`, and
calls ScanKit; `scantool` is the same ScanKit with a command line on it. Within
ScanKit, a `ScannerBackend` (`ICCBackend`, `SANECLIBackend`) turns a
`ScanConfig` into a TIFF on disk and nothing more; `Pipeline` decides the page —
threshold, clean, crop, snap; `G4` and `ImageEncode` encode it; `OCR` reads it;
`PDFWriter` assembles the pages it is handed; `Archive` picks where the file
goes. Values — `ScannerInfo`, `GrayImage`, `ProcessedPage`, `G4.Stream`,
`OCR.Word`, `PDFWriter.Page` — flow between them and nothing reaches back.

A change that needs ScanKit to import a UI framework, a view to decide a paper
size, or a backend to know what a page is, is at the wrong layer.

**Incorrect (a view deciding something ScanKit owns):**

```swift
// ContentView
let isA4 = abs(widthMM - 210) < 3 && abs(heightMM - 297) < 3   // paper policy in a view
```

**Correct (ScanKit states the rule; the app shows it):**

```swift
// ScanKit
public static func paperSizeName(widthMM: Double, heightMM: Double, toleranceMM: Double = 3) -> String?
// AppModel
Pipeline.paperSizeName(widthMM: mmW, heightMM: mmH) ?? "\(Int(mmW))×\(Int(mmH)) mm"
```
