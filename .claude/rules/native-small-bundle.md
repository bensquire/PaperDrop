---
title: Small, Because SANE Is the Only Weight
impact: MEDIUM
impactDescription: The app is 22 MB and 21 MB of it is the SANE stack; growth anywhere else is a signal
tags: [native, macos, bundle, dependencies, size, sane]
paths: ["Package.swift", "bundle.sh", "scripts/vendor-sane.sh", "Sources/**"]
---

## Small, Because SANE Is the Only Weight

**Impact: MEDIUM**

`PaperDrop.app` is 22 MB (`du -sh`, 6 October 2026): 21 MB is the vendored SANE
stack — `scanimage`, 11 dylibs and all 85 backends — and the app's own binary is
452 KB after `strip`. The package has no third-party Swift dependency and the
app embeds no framework of its own; the rest is the system's — ImageCaptureCore,
Vision, ImageIO, IOUSBHost, SwiftUI. That is a consequence of using the system's
features and a check on it: a feature that arrives with a package, a second
helper binary, or a bitmap catalogue for what SF Symbols already say is a sign
the wrong path was taken. The SANE stack ships whole on purpose, so a legacy USB
scanner works with no installs; trimming backends is the user's decision, not a
size fix. Check `du -sh PaperDrop.app` after `make bundle`; growth needs a
reason.

**Incorrect:**

```swift
// Package.swift
.package(url: "https://github.com/…/SomePDFKit", from: "2.0.0")   // for what PDFWriter already does
```

**Correct:**

```swift
import Vision   // already on every Mac
```
