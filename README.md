# scantools

Scanning toolkit for the Canon CanoScan LiDE 110 on macOS, built on SANE
(`brew install sane-backends`) because Canon's driver is dead and Image
Capture barely works with it.

## Layout

- `engine/` — Python pipeline. Document scanning (`scandoc.py` and friends)
  is the original prototype, superseded by the Swift port in ScanKit (which
  has since gained multi-blob crop, ink-mass trimming, and layout-preserving
  placement the Python side lacks) — kept for CLI use, not maintained in
  lockstep. Photo stacking (`scanstack2.py`/`remerge.py`) is still canonical
  here; it has no Swift port yet.
  - `scandoc.py` — documents → compact 1-bit G4 PDF (~20 KB/page): Otsu
    threshold, bed-edge removal, despeckle, content-cluster crop, standard
    paper-size snap
  - `scanpage.py` / `makepdf.py` — single-page scan and PDF assembly
    (entry points used by the PaperDrop app)
  - `scanstack2.py` — photos → multi-pass 16-bit stack with sub-pixel
    alignment (noise ≈ ÷√N)
  - `remerge.py` — re-merge saved passes without rescanning
- `apps/PaperDrop/` — minimal SwiftUI document-archiver app

Setup: `python3 -m venv venv && ./venv/bin/pip install -r requirements.txt`

## Development

- `make test` — XCTest suite (AAA style, `test_subject_expectation` naming)
  over the ScanKit pipeline
- `make lint` / `make format` — Apple's toolchain-bundled `swift format`
  (config: `.swift-format`); no external tools required
- `make bundle` / `make release` — signed app bundle / notarized DMG
- Pre-commit hook runs lint + tests + Python compile check:
  `git config core.hooksPath .githooks` (already set locally)

## Scanner facts (LiDE 110 + SANE genesys, learned empirically)

| Resolution | Verdict |
|---|---|
| 75–300 | fine; ~20 s full bed |
| 600 | sweet spot for prints; 35 s |
| 1200 | best real quality; 93 s |
| 2400 | works but ~10 min; overkill for prints |
| 4800 | **broken**: 2× vertical stretch and 2× offset error; also horizontally interpolated |

Operational rules:

- **Always `--force-calibration`.** The calibration cache mis-applies and
  causes heavy RGB column striping.
- **Never kill a scan mid-pass.** It wedges the scanner (dark, striped,
  geometry-broken output) until a USB power-cycle (unplug/replug — it is
  USB-powered).
- The carriage pauses mid-scan while USB buffers drain at high dpi —
  stop-and-go is normal, not a hang.
- Between-pass registration offsets are real: sub-pixel vertically, and
  occasionally quantised jumps (±32/±64 px at 2400 dpi) from calibration
  cropping. The stacker measures and corrects them (cap: 30 px).
- 16-bit output is genuine (`--depth 16`); mode list is Color/Gray only,
  no hardware lineart, no exposure control (so HDR multi-exposure is out;
  multi-pass averaging is the available trick).
