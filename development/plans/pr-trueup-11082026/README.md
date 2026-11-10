# PR true-up — 2026-11-08

This is the execution package for the stability-first release sequence. Its first deliverable is
`PR-trueup-11082026`, branched from `550755f6dffcf15852ae76c8b206fe27b6da6461`, released as
`v1.0.1` before any retained external PR. It freezes the existing WolkaraForever application UI,
introduces golden-evidence enforcement, and replaces rewriting-based integration with normal
merge-then-squash release work.

Read in this order: `SAFETY_CONTRACT.md`, `OPEN_PR_AUDIT.md`, `BASELINE_BLOCKER_2026-11-08.md`, `EXECUTION.md`,
`DOCS_AND_EVIDENCE.md`, then the applicable `PR-<number>.md` added to this directory during each
feature release. `NEXT_AGENT_PROMPT.md` is the authoritative continuation prompt;
`INDEPENDENT_REVIEW_PROMPT.md` is the separate audit instruction.

No product feature is intentionally changed by this policy release. The newly committed golden
images are evidence of existing fixture states, not a replacement design.
