---
branch: feat/feature-48-wi-2-chapter-scroll-offset
threadId: 019e1bd6-a8ba-7ab1-a518-a8c2c640bbc8
rounds: 1
final_verdict: ship-as-is
date: 2026-05-12
---

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| TXTReaderContainerView.swift:578 | High | `chapterScrubberGlobalOffset` at `seekValue=1.0` returns `globalStart + textLength` == `chapterEnd`, which fails the half-open containment check in `chapterLocalScrollOffset` — scrubber dragged to 100% drops the target silently. | Fixed: clamped to `globalStart + min(Int(seekValue × length), length - 1)`; zero-length guard returns `globalStart`. 3 boundary tests added. |
| TXTTextViewBridge.swift:128 | Medium | `shouldScroll` caller passed `sourceChanged = textChanged || attrChanged || configChanged`, so config-only rebuilds (font/theme changes) re-arm scroll dedupe and could jump user back to a stale search/scrubber target. | Fixed: caller now passes `textChanged || attrChanged` (source identity only). 1 test added for config-only non-arm behavior. |
| TXTChapterScrollOffsetTests.swift:31 | Low | Tests missed: `seekValue=0.0/1.0`, `globalOffset==chapterEnd` (exclusive boundary), `globalOffset==chapterEnd-1` (last valid), zero-length chapter. | Fixed: 5 boundary tests added. |

## Round 2

Not required. Codex confirmed: "No findings in the updated scope."

## Summary verdict

All 3 findings fixed inline. High was a genuine boundary bug (seekValue=1.0 dropped silently). Medium was a scope issue (too broad a sourceChanged condition). Low was coverage gap. All 11 tests passing. ship-as-is.
