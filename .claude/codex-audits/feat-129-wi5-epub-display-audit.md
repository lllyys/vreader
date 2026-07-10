---
branch: feat/129-wi5-epub-display
threadId: 019f4e6b-8d27-7be2-aebf-f23f617e2205
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #129 WI-5 (apply Display settings to the EPUB reader)

Auditor: Codex (`scripts/run-codex.sh`, model gpt-5.6-sol, medium effort), read-only sandbox.
Session/thread: `019f4e6b-8d27-7be2-aebf-f23f617e2205`. Full transcript: `.reports/wi5-audit-r1.txt`.

Scope audited: the WI-5 diff — `EpubPreferencesMapper.kt` (new), `ReaderActivity.kt` (wiring),
`EpubPreferencesMappingTest.kt` (RED, new), `EpubDisplaySettingsConnectedTest.kt` (connected, new).

## Round 1

**Verdict: no Critical or High findings.** The auditor independently confirmed every Readium API
assumption and every conversion:

- `fontSize = fontSizeSp / 18.0`, `lineHeight = lineSpacing.toDouble()`, `pageMargins = marginDp / 20.0` — correct.
- theme background/ink → ARGB → Readium `Color` — correct; Serif/Sans → `FontFamily.SERIF`/`SANS_SERIF` — correct.
- `EpubPreferences` 3.3.0 constructor supports all used named args + types; `plus`/`+` is right-biased for
  non-null RHS fields, so `EpubPreferences(scroll = true) + mapped` keeps `scroll=true` while taking every
  mapped display field; `submitPreferences(EpubPreferences)` exists and returns `void`. `scroll` left null.
- collection runs on the main-thread `lifecycleScope`, cancelled on activity destruction, no concurrent
  navigator access; duplicate first emission is harmless; NaN/Inf handling acceptable (store clamps upstream).

### Findings + resolutions

| # | Severity | Finding | Resolution |
|---|----------|---------|------------|
| 1 | Medium | Connected test mutates the process-wide `ReaderSettingsStore` but restores it outside a `finally`; a mid-test failure leaks a non-default theme into later tests. | FIXED — wrapped the whole body in `try/finally`; the `finally` restores the EXACT pre-test settings captured via `store.current()` (all five fields), not a forced `Paper`. |
| 2 | Low | The two poll loops used `return@repeat`, which only returns from the iteration lambda (not `repeat`), so a success still waited ~24s. | FIXED — extracted a `pollForActivity(...)` helper that `return`s the instant the predicate holds. |
| 3 | Low | `submitPreferences` failure was swallowed by `runCatching` with no log. | FIXED — added `.onFailure { android.util.Log.w("ReaderActivity", …, it) }` (matches the app's `android.util.Log` convention). |
| 4 | Low | Test-hook comment claimed the WebView is "actually rendering"/"reached the live WebView" — overstates (it proves Readium *accepted/computed* the setting, not a painted pixel). | FIXED — reworded the `appliedBackgroundArgb()` doc + the test class KDoc to say "accepted/computed by the live navigator; a pixel/CSS assertion is WI-8 acceptance." |

After the fixes: JVM `EpubPreferencesMappingTest` re-run GREEN; the connected
`EpubDisplaySettingsConnectedTest` re-run GREEN (audit fixes touched the test code, so it was re-run per
rule 55). No open Critical/High/Medium findings remain → **Gate-4 clean in 1 round. final_verdict:
ship-as-is.**
