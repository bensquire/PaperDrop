---
title: Commit Messages Are Prose With the Measurements
impact: HIGH
impactDescription: The history is where the reasoning is kept
tags: [workflow, git, commits, history]
---

## Commit Messages Are Prose With the Measurements

**Impact: HIGH**

When told to commit, the message says what changed and why, in prose, with the
measurements that justified it — the scan or file, the figure before, the figure
after — and what was tried and taken out, if anything was. A decision that rests
on Apple's documentation names the page. One commit per change of meaning: work
that was already in the tree and is not part of the change goes in its own
commit, described honestly. End with the attribution lines the session
prescribes.

**Incorrect:**

```
Fix icon
```

**Correct:**

```
Losslessly halve the icns: oxipng'd iconset + direct repack

iconutil re-encodes PNGs when packing, so the container is rebuilt
directly (scripts/repack-icns.py): optimised PNG chunks, ic04/ic05 ARGB
kept verbatim, info plist dropped. Pixel-identical at every size;
128956 -> 60319 bytes.
```
