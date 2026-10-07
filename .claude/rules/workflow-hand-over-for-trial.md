---
title: Hand Work Over for the User to Try
impact: CRITICAL
impactDescription: The user judges a feature in the app, on a scanner, not in a report
tags: [workflow, handover, bundle, app, scanner]
---

## Hand Work Over for the User to Try

**Impact: CRITICAL**

When a change the user can see in the app is done and checked, put it in front
of them there. A change that only `scantool`, the tests, the rules or the docs
show is handed over as what it is: the command to run, the suite's result, the
file to read.

1. `make bundle`, so `PaperDrop.app` carries the change. It signs with the
   Developer ID identity and a timestamp; `CODESIGN_IDENTITY=- ./bundle.sh`
   signs ad hoc where that identity is not available.
2. Relaunch it: `pkill -x PaperDrop; open PaperDrop.app`. Scanned pages do not
   survive a relaunch — the work folder is cleared at launch — so a relaunch is
   a clean start. Eight settings persist in `UserDefaults` under
   `com.bensquire.paperdrop`: the default resolution, Document or Photo mode,
   OCR, paper snapping, uniform page size, the paper choice and its
   orientation, and the archive folder. Say which the trial assumes.
3. Say what to scan, on which scanner and backend, what to look at, and what the
   figures were. A saved PDF lands in the archive folder (`~/Documents/Scans`
   by default) and Finder shows it.
4. Stop.

**Incorrect (declaring done from the command line):**

```
The suite passes and scantool process gives an A4 page. Done.
```

**Correct (the app relaunched, the eye pointed):**

```
Rebuilt and relaunched. On the LiDE 110, scan an A4 page at 200 dpi: the
status bar should end "A4 (scanned at 150 dpi)", and the saved PDF should be
A4, not 162 × 200 mm as before.
```
