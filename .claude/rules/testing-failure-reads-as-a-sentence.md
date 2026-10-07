---
title: A Failure Reads as a Sentence
impact: MEDIUM
impactDescription: A bare comparison fails as a pair of numbers with no story
tags: [testing, assertions, messages, xctest]
paths: ["Tests/**/*.swift"]
---

## A Failure Reads as a Sentence

**Impact: MEDIUM**

An `XCTAssert…` carries a message that says what was measured and what it
should have been, unless the expression already says it (`XCTAssertNil(crop)`
on a blank page). In a loop or a table the message names the input.
`XCTUnwrap` for the thing the rest of the test cannot run without, with a
message saying what was missing. A helper that asserts on the caller's behalf
takes `file:` and `line:` so the failure lands on the test, not the helper.

**Incorrect:**

```swift
XCTAssertTrue(t > 20 && t <= 230)
XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 3)
```

**Correct:**

```swift
XCTAssertTrue(t > 20 && t <= 230, "threshold \(t) should fall between the ink (20) and the paper (230)")
XCTAssertEqual(mm(c.y1 - c.y0), 297, accuracy: 3, "height should snap to A4")
let c = try XCTUnwrap(crop, "a page with ink should have a crop")
```
