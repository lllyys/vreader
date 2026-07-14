---
branch: feat/131-wi9-entry-acceptance
threadId: 019f604a-42f9-7950-81df-5f4417c3b4d4, 019f6057-7472-7a51-923f-d545c68961fc
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #131 WI-9 (Android bilingual entry wiring + EPUB VM/cross-spine finalize)

Independent Codex audit (rule 53, `scripts/run-codex.sh -e high`). Two rounds.
Author (this lane) ≠ auditor (Codex) — author/auditor separation preserved.

## Scope

The final #131 WI: make bilingual mode user-reachable (top-chrome pill + More-menu
Bilingual row + setup→AI-providers routing on TXT/MD + EPUB) and complete the two
deferred WI-7b findings (a: `onEpubBlocksEnumerated`→`translationsByUnit`; b:
cross-spine language-switch DOM reconcile).

Files audited: `reader/chrome/ReaderTopChrome.kt`, `reader/chrome/ReaderChromeScaffold.kt`,
`reader/chrome/BilingualMoreRow.kt`, `reader/EpubReaderChrome.kt`,
`reader/TxtReaderActivity.kt`, `reader/ReaderActivity.kt`,
`bilingual/BilingualViewModel.kt`, `bilingual/EpubBilingualController.kt`.

## Round 1 (thread 019f604a-42f9-7950-81df-5f4417c3b4d4) — 3 High, 2 Medium, 1 Low

- **High-1 — fresh unconfigured user has no AI-config entry.** The unconfigured
  Bilingual More row is the design's NON-interactive Disabled row (`vreader-more.jsx`
  renders `onClick={disabled ? undefined : on}`), so setup is reachable only from the
  configured toggle / an enabled pill. **ACCEPTED as a design-gate matter, NOT a code
  bug** — making the disabled row clickable would violate rule 51. This is the design/
  acceptance amendment the plan already flags (§AI-config reachability); the fresh-user
  `unconfigured → Set up → add provider` leg is #131-owned and verified by the merged
  WI-AIP `ReaderAiProvidersConnectedTest`. The orchestrator's acceptance pass / a
  follow-up design amendment owns any standalone unconfigured entry.
- **High-2 — EPUB first-enable race. FIXED.** The More toggle's `setEnabled(true)` only
  ENQUEUES an async VM command, so an immediate `scheduleBilingual()` saw `enabled=false`
  and no-op'd with nothing to reschedule. Replaced with an `enabled` false→true StateFlow
  observer in `buildBilingual` (the EPUB analog of TXT's enabled-keyed `LaunchedEffect`);
  `onBilingualToggle(true)` no longer schedules directly.
- **High-3 — mid-book language reconcile could leave stale old-language decorations.
  FIXED.** `reconcileLanguageChange` now CLEARS the old DOM (verified) under the same
  mutex+token BEFORE `applyLocked`, and returns a Boolean; the host advances
  `bilingualLang`/`bilingualUnit` ONLY on true. New empty-enumeration regression test
  proves the old DOM is reaped with no re-inject.
- **Medium-1 — reused AI Providers sheet not themed. FIXED.** Wrapped
  `ReaderAiProvidersSheet` in `BackupSurface(darkOverride = theme.isDark)` at both TXT +
  EPUB mounts so its `LocalBackupTokens` follow the active reader theme.
- **Medium-2 — dead #134 Details/Share when `bookDetails == null`. FIXED.**
  `readerMoreRows` gained `includeDetailsShare = bookDetails != null`; a bilingual-only /
  details-not-yet-loaded host omits the Details/Share rows (no dead control).
- **Low — host activities growing. ACCEPTED with rationale.** `ReaderChromeScaffold.kt`
  (the file this WI newly pushed over 300) WAS split into `reader/chrome/BilingualMoreRow.kt`
  (255 lines now). The `ReaderActivity`/`TxtReaderActivity` growth is additive routing on the
  established large-host pattern; a full host extraction is a separate refactor out of this
  additive WI's scope.

## Round 2 (thread 019f6057-7472-7a51-923f-d545c68961fc) — 0 Critical, 0 High, 1 Medium

- **Medium — reconcile returned `true` even when superseded mid-apply. FIXED.**
  `applyLocked` silently returns early if the session token changes during translate/inject,
  but `reconcileLanguageChange` returned `true` unconditionally afterward, so the caller
  advanced its recorded language for a superseded apply. Now returns `session == token` after
  `applyLocked`. New regression test bumps the session during the reconcile translate and
  asserts `false`.
- Round 2 confirmed correct: single first-enable scheduling source; clear-before-
  enumerate/translate/inject with no stale-language retention; failed-clear leaves the
  transition pending; both AI-provider mounts derive dark tokens from the reader theme; both
  chrome hosts omit Details/Share when `bookDetails == null`; the accepted design-gate matter
  was not re-raised.

## Verdict

`follow-up-recommended` — every Critical/High/Medium **code** finding is fixed and covered by
tests. The single remaining item (High-1 fresh-unconfigured-user reachability) is an accepted
rule-51 design-gate matter, not a code defect; it is owned by the orchestrator's acceptance
pass / a design amendment, and the fresh-user leg is already verified by the merged WI-AIP
connected test.

## Test evidence (this lane, on the leased emulator-5554, API 35)

- JVM: `EpubBilingualControllerTest` 11/0 (incl. clear-before-apply, empty-enum, superseded-
  during-translate); `BilingualViewModelPrefetchTest` (onEpubBlocksEnumerated populates
  translationsByUnit + disabled-ignore).
- Connected: `EpubBilingualEntryTest` 2/0 (finding a: VM translationsByUnit reflects the EPUB
  unit; finding b: mid-book reconcile re-injects the current resource);
  `TxtReaderBilingualEntryTest` 4/0 (More-row Toggle/Disabled render, toggle→setup, setup
  "Set up"/"Change…"→AI Providers, pill mounts+re-opens setup).
- Regression (no #132/#134/#135 break): `TxtReaderBilingualConnectedTest` 8/0,
  `EpubBilingualConnectedTest`, `EpubReaderChromeTest` 3/0, `TxtReaderChromeUiTest` 6/0,
  `MorePopupTest` 11/0, `ReaderChromeConnectedTest` 6/0.
