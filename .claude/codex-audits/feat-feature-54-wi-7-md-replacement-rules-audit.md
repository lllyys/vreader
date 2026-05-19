---
branch: feat/feature-54-wi-7-md-replacement-rules
threadId: 019e3e21-77b3-7dd3-9ab6-abed85e4c495
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex audit — feature #54 WI-7 (content replacement rules in the native MD reader)

Gate-4 implementation audit of commit `301c82e` plus the follow-up
working-tree edits applied to resolve round-1 findings. WI-7 is the final
work item of feature #54.

## Scope audited

- `MDFileLoader.load` gains a `replacementRules: [ReplacementRuleDescriptor]`
  parameter (default `[]`); builds a transform chain over the decoded source
  text before `parser.parse` — `ReplacementTransform` first, then
  `SimpTradTransform`. An all-empty chain skips `TextMapper`.
- `MDReaderViewModel.open` forwards the new parameter.
- `MDReaderContainerView.task` fetches the enabled `ContentReplacementRule`
  rows scoped to the book and passes them to `open(...)`.
- New tests: `MDReaderReplacementRulesTests`.

## Round 1 — findings

**Medium — `MDReaderContainerView.fetchReplacementRules` filtered in memory**
The fetch used a bare `FetchDescriptor<ContentReplacementRule>` (no
predicate) and filtered `enabled && (scopeKey.isEmpty || scopeKey == bookKey)`
in Swift. Every Markdown open scaled with the full rule table, including
rows for unrelated books.

**Low #1 — Chinese-conversion composition test did not prove ordering**
`composesWithChineseConversion` used the rule `我的 → 你的`; `我的` is
unaffected by simp/trad, so the test still passed if the production chain
order were accidentally flipped.

**Low #2 — no test for the SwiftData fetch helper**
The new fetch logic (scope filter, `enabled` filter, nil-container
fallback) had no coverage — the test suite exercised only `MDFileLoader.load`.

No `Sendable` leak found: `ContentReplacementRule` instances stay inside the
detached fetch; only `[ReplacementRuleDescriptor]` (value type) crosses back.
No hidden MD offset/highlight/bookmark mismatch — MD locators/anchors are
built from rendered text, not source coordinates, so the documented
"rule change requires reopen" behavior is the only consequence.

## Round 1 fixes applied

- **Medium**: extracted the fetch into a new pure namespace
  `vreader/Services/MD/MDReplacementRuleFetcher.swift` (extraction also makes
  it unit-testable — resolves Low #2). The fetch now runs the filter in the
  `FetchDescriptor` `#Predicate`, not in memory. `MDReaderContainerView.task`
  calls `MDReplacementRuleFetcher.rules(...)`; the inline helper is deleted.
  - **Bug found while fixing**: SwiftData's `#Predicate` does NOT reliably
    translate `String.isEmpty` to the backing-store query — it silently
    matched zero rows, so global replacement rules (`scopeKey == ""`) would
    never apply in the MD reader. Fixed by comparing `scopeKey == ""`
    explicitly. This production defect was caught precisely because Low #2's
    fix added a SwiftData-backed test.
- **Low #1**: rewrote `composesWithChineseConversion` to use the simplified
  token `测试`; the rule matches the simplified form `测试 → 检测`. Chain order
  must be replacement-then-conversion (`测试→检测→檢測` matches; flipped
  `测试→測試` makes the rule miss). Five assertions only pass for the correct
  order.
- **Low #2**: new SwiftData-backed suite
  `vreaderTests/Services/MD/MDReplacementRuleFetcherTests.swift` (10 tests)
  against an in-memory SchemaV6 container: nil-container fallback,
  global/book/other-book scope selection, mixed-scope selection, disabled-row
  exclusion at fetch time, `order` sort, mapping fidelity, empty store, and
  the async wrapper path.

All 20 WI-7 tests pass; regression suites (`MDFileLoader`,
`MDReaderViewModel`, `ReplacementTransform`) green; full build succeeds.

## Round 2 — re-verification

Codex re-reviewed the working-tree fixes. Verdict: no remaining
Critical/High/Medium findings. The Medium is genuinely resolved (the fetch
filters at the store via the predicate). Both Lows are resolved (the
ordering test now proves chain order; the new SwiftData-backed suite covers
the fetch helper).

## Final verdict

**ship-as-is** — zero open Critical/High/Medium findings after 2 rounds.
