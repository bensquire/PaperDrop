---
title: A Comment Is Short, and Says Why
impact: HIGH
impactDescription: A comment costs every reader time and every token money; it earns that or it goes
tags: [quality, comments, documentation, measurements, brevity]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "bundle.sh", "scripts/**"]
---

## A Comment Is Short, and Says Why

**Impact: HIGH**

A comment adds what the code cannot say — why this, what was measured, what was
rejected — in as few plain words as will still read. It never restates a
function or property name. A claim carries its measurement: the scan or file,
before, after. A constant carries the measurement that set it. A decision that
rests on Apple's documentation carries the page's path, as
`native-check-apples-documentation` says. No flourish, no anecdote told twice,
and no comment about code or a layout that has gone.

**Incorrect (restates the name; no provenance; flowery):**

```swift
/// Returns the thumbnail.
let thumb = ImageEncode.thumbnail(of: tiff, maxPixelSize: 400)

/// We found after a great deal of testing that three workers is a really
/// good number that works well on most machines …
```

**Correct (the why and the number, then stop):**

```swift
// ImageIO decodes only what the thumbnail needs: 7 ms against 40 ms
// drawing the full 300 dpi page (154 against 22 ms at 600)
// (/documentation/imageio/cgimagesourcecreatethumbnailatindex(_:_:_:)).
let thumb = ImageEncode.thumbnail(of: tiff, maxPixelSize: 400)
```
