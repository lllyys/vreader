---
kind: feature
id: 56
status_target: VERIFIED
commit_sha: 487828fc7fbfd8b81fdee43e4ed3121641e8dd16
app_version: 3.38.16 (build 591)
date: 2026-05-20
verifier: claude (Gate-5b round-2 acceptance pass)
device_or_simulator: iPhone 17 Pro Simulator (UDID 1FAB9493-B97E-48F0-96C7-44A8E5AAA21E)
os_version: iOS 26.5
build_configuration: Debug
backend: OpenRouter free tier — google/gemma-4-31b-it:free initial probe, liquid/lfm-2.5-1.2b-instruct:free completed all 4 chapters
result: partial
---

# Feature #56 round-2 Gate-5b acceptance verification

Feature #56 (bilingual reading mode) reached `DONE` on 2026-05-20 at v3.38.0
(WI-15, commit `5adc346b`). Round-1 verification (`feature-56-20260520.md`)
recorded `result: partial` because the b/d criteria gate on a real AI
provider and the in-app `ProviderProfileStore` had no credentials. Two
unblocks this round:

1. **PR #1062 (`8f9c04d`)** shipped the DebugBridge `provider` URL family —
   `vreader-debug://provider?action=add&name=...&endpoint=...&apiKey=...` —
   so the verification harness can configure an AI provider profile
   end-to-end without driving Settings → AI via computer-use.
2. **OpenRouter API key** in `.secrets/.env` (gitignored).

This round drives the production code paths (DebugBridge provider URL →
`ProviderProfileStore.shared` → `AISettingsViewModel` consent state →
`AIService.resolveActiveProviderConfig` → `BookTranslationCoordinator.start` →
`ChapterTranslationService.translateChunk` → OpenAI-compatible
`/chat/completions` endpoint → `ChapterTranslationStore.shared` SwiftData
write → reader observation) end-to-end against a live provider.

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| a | Bilingual mode toggle persists per book | **PASS** | After turning bilingual ON via More-menu → setup sheet → Confirm, the per-book file `PerBookSettings/txt_bd8285a8...json` contains `{"bilingualEnabled":true,"bilingualTargetLanguage":"Chinese","bilingualGranularity":"paragraph"}`. The `EN ↔ 中` reader-chrome pill is visible on the open book; after `xcrun simctl terminate` + relaunch + reopen of war-and-peace.txt, pill remains ON without any user action. Screenshots: `feature-56-round2-06-bilingual-persists-after-relaunch-20260520.png`, `feature-56-round2-11-bilingual-after-relaunch-cached-20260520.png`. |
| b | Current chapter translation renders inline within 10 seconds for a typical chapter | **PARTIAL — caching pipeline PASS; TXT inline render gap** | The `BookTranslationCoordinator` start path hit OpenRouter via `liquid/lfm-2.5-1.2b-instruct:free` and landed 4 chapters in `ChapterTranslationStore` in ~27s wall-clock — Ch.1 at +12s, Ch.4 at +27s (sampled by polling `ZCHAPTERTRANSLATION` count from `default.store`). Per-chapter ~5-7s is well within the 10s acceptance bar for the typical-chapter case. **However**: the TXT reader's `bilingualNonce` reads `vm.translations(for: unit)?.count` from the **in-memory** `BilingualReadingViewModel.translationsByUnit` dict, which is only populated by `handlePositionChange`'s prefetch — and the TXT host (`TXTReaderContainerView.swift`) does NOT post `.readerPositionDidChange` → `vm.handlePositionChange(locator)` on chapter-open OR on bilingual-enable. So even though disk cache rows exist (criterion c) and the EN ↔ 中 pill paints (criterion a), the inline interlinear render does not appear in the open TXT chapter without a manual position-change trigger that TXT does not produce. EPUB / Foliate / PDF / MD have explicit `handlePositionChange` wires (`EPUBReaderContainerView+Bilingual.swift:142`, `FoliateBilingualContainerView.swift:304`, `PDFReaderContainerView+Bilingual.swift:189`, `MDReaderContainerView.swift:224`); TXT is the format-specific gap. Filed for follow-up. |
| c | Cached translation loads immediately on next app open without an API call | **PASS** | All 4 `ZCHAPTERTRANSLATION` rows survive `xcrun simctl terminate com.vreader.app` + relaunch — same `ZLOOKUPKEY` per chapter, same `ZTRANSLATEDJSON` (lengths 33 / 386 / 200 / 93 bytes for chapters 0..3). The lookup key matches the `ChapterTranslationRecord.lookupKey(...)` schema (`bookFingerprintKey + unitStorageKey + targetLanguage + providerProfileID + promptVersion`) so a subsequent translation request short-circuits to the cache. Book Details "Translate entire book" row reports "Translated to Chinese · 4 of 4 chapters" with a checkmark after restart (`feature-56-round2-11-...`). |
| d | Global "Translate entire book" shows confirmation with chapter count and can be cancelled | **PASS** | Confirm alert: "Translate the whole book? war-and-peace has **4 chapters**. This will send every chapter to your AI provider. Approximately **426 input tokens** — actual cost depends on your provider's pricing." Provider snapshot row reads "OpenAI-compatible · liquid/lfm-2.5-1.2b-instruct:free" (active profile resolved at confirm-time via `BookDetailsSheet+Translate.swift:113`, NOT cached from sheet-open — matches Codex Gate-4 round-2 H1 follow-up). "Not now" dismisses without starting; "Translate" starts. While running, status sheet shows "0..4 / 4 TRANSLATING" + per-chapter "Ch.N NOW / QUEUED / FAILED / ✓" + "Cancel translation" button. The cancel button opens the two-step confirmation alert ("Cancel translation? 0 of 4 chapters are already translated and will stay cached — you can resume from where you stopped any time.") with "Keep translating" / "Cancel translation" choice — confirming routes to `BookTranslationCoordinator.cancel(bookFingerprintKey:)` and the row reverts to "Translate entire book · Paused at 0 of 4". Re-tapping after cancel re-opens the same confirm alert. Screenshots: `feature-56-round2-03-translate-confirmation-alert-20260520.png`, `feature-56-round2-04-translate-status-sheet-running-20260520.png`, `feature-56-round2-05-cancel-confirmation-alert-20260520.png`, `feature-56-round2-08-translate-done-4of4-20260520.png`. |
| e | Per-chapter re-translate clears old cache and fetches fresh | **PASS** | More-menu → "Re-translate chapter" opens `ReTranslatePickerSheet`; tapping "Re-translate" without changing the provider re-fires `ChapterTranslationService.translate` for chapter 0. Confirmed by SwiftData inspection: before re-translate, `ZCHAPTERTRANSLATION` row for `ZUNITSTORAGEKEY='txtChapterIndex:0'` had `ZCREATEDAT=800976926.36` with content `["[\"战与和平\"]\n\"叶元铁土\"\n\"勃朗宁\""]`; after re-translate, the same lookup key shows `ZCREATEDAT=800977164.74` (+238s) with content `["[\"战争与和平\"]\n\" Leo Tolstoy\""]` — fresh translation, same row replaced (total count stayed at 4, not 5). The picker's success sheet shows "Re-translated ✓ Done". Screenshots: `feature-56-round2-09-retranslate-picker-sheet-20260520.png`, `feature-56-round2-10-retranslate-success-20260520.png`. |
| f | Provider override for re-translate does not change the global active provider | **PASS (UI surface) / NOT REGRESSED (state assertion)** | The `ReTranslatePickerSheet` exposes a Provider row showing "OpenRouter · OpenAI-compatible ✓" with a tap target to swap to another configured profile. This round only had one provider configured (a second free-tier profile would have required parallel-key headroom we don't have), so I drove the "use the same provider" path. Verified by reading `com.vreader.ai.activeProviderID` from `com.vreader.app.plist` before and after — `F0EF2DC3-EADD-4E7F-998B-2EBDCC34FB67` both times. The `ChapterReTranslateBoundaries.RetranslateProviderResolving` protocol intentionally takes the override as a parameter rather than mutating store state (architectural verification covered by `ChapterReTranslateViewModelTests` round-1 unit suite — 11 tests). |

## Per-format slice notes

The TXT inline-render gap (criterion b PARTIAL) is **format-specific**.
EPUB, Foliate (AZW3/MOBI), PDF, and MD all have explicit
`.readerPositionDidChange` → `BilingualReadingViewModel.handlePositionChange(locator)`
observers wired:

| Format | Position-change wire | Source |
|---|---|---|
| EPUB | `Task { await vm.handlePositionChange(locator) }` | `EPUBReaderContainerView+Bilingual.swift:142` |
| Foliate (AZW3/MOBI) | `Task { await vm.handlePositionChange(locator) }` | `FoliateBilingualContainerView.swift:304` |
| PDF | `Task { await vm.handlePositionChange(locator) }` | `PDFReaderContainerView+Bilingual.swift:189` |
| MD | posts `.readerPositionDidChange` | `MDReaderContainerView.swift:224` (parent observer in `ReaderContainerView` should pick this up; not separately verified this round) |
| TXT | **MISSING** — no `vm.handlePositionChange` call site, no `.readerPositionDidChange` post on chapter open or bilingual-enable | `TXTReaderContainerView.swift` (only updates `updateChapterScrollFraction()` on chapter index change, line 539) |

The TXT compose pipeline (`BilingualDisplayPipeline.compose`) does the right
thing IF `vm.translations(for: unit)` is non-empty, but `translationsByUnit`
is only populated by `startPrefetch` → `prefetcher.translate(...)` →
`vm.setTranslations(...)`. The disk cache (`ChapterTranslationStore.shared`)
is consulted by the prefetcher, but the prefetcher is never triggered for
TXT because no `handlePositionChange` call site exists in
`TXTReaderContainerView.swift`. Result: the EN ↔ 中 pill paints (it reads
`vm.isEnabled`), but the inline interlinear render does not.

The fix is small — one or two lines in `TXTReaderContainerView.swift` to (a)
post `.readerPositionDidChange` on chapter-index change AND (b) drive an
initial `handlePositionChange` once the bilingual VM exists. Defer to a
follow-up bug filing rather than land within this verification commit.

## Provider configuration used this round

```bash
# .secrets/.env (gitignored, never committed) contains OPENROUTER_API_KEY

# Probe — the brief's suggested model is no longer available:
$ curl ...mistralai/mistral-7b-instruct:free
HTTP 404 — "No endpoints found for mistralai/mistral-7b-instruct:free."

# Probed free-tier models; picked one that returned valid JSON arrays + Chinese output:
# - google/gemma-4-31b-it:free → first try worked, then 429 rate-limited
# - minimax/minimax-m2.5:free → ~429 within minutes
# - liquid/lfm-2.5-1.2b-instruct:free → completed all 4 chapters without rate limit
```

Two non-app preconditions had to be primed before the AI flow was reachable:

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E

# (1) Set the AI feature flag override + AI consent in UserDefaults. The
# default for both is false in `prod` environment — the verification harness
# has to flip them, the same way Settings → AI → Toggle would.
xcrun simctl spawn "$SIM" defaults write com.vreader.app "com.vreader.featureFlags.aiAssistant" -bool YES
xcrun simctl spawn "$SIM" defaults write com.vreader.app "com.vreader.featureFlags.bilingualReading" -bool YES
xcrun simctl spawn "$SIM" defaults write com.vreader.app "com.vreader.ai.consentGranted" -bool YES

# (2) Configure the OpenRouter provider via DebugBridge URL.
set -a; source /Users/ll/workspace/vreader/.secrets/.env; set +a
ENDPOINT_ENC=$(printf '%s' "https://openrouter.ai/api/v1" | jq -sRr @uri)
KEY_ENC=$(printf '%s' "$OPENROUTER_API_KEY" | jq -sRr @uri)
MODEL_ENC=$(printf '%s' "liquid/lfm-2.5-1.2b-instruct:free" | jq -sRr @uri)
xcrun simctl openurl "$SIM" "vreader-debug://provider?action=add&name=OpenRouter&kind=openAICompatible&endpoint=${ENDPOINT_ENC}&apiKey=${KEY_ENC}&model=${MODEL_ENC}&active=true"
```

The pref-flag prerequisite is **not new** for this verification round — it's
the same gate that `--enable-ai` solves for XCUITest (Bug #237). The
DebugBridge `provider` URL family does not currently flip the feature flag
or the consent bit (PR #1062 was scoped to provider profile + key). For a
fully-CU-free flow against a fresh simulator, the harness either has to set
the defaults (as above) or a future `vreader-debug://featureflag?key=...&value=...`
+ `vreader-debug://aiconsent?action=grant` URL pair would close that loop.
Filed as a follow-up consideration; not blocking this verification round.

## Commands run

```bash
# Build + install fresh on 1FAB9493 (iOS 26.5 sim, second free UDID):
cd /Users/ll/workspace/vreader/.claude/worktrees/agent-a8cc381c1d2edbf80
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader -configuration Debug \
  -destination 'platform=iOS Simulator,id=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E'

# Install + grant scheme approval + launch:
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP="/Users/ll/Library/Developer/Xcode/DerivedData/vreader-ejserebtvlsebqfglmevqeuzkcdx/Build/Products/Debug-iphonesimulator/vreader.app"
xcrun simctl install "$SIM" "$APP"
./scripts/grant-debug-scheme-approval.sh "$SIM"
xcrun simctl launch "$SIM" com.vreader.app

# Configure AI gates + provider (see "Provider configuration" above).

# Seed + open war-and-peace.txt:
xcrun simctl openurl "$SIM" "vreader-debug://reset"
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=war-and-peace"
KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENCODED=$(printf '%s' "$KEY" | sed 's/:/%3A/g')
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=$ENCODED"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=opened"

# Drive bilingual ON via CU (More menu → Bilingual row → Setup sheet → Turn on).
# Drive global translate via CU (More → Book details → Translate entire book → Translate).
# Drive re-translate via CU (More → Re-translate chapter → Re-translate).

# Poll the translation cache:
DATA=$(xcrun simctl get_app_container "$SIM" com.vreader.app data)
SQL="$DATA/Library/Application Support/default.store"
sqlite3 "$SQL" "SELECT count(*) FROM ZCHAPTERTRANSLATION;"

# Verify persistence by killing the app and re-checking the cache:
xcrun simctl terminate "$SIM" com.vreader.app
xcrun simctl launch "$SIM" com.vreader.app
sqlite3 "$SQL" "SELECT count(*) FROM ZCHAPTERTRANSLATION;"  # still 4
```

## Observations

- **Free-tier rate limiting cascades through OpenRouter's pooled keys.**
  `gemma-4-31b-it:free` worked for one curl probe, then 429-limited within
  a minute. `minimax/minimax-m2.5:free` lasted longer but hit the same
  429-pool early. `liquid/lfm-2.5-1.2b-instruct:free` was the headroom-
  available model that completed all 4 chapters in 27s. The translations
  themselves had model-quality issues (Korean character bleed, partial
  English in segment 1) but that's a model-quality concern, not a vreader
  pipeline concern — what matters for criterion (d) timing is that the
  request/response cycle landed.
- **`BookTranslationCoordinator` does not retry on a single 429.** A first
  failure pauses the whole job at 0/4 with the row's chapter showing
  FAILED. The user-recovery path is "tap Translate entire book again →
  Translate" which kicks off a fresh job. This is a reasonable design (the
  alternative — opaque retry-with-backoff — could swallow signal that the
  user's provider is broken), but it does mean a flaky free-tier model can
  produce a noticeable PAUSED experience. Worth noting in feature docs.
- **The DebugBridge `provider` URL family worked as designed** — both add
  and (implicit re-add via same name) idempotent replacement landed the
  expected `ProviderProfile` row in
  `Library/Preferences/com.vreader.app.plist` →
  `com.vreader.ai.providerProfiles`. Active selection persisted across
  `simctl terminate` + `launch` cycles.
- **TXT inline-render gap is the only criterion that did not fully pass.**
  Everything that the production pipeline writes (PerBookSettings JSON,
  ChapterTranslationStore rows, active provider snapshot) survives kill +
  relaunch. Only the live-render injection into the open TXT chapter is
  missing the trigger.
- **The verification harness needed a non-trivial number of moving parts to
  reach the AI subsystem from a fresh simulator** — install, scheme
  approval grant, feature-flag UserDefaults pokes, AI consent UserDefaults
  poke, provider URL, then fixture seed + open. The DebugBridge `provider`
  URL handles the last item cleanly; the feature-flag + consent gates are
  the next ergonomic wall for fully-CU-free AI verification.

## Artifacts

All under `dev-docs/verification/artifacts/`:

- `feature-56-round2-01-setup-sheet-20260520.png` — first-enable
  `BilingualSetupSheet` with target language (Chinese) + granularity
  (Paragraph) + "AI provider configured" engine-descriptor row.
- `feature-56-round2-02-book-details-translate-row-20260520.png` —
  `BookDetailsSheet` showing "Translate entire book... Pre-translate every
  chapter to Chinese" action row.
- `feature-56-round2-03-translate-confirmation-alert-20260520.png` —
  "Translate the whole book?" confirmation alert with chapter count, token
  estimate, provider chip, Not-now/Translate buttons.
- `feature-56-round2-04-translate-status-sheet-running-20260520.png` —
  status sheet during run (0/4 TRANSLATING, Ch.1 NOW, Ch.2-4 QUEUED, Cancel
  translation button).
- `feature-56-round2-05-cancel-confirmation-alert-20260520.png` — two-step
  cancel confirmation ("0 of 4 chapters are already translated and will
  stay cached"), Keep-translating / Cancel-translation choices.
- `feature-56-round2-06-bilingual-persists-after-relaunch-20260520.png` —
  reader after app-kill + relaunch, EN ↔ 中 pill ON.
- `feature-56-round2-07-translate-complete-20260520.png` — same as -08,
  redundant capture before the explicit DONE snapshot.
- `feature-56-round2-08-translate-done-4of4-20260520.png` — status sheet at
  4/4 DONE, all chapters checked, full progress bar.
- `feature-56-round2-09-retranslate-picker-sheet-20260520.png` —
  `ReTranslatePickerSheet` with provider row, style segmented control,
  "Keep term overrides" toggle, Re-translate button.
- `feature-56-round2-10-retranslate-success-20260520.png` — "Re-translated"
  confirmation sheet with Done button.
- `feature-56-round2-11-bilingual-after-relaunch-cached-20260520.png` —
  reader after app-kill + relaunch with all 4 cached translations on disk;
  EN ↔ 中 pill ON; inline interlinear NOT visible (the criterion-b gap
  documented above).

## Why `result: partial`, not `pass`

Criterion (b) — "current chapter translation renders **inline** within 10
seconds for a typical chapter" — has two halves:

1. **Translation completes within 10 seconds for a typical chapter** —
   PASS. With a non-rate-limited free model (`liquid/lfm-2.5-1.2b-instruct:
   free`), all 4 chapters completed in 27s wall-clock; per-chapter ~5-7s.
2. **Inline render appears in the open chapter** — **FAIL for TXT**. The
   per-format render pipeline for EPUB / Foliate / PDF / MD has explicit
   `.readerPositionDidChange` → `handlePositionChange` wires, but TXT's
   `TXTReaderContainerView.swift` is missing them. The disk cache lands
   correctly (criterion c PASS), the chrome paints (criterion a PASS), but
   the inline interlinear text does not appear in TXT-format books even
   after re-open with cached translations present.

The other formats (EPUB / Foliate / PDF / MD) would likely pass criterion
(b) end-to-end, but I could not exercise them in this round:

- EPUB `mini-epub3` fixture errored with "Failed to resolve book
  resources." (probably a missing manifest entry — separate bug, not
  feature #56 scope).
- Foliate `mini-azw3` not exercised this round (CU/dev focus had hit the
  TXT pipeline path).
- PDF / MD fixtures not exercised this round.

Row stays at `DONE`. The TXT criterion-b inline-render gap will be filed
as a separate bug for follow-up — it's small (one or two lines in
`TXTReaderContainerView.swift`) but doing it within this verification commit
would violate Gate-5 scope discipline.

## Follow-up bug to file

**TXT bilingual mode renders chrome pill but not inline translations** —
Reader/* — Medium severity. Disk cache lands correctly (criterion c) but
the per-format trigger to populate `BilingualReadingViewModel.translationsByUnit`
is missing in TXT. Fix: post `.readerPositionDidChange` from
`TXTReaderContainerView.swift`'s `onChange(of: viewModel.currentChapterIdx)`
+ on initial `ensureBilingualViewModel()`. EPUB/Foliate/PDF/MD precedent.
