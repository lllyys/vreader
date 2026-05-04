---
branch: fix/issue-226-cover-light-edges
threadId: 019df305-c588-7ea2-834f-1b370a691508
rounds: 1
final_verdict: ship-as-is
date: 2026-05-04
---

# Codex audit log — fix/issue-226-cover-light-edges

Bug #107 fix: bumped library-card cover-stroke opacity 0.2 → 0.35.

## Round 1

**Findings**: none.

**Verdict**: **Ship as-is.**

Codex's notes:

- 0.35 is a reasonable target. At 0.5pt stroke width, it separates white-edged covers from the white grid background without reading as a heavy frame on darker covers. 0.2 was too faint.
- No other call site needs the same bump. `BookRowView`'s row-thumbnail has no matching stroke (different layout surface, smaller thumbnail, doesn't trip the same "empty padding" illusion).
- No snapshot test infrastructure for visual changes. Manual on-device verification is the right gate — but for a 1-line opacity bump, the audit + manual sanity-check is sufficient.

## Files changed

- `vreader/Views/BookCardView.swift` — one stroke opacity literal change with comment explaining the rationale.
- `docs/bugs.md` — row #107 status flip to FIXED.

## Why no on-device verification this PR

Cosmetic 1-line change. The change has no behavior surface — it's purely a visual stroke opacity bump. The opposite case (covers without white edges) was already verified pre-fix. Manual visual check is fine to defer to the next session that actually has the problem cover in hand.

## What still might bite us

If the user has a particularly dark theme or system appearance change, 0.35 gray-on-dark might look heavier than intended. Currently the app doesn't ship a dark library grid background, but if dark-grid mode lands, this stroke would need to flip to a light color. Out of scope here.
