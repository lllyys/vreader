---
branch: fix/issue-598-txtchapterhighlight-suite-hang
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

## Context

Fix for bug #175 / GH #598. Codex MCP unavailable this session (every call returns `stream disconnected before completion`). Manual fallback per rule 47.

## Files in scope

- `vreader/Views/Reader/TXTReaderContainerView.swift` (single function rewritten, +8 / −4 lines, behaviour unchanged)
- `docs/bugs.md` (row #175 IN PROGRESS flip + root-cause note)

## Manual audit evidence

### Files read

- `vreader/Views/Reader/TXTReaderContainerView.swift` lines 594–626 (full function before + after).
- `vreader/Views/Reader/TXTChapterHighlightHelper.swift` (full — the underlying helper called from both branches).
- `vreaderTests/Views/Reader/TXTChapterHighlightRenderingTests.swift` (full — 5 `@Test` cases).

### Symbols / signatures verified

- `TXTReaderContainerView.chapterLocalHighlightRanges` signature unchanged: `(persistedGlobalRanges: [NSRange], tempGlobalRange: NSRange?, chapterIndex: Int, chapters: [TXTChapter]) -> (persisted: [NSRange], temp: NSRange?)`.
- `TXTChapterHighlightHelper.highlightsForChapter` returns `[NSRange]` (empty when index out-of-bounds, when chapter has no UTF-16 data, or when all ranges fall outside the chapter).
- `Array<NSRange>.first` returns `NSRange?`.
- Single caller at `TXTReaderContainerView.swift:537` (`chapterReaderContent` body) — its destructuring `let highlights = Self.chapterLocalHighlightRanges(...)` is unaffected by the internal rewrite.

### Behavioural equivalence

The two implementations are logically equivalent:

| Input case | Old (flatMap) | New (if let) |
|------------|---------------|---------------|
| `tempGlobalRange == nil` | flatMap on `.none` → `nil` (closure not run) | `else` branch → `nil` (closure not run) |
| `tempGlobalRange == .some(r)`, helper returns `[]` | flatMap on `.some(r)` → `.first` is nil → `nil` | `if let` → helper returns `[]` → `.first` is nil → `nil` |
| `tempGlobalRange == .some(r)`, helper returns `[a]` | flatMap → `.first` is `.some(a)` → `.some(a)` | `if let` → `.first` is `.some(a)` → `.some(a)` |

All 5 existing tests pass post-fix (target suite, 0.002s end-to-end). Full vreaderTests Swift Testing run reports **"Test run with 801 tests in 84 suites passed after 2.455 seconds"** — no regressions. XCTest flakes (AutoPageTurnerTests + TTSServiceSpeedControlTests) are pre-existing per bug #167's close-gate note, unrelated to this change.

### Per-dimension findings

**1. Correctness vs root cause.** The hang trigger is the combination of "static func on @MainActor-isolated SwiftUI View type" + "Swift Testing `@Suite struct` context" + "`Optional<NSRange>.flatMap` with non-nil input that calls a helper returning `[NSRange]` and projects `.first`." Empirically isolated by Probes 1–9 (XCTest works, pure flatMap works, direct helper call works, inlined body works — only the static-func call from Swift Testing hangs). Rewriting the `Optional.flatMap` pattern as an explicit `if let / else` removes the trigger. The fix targets the surfaced symptom (Swift Testing introspection of the flatMap path on a SwiftUI View static func) without changing observable behaviour.

**2. Edge cases.** All four enumerated input cases above produce identical output. `if let / else` is a complete dispatch — no fall-through risk.

**3. Security.** None — pure-arithmetic NSRange math. No JS, no user input, no network. N/A.

**4. Duplicate code.** None introduced.

**5. Dead code.** None.

**6. Shortcuts & patches.** The `if let` rewrite is the minimal change addressing the toolchain-level symptom. The root cause likely lives in Swift Testing's macro/introspection layer; reporting a Swift Testing bug upstream would be the long-term fix, but is out of scope for a single bug-cron iteration. The new code is conventional Swift — not a workaround masquerading as logic.

**7. VReader compliance.** Swift 6 concurrency unchanged (no actor isolation change). File-size budget: `TXTReaderContainerView.swift` is ~770 lines (well above the 300 guideline already, separate-WI concern; this fix adds +4 net lines and doesn't worsen the existing situation).

**8. Bridge safety.** Not bridge code. N/A.

### Edge cases checked

- Empty `persistedGlobalRanges` + non-nil `tempGlobalRange` outside chapter → returns `([], nil)` (this is the exact previously-hanging case from probe `c`).
- Non-empty `persistedGlobalRanges` + nil `tempGlobalRange` → returns `(filtered, nil)`.
- Both inputs filled, target chapter contains both → returns `(translated_persisted, translated_temp)`.
- Out-of-bounds `chapterIndex` (e.g. 5 with 3 chapters) → helper returns `[]` from the guard, function returns `([], nil)`.

### Risks accepted

- Underlying Swift Testing / SwiftUI View interaction bug is not fixed upstream — only the local trigger is removed. If another static func on a SwiftUI View hits the same pattern, the hang can recur. Filed only as a documentation note in the bug row's history; not a separate tracker entry.

### Tests added or intentionally deferred

- No new tests added. The existing `TXTChapterHighlightRenderingTests` suite (5 `@Test` cases) covers the exact behaviours; they were always logically correct but were prevented from running by the harness hang. Post-fix they pass in 0.002s.

## Verdict

**ship-as-is** (manual fallback, 1 round). Minimal-risk rewrite, behaviour-preserving, unblocks 5 tests + the full vreaderTests Swift Testing run.
