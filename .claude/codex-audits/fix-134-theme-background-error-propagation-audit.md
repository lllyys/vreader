---
branch: fix/134-theme-background-error-propagation
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

Same family as bugs #129/#130/#131 (silent error swallow). Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/Reader/ReaderSettingsPanel.swift` | Added `backgroundErrorMessage` @State + alert; replaced 4 `try?` calls (3 in PhotosPicker handler + 1 in Remove button) with do/catch. |
| `docs/bugs.md` | New row #134 (FIXED, Low, GH: #287). |

### Failure paths now surfaced

1. `item.loadTransferable` throws → "Could not load image: <error>".
2. `item.loadTransferable` returns nil (legitimately empty result) → "Selected image returned no data."
3. `UIImage(data:)` returns nil (corrupt/unsupported format) → "Could not decode image — unsupported format?"
4. `ThemeBackgroundStore.saveBackground` throws → "Could not save background: <error>".
5. `ThemeBackgroundStore.removeBackground` throws → "Could not remove background: <error>".

### Edge cases checked

- **PhotosPicker dismissed without selection** (`newItem == nil`): `guard let item` returns; no side effects, no alert.
- **`UIImage(data:)` succeeds but `saveBackground` fails** (e.g., disk full): user sees specific save error; `useCustomBackground` does NOT flip true (stays at previous value); pickerItem cleared.
- **Save throws but image was decoded**: same as above — image bytes never reach disk; toggle stays as it was.
- **Remove on a theme that never had a background**: `removeBackground`'s file-existence check returns early (no-op, no throw). Toggle flips to false. No alert.
- **Multiple errors in sequence**: alert state is single-message — newer errors overwrite older ones. Acceptable since errors are user-action-driven (one at a time).
- **Alert dismissal**: `.alert(isPresented:)` binding clears `backgroundErrorMessage` on dismiss. State stays clean.

### What I deliberately did NOT change

- `ThemeBackgroundStore` itself: the `loadBackground` path keeps its `try? Data(contentsOf:)` because returning nil is the documented "no background" semantic — not an error case.
- The Toggle for `useCustomBackground`: unchanged.
- The opacity slider: unchanged.

### Tests added

None. UI-state plumbing change. The `ThemeBackgroundStore`'s save/remove already throw; this PR just propagates those throws into a user-visible alert.

### Verdict

**ship-as-is**. Same shape as the recent error-propagation batch. No new abstractions, no risk.
