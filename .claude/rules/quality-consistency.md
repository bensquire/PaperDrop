---
title: Match the Code Around You
impact: HIGH
impactDescription: One idiom for one job, so a reader learns it once
tags: [quality, consistency, idioms, reuse]
paths: ["Sources/**/*.swift", "Tests/**/*.swift"]
---

## Match the Code Around You

**Impact: HIGH**

New code reads like the file it lands in: the same naming, comment density,
error style (`ScanError`), and idioms. Before writing a helper, look for the one
that exists — `ImageEncode.jpeg`, `ImageEncode.thumbnail`,
`ImageEncode.encode`, `Archive.destination`, `Archive.fileName`,
`ScannerInfo.baseName`, `ScannerInfo.sameModel`, `ScannerInfo.match(in:)`,
`Pipeline.resolution(of:)`, `Pipeline.paperCrop`, and in `SANECLIBackend`,
`runAsync` with its `PipeDrain` and `processLock.withLock` — and call it. In
tests, each file has its builders: `makeGray`, `cleanedBinary` and `mm(_:)` in
`PipelineTests.swift`; `makePage`, `makeStream`, `pdfText`, `readerText` and
`pageContent` in `OutputTests.swift`. A second spelling of the same thing is a
bug waiting for one of them to drift: the app's paper sizes had already drifted
from `Pipeline`'s on Letter before `AppModel.fixedPapers` was derived from them.

**Incorrect (a fresh spelling of an existing helper; a second table):**

```swift
let model = scanner.name.replacingOccurrences(of: " (SANE)", with: "")
let papers = [("A4", 210.0, 297.0), ("Letter", 215.9, 279.4)]
```

**Correct:**

```swift
let model = scanner.baseName
let all = Pipeline.paperSizesMM + Pipeline.photoSizesMM
```
