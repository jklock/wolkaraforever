# Source-built enablement

> Verified: 2026-11-21 · Source: `8375cbb` · Proof: current execution-mode source review

Keep this item only while source-built execution needs work beyond the supported Developer-service route: a direct Xcode build sets no `TOLKARA_MODE`, so its first launch asks, and the mode behind it must be available in that build. Any change must preserve the no-game-code-signing boundary and test the exact enabled path.
