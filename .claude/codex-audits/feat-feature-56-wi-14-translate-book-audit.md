---
branch: feat/feature-56-wi-14-translate-book
threadId: 019e4349-57e7-7ba2-81f0-288bcd4fe0ba
rounds: 3
final_verdict: ship-as-is
date: 2026-05-20
---

# Gate-4 audit — feature #56 WI-14 (translate entire book)

Author: Claude Code (implementer).
Auditor: Codex MCP (`mcp__plugin_codex-toolkit_codex__codex`), read-only sandbox.

Author/auditor separation satisfied (rule 47): Codex MCP is a separate
process from this Claude Code session.

## Round 1 — initial audit

Codex returned 0 Critical, 3 High, 3 Medium, 2 Low findings against the
working-tree diff. Verdict: block-recommended.

| File / line | Severity | Finding |
|---|---|---|
| `ReaderContainerView.swift:351-383` + per-format containers | High | Only TXT published `.readerBookTranslationTextProviderAvailable`; EPUB/MD/Foliate omitted, so the translate row stays hidden on those formats |
| `LibraryView+Body.swift:44` | High | `LibraryCardTranslateBadge` never renders because the only `BookCardView` call site didn't pass `translateProgress` |
| `TranslateBook/ReaderTranslateBanner.swift:18` | High | The banner is defined but never composed/observed anywhere in the reader chrome |
| `ReaderContainerView.swift:368-382` | Medium | Provider snapshot resolved when the text provider becomes available, not when the user confirms — risk of stale label/profile |
| `BookDetailsSheet+Translate.swift:66-72` | Medium | "Change provider" CTA is a placeholder dismiss with no route to a picker |
| `BookTranslationProgress.swift:80-88` | Medium | `BookTranslationEstimate` only carries `unitCount` — the planned token/cost/time fields are missing |
| `BookDetailsSheet.swift:35` | Low | File back over the rule-50 ~300-line limit (320 LoC) |
| `TranslateStatusSheet.swift:38-58` | Low | `onClose` is dead API with a `.onAppear { _ = onClose }` warning suppression |

### Round-1 fixes

- EPUB/MD/Foliate `ensureBilingualViewModel` now post
  `.readerBookTranslationTextProviderAvailable` with the constructed
  `ChapterTextProviding` (TXT already did).
- `LibraryView` adds `translationProgressByBook: [String: BookTranslationProgress]`
  + `.onReceive(.readerBookTranslationProgressDidChange)` mirror;
  `LibraryView+Body.swift` threads `translateProgress` into `BookCardView`.
- `ReaderContainerView` mounts `ReaderTranslateBanner` in the chrome
  overlay area, observes `translateBookVM.progress.isRunning`, anchored
  under the chrome.
- Provider snapshot resolved fresh inside the overlay modifier's
  `onConfirm` AND a `resolveProviderLabel` closure passed into
  `presentConfirm` resolves the alert's provider label from
  `ProviderProfileStore.shared.activeProfileSnapshot()`. Removed cached
  config / profileID / label state from `ReaderContainerView`.
- `BookTranslationEstimate` extended with `approximateInputTokens: Int?`;
  `BookTranslationCoordinator.estimate(...)` samples up to 5 units,
  averages chars/unit, extrapolates `totalChars / 4` for the rough
  token count. `TranslateBookConfirmAlert` renders the estimate when
  present.
- `BookDetailsSheet.swift` split — card rendering moved to
  `BookDetailsSheet+Cards.swift`. Now 250 LoC.
- Removed `onClose` parameter from `TranslateStatusSheet`.
- "Change provider" CTA: documented as accepted follow-up
  (rule 47 allows Low/Medium accept-with-rationale).

## Round 2 — audit-fix verification

Codex returned 0 Critical, 2 High, 2 Medium findings. Verdict:
block-recommended.

| File / line | Severity | Finding |
|---|---|---|
| `ReaderContainerView.swift:219` + `BookDetailsSheet+Translate.swift:58` + `BookTranslationViewModel.swift:88` | High | `ReaderTranslateBanner` is composed but `vm.progress` only updates while the Book Details overlay is mounted (overlay's `onDisappear` called `stopObserving`). Banner goes stale after sheet dismisses |
| `FoliateBilingualContainerView.swift:157, 97` | High | Foliate now posts the text-provider notification, but only from `ensureBilingualViewModel`, which only runs after a bilingual toggle. On a normal Foliate book open the provider is never published, so the translate row stays hidden |
| `BookDetailsSheet+Translate.swift:74` | Medium | "Change provider" CTA still dismiss-only (rationale documented; carried forward) |
| `BookTranslationProgress.swift:80` | Medium | Estimate now has tokens but still missing cost/time (partial vs design); rationale: cost depends on provider pricing which we don't track |

### Round-2 fixes

- `ReaderContainerView.onReceive(.readerBookTranslationTextProviderAvailable)`
  starts observation eagerly (`Task { await vm.startObserving() }`)
  when the VM is constructed. Book Details overlay no longer calls
  `stopObserving()` on `onDisappear` — only re-calls `startObserving()`
  on appear (idempotent). Comment in
  `BookDetailsSheet+Translate.swift` documents the host-scoped (not
  sheet-scoped) lifetime.
- `FoliateBilingualContainerView`: `.foliateSectionLoaded` `.onReceive`
  block now calls a new `publishTranslateBookTextProviderIfReady()`
  helper BEFORE `handleSectionLoaded(...)`. The helper guard-lets the
  `coordinatorBox?.coordinator`, builds a `FoliateChapterTextProvider`,
  and posts `.readerBookTranslationTextProviderAvailable`. Post moved
  out of `ensureBilingualViewModel`. Idempotent — host caches by
  `fingerprintKey`.

## Round 3 — verification pass

Codex returned 0 Critical, 0 High, 0 Medium findings.

All round-1 + round-2 items resolved or explicitly accepted with
rationale (rule 47). No new findings introduced.

**Final verdict: ship-as-is**

## Auditor concerns explicitly checked

| Concern | Status |
|---|---|
| `resolveProviderLabel` closure Sendable correctness | OK — closure does not capture `self`; only reads `ProviderProfileStore.shared` |
| Foliate text-provider crossing actor via `NotificationCenter.object` | OK — `FoliateChapterTextProvider` is an actor satisfying `ChapterTextProviding: Sendable` |
| 5-unit estimate sampling cost in Foliate (bridge round-trips) | OK — bounded, tolerable for the confirm path |
| AsyncStream.Continuation dict cleanup race | OK — coordinator is an actor, all mutations serialize on its executor |
| BookTranslationCoordinator.start service+provider capture | OK — both injected before Task spawn, Sendable |
