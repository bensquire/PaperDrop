---
title: Challenge a Rule When It Is in the Way
impact: CRITICAL
impactDescription: The rules serve the best system; a rule that blocks a better one is a defect to raise, not a wall to work around
tags: [workflow, rules, architecture, standards, judgement]
---

## Challenge a Rule When It Is in the Way

**Impact: CRITICAL**

These rules exist to make the best system, not to be obeyed for their own
sake. When following one would make the code, the architecture, a standard
or the product worse — or when a better way exists that a rule forbids —
raise it with the user, plainly: which rule, what it costs here, what the
alternative is, and what it would take. Then wait. Sometimes the answer is to
rearchitect, change a standard, or rewrite the rule.

Complying in silence and breaking the rule in silence both hide the decision,
so do neither. A rule the user has just confirmed stands.

**Incorrect (working under it in silence):**

```
testing-deterministic keeps scanners out of the suite, so I've left the
stale-address retry in SANECLIBackend.scan untested.
```

**Correct (the case made, the decision left with the user):**

```
testing-deterministic and the retry in SANECLIBackend.scan pull against each
other: the retry only runs when scanimage fails with "Invalid argument",
"Device busy" or an I/O error, and runAsync builds its Process privately, so
no test can cause that without a scanner. Pinning it means handing
SANECLIBackend a runner to call instead of Process — a seam the backend does
not have today. Want the seam, or keep the retry covered by scantool runs on
the LiDE 110?
```
