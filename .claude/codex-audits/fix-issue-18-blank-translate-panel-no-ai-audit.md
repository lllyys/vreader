---
branch: fix/issue-18-blank-translate-panel-no-ai
threadId: 019df757-e166-7b70-8937-e4cd784eb05f
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #91 closure (GH #18)

## Round 1 — initial findings

| File | Severity | Issue | Resolution |
|------|----------|-------|------------|
| `docs/bugs.md:221` | Low | Row's evidence wording overstated coverage by saying "Verified by … tests" for all 3 entry points, when only entry points 1 + 2 have direct tests. Entry point 3 (`.readerTranslateRequested` handler) is verified by code inspection of `ReaderContainerView:152`. | Fixed: row reworded to distinguish tested coverage (entry points 1 + 2 — cite specific test names) from code-inspected coverage (entry point 3, with rationale that the underlying gate is the same one tested). |

Codex confirmed closure correctness:
> No closure-correctness bug found. I did not find any additional translate entry point that bypasses the new gate. ... So bug #91 being marked FIXED as a side effect of bug #90 is reasonable, and GH #18 should be closed as fixed-by-PR-#250 side effect, not as a duplicate of #17.

## Round 2 — verification re-pass

Codex confirmed clean after the wording fix.

## Visual verification (added post-audit)

Performed on iPhone 17 Pro Simulator (iOS 26.4) against merged-main v3.13.15 with consent revoked:

1. **Chrome bar** — screenshot shows 6 icons (`< 🔍 📑 ☰ 🔊 aA`); no AI sparkles button. Toolbar gate verified.
2. **Long-press edit menu** — submenu shows `Highlight Add Note Define` then a chevron `>`. No vreader-Translate action.
3. **Overflow expansion** — chevron expands to `Highlight / Add Note / Define / Copy / Look Up / Translate / Search Web / Share…`. The "Translate" item has a globe icon, not `character.book.closed`.
4. **Tap "Translate"** — opens iOS's system Translation dialog with text "The selected content will be sent to Apple to process the translation. You can choose to always translate offline in Settings. About Translation & Privacy…". This is Apple's built-in Translation framework, NOT vreader's AI translate. Bug #91's failure path (vreader AI panel opening blank) cannot be reached.

## Final verdict

**ship-as-is**

Bug #91 is genuinely closed by side effect of PR #250 (bug #90 fix, v3.13.13). All three entry points are gated by `AIReaderAvailability.isAvailable`. Visual verification on the merged-main v3.13.15 build confirms the gates work end-to-end on the simulator. The expanded-menu "Translate" item is iOS's system Translation, not vreader's — confirmed by tapping it and observing Apple's privacy dialog.

No code change in this branch — the closure is documentation only (tracker row TODO → FIXED with cited evidence).
