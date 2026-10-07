---
title: Use the System's Feature, Not a Copy of It
impact: HIGH
impactDescription: The OS version already handles accessibility, Dark Mode, localisation and next year's macOS
tags: [native, macos, swiftui, imagecapturecore, vision, imageio, sf-symbols]
paths: ["Sources/PaperDrop/**/*.swift", "Sources/ScanKit/**/*.swift"]
---

## Use the System's Feature, Not a Copy of It

**Impact: HIGH**

PaperDrop should feel like a Mac app Apple could have shipped: it behaves the
way the user's other apps behave, by using what macOS provides rather than
building a version of its own. Before writing a control, a panel, a picker or
an alert, ask whether the OS has one. It usually does.

- **Scanners** are ImageCaptureCore first: local devices and AirScan/eSCL
  network scanners, with no driver of ours.
- **Text recognition** is Vision, on the device; **encoding** is ImageIO — the
  G4 TIFF, the JPEG pages, the thumbnails.
- **Choosing the archive folder** is `fileImporter`; **showing the saved PDF**
  is `NSWorkspace.activateFileViewerSelecting`, so Finder does it.
- **Undoing** Remove Page and Discard Pages is the window's `UndoManager`, from
  the Edit menu, rather than a confirmation up front.
- **Settings** is a `Settings` scene with a grouped `Form`, System Settings' own
  look.
- **Icons** are SF Symbols, chosen for their meaning, at the system's sizes and
  weights.
- **Text, colour and spacing** are `Font` styles, semantic colours and standard
  control sizes. Nothing hard-coded that the system defines.
- **Accessibility** comes from the controls themselves, plus labels on
  icon-only buttons and Move Earlier and Move Later actions on each page for
  those who cannot drag.

Native is not generic: the page grid, the paper snapping and the PDF writer are
the app's own work. Two parts stand in for the system on purpose — the
hand-written `PDFWriter`, which embeds the G4 stream losslessly, and the bundled
SANE stack, which drives the USB scanners ImageCaptureCore no longer can. A
change to either is raised with the user first.

**Incorrect (a folder picker of our own):**

```swift
TextField("Archive folder", text: $model.archivePath)   // a path typed by hand
```

**Correct (the system's):**

```swift
Button("Choose…") { choosingFolder = true }
    .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder]) { … }
```
