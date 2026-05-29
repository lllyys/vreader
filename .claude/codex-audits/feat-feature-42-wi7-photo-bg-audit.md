---
branch: feat/feature-42-wi7-photo-bg
threadId: codex-exec-wi7-r1..r4
rounds: 4
final_verdict: ship-as-is
date: 2026-05-29
---

# Codex audit — feat/feature-42-wi7-photo-bg (Feature #42 WI-7 photo/custom-bg compositing)

Verdict: **ship-as-is** (round-4 confirm)

Driver: cc-suite `codex exec` (ChatGPT subscription, default model).

## Rounds
- **Round 1**: HIGH (stale WKUserScript resurrects transparency after live disable), MEDIUM (asymmetric applyTransparency false-path no-op), LOW (jsStringLiteral not fully general).
- **Round 2**: Medium + Low resolved. HIGH persisted (persistent WKUserScript re-fires on reused content-controller re-navigation).
- **Round 3**: round-2 HIGH partially fixed (live DOM), but NEW HIGH: seed-only-if-unset leaves a fresh navigator open stuck on a prior session's stale localStorage '0'.
- **Round 3+ fix**: localStorage = single source of truth, written authoritatively by Swift (`syncTransparentState` on every `locationDidChange` + `setTransparentBackground` on toggle); the only persistent user script is a READ-ONLY self-gating applier. CSS specificity raised to `html:root` so it wins regardless of source order; applier re-appends last.
- **Round 4 (confirm)**: ship-as-is. Both round-3 HIGHs resolved; no remaining Critical/High.

## Device verification (iPhone 17 Pro Sim, Readium flag ON)
- photo + custom-bg → `html` rgba(0,0,0,0), localStorage '1', image composites behind text.
- live→dark (no image) → `html` opaque rgb(0,0,0), localStorage '0'.
- live→photo again → `html` rgba(0,0,0,0), localStorage '1' (stale-storage + cascade-order both fixed).
- Screenshot: dev-docs/verification/artifacts/feature-42-wi7-photo-bg-readium-20260529.png
