---
title: A Change Is Checked, Not Believed
impact: CRITICAL
impactDescription: A 200 dpi request the LiDE 110 delivered at 150 dpi made an A4 page 162 × 200 mm
tags: [workflow, verification, tests, lint, bundle, scanner]
paths: ["Sources/**", "Tests/**", "Package.swift", "bundle.sh", "scripts/**"]
---

## A Change Is Checked, Not Believed

**Impact: CRITICAL**

Before saying a change is done:

1. **`make lint`** — `swift format lint --strict` over `Sources`, `Tests` and
   `Package.swift`, exactly as CI and the pre-commit hook run it. 0.2 s.
2. **`make test`**, the whole suite. `swift test` builds all three targets, so
   it also catches a compile error in the app or `scantool`; the 35 tests take
   about 5 s warm.
3. **The bundle**, for a change to `bundle.sh`, `scripts/vendor-sane.sh` or the
   bundled paths in `SANECLIBackend.swift`: `CODESIGN_IDENTITY=- ./bundle.sh`,
   then `scripts/vendor-sane.sh --verify`, as CI does. The three describe one
   layout.
4. **The real thing**, for anything touching scanning, the pipeline, OCR or the
   PDF: a page scanned in the relaunched app, or `swift run scantool [--sane]
   scan <dir> [dpi]` on the attached scanner; `swift run scantool process
   <scan.tiff> <out.pdf>` runs the pipeline alone on a saved scan and prints
   the page size, dpi, PDF size and time. Open the PDF in Preview and search
   it. Name the scanner and the backend.

Report what was run and what it showed. A check that was skipped is named as
skipped, not left out — "no scanner attached, so the scan was not tried" is a
result.

**Incorrect (one class, no lint, no real page):**

```
Ran PipelineTests; passes. Done.
```

**Correct:**

```
lint clean; 35 tests in 4.3 s; 200 dpi scan of an A4 letter on the LiDE 110
in the app: scanned at 150 dpi, page A4 210 × 297 mm (was 162 × 200).
```
