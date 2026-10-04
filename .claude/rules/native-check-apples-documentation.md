---
title: Check Apple's Documentation Before Using Its API
impact: HIGH
impactDescription: A guessed signature compiles by luck; a copied feature is one the OS already had
tags: [native, documentation, scrapple, apple, hig, wwdc]
paths: ["Sources/**/*.swift"]
---

## Check Apple's Documentation Before Using Its API

**Impact: HIGH**

Before using a system API you are not certain of, before building anything the
system might already provide, and before stating a platform convention as fact,
look it up. `scrapple` holds Apple's framework documentation, WWDC transcripts
and sample code offline — not the Human Interface Guidelines, whose conventions
are in the design talks; the `apple-docs` skill says how to ask it. A symbol
name is the best query. A decision that rests on what a page says carries the
page's path in a one-line comment, so the next reader can check it too. A doc
that contradicts a deliberate design choice is raised with the user, not
followed or ignored in silence.

**Incorrect (guessed: the delegate method's name and threading, from memory):**

```swift
func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) { … }   // called on which thread?
```

**Correct (looked up, and named):**

```sh
scrapple search "ICScannerDeviceDelegate didScanTo" --type doc --limit 3 --human
```

```swift
// /documentation/imagecapturecore/icscannerdevicedelegate/scannerdevice(_:didscanto:)-10whl
func scannerDevice(_ scanner: ICScannerDevice, didScanTo url: URL) { … }
```

Reference: `scrapple` (github.com/searlsco/scrapple); Apple Developer Documentation.
