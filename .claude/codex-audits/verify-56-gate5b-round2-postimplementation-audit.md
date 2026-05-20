# Codex audit log — verify/56-gate5b-round2-postimplementation

**Branch**: verify/56-gate5b-round2-postimplementation
**Type**: verification-only (evidence file + version bump + verification artifacts; no Swift code changes)
**Verdict**: ship-as-is (manual audit; Codex MCP unavailable / not invoked for verification-only commits per rule 47 §"Manual fallback")

## Manual Audit Evidence (rule 47 §"Manual fallback when AI auditor unavailable")

### Files read
- `dev-docs/verification/SCHEMA.md` — confirmed frontmatter contract for this evidence file
- `dev-docs/verification/feature-56-20260520.md` — round-1 evidence, baseline for what was previously partial
- `docs/features.md` row #56 — acceptance criteria (a-f) verified against
- `vreader/Services/AI/AIService.swift` (resolveActiveProviderConfig) — confirmed feature-flag + consent gates that the harness has to flip
- `vreader/Services/FeatureFlags.swift` — confirmed `aiAssistant` + `bilingualReading` flag keys
- `vreader/Services/AI/AIConsentManager.swift` — confirmed `com.vreader.ai.consentGranted` UserDefaults key
- `vreader/Services/AI/BookTranslationCoordinator.swift` — confirmed start path + service.translate dispatch
- `vreader/Services/AI/ChapterTranslationService.swift` — confirmed lookupKey + chunk decode pipeline
- `vreader/Services/AI/TranslationChunkContract.swift` — confirmed strict-JSON-array prompt shape
- `vreader/Services/AI/AIProvider.swift` (`OpenAICompatibleProvider`) — confirmed `chat/completions` URL construction + HTTPS-or-localhost validation
- `vreader/ViewModels/BilingualReadingViewModel.swift` + `+Prefetch.swift` — confirmed setEnabled persistence + handlePositionChange prefetch trigger
- `vreader/Views/Reader/TXTReaderContainerView.swift` + `+Bilingual.swift` — confirmed bilingualNonce reads `vm.translations(for:)` and the MISSING `.readerPositionDidChange` post / `handlePositionChange` call on TXT chapter-open (the criterion-b TXT gap)
- `vreader/Views/Reader/EPUBReaderContainerView+Bilingual.swift:142` — confirmed EPUB DOES wire `Task { await vm.handlePositionChange(locator) }` (counter-evidence that the gap is TXT-specific)
- `vreader/Views/Reader/FoliateBilingualContainerView.swift:304` — confirmed Foliate wire
- `vreader/Views/Reader/PDFReaderContainerView+Bilingual.swift:189` — confirmed PDF wire
- `vreader/Views/Reader/BookDetails/BookDetailsSheet+Translate.swift:113-131` — confirmed confirmTranslate path resolves `aiService.resolveActiveProviderConfig()` + `activeProfileSnapshot()` (and silently dismisses on `try?` nil — which was the symptom when feature-flag was off)

### Symbols / signatures verified
- `FeatureFlagKey.aiAssistant.rawValue` → "aiAssistant" → UserDefaults key `com.vreader.featureFlags.aiAssistant` (per `persistenceKeyPrefix + key.rawValue`)
- `AIConsentManager.consentKey` → "com.vreader.ai.consentGranted"
- `PerBookSettings` JSON shape: `{bilingualEnabled, bilingualTargetLanguage, bilingualGranularity}` — confirmed by reading `txt_bd8285a8....json` post-toggle
- `ZCHAPTERTRANSLATION` schema: `ZBOOKFINGERPRINTKEY`, `ZLOOKUPKEY`, `ZUNITSTORAGEKEY`, `ZTARGETLANGUAGE`, `ZPROMPTVERSION`, `ZPROVIDERPROFILEID`, `ZTRANSLATEDJSON`, `ZCREATEDAT`, `ZSOURCEPARAGRAPHCOUNT` — confirmed against SwiftData CoreData-backed sqlite
- DebugBridge `provider` URL schema (kind / endpoint / apiKey / model / active) — confirmed by reading `DebugCommand.swift` `ProviderAction` parsing and verifying handler in `RealDebugBridgeContext+Provider.swift`
- Active provider persisted in `com.vreader.app.plist` under `com.vreader.ai.activeProviderID` (UUID) + `com.vreader.ai.providerProfiles` (JSON array) — confirmed by `plutil -p` before/after re-translate

### Edge cases checked
- Bilingual ON persists across `xcrun simctl terminate` + `launch` — VERIFIED (criterion a)
- ChapterTranslationStore rows survive `simctl terminate` + relaunch — VERIFIED (criterion c)
- "Translate entire book" confirm alert shows chapter count + token estimate + provider chip — VERIFIED (criterion d)
- "Cancel translation" produces two-step confirm with "Keep translating" / "Cancel translation" — VERIFIED
- After cancel, the row reverts to "Paused at 0 of 4" and re-tapping re-opens the confirm — VERIFIED
- Re-translate replaces the row (count stays at 4, not 5) with fresh `ZCREATEDAT` + new content — VERIFIED (criterion e)
- Provider override picker exposed but global `com.vreader.ai.activeProviderID` unchanged — VERIFIED (criterion f, partial — only same-provider path exercised)
- Free-tier OpenRouter rate-limiting → coordinator pauses job at first 429 — DOCUMENTED (not a vreader bug, but worth noting in observations)
- TXT criterion-b inline render gap — DOCUMENTED + FILED for follow-up

### Risks accepted
- **`result: partial` instead of `pass`** because criterion (b) fails for TXT-format books on the inline-render half. Row stays at `DONE`; the row → `VERIFIED` flip is correctly gated until the TXT inline-render gap is fixed. Hook `check_terminal_status_evidence.sh` will not allow a `VERIFIED` flip with a `partial` evidence file, so no escape hatch is needed.
- **Provider override (criterion f)** — only same-provider path exercised because configuring a second OpenRouter free-tier key would still hit the same pooled rate limits. Code path is exercised by 11 round-1 ChapterReTranslateViewModelTests in unit suite; UI surface is verified. Accepted as PASS.
- **EPUB / Foliate / PDF / MD inline-render verification not exercised this round** — `mini-epub3` fixture errors on open ("Failed to resolve book resources" — unrelated bug, not feature #56 scope). The TXT gap is documented; the other formats' rendering wires are confirmed by code-read but not exercised end-to-end this round.

### Tests added or intentionally deferred
- No new tests in this commit (verification-only).
- TXT inline-render gap to be filed as a separate bug for fix in a dedicated branch. That bug will need its own test (regression: `TXTReaderContainerView` posts `.readerPositionDidChange` on chapter-index change AND ensures bilingual VM gets `handlePositionChange` driven once on bilingual-enable so cached chapters render).

## Why ship-as-is

This commit ships an evidence file + 11 verification screenshots + version bump (3.38.15 → 3.38.16). No Swift code is modified. The evidence file is rich (every criterion has observed behavior + commands run + screenshots). The follow-up bug for the TXT render gap will be filed under `docs/bugs.md` in a separate commit on this same branch.

Verdict: **ship-as-is**.
