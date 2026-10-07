---
title: Code Reads Like the Prose Around It
impact: HIGH
impactDescription: The next reader is a person, usually months later, often the author
tags: [quality, readability, naming]
paths: ["Sources/**/*.swift", "Tests/**/*.swift"]
---

## Code Reads Like the Prose Around It

**Impact: HIGH**

Names say what a thing is in the words the domain uses — `cleanComponents`,
`contentCrop`, `snapToPaper`, `bedOriginPt`, `resolution(of:)`,
`minSpeck(dpi:)` — so a call site reads as a sentence. Short names are right
where the convention uses them (`w`, `h`, `x`, `y`, `bw`, `dpi` in a pixel loop)
and wrong anywhere else. A function does what its name says and nothing more;
one that needs "and" in its name is two. Nesting is shallow; the early `guard`
says what a function refuses. Cleverness that needs a comment to decode is
replaced by the plain version, unless it is necessary — then the comment says
why, with the measurement.

**Incorrect:**

```swift
func proc(_ g: Pipeline.GrayImage, _ d: Int, _ f: Bool) -> Pipeline.Crop? {
    if f { if g.width > 0 { /* … forty lines … */ } }
    return nil
}
```

**Correct:**

```swift
/// Dust size in pixels at a resolution: 4 px at 300 dpi, scaled by
/// area so a full stop survives at 150 dpi. Never below 2, so lone
/// noise pixels always go.
public static func minSpeck(dpi: Int) -> Int {
    let scale = Double(dpi) / 300
    return max(2, Int((4 * scale * scale).rounded()))
}
```
