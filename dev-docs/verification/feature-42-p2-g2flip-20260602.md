---
kind: feature
id: 42
status_target: DONE
commit_sha: 439351ada8215963f3de65468d83f98606c61302
app_version: "3.42.42 (805)"
date: 2026-06-02
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #42 Phase 2 — G2 flag flip (kindleConvertOnImport default ON) device verification

User ratified the G2 flip (default OFF→ON). This verifies that, with no launch flag,
a real Kindle file now converts to EPUB on import and renders via the default Readium
engine.

## Acceptance criteria

| Criterion | Method | Observed | Result |
|---|---|---|---|
| With `kindleConvertOnImport` default ON (no flag), a real AZW3 import converts to a first-class EPUB | Launched the default-ON build with NO `--enable-kindle-convert` flag; `vreader-debug://reset`; imported the real `被讨厌的勇气` AZW3 (6.3 MB, KF8) via the Documents/Inbox `openurl` path | The library cell shows **"EPUB format"** (was "AZW3 format" under default-OFF); `vreader-debug://snapshot` reports **`format: epub`** | pass |
| The converted EPUB renders via the Readium engine | Opened the imported book | The COPYRIGHT page + Chinese metadata (书名/作者/出版社/ISBN) render cleanly via the default Readium EPUB host | pass |

## Commands run

```bash
# default-ON build, NO --enable-kindle-convert flag
xcrun simctl launch <UDID> com.vreader.app          # no flag
xcrun simctl openurl <UDID> "vreader-debug://reset"
cp bei-tao-yan.azw3 "$APP_DATA/Documents/Inbox/"
xcrun simctl openurl <UDID> "file://$APP_DATA/Documents/Inbox/bei-tao-yan.azw3"
# library shows "… EPUB format"; snapshot → format: epub
```

## Observations

- The flip is the human-gated G2 the user ratified. Compared to the WI-5 run (default
  OFF → the same AZW3 imported native `.azw3`), the same file under default ON now
  converts to EPUB and routes through Readium — the intended Phase-2 behavior.
- Existing native `.azw3` books (imported before the flip) are unaffected; only NEW
  imports convert. A user can revert via the persisted `kindleConvertOnImport`
  override OFF (`FeatureFlagsTests.kindleConvertOnImportOverridePersists`).

## Artifacts

- `dev-docs/verification/artifacts/feature-42-p2-g2-flip-azw3-converted-to-epub-20260602.png`
