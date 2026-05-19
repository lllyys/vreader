---
branch: fix/issue-957-replacement-rules-banner-stale-reading-mode
threadId: 019e4281-974b-7f83-82f2-63895f55dc89
rounds: 2
final_verdict: ship-as-is
date: 2026-05-20
---

# Codex Gate-4 audit — fix/issue-957 (Bug #231 / GH #957)

Bug summary: `ReplacementRulesView.nativeModeBannerText` still pointed
users at the Reading Mode picker that feature #54 removed (WI-4) and
claimed rules apply "only when reading in Unified mode" — a stale
premise after WI-7 wired replacement rules into the native Markdown
reader. Fix rewrites the banner to state post-#54 reality and updates
`ReplacementRulesViewBannerTests` in lockstep.

Diff scope (3 files):

- `vreader/Views/Settings/ReplacementRulesView.swift` — `nativeModeBannerText` rewritten + lead doc + inline comments updated.
- `vreaderTests/Views/Settings/ReplacementRulesViewBannerTests.swift` — assertions rewritten to pin post-#54 truth table.
- `docs/bugs.md` — row 231 status TODO → IN PROGRESS (then FIXED in this PR's pre-FIXED verify step).

## Round 1 — `019e4281-974b-7f83-82f2-63895f55dc89`

| file:line | severity | issue | resolution |
|---|---|---|---|
| `vreaderTests/Views/Settings/ReplacementRulesViewBannerTests.swift:33` | Low | The rewritten banner copy is factually aligned with post-#54 reality, but the new tests only pinned `Markdown`/`MD` presence, absence of `Unified mode`/`Reading Mode`, and presence of `TXT`. EPUB / AZW3 pending-support claims and PDF unsupported claim were unguarded, so a future drift could silently produce an incomplete or misleading banner and still pass. The `MD` substring fallback was weaker than the comment implied — could pass on an unrelated `MD` token without naming Markdown to users. | **Fixed.** Dropped the `MD` OR-fallback, kept "Markdown" by name. Added `bannerText_namesPendingFormats_EPUB_AZW3_TXT` (pins EPUB + AZW3 + TXT). Added `bannerText_namesPDFAsUnsupported` (pins both "PDF" and "not supported"). |

Round-1 verdict: 1 Low finding, fix applied in round 2.

## Round 2 — verify

| file:line | severity | issue | resolution |
|---|---|---|---|
| — | — | — | — |

Round-2 verdict: **zero findings, ship-as-is**.

Codex also confirmed:
- Banner substance matches the codebase + docs: `MDFileLoader` does
  wire the transform chain; EPUB / AZW3 / TXT replacement-rule wiring
  remains deferred (feature #54 plan §4 Phase D + feature #42).
- The `Reading Mode` and `Unified mode` negative assertions are the
  right trip-wires for the stale guidance.
- Renaming the Swift Testing suite name from `(bug #128 / GH #275)`
  to `(bug #231 / GH #957)` is safe — no CI / dashboard depends on
  the old suite name (repo-local check).
- Rule 51 (no self-designed UI) is not a blocker: this is an
  existing-surface text correction, in scope for the
  "Existing-surface bug fixes that restore broken UI back to its
  designed state" carve-out.
- The `not supported` substring assertion is intentionally strict — a
  future copy change to `unsupported` would be a legitimate
  lockstep-update event, not gratuitous brittleness.
- No localization concern: the banner is a hard-coded English
  `static let`, not `NSLocalizedString`, so English substring
  assertions are consistent with the implementation.
- File sizes within convention: source 238 lines, tests 107 lines.

## Summary verdict

`ship-as-is` after 2 audit rounds. One round-1 Low finding (test
under-assertion) fixed by tightening the truth-table coverage; round-2
clean.
