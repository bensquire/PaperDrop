---
title: Add a Case and Its Behaviour, Not an `if`
impact: HIGH
impactDescription: A special case on shared code is a band-aid the next change tears off
tags: [quality, extensibility, altitude, design]
paths: ["Sources/**/*.swift"]
---

## Add a Case and Its Behaviour, Not an `if`

**Impact: HIGH**

The places the app grows have a single mechanism behind them. A scanner backend
is a type that conforms to `ScannerBackend` — discover, capabilities, scan,
cancel — not a branch in `AppModel`. A kind of page is a `PDFWriter.Content`
case that carries its own size and is written by its own arm of the `switch`
in `PDFWriter.build`: `.g4` as a CCITTFaxDecode image, `.jpegGray` as DCTDecode.
A paper size is a row in `Pipeline.paperSizesMM` (a snap candidate and a name)
or `photoSizesMM` (a name and a toolbar choice, never snapped to). `ScanMode`
is `CaseIterable` so whatever lists the modes needs no telling. Adding one of
these means adding the case and its behaviour — not an `if` for the new one.

When a change wants a special case on shared code, the fix is usually one level
deeper: make the shared mechanism carry what the case needs. A forced paper size
and an automatic snap both place their page through `Pipeline.paperCrop`, so
the placement policy has one home rather than an `if fixedMM` in two places.

**Incorrect (the writer guessing the kind of page from other fields):**

```swift
let isPhoto = page.ocrWords.isEmpty && page.dpi < 300   // then a second image path
```

**Correct (the case carries what it needs through the one mechanism):**

```swift
switch page.content {
case let .g4(stream): …                  // CCITTFaxDecode
case let .jpegGray(data, _, _): …        // DCTDecode
}
```
