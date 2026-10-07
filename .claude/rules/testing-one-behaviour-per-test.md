---
title: One Behaviour Per Test, Named as a Sentence
impact: HIGH
impactDescription: A test of several things fails for one and hides the rest
tags: [testing, naming, scope, xctest]
paths: ["Tests/**/*.swift"]
---

## One Behaviour Per Test, Named as a Sentence

**Impact: HIGH**

A test pins one behaviour, and its name says which, as `test_subject_behaviour`
that reads in the report: `test_contentCrop_prefersA4OverLetterForShortContent`,
`test_cleanComponents_keepsAFullStopAt150dpi`,
`test_destination_neverReusesAnExistingName`. A name with "and" that lists
unrelated checks is usually two tests; one whose "and" describes one observable
outcome is fine — `test_merge_prefersTheSANETwinAndKeepsOtherSuffixes` checks a
single merged list. When the same behaviour is asked of several inputs, check
them in one test with the input in every message, rather than copy the test.

Test the behaviour, not the implementation: where the crop lands in
millimetres, what a PDF reader extracts, which file name is picked — not which
private function ran. Code that talks to a scanner or to Vision keeps its
decisions in small functions the tests reach with `@testable`:
`SANECLIBackend.parseDeviceList` reads `scanimage`'s output with no scanner, and
`OCR.recognitionLanguages` picks languages with no Vision request. A new
decision inside a backend gets the same treatment.

**Incorrect:**

```swift
func test_pipelineWorks() {
    // thresholds, cleans, crops, snaps and encodes one bed, asserting on each
}
```

**Correct:**

```swift
func test_cleanComponents_removesBorderTouchingInk() { … }
func test_contentCrop_snapsContentWiderThanA4ToLetter() throws { … }
func test_parseDeviceList_readsDeviceAndModelPerLine() { … }
```
