---
branch: feat/feature-60-wi-2-theme-tokens
threadId: 019e2db2-e1e4-7b12-bbe4-f4b8855d8296
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 implementation audit — Feature #60 WI-2 (theme tokens)

Per `.claude/rules/47-feature-workflow.md` Gate 4. Audit of the
`ReaderThemeV2` 10-accessor surface (7 color tokens + 3 predicates)
plus its Codable migration alias for existing per-book persisted
theme choices.

## Scope

Branch: `feat/feature-60-wi-2-theme-tokens`

### Production source (1 file)

- `vreader/Models/ReaderThemeV2.swift` — new enum (paper / sepia /
  dark / oled / photo), 10 accessors, CaseIterable + Sendable, custom
  Codable decoder accepting both new names AND legacy `ReaderTheme`
  rawValues ("light" → `.paper`; "sepia" / "dark" preserved).
  Encoding always emits the new name. ~225 lines (under the 300-line
  guideline).

### Tests (2 files)

- `vreaderTests/Models/ReaderThemeV2Tests.swift` — 28 tests covering
  case set, default, raw-value semantic names, hand-picked per-token
  pins, the full 5×7 per-theme/per-token matrix (added round 2),
  boolean predicates, Sendable conformance, cross-theme background
  distinctness.
- `vreaderTests/Models/ReaderThemeMigrationTests.swift` — 10 tests:
  legacy `"light"` → `.paper`; legacy `"sepia"` / `"dark"` preserved;
  new-name round-trip across all 5 cases; encode always emits new
  name; byte-stable round-trip; one-way migration for legacy `"light"`;
  unknown / empty strings throw DecodingError.

## Round 1 findings

Zero Critical / High / Medium. Two Lows.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Models/ReaderThemeV2Tests.swift:48` | Low | Drift tests only pinned a subset of the per-theme/per-token grid. `chromeColor` was completely unpinned; most non-paper `backgroundColor` / `paperColor` / `inkColor` values were unchecked. A typo in an unexercised switch arm would have shipped unnoticed. | **Fixed.** Added `tokenMatrix_everyThemeEveryToken_matchesDesignBundle`: 35-row table (5 themes × 7 color tokens) byte-exact against `vreader-themes.jsx`. Sanity-bounded with `#expect(rows.count == 35)`. Per-row failure messages name theme + token + RGBA axis. |
| 2 | `vreader/Models/ReaderThemeV2.swift:2` | Low | Comments said "9-token surface" but the API has 10 accessors (7 colors + 3 predicates). Same wording also in test header. | **Fixed** in 3 places: file-header purpose, impl MARK, test-file purpose. Normalized to "10-accessor surface (7 color tokens + 3 predicates)". |

## Round 2 findings

Zero Critical / High / Medium. One residual Low.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreader/Models/ReaderThemeV2.swift:14` | Low | One inline comment ("this file extends with 9 tokens and 5") was missed in round-2's normalization. | **Fixed.** Changed to "this file extends with 10 accessors and 5" — now consistent across the whole file. |

## Round 3 verification

Codex final verdict (quoted from thread `019e2db2-e1e4-7b12-bbe4-f4b8855d8296`):

> Gate 4 passes cleanly. Zero open Critical/High/Medium/Low findings
> remain.
>
> Final verdict: WI-2 is audited and acceptable to ship as dormant
> foundational infra. The token surface, design-value pins, migration
> alias behavior, Sendable posture, and file-size guideline all
> check out.

## Cross-checks performed by Codex

- **Token drift**: implementation values match `vreader-themes.jsx`
  including Photo's alpha surfaces and OLED pure black.
- **Migration alias safety**: decoder accepts ONLY intended legacy/new
  names; preserves one-way `"light" → "paper"` migration; throws on
  unknown/empty strings rather than silently coercing.
- **Concurrency / file size**: 225 lines (under the 300-line
  guideline); enum is Sendable without mutable shared state.

## Intentionally deferred

`AccentContrastTests` from the plan's WI-2 test catalogue. The plan
specifies "accent vs `ink` ≥ 3.0 WCAG contrast", but a quick math
check on Paper theme yields contrast ~2.1 — the threshold conflicts
with the committed design tokens. Per rule 51 (no self-designed UI),
the threshold cannot be lowered or the design adjusted unilaterally
in a cron iteration. Filed as follow-up; Codex accepted the deferral
as appropriate for dormant foundational infra.

## Test gate

```
xcodebuild test -only-testing:vreaderTests/ReaderThemeV2Tests \
                -only-testing:vreaderTests/ReaderThemeMigrationTests
```

Result: 30 tests in 2 suites, all passing. ** TEST SUCCEEDED **

## Summary verdict

**Ship-as-is.** Gate 4 clean after 3 rounds. All findings closed.
WI-2 ships the `ReaderThemeV2` 10-accessor surface as audited
dormant foundational infra; the WI-4+ behavioral PRs will consume
this surface to migrate the reader engines to the v2 visual identity.
