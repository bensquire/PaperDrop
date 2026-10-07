---
title: Fast and Lean Where It Counts, and Measured
impact: HIGH
impactDescription: A 600 dpi full-bed scan is over 36 million pixels; Vision peaks near 450 MB on one such page
tags: [quality, performance, memory, concurrency, imageio, vision]
paths: ["Sources/ScanKit/**/*.swift", "Sources/PaperDrop/AppModel.swift"]
---

## Fast and Lean Where It Counts, and Measured

**Impact: HIGH**

The cost is in a few places, and each is written for the machine with its
measurement beside it:

- **Per-pixel passes in `Pipeline`.** `cleanComponents` marks what it has
  visited in a 1-byte-per-pixel bitmap, not a 4-byte label image (~145 MB at
  600 dpi on a full bed); `contentCrop` works on an 8× downsampled grid.
- **OCR when saving.** `AppModel.savePDF` builds pages on three workers, not one
  per core, because Vision peaks at ~170 MB per 300 dpi page (~450 MB at 600).
- **Thumbnails.** `ImageEncode.thumbnail` lets ImageIO decode only what the
  thumbnail needs: 7 ms against 40 ms drawing the whole 300 dpi page.
- **Child processes.** `runAsync` drains both pipes while `scanimage` or `ioreg`
  runs, because a child blocks once it fills the 64 KB pipe buffer.

Everything else is written for the reader. Which is which is decided by
measuring — the time `scantool process` prints, the suite's own time, a
signpost or a timer around the step — and a comment on a fast path says what it
cost before and after. A hot path that allocates per pixel, or a fan-out with no
bound, is fixed; code off those paths is left plain.

**Incorrect (a label image; one Vision request per core):**

```swift
var labels = [Int32](repeating: 0, count: w * h)   // 4 bytes/px
DispatchQueue.concurrentPerform(iterations: builders.count) { i in … }
```

**Correct (lean, bounded, and the measurement kept):**

```swift
var visited = [Bool](repeating: false, count: w * h)   // 1 byte/px
// Three because Vision peaks at ~170 MB per 300 dpi page (~450 MB at 600).
DispatchQueue.concurrentPerform(iterations: min(3, builders.count)) { worker in … }
```
