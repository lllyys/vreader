---
branch: fix/issue-456-auto-page-turn-unwired-in-epub
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex audit log — bug #156 / GH #456

## Audit context

Codex MCP recently disconnected on retries this session; manual mini-audit
per `/fix-issue` Phase 4f. The fix is small and well-contained (one new
`OptionSet` flag + one gating condition + capability assignments per
format), so manual audit is appropriate.

## Diff under audit

```
docs/bugs.md                                            |   2 +-
vreader/Models/FormatCapabilities.swift                 |  10 ++++++-
vreader/Views/Reader/ReaderSettingsPanel.swift          |  12 ++++++-
vreaderTests/Models/FormatCapabilitiesTests.swift       |  35 +++++++++++++++
```

## Per-dimension findings

### 1. Correctness

| Severity | Finding |
|---|---|
| — | None. The fix is the recommended cheap-path mitigation called out in the bug body: gate the `autoPageTurnSection` by capability so the toggle only renders for formats whose host wires `AutoPageTurner`. The capability is set only on TXT and MD (matching `grep -rln 'AutoPageTurner' vreader/`). EPUB / PDF / AZW3 do not get the flag, so the panel hides the section for those formats. |

### 2. Edge cases

| Severity | Finding | Resolution |
|---|---|---|
| — | `formatCapabilities` is `Optional` and tests/previews/legacy callers don't supply it. Default-true (`.contains(.autoPageTurn) ?? true`) preserves the section in those contexts so the existing test fixtures + previews stay green. Matches the `chineseConversionSupported` precedent at `ReaderSettingsPanel.swift:382` ("trust user preference" when caller doesn't supply caps). |
| — | The wrapping `if store.epubLayout == .paged` gate stays — auto-page-turn only makes sense when the user has chosen paginated mode, regardless of format. The `epubLayout` flag is overloaded across formats (TXT/MD's `isPagedMode` at `TXTReaderContainerView.swift:574` reads it too), so this gate is appropriate to keep. |
| — | The `pageTurnAnimationSection` (None/Slide/Cover) is intentionally NOT moved behind the new `.autoPageTurn` capability gate — it's used for manual page-turn animation by `NativeTextPagedView`, `MDReaderContainerView`, `UnifiedPagedView`, and `UnifiedTextRenderer`, which is a strict superset of the auto-turn-supporting hosts. Future work could capability-gate the animation picker too, but that's out of scope for this bug fix. |

### 3. Concurrency / Sendable

| Severity | Finding |
|---|---|
| — | `FormatCapabilities` is `OptionSet, Sendable, Hashable` — adding a new `static let` keeps all three. No actor crossings introduced. `formatCapabilities` flows through `ReaderSettingsPanel` as a value-type struct property; no mutability. |

### 4. Test coverage

| Severity | Finding |
|---|---|
| — | Added 5 new test cases / assertions to `FormatCapabilitiesTests.swift`: (a) TXT contains `.autoPageTurn`, (b) MD contains `.autoPageTurn`, (c) EPUB does NOT contain `.autoPageTurn`, (d) PDF does NOT contain `.autoPageTurn`, (e) AZW3 does NOT contain `.autoPageTurn`. Plus one regression-guard parameterized loop (`only_txt_and_md_supportAutoPageTurn`) that verifies the per-format expectations across `BookFormat.allCases` — forcing both the capability set AND the gating site to be updated together if a future format gains AutoPageTurner wiring. All 19 tests in the suite pass. |

### 5. SwiftUI reactivity

| Severity | Finding |
|---|---|
| — | `formatCapabilities` is a `let` property on the panel struct, captured at panel-creation time via `BookFormat(rawValue:)?.capabilities` in `ReaderContainerView.swift:261`. The conditional `if formatCapabilities?.contains(.autoPageTurn) ?? true { autoPageTurnSection }` evaluates once per body invocation; capability sets are immutable per book session, so no reactivity bug. |

### 6. vreader compliance

| Severity | Finding |
|---|---|
| — | Swift 6 strict concurrency: clean. File sizes: `ReaderSettingsPanel.swift` was already 400+ lines pre-fix; this fix adds 12 lines (8 of comment, 3 of code, 1 blank) — does not push the file into a new tier. `FormatCapabilities.swift` 82 → 90 lines. No DEBUG-only code added. No JS / WKWebView surface touched. |

### 7. Pre-FIXED simulator verification

Live verification on iPhone 17 Pro Sim (iOS 26.4, fix branch installed):

| Format | Open EPUB Layout = Paged | Auto Page Turn section | Result |
|---|---|---|---|
| EPUB (mini-epub3) | Paged selected | **HIDDEN** ✓ | PASS — the section between `None|Slide|Cover` and `Font Size` no longer contains the toggle |
| TXT (war-and-peace) | Paged selected | **VISIBLE** ✓ | PASS — toggle + interval slider + footer all render as before |

Screenshots:
- `/tmp/bug-156-fix/05-epub-page-turn.png` — EPUB settings: Page Turn Animation visible; Auto Page Turn HIDDEN; Font Size next.
- `/tmp/bug-156-fix/09-txt-auto-find.png` — TXT settings: Page Turn Animation visible; Auto Page Turn VISIBLE; Font Size next.

(Not committed as artifacts since this is a small UI capability gate; the screenshots are reproducible by anyone running the working-tree binary against the same fixtures.)

## Manual audit evidence (Phase 4f)

Per `.claude/rules/47-feature-workflow.md` manual-fallback rules:

**Files read**:
- `vreader/Models/FormatCapabilities.swift` (full)
- `vreader/Models/BookFormat.swift:36-37` (`capabilities` convenience property)
- `vreader/Views/Reader/ReaderSettingsPanel.swift:39-58, 246-275, 375-402` (body + autoPageTurnSection + capability-gating precedent)
- `vreader/Views/Reader/ReaderContainerView.swift:255-265` (call site that supplies `formatCapabilities`)
- `vreader/Views/Reader/TXTReaderContainerView.swift:573-575` (`isPagedMode` consumes `store.epubLayout`)
- `vreaderTests/Models/FormatCapabilitiesTests.swift` (existing test patterns + new assertions)

**Symbols / signatures verified**:
- `FormatCapabilities.autoPageTurn = FormatCapabilities(rawValue: 1 << 9)` — slot 9 is unused (slots 0-8 are pre-existing).
- `BookFormat.allCases` enumerates `.txt, .md, .epub, .pdf, .azw3` — all 5 covered by the regression-guard test.
- `formatCapabilities?.contains(.autoPageTurn) ?? true` — `Optional<FormatCapabilities>.contains(_:)` desugars to `.contains(member)` on the non-nil branch and `nil` propagates → `?? true` defaults to "show". Correct semantics for legacy callers.
- `xcodebuild test -only-testing:vreaderTests/FormatCapabilitiesTests` returns 19 tests passed (was 14 pre-fix).
- `xcodebuild build` returns BUILD SUCCEEDED with no warnings (other than the pre-existing "Run script build phase Inject DebugBridge URL types runs every build" notice).

**Edge cases checked**: see Dimensions 2 + 4 above.

**Risks accepted**:
- The proper fix (wire `AutoPageTurner` into EPUB / PDF / Foliate / Unified hosts) remains as feature-class follow-up. Not in scope for this bug; bug body explicitly says "stays open as feature-class follow-up." This commit ships the cheap mitigation only.

**Tests added**:
- 5 new `@expect` assertions on existing per-format tests (TXT/MD have `.autoPageTurn`; EPUB/PDF/AZW3 don't).
- 1 new regression-guard test `only_txt_and_md_supportAutoPageTurn` parameterized over `BookFormat.allCases`.
- Total new test methods: 1 (`azw3_doesNotSupportAutoPageTurn` and the regression-guard); existing test methods extended with new `#expect` calls.

**Tests intentionally deferred**:
- A SwiftUI `ViewInspector`-style test of the `autoPageTurnSection` rendering. ViewInspector isn't in the project, and the visual gate is best verified at the simulator level (which Phase 6a covers). The capability check that gates it is fully unit-tested.

## Verdict

**ship-as-is** — zero Critical/High/Medium findings. The fix is the
documented cheap-path mitigation; works as intended at the simulator
level; has unit-test regression coverage for the per-format capability
matrix.
