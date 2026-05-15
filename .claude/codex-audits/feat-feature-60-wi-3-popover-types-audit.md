---
branch: feat/feature-60-wi-3-popover-types
threadId: 019e2d7a-7159-7b70-a703-4a2ac399ea88
rounds: 3
final_verdict: ship-as-is
date: 2026-05-16
---

# Codex Gate 4 implementation audit — Feature #60 WI-3 (foundational popover types)

Per `.claude/rules/47-feature-workflow.md` Gate 4. Audit of the three
new value types lifted out of WI-4 (SelectionPopover) so the popover
view in later WIs is authored against a stable, audited surface.

## Scope

Branch: `feat/feature-60-wi-3-popover-types`

Files changed (all new):

- `vreader/Models/NamedHighlightColor.swift`
- `vreader/Models/SelectionPopoverAction.swift`
- `vreader/Models/AccentColor.swift`
- `vreaderTests/Models/NamedHighlightColorTests.swift`
- `vreaderTests/Models/SelectionPopoverActionTests.swift`
- `vreaderTests/Models/AccentColorTests.swift`

Plan reference: `dev-docs/plans/20260515-feature-60-visual-identity-v2.md`.

## Round 1 findings

Zero Critical / High / Medium. Three Low findings + one plan-doc drift note.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `vreaderTests/Models/NamedHighlightColorTests.swift:7` | Low | Header comment claimed the compatibility test "proves the storage boundary is preserved" but the test only exercises `from(storageString:)` on literals — does not touch `Highlight.color`, `HighlightRecord.color`, backup DTO encode/decode, or export/import DTOs. | **Reworded** the header to say the test pins decode behavior, not storage-boundary preservation. The storage guarantee lives in the design of those files (still raw `String`) and in Codex Gate 2 plan audit. |
| 2 | `vreaderTests/Models/NamedHighlightColorTests.swift:91` | Low | Detailed comment block above `compatibility_existingStorageStringsRemainValidAndUnaltered` over-claimed in the same way. | **Reworded** to "pin the decode contract of `from(storageString:)`", added an explicit caveat that schema narrowing is caught by Gate 2 plan audit, not this unit test. |
| 3 | `vreaderTests/Models/AccentColorTests.swift:17` | Low | Pins hex values but didn't pin enum exhaustiveness — a future fourth case wouldn't fail the existing tests. | **Added** `CaseIterable` conformance to `AccentColor` + two new tests: `allCases_containsExactlyThreeStops` and `exhaustiveSwitch_handlesEveryStop`. |
| — | `dev-docs/plans/20260515-feature-60-visual-identity-v2.md:257` | Note (non-blocking) | Plan doc still showed `NamedHighlightColor.yellow.hex == "#fff3a3"` — outdated against the design bundle (`#f0d25a`). | **Fixed** to `#f0d25a`, added the other three colors inline. |

## Round 2 findings

Zero Critical / High / Medium. One Low.

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `dev-docs/plans/20260515-feature-60-visual-identity-v2.md:261` | Low | WI-3 test-catalog bullet still described a compatibility test that round-trips through `Highlight.color = ... → fetch → from(storageString:)`. Actual test is decode-only. | **Reworded** to "Decode-contract pin" matching what the implementation does, with explicit caveat that storage-type narrowing is caught by Gate 2 plan audit. |

## Round 3 verification

Codex final verdict (quoted from thread `019e2d7a-7159-7b70-a703-4a2ac399ea88`):

> Gate 4 final verdict: clean. Zero open Critical/High/Medium findings,
> and no remaining Low findings in the audited WI-3 implementation
> files. The final plan wording now matches the implemented
> `NamedHighlightColor` test, the additive storage boundary remains
> intact, and the type/test surfaces are consistent with the revised
> plan v2.

## Cross-checks performed by Codex

- Hex drift: `SelectionPopover.colorMap` in `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx:441` matches `NamedHighlightColor` (`yellow #f0d25a`, `pink #e88ca0`, `green #8cc88c`, `blue #8cb4e8`).
- AccentColor stops match Feature #60's row in `docs/features.md:101` (`#8c2f2f` / `#d6885a` / `#e8b465`).
- Storage boundary preserved: `Highlight.color`, `HighlightRecord.color`, `BackupHighlight.color`, and `ExportedAnnotation.color` all remain raw `String` / `String?`.

## Test gate

```
xcodebuild test -only-testing:vreaderTests/NamedHighlightColorTests \
                -only-testing:vreaderTests/SelectionPopoverActionTests \
                -only-testing:vreaderTests/AccentColorTests
```

Result: 15 tests in 3 suites, all passing. ** TEST SUCCEEDED **

Broader `vreaderTests` suite shows pre-existing failures (BookFormatAZW3Tests = Bug #200; BookSourceHTTPClientTests + ReplacementTransformTests untouched by this diff) — none introduced by WI-3.

## Summary verdict

**Ship-as-is.** Gate 4 clean after 3 rounds; all Low findings closed with reworded test comments + plan doc, plus the AccentColor exhaustiveness pins. No code-correctness issues, no storage-boundary changes, no Swift 6 concurrency issues, no security surface.
