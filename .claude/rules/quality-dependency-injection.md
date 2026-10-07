---
title: Dependencies and Settings Are Handed In as Values
impact: HIGH
impactDescription: Code that reaches for a global, the clock or the machine's settings cannot be tested, varied or reused without them
tags: [quality, dependency-injection, values, testability]
paths: ["Sources/**/*.swift", "Tests/**/*.swift"]
---

## Dependencies and Settings Are Handed In as Values

**Impact: HIGH**

A type or function takes its collaborators and its settings as values, and
whoever calls it hands them in. `ScanConfig` carries the resolution, mode and
area to a backend; `Pipeline.processDocument` takes the dpi, the snap slack and
any forced paper size; `Archive.defaultTitle(for:)` takes the date and
`Archive.destination(for:in:untitledDate:)` the folder and the date an
untitled document is named for; `OCR.recognitionLanguages` takes the
user's languages and Vision's, and `OCR.recognize` is what reads
`Locale.preferredLanguages`. A backend is a `ScannerBackend`, chosen by whoever
holds it — `AppModel.backend(for:)`, `scantool`'s `--sane`. The surroundings are
read once, at the edge or at construction: `AppModel` reads its settings from
`UserDefaults` at launch, and `SANECLIBackend.init` finds `scanimage` and builds
its environment. Tests hand in a fixed date, a temporary directory, a list of
languages.

When a knob is added, it is added once — on the type that uses it — and reached
through the value that carries that type, not mirrored on every caller. Paper
sizes live in `Pipeline.paperSizesMM` and `photoSizesMM`; `AppModel.fixedPapers`
is derived from them.

**Incorrect (a setting and the clock read inside the engine):**

```swift
// in Pipeline.contentCrop
let slack = UserDefaults.standard.bool(forKey: "paperSnap") ? 25.0 : 0
// in Archive
let title = "Scan " + formatter.string(from: Date())
```

**Correct:**

```swift
Pipeline.processDocument(gray, dpi: dpi, snapSlackMM: snap ? 25 : 0, fixedMM: fixed)
Archive.defaultTitle(for: date)   // the test hands in 2026-10-04 08:45:12
```
