---
branch: fix/128-replacement-rules-info-banner
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Small UX banner addition. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Settings/ReplacementRulesView.swift` | Add info banner Section above the rules list |
| `docs/bugs.md` | New row #128 (PARTIALLY FIXED, Medium, GH: #275) |
| `docs/features.md` | Feature #27 row updated with slice verification + bug #128 reference |

### What was added

A static `Section` at the top of `ReplacementRulesView`'s `List` containing:

```swift
Label {
    Text("Rules apply only when reading in Unified mode. Switch from the reader's Settings → Reading Mode.")
        .font(.footnote)
        .foregroundStyle(.secondary)
} icon: {
    Image(systemName: "info.circle").foregroundStyle(.secondary)
}
```

### Why partial fix

Bug #128 has two paths:
1. **Wire native TXT/MD pipeline through transforms** (proper fix) — substantial work; `TXTAttributedStringBuilder` doesn't accept transforms today.
2. **Add visibility for the limitation** (this PR) — cheap; gives users immediate feedback so they don't silently configure rules that won't apply.

Path 2 is the minimum viable mitigation. Path 1 stays open as a follow-up — bug #128 row notes the partial-fix status.

### Edge cases checked

- **Empty rules list**: banner shows above the existing `ContentUnavailableView`. Both render — banner first, then the no-rules placeholder.
- **Non-empty rules list**: banner shows above the rules. Rules row tapping/editing/deleting/reordering works unchanged.
- **No localization**: banner string is hardcoded English; matches rest of the file (`"No Replacement Rules"`, `"Replacement Rules"` title, etc.). No i18n regression.
- **List style impact**: adding a Section to a List doesn't change rendering of other rows.

### Tests added

None. Banner is static UI text — no logic to test. Existing `ReplacementTransform` tests (14) cover the actual rule application logic.

### Verdict

**ship-as-is**. 12-line UX clarity addition + tracker updates. No behavior change to the transform pipeline or rule storage. Mitigates bug #128's discoverability problem while the proper fix stays in the queue.
