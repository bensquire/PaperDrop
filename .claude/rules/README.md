---
title: PaperDrop Rules Index
impact: LOW
impactDescription: About the rules themselves; loads only when a rule is being written
tags: [meta, rules]
paths: [".claude/rules/*.md"]
---

# PaperDrop Rules

Modular, machine-readable rules for working on PaperDrop. Each file is one rule,
named `{section}-{rule-name}.md`, with YAML frontmatter Claude Code reads: a rule
with `paths` loads only when a matching file is in play; one without applies
always. `_sections.md` defines the sections and their order; `_template.md` is the
shape of a new rule.

## Rules Index

### Workflow

- [workflow-challenge-the-rules](workflow-challenge-the-rules.md) - A rule in the way is raised with the user, not obeyed or broken in silence
- [workflow-no-commits-unless-told](workflow-no-commits-unless-told.md) - Never commit or push unless told to
- [workflow-hand-over-for-trial](workflow-hand-over-for-trial.md) - Bundle, relaunch, say what to scan and what to look at, stop
- [workflow-checking-work](workflow-checking-work.md) - Lint, the whole suite, the bundle when its layout moves, then a real scan
- [workflow-commit-messages](workflow-commit-messages.md) - Prose, with the measurements
- [workflow-diagnostics](workflow-diagnostics.md) - Env-gated to keep, separate file to throw away
- [workflow-todo-entries](workflow-todo-entries.md) - `ISSUES.md` entries are short, and say what was done

### Quality

- [quality-separation-of-concerns](quality-separation-of-concerns.md) - ScanKit knows no window; dependencies run one way
- [quality-dependency-injection](quality-dependency-injection.md) - Settings, dates and collaborators handed in as values
- [quality-readability](quality-readability.md) - Code reads like the prose around it
- [quality-consistency](quality-consistency.md) - Match the code around you; reuse the helper that exists
- [quality-extensible](quality-extensible.md) - Add a case and its behaviour, not an `if`
- [quality-performant](quality-performant.md) - Fast and lean where it counts, and measured
- [quality-secure](quality-secure.md) - Nothing leaves the machine; two named children; nothing overwritten
- [quality-comments-carry-measurements](quality-comments-carry-measurements.md) - Short, says why, carries the number or the doc path
- [quality-formatting-is-the-tools](quality-formatting-is-the-tools.md) - `swift format` decides; `make lint` before handing over
- [quality-images-minified](quality-images-minified.md) - The right container, lossless first, then lossy to the edge, judged at 1:1

### Testing

- [testing-arrange-act-assert](testing-arrange-act-assert.md) - Each step present, in order
- [testing-one-behaviour-per-test](testing-one-behaviour-per-test.md) - One behaviour, named as a sentence
- [testing-ground-truth-with-teeth](testing-ground-truth-with-teeth.md) - Judge in millimetres and in what a reader extracts; say what the alternative measures
- [testing-deterministic](testing-deterministic.md) - Generated fixtures, no scanner, no clock, no order
- [testing-fast](testing-fast.md) - Fast by paying only for what the test needs, never by seeing less
- [testing-failure-reads-as-a-sentence](testing-failure-reads-as-a-sentence.md) - Messages on every assertion

### Native

- [native-use-the-systems-feature](native-use-the-systems-feature.md) - ImageCaptureCore, Vision, ImageIO, the undo manager, SF Symbols
- [native-keyboard-and-menus](native-keyboard-and-menus.md) - The shortcuts every Mac user knows
- [native-small-bundle](native-small-bundle.md) - SANE is the bundle; nothing else grows it
- [native-check-apples-documentation](native-check-apples-documentation.md) - Look it up in `scrapple` before using, copying or asserting

### Communication

- [communication-plain-language](communication-plain-language.md) - ISO 24495-1: relevant, findable, understandable, usable
