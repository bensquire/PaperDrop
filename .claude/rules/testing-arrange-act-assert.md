---
title: Every Test Arranges, Acts and Asserts
impact: HIGH
impactDescription: A test with a step missing tests something other than it claims
tags: [testing, aaa, structure, xctest]
paths: ["Tests/**/*.swift"]
---

## Every Test Arranges, Acts and Asserts

**Impact: HIGH**

Every test has three steps, in this order, each present and identifiable, and
the file marks them `// Arrange`, `// Act`, `// Assert` — or
`// Arrange / Act / Assert` when one line is all three, as the table checks in
`PaperSizeNameTests` are:

1. **Arrange** — build the input. A synthetic bed from `makeGray`, a packed page
   from `makePage`, a temporary directory holding the files the test needs.
2. **Act** — the one call under test. One act per test where the design
   allows; a test that acts twice is two tests, or a test of the pair.
3. **Assert** — `XCTAssert…` against what the act produced; `XCTUnwrap` for
   the thing the rest cannot run without.

The steps need not be on separate lines, but a reader should be able to point at
the input, the call, and the check.

**Incorrect (the arrangement and the act hidden inside the assert; no act at all):**

```swift
XCTAssertEqual(Archive.destination(for: "Letter", in: dir).lastPathComponent, "Letter 3.pdf")

func test_paperSizes_listFourSizes() { XCTAssertEqual(Pipeline.paperSizesMM.count, 4) }
```

**Correct:**

```swift
// Arrange — "Letter.pdf" and "Letter 2.pdf" already exist
for name in ["Letter.pdf", "Letter 2.pdf"] {
    try Data().write(to: dir.appendingPathComponent(name))
}

// Act
let dest = Archive.destination(for: "Letter", in: dir)

// Assert
XCTAssertEqual(dest.lastPathComponent, "Letter 3.pdf")
```
