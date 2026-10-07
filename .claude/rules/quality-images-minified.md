---
title: Every Image Is as Small as It Can Be Without Showing It
impact: MEDIUM
impactDescription: The app icon was 128,956 bytes before it was optimised and 60,319 after, pixel for pixel the same
tags: [quality, images, assets, size, png, icns]
paths: ["images/**", "icon/**", "README.md"]
---

## Every Image Is as Small as It Can Be Without Showing It

**Impact: MEDIUM**

An image that is *presentation* — the README's icon and screenshot, the app
icon — is minified to the highest degree that introduces no visible artefact.
In order:

1. **The right container.** A photograph is WebP (or JPEG); flat graphics,
   screenshots with text and icons are PNG.
2. **Lossless first.** `oxipng -o max --strip safe` for PNG; `jpegtran
   -optimize -progressive` for JPEG. Identical pixels, smaller file.
3. **Then lossy, to the edge.** `cwebp -q 90 -m 6` or JPEG quality 85–90.
   Lower until an artefact shows, then back up one step.
4. **Look.** Side by side with the original at 1:1, on the busiest region.

The app icon is drawn in code: `swift icon/makeicon.swift`, from the repo root,
writes `icon/PaperDrop.iconset`. After `oxipng` on the iconset,
`scripts/repack-icns.py icon/PaperDrop.icns icon/PaperDrop.iconset <out.icns>`
rebuilds the container directly, because `iconutil` re-encodes the PNGs and
throws the optimisation away.

Report the before and after sizes in the commit.

Test input is not presentation: the suite draws its images in code, and a scan
kept to check the pipeline is left exactly as the scanner wrote it — its
recorded dpi and its noise are what the pipeline is judged on.

**Incorrect:**

```
images/screenshot.png   (straight from screencapture, never run through oxipng)
```

**Correct:**

```
icon/PaperDrop.icns   60,319 bytes (was 128,956): oxipng'd iconset, repacked
by scripts/repack-icns.py; pixel-identical at every size
```
