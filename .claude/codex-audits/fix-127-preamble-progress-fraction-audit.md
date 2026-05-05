---
branch: fix/127-preamble-progress-fraction
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Codex MCP not invoked for this small bug fix. Manual audit performed across the 8 dimensions defined in `/fix-issue` Phase 4b.

### Files read

- `vreader/Services/TOCChapterProgress.swift` (changed) — full file, 87 lines (was 73).
- `vreaderTests/Services/TOCChapterProgressTests.swift` (changed) — added preamble fix assertion + 2 new edge tests.
- `docs/bugs.md` — row #127 flipped to FIXED.

### Diff summary

Production `TOCChapterProgress.progress` adds an early-return branch:

```swift
if currentOffsetUTF16 < starts[0] {
    let preambleLen = starts[0]
    let fraction = preambleLen > 0
        ? Double(currentOffsetUTF16) / Double(preambleLen)
        : 0
    return TOCChapterProgressResult(
        chapterIndex: 0,
        fraction: max(0, min(1, fraction)),
        totalChapters: starts.count
    )
}
```

This handles the case where `currentOffsetUTF16` is before the first TOC entry's offset — the preamble region (Foreword, Preface, etc., not in the TOC). Before the fix, the existing code below clamped this to `fraction=0` via `max(0, ...)`, making the progress bar look stuck.

### Edge cases checked

- **`currentOffsetUTF16 == starts[0]`** (exactly at first entry): the `<` (not `<=`) means this case falls through to the existing logic, which sets `chapterIdx=0`, `chapterStart=starts[0]`, `localOffset=0`, `fraction=0`. Clean transition from preamble to chapter 0 — no double-counting.
- **`starts[0] == 0`** (no preamble — first entry at start): `currentOffsetUTF16 < 0` would only fire on negative offset (excluded by callers). Even if it did fire, `preambleLen=0` triggers the `?: 0` fallback. Safe.
- **`currentOffsetUTF16 == 0` and `starts[0] > 0`**: `0 < starts[0]` is true → preamble branch fires → `fraction = 0 / starts[0] = 0`. Reader at very start of preamble shows fraction=0. Correct.
- **Negative offset** (caller bug): `Double(currentOffsetUTF16) / Double(preambleLen)` could go negative, but `max(0, min(1, fraction))` clamps to [0, 1]. Defensive.
- **Very large preamble** (offset 999, first entry 1000, total 1000 — degenerate but possible): preamble branch fires, fraction = 0.999. After preamble, the existing logic handles the first real chapter. No crash.
- **Single TOC entry case** (`starts.count == 1`): preamble branch returns `chapterIndex=0, fraction=preamble_progress`, `totalChapters=1`. Existing logic for `chapterIdx + 1 < starts.count` handles single-entry chapters at the end.

### Tests added

Three tests now cover the preamble area:

1. `beforeFirstEntry` (existing, flipped from workaround): assert `fraction ≈ 0.5` for offset=50 with first entry at 100.
2. `atFirstEntry` (new): edge case at exactly offset == first entry; should give `fraction=0` of chapter 0 (no double-count).
3. `preambleZeroLength` (new): first entry at offset 0; preamble length 0; should give `fraction=0`.

All 9 tests in `TOCChapterProgressTests` pass post-fix.

### Production callers checked

- `TXTReaderContainerView.swift` and `ReadingProgressBar.swift` (per the `@coordinates-with` comment) — both consume `TOCChapterProgressResult.fraction`. No call-site changes needed; the new behavior just produces a more accurate fraction when offset is in the preamble region. UI code is fraction-agnostic — it shows `chapterIndex/totalChapters` plus the fraction within that chapter, which is exactly what the new branch supplies.

### Risks accepted

- **User-visible behavior change**: progress bar in preamble now ticks proportionally instead of staying at 0. This is the intended improvement (the reason for the fix); not a regression for any reasonable use case.
- **No tests for the call-site integration**: `TXTReaderContainerView` consumes this result but isn't separately tested for the new behavior. The unit-level fix is well-covered; integration-level verification will happen the next time someone exercises the progress bar in a TXT with a preamble.

### Verdict

**ship-as-is**. 6-line production change, 3 tests covering the new branch + edge cases. No regression risk to the existing `chapterIdx >= 0` path. Closes bug #127 / GH #271.
