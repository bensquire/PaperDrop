---
title: The User's Pages Stay Here, and Nothing Is Overwritten
impact: HIGH
impactDescription: A scanner app that sends a page anywhere, overwrites a saved document or signals the wrong process has broken trust
tags: [quality, security, privacy, process, files, signing]
paths: ["Sources/**/*.swift", "bundle.sh", "scripts/**"]
---

## The User's Pages Stay Here, and Nothing Is Overwritten

**Impact: HIGH**

- **Nothing leaves the machine.** There is no network code and no telemetry;
  OCR is Vision, on the device. Network scanners are found and driven by
  ImageCaptureCore itself. A change that adds a network call or analytics needs
  a reason the user would accept, stated in the review.
- **Two child processes, named.** `scanimage` — the copy bundled in
  `Contents/Helpers`, else Homebrew's — and `/usr/sbin/ioreg`, each run by
  absolute URL with an argument array, never through a shell. The one process
  PaperDrop signals that is not its own is the Canon IJScanner2 driver, found by
  its `UsbExclusiveOwner` line in `ioreg` and sent SIGTERM; `USBReset`
  re-enumerates a device only when exactly one matches the scanner's name. A
  wider match or a new signal gets the same care, and a reason in the review.
- **Input is untrusted.** A scan comes from a device or a file: ImageIO decodes
  it, `G4.extractStream` checks the byte order, the compression, the strip count
  and that the strip lies inside the data before reading it, and
  `Pipeline.resolution(of:)` ignores a recorded dpi under 50.
- **Unsafe means justified.** `withUnsafeMutableBytes` and `nonisolated(unsafe)`
  appear where a comment says why every write is in bounds and disjoint
  (`Pipeline.processDocument`, the OCR workers in `AppModel.savePDF`). Nowhere
  else.
- **Output is written safely.** `Archive.destination` picks the first free
  "name.pdf", "name 2.pdf", …, and the write uses `.withoutOverwriting`; "/" and
  ":" in a title become "-" and leading dots are dropped, so a name can neither
  leave the folder nor hide. Scans in progress live in the temporary `PaperDrop`
  folder: each is deleted once processed, and the folder at launch.
- **Signed, hardened and notarised; not sandboxed.** `bundle.sh` signs every
  vendored Mach-O, then the app, with the hardened runtime and a timestamp, and
  passes no entitlements; `release.yml` notarises the app and the DMG.
  `Info.plist` says why the app writes to Documents. Adding the sandbox or an
  entitlement is the user's decision.

**Incorrect:**

```swift
try data.write(to: dir.appendingPathComponent(title + ".pdf"))   // overwrites; "a/b" leaves the folder
```

**Correct:**

```swift
let dest = Archive.destination(for: title, in: dir, untitledDate: now)
try data.write(to: dest, options: .withoutOverwriting)
```
