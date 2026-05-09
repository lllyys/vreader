---
branch: fix/issue-468-unified-mode-txt-capability-gate
threadId: 019e0c04-579f-7d70-bd7b-9b15923f9149
rounds: 2
final_verdict: ship-as-is
date: 2026-05-09
---

# Codex audit log — bug #158 / GH #468

Fix: capability-gate `.unifiedReflow` away from TXT, hide Reading Mode picker
when format lacks the capability, gate replacement-rule loading on the same
capability, update bug #128's banner copy to name the supported formats so
TXT users don't follow the "switch to Unified" hint into a missing picker.

## Round 1 (initial audit)

### Findings

- **`vreader/Views/Reader/ReaderSettingsPanel.swift:539`** | Medium | The fix
  hides the picker and the dispatcher correctly keeps TXT out of unified, but
  it does not normalize stale persisted `readingMode = .unified`. Global
  defaults still load `.unified` from `ReaderSettingsStore` and per-book
  overrides still re-save `.unified` in `savePerBookSnapshot()`, so a TXT
  book can remain in an impossible state indefinitely. Leaks into secondary
  behavior such as `ReaderContainerView.swift:244`, which still loads
  unified-only replacement rules whenever the stale preference is present
  even though TXT now renders natively.
  - **Resolution**: added capability guard at `ReaderContainerView.swift:252`
    (formerly :244) so the rule-load guard now mirrors the dispatcher's own
    check at line 102-103. Stale `readingMode == .unified` for TXT no longer
    triggers `loadReplacementRules()`. Did NOT normalize the persisted value
    back to `.native` — the dispatcher + rule-load guard together neutralize
    the stale state's user-visible effects, and the persisted value remains
    correct if the user later opens an EPUB where unified IS supported.

- **`vreaderTests/Views/Reader/ReaderSettingsPanelReadingModeGateTests.swift:40`**
  | Medium | The new complex-EPUB test (`gate_hidden_whenComplexEPUB`) proves
  only the pure helper, not the production wiring. The real sheet call site
  still passes `BookFormat(...).capabilities` from
  `ReaderContainerView.swift:261`, which is the simple-EPUB default and does
  not carry the runtime `isComplexEPUB` signal. So the app still shows the
  Reading Mode picker for complex EPUBs even though the new suite implies
  otherwise.
  - **Resolution**: renamed test to `gate_helperSemantics_followComplexEPUBCapability`
    with a doc comment explicitly noting it covers helper semantics only, not
    end-to-end. Threading the runtime `isComplexEPUB` signal through to the
    panel is feature-class scope (same gap already documented in
    `chineseConversionSupported`).

## Round 2 (re-verify)

> No findings.
>
> Both fixes are correctly applied:
> - `ReaderContainerView.swift:252` now mirrors the dispatch predicate at
>   `ReaderContainerView.swift:102`, so a stale TXT `readingMode == .unified`
>   no longer loads unified-only replacement rules.
> - `ReaderSettingsPanelReadingModeGateTests.swift:40` now accurately
>   describes helper-only semantics.
>
> Residual gap, but not introduced by this patch: `ReaderContainerView.swift`
> at lines 102, 252, 261 all still rely on `resolvedBookFormat.capabilities`,
> so they share the existing simple-EPUB default and do not reflect runtime
> complex-EPUB fallback. The new rule-load guard did not make that worse; it
> just matches the existing dispatcher behavior.
>
> For bug #158's cheap-path mitigation, the shipping path looks sufficient:
> TXT no longer advertises `.unifiedReflow`, the Reading Mode picker is
> hidden for TXT, unified dispatch is blocked for TXT, and unified-only
> replacement rules are no longer loaded for stale TXT unified preferences.

## Verdict

**ship-as-is.** Zero open findings after round 2. The cheap-path mitigation
is sufficient; the proper-fix path (rewrite Unified TXT renderer to render
full content + restore chrome + integrate chapter detector + fix
toggle-blank) remains feature-class scope.
