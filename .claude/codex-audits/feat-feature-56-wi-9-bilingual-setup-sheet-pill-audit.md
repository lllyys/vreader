---
branch: feat/feature-56-wi-9-bilingual-setup-sheet-pill
threadId: 019e425b-3bf0-7bc0-82a6-296270c4c3b6
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Feature #56 WI-9 — Codex audit log

WI-9 ships `BilingualSetupSheet` + `BilingualPill` + `ReaderTopChromeSlot.bilingualPill`. Audit ran across 3 rounds against the Codex MCP read-only sandbox. All Critical/High/Medium findings resolved; final verdict `ship-as-is`.

## Round 1 — initial audit (8 findings)

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `vreader/Views/Reader/Bilingual/BilingualSetupSheet.swift:116` | **High** | `ReaderSheetChrome(onClose:)` was wired to `onConfirm`, so tapping `X` performed the same state-changing action as "Turn on bilingual mode" instead of dismiss/cancel. Could silently enable bilingual mode when the user was backing out. | **Fixed** — split `onCancel` from `onConfirm`; the sheet's close button routes to `onCancel`, only the CTA persists. |
| `BilingualSetupSheet.swift:149` | **Medium** | Stale persisted language keys were handled by the pill but not by the sheet. An unknown `state.languageKey` left the picker grid with no selection painted, and confirming preserved the stale key. | **Fixed** — `BilingualSetupSheetState.normalised()` canonicalises through `BilingualLanguage.findOrDefault`; invoked from `.onAppear` so the picker always paints a selection. |
| `BilingualSetupSheet.swift:76` | **Medium** | AI-provider chip modeled as a bare `Bool`. The configured state could not render the provider-specific descriptor the design promises; degraded to generic "AI provider configured". | **Fixed** — introduced `BilingualEngineDescriptor` value type (configured + providerName + subtitle) with `displayTitle` / `displaySubtitle` computed properties. Host (WI-10..15) constructs it from `ProviderProfileStore`. |
| `BilingualSetupSheet.swift:121` | Low | Top preview strip from `BilingualSetupSheet` in JSX was missing. | **Fixed** — `BilingualSetupPreview` view in `BilingualSetupSheet+Sections.swift` renders sample source + per-language translation pair with per-script font + RTL flag. |
| `BilingualPill.swift:96` | Low | `EN` badge was implemented as a circle; design specifies a 16×16 rounded-square (corner radius 4). | **Fixed** — `Circle()` → `RoundedRectangle(cornerRadius: 4)`. |
| `BilingualSetupSheet.swift:1` | Low | Rule-22 comment drift: header described an edit-mode contract the implementation doesn't carry. | **Fixed** — header rewritten to match current behavior. |
| `BilingualLanguagePickerCell.swift:1` | Low | Header claimed the extraction kept the parent under ~300 LOC, but the parent was 347 LOC. | **Fixed** — moved engine + preview to `BilingualSetupSheet+Sections.swift`; parent now 301 lines (effectively under ~300). Header rewritten to reflect the split. |
| `BilingualSetupSheet.swift:91` | Low | `ctaLabel(aiConfigured:)` carried dead branching — both branches returned the same string. | **Fixed** — collapsed to `static let primaryCTALabel = "Turn on bilingual mode"`. |

5 new tests added for the descriptor display surface + `normalised()` fallback. Full suite 6544/6544 green at the round-1 fix commit.

## Round 2 — re-audit after round-1 fixes (1 finding)

| File | Severity | Issue | Resolution |
|---|---|---|---|
| `BilingualSetupSheet.swift:129` | Low | Comment on `onCancel` said "Tap on the system swipe-down also routes here," but this view only wires `onCancel` to the close button. Overstates the contract — the host's `.sheet(..., onDismiss:)` is what would carry swipe-down handling. | **Fixed** — comment rewritten to scope the closure's contract to what THIS view wires (close button), while documenting the host-side composition expectation for the WI-10..15 sites. |

Round-1 fixes confirmed correct. No new issues introduced by the round-1 cycle.

## Round 3 — re-audit after round-2 fix (0 findings)

> No remaining findings from the WI-9 audit. That comment now accurately distinguishes what `BilingualSetupSheet` itself wires from what the future sheet composition sites must guarantee.

Verdict: **`ship-as-is`**.

## Summary

- Plan-correctness: WI-9 delivers `BilingualSetupSheet` + `BilingualPill` + the chrome layout extension the plan promises.
- Edge cases: stale persisted language keys normalised; nil-language + transient host state guard in `ReaderTopChrome.shouldShowBilingualPill`; CJK + RTL scripts surface correctly in the picker, pill, and preview.
- Security: nothing relevant (no JS, no WKWebView, no Keychain reads from this WI's surfaces).
- Concurrency: SwiftUI Views; no actor isolation concerns introduced.
- File-size budget: every WI-9 file is ≤301 lines (rule 50 §9).
- Design fidelity: matches `vreader-bilingual.jsx` for both surfaces, including the registry-fallback path the design's `(BILINGUAL_LANGS.find(...) || BILINGUAL_LANGS[0])` pattern uses.
- Rule 51: every new visible UI element comes from `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual.jsx` + `design-notes/feature-60-followups.md §2.2`. No self-designed UI.
- Rule 22 comment maintenance: file headers describe current behavior after the round-1 / round-2 cycles.
