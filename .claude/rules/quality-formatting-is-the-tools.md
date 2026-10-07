---
title: Formatting Is Decided by the Tool
impact: MEDIUM
impactDescription: No formatting diffs, no style arguments in review, no surprise in CI
tags: [quality, formatting, swift-format, lint]
paths: ["Sources/**/*.swift", "Tests/**/*.swift", "Package.swift"]
---

## Formatting Is Decided by the Tool

**Impact: MEDIUM**

`swift format` and `.swift-format` are the style: four spaces, 110 columns,
ordered imports, lower camel case, no semicolons, no block comments, shorthand
type names. `make format` applies it; `make lint` checks it with `--strict`, so a
warning fails, over `Sources`, `Tests` and `Package.swift` — the same command CI
and the pre-commit hook run. There is no SwiftLint and no edit hook here, so run
`make lint` before handing over; it takes 0.2 s. Write the code the way the tool
leaves it rather than hand-formatting around it.

`NeverForceUnwrap`, `NeverUseForceTry` and `NeverUseImplicitlyUnwrappedOptionals`
are on, so a nil or a thrown error goes down the path the code already has for
failure — a `guard let` that throws `ScanError`, a `try` that propagates —
rather than crashing the app mid-scan. Where a value truly cannot be nil, say
why in a comment and put `// swift-format-ignore: NeverForceUnwrap` on the line
above it, as `ICCBackend.init` does for its device mask.

The formatter is the one in the active Xcode toolchain (6.3.0 with Xcode 26.6),
not a separate copy, and CI pins Xcode 26.6, so a local Xcode 26.6 lints
exactly as CI does. A finding one machine reports and the other does not
means the versions differ: compare
`swift format --version` before changing code to satisfy either.

**Incorrect:**

```swift
/* Otsu threshold */
import Vision
import CoreGraphics
```

**Correct:**

```swift
// Otsu threshold
import CoreGraphics
import Vision
```
