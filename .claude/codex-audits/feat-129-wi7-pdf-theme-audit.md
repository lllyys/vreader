---
branch: feat/129-wi7-pdf-theme
threadId: 019f4e90-e493-7e31-8c2a-cef4d638e040
rounds: 2
final_verdict: ship-as-is
---

# Codex audit — feature #129 WI-7 (Android PDF reader display settings: theme background)

Gate-4 implementation audit for WI-7: the PDF viewer backdrop inherits the theme background from the
global `ReaderSettingsStore` (PDF is rasterized — theme bg ONLY, no font/size/spacing, and NO Display
sheet / Aa slot — rule 51).

Scope audited:
- `android/app/src/main/kotlin/com/vreader/app/reader/PdfDisplayBackdrop.kt` (new pure mapping `ReaderSettings.pdfBackdrop() = theme.background`)
- `android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderActivity.kt` (collects settings live, gates composition, threads the backdrop)
- `android/app/src/main/kotlin/com/vreader/app/reader/PdfReaderScreen.kt` (composables extracted from the Activity in round 2)
- `android/app/src/test/kotlin/com/vreader/app/reader/PdfDisplayBackdropTest.kt` (JVM RED test)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/PdfDisplaySettingsConnectedTest.kt` (connected smoke)

## Round 1 (thread 019f4e90-e493-7e31-8c2a-cef4d638e040) — findings

- **High** — The Paper fallback rendered before DataStore's first emission → a user with a stored
  Dark/OLED/Photo theme could see a wrong bright frame on open/rotation; the test hook also went
  non-null before persisted settings arrived. Fix: gate PDF composition on `settingsOrNull`.
- **High** — The connected test's open-time assertion raced the fallback `SideEffect` (polling only
  for non-null could capture Paper). Fix: after gating, poll for the Dark ARGB specifically.
- **Medium** — Semantic: the `SideEffect` recorded the fallback as "applied", contrary to the
  "null until first emission" comment. Fix: run the `SideEffect` only after non-null settings.
- **Low** — `PdfBackdrop` constant + the default `backdrop` param were now unused fallback paths.
  Fix: remove them; make `backdrop` mandatory.
- **Low** — `PdfReaderActivity.kt` was 314 lines (> ~300 limit). Fix: extract the PDF composables.

Rule-51 confirmed respected (no Aa slot / Display sheet added); theme mapping correct; live collection
lifecycle-aware; unknown persisted themes already fall back to Paper in `ReaderSettingsStore`;
config-change re-collection correct.

## Fixes applied

1. `PdfReaderActivity` GATES composition on `settingsOrNull`: null → an empty full-screen surface,
   the test hook stays null; non-null → derive the backdrop, run the `SideEffect`, render. No wrong
   frame can flash for a stored dark theme (High #1 + Medium resolved).
2. The connected test polls for the Dark ARGB specifically, not merely non-null (High #2 resolved).
3. `PdfBackdrop` fallback + default param REMOVED; the composables moved to `PdfReaderScreen.kt` with
   `backdrop` mandatory (Low #1 + Low #2 resolved). `PdfReaderActivity` = 185 lines, `PdfReaderScreen`
   = 151 lines — both under the limit.

## Round 2 (thread 019f4e97-8a4a-7e32-af58-a9f481801e0b) — re-audit

> No Critical, High, Medium, or Low findings.
> Ship verdict: WI-7 fixes are clean and ready to ship.

## Verdict

**ship-as-is** — all round-1 findings resolved; round-2 clean.

Test gates:
- JVM: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (`:app:testDebugUnitTest --tests '*PdfDisplayBackdrop*'`).
- Connected: `RUN-ANDROID-TESTS RESULT: SUCCEEDED` (`PdfDisplaySettingsConnectedTest`, 1 test on vreader-test AVD);
  regression `PdfReaderActivityTest` 4/4 still pass with the gating change.
