---
branch: feat/feature-42-wi8-new-highlight
threadId: codex-exec-wi8-r1-r2
rounds: 2
final_verdict: ship-as-is
date: 2026-05-29
---

# Gate-4 audit — Feature #42 WI-8 refinement (create highlight from a Readium text selection)

Independent auditor: Codex (`codex exec --sandbox read-only`). Author/auditor
separation preserved (separate process).

## Round 1 — follow-up-recommended

| Severity | Issue | Resolution |
|---|---|---|
| Medium | `ReadiumReaderCoordinator.navigator(_:shouldShowMenuForSelection:)` returned `true`, so Readium's native edit menu showed *on top of* the designed `SelectionPopoverView` — overlapping/undesigned UI (rule 51 concern). | Fixed (commit ed49e777): returns `false` — the selection is forwarded via `onSelection?` then the native menu is suppressed; the designed popover is the sole selection-action surface, matching the legacy reader. |
| Low | `ReadiumSelectionTokenCacheTests.swift` was not in the `vreaderTests` Sources build phase, so its tests never ran. | Fixed: xcodegen wires it. Wiring it in revealed the test could not compile (Readium `Selection.init` is `internal`), so `ReadiumSelectionTokenCache` was made **generic** over the stored value (`<Value>`); production specializes `<Selection>`, the cache dropped its `ReadiumNavigator` import, and the test exercises the value-agnostic round-trip with a `String` stand-in. 5 token-cache tests now run (7555 → 7560). |

Round 1 also confirmed NO correctness issue in the Selection→HighlightRecord
mapping: the new path stores the Readium container-relative href, which
`ReadiumDecorationHighlightAdapter.resolveHref` exact-matches against the reading
order, so the WI-8 href-space mismatch class is covered. Token consume/stale
rejection, host-scoped token misses for the legacy `.readerHighlightRequested`
path, and `clearSelection()` plumbing all sound.

## Round 2 — ship-as-is (commit ed49e777)

Both round-1 findings confirmed resolved; no new Critical/High/Medium from the
menu suppression or the cache genericization. `shouldShowMenuForSelection`
returning `false` correctly suppresses the default menu while still presenting
the custom popover; the generic `<Selection>` specialization behaves identically;
the String-stand-in test fully covers the value-agnostic round-trip; file sizes
within budget; legacy highlight-create paths untouched.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. Full serial `vreaderTests`: 7560
pass. `xcodebuild build`: BUILD SUCCEEDED. Device slice-verification (Readium
selection → designed color picker → persisted+rendered highlight → restore
round-trip) recorded in the PR description.
