---
name: build
description: Build, test, lint and bundle PaperDrop — the SwiftPM package that holds the ScanKit engine, the SwiftUI app and the scantool CLI, with the SANE scanner stack vendored into the app — and what the release path does. Use when building the app or scantool, running the suite or one test, linting or formatting, bundling PaperDrop.app for a trial, re-vendoring SANE, or asked how a release is cut.
---

# Building PaperDrop

PaperDrop is a SwiftPM package (`Package.swift`, tools 5.9, macOS 26): the `ScanKit`
library, the `PaperDrop` app, the `scantool` CLI and the `ScanKitTests` XCTest target.
There is no Xcode project and no third-party Swift package. The `Makefile` holds the
everyday commands; `bundle.sh` turns the release build into `PaperDrop.app`.

## Prerequisites

- Xcode 26 with the macOS 26 SDK (measured here with Xcode 26.6, Swift 6.3.3). The
  tests are built for macOS 26 and run only there. `swift format` ships with the
  toolchain (6.3.0 here), so linting needs nothing else.
- For the bundle: Homebrew's `sane-backends`. When `Vendor/sane` is missing,
  `bundle.sh` runs `scripts/vendor-sane.sh`, which copies `scanimage`, libsane and
  every backend from `/opt/homebrew/opt/sane-backends` into `Vendor/sane` and
  rewrites their install names to `@rpath`. `Vendor/` is git-ignored.
- A connected scanner, for anything that scans. Nothing in the suite needs one.

## Commands

| Command | What it does |
|---|---|
| `swift build` | Debug build of all three targets into `.build/debug/`. 12 s from empty; about a second when nothing changed. |
| `make test` | `swift test`. It builds every target — the app and `scantool` too, so a compile error anywhere fails it — and runs the 35 XCTest cases: 4.3 s of tests, about 6 s warm, 20 s from empty. |
| `swift test --filter ContentCropTests` | One test class. `--filter ArchiveTests/test_destination_neverReusesAnExistingName` runs one test. Under a second warm. |
| `make lint` | `swift format lint --strict --recursive Sources Tests Package.swift`: the style in `.swift-format` (4 spaces, 110 columns), with warnings failing. 0.2 s. |
| `make format` | The same tool, rewriting in place. |
| `swift run scantool help` | The headless harness. `list`, `caps` and `scan <dir> [dpi] [bw\|gray\|color]` drive a real scanner (ImageCaptureCore by default; `--sane` for SANE, which outside the app means Homebrew's `scanimage`); `process <in.tiff> <out.pdf> [dpi] [WxH] [fixed:WxH]` runs the document pipeline, OCR and PDF writer on a saved scan and prints the page size, dpi, PDF size and time; `usbreset [tokens]` re-enumerates a real USB device, as unplugging it would. |
| `make bundle` | `./bundle.sh`: vendors SANE if needed, builds with `-c release -Xswiftc -Osize` (12 s from empty), assembles `PaperDrop.app` — the stripped binary, the icon, `scanimage` in `Contents/Helpers`, the dylibs and backends in `Contents/Frameworks`, `sane.d`, the licences and `Credits.html` in `Resources`, a generated `Info.plist` — then signs every vendored Mach-O and the app with the hardened runtime and a timestamp. |
| `open PaperDrop.app` | Launch the bundle. Quit a running copy first: `pkill -x PaperDrop`. |
| `scripts/vendor-sane.sh --verify` | Checks that every library reference in `Vendor/sane` resolves inside the tree, as CI does after bundling. |
| `make clean` | `swift package clean`, then removes `PaperDrop.app`, `PaperDrop.dmg` and `Vendor/`, so the next bundle vendors SANE from Homebrew again. |

`bundle.sh` signs with the Developer ID identity in the login keychain by default, and
`--timestamp` makes a round trip to Apple's timestamp server. `CODESIGN_IDENTITY=-
./bundle.sh` signs ad hoc, as CI's smoke bundle does; `VERSION=x.y.z` sets the
marketing version (default 0.1.0). The bundle is 22 MB, 21 MB of it the SANE stack.

The `Contents/Helpers`, `Frameworks` and `Resources` layout `bundle.sh` writes is
also written into `SANECLIBackend.swift` (the bundled `scanimage` and its
`SANE_CONFIG_DIR` and `LD_LIBRARY_PATH`) and checked by CI's verify step. A change to
one is a change to all three.

## What CI checks

`.github/workflows/ci.yml` runs on pushes to `main` and on pull requests: macOS 26
with Xcode 26.6 pinned, `brew install sane-backends`, `make lint`, `make test`,
an ad-hoc `./bundle.sh`, then `scripts/vendor-sane.sh --verify` and a check that
`Contents/Helpers/scanimage` is executable. Runs take 1.3–2.1 minutes and are stopped
at 10. `make lint && make test` is the local equivalent of everything but the bundle.
CI's `swift format` is whichever ships with its Xcode, so a lint result that differs
from yours means the versions differ (`swift format --version`).

`.githooks/pre-commit` runs `make lint`, then `make test`. It is on in a clone where
`git config core.hooksPath .githooks` has been set.

## Release

Run only when the user asks.

- `make release` runs `release.sh`: `bundle.sh` with the Developer ID identity,
  `scripts/make-dmg.sh` to stage `PaperDrop.dmg` (the app beside an Applications
  link), then notarization and stapling through the `paperdrop` keychain profile when
  one is stored. Without it, the DMG is built and the script says it is not notarized.
- Pushing a `v*` tag runs `.github/workflows/release.yml`: lint and test, sign with
  the Developer ID certificate from repository secrets, notarize and staple the app,
  build, sign, notarize and staple `dist/PaperDrop-<version>.dmg`, then publish a
  GitHub Release whose notes name the bundled SANE version. A version with a hyphen
  is published as a prerelease.

## When it fails

- `make bundle` stops at `codesign` on a Mac without the Developer ID identity: use
  `CODESIGN_IDENTITY=- ./bundle.sh`.
- `bundle.sh` stops in `scripts/vendor-sane.sh` when `Vendor/sane` is gone and
  Homebrew has no `sane-backends`: `brew install sane-backends`, then bundle again.
