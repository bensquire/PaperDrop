---
title: Diagnostics Are Gated to Keep, Separate to Throw Away
impact: MEDIUM
impactDescription: A debug block woven into a backend has to be edited out of the backend
tags: [workflow, diagnostics, environment, scantool]
paths: ["Sources/**"]
---

## Diagnostics Are Gated to Keep, Separate to Throw Away

**Impact: MEDIUM**

Much of what an investigation needs already reports: `scantool` drives either
backend and the pipeline without the app and prints what it found and how long
it took, and when `scanimage` fails its own stderr comes back as the error text
(`runAsync`). A diagnostic worth keeping is gated behind an environment
variable — none exists yet; name one `PAPERDROP_…` — read once at the edge, in
`AppModel` or `scantool`'s `main.swift`, and handed to ScanKit as a value.
Diagnostics for one investigation go in a separate file, marked temporary, and
are deleted before handover, so stripping them never means editing
`SANECLIBackend` or `Pipeline` themselves.

**Incorrect (a dump inline in the scan path):**

```swift
// in SANECLIBackend.scanOnce, between the arguments and runAsync
if ProcessInfo.processInfo.environment["DEBUG_SANE"] != nil {
    print(args.joined(separator: " "))
}
```

**Correct (its own file, one call, one deletion):**

```swift
// Sources/scantool/Debug.swift — TEMPORARY, not for commit
func dumpCrop(_ page: Pipeline.ProcessedPage) { … }

// scantool/main.swift, after processDocument
dumpCrop(page)  // TEMPORARY
```
