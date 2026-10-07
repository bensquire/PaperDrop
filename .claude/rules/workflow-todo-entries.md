---
title: An Issue Entry Is Short, and Says What Was Done
impact: MEDIUM
impactDescription: The issue list is for scanning; the reasoning lives in the commit
tags: [workflow, issues, todo, planning]
paths: ["ISSUES.md"]
---

## An Issue Entry Is Short, and Says What Was Done

**Impact: MEDIUM**

The list of what is wrong or left is `ISSUES.md` at the repo root, the user's
local tracker; it stays out of commits unless they say otherwise. Its header
states its shape, and entries keep to it: sections by kind of finding, ordered
by severity within each; one checkbox per issue with a bold one-sentence title;
**confirmed** when it was reproduced on hardware rather than read from the code;
the evidence in a sentence or two, with its figure where it has one. A ticked
entry carries a one-line *Fixed:* note naming what changed; an open one says why
it is still open. An issue is listed once, in the section for its kind.

The reasoning — what was measured, what was tried, why it was taken out —
lives in the commit that did it and the code that carries it. A figure that
sets the bar belongs in the entry (`162 × 200 mm`); a paragraph does not.

**Incorrect:**

```
- [x] **Saving overwrites files.** Looked at how Data.write behaves … tried
  three approaches … (three paragraphs on atomic writes and Finder naming)
```

**Correct:**

```
- [x] **Saving overwrites an existing PDF without warning.** *Fixed:
  `Archive.destination` picks "name 2.pdf", … and the write uses
  `.withoutOverwriting`; "/" and ":" in names become "-".*
```
