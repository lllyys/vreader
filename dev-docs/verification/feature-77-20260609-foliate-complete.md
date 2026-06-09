---
kind: feature
id: 77
status_target: VERIFIED
commit_sha: 97973cedf0a6f8c7da0555555b609c73e2f17078
app_version: 3.59.32 (build 932)
date: 2026-06-09
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator (61149F0E-DC18-4BE2-BB37-52659F1F4F62)
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (MockAIProvider, key-free)
result: pass
---

# Feature #77 — Gate-5b COMPLETE: inline bilingual loading shimmer (all engines)

Supersedes the partial run in `feature-77-20260609.md`. The earlier run verified
Readium (default EPUB) + legacy EPUB (paged + continuous) but left Foliate (AZW3)
unconfirmed (the translation never replaced the shimmer). That was root-caused as
**bug #334 / GH #1586** (a foliate-host.js section-text extraction defect, NOT a
#77 shimmer defect) and fixed in v3.59.32 (merge `97973ced`). With #334 fixed, the
Foliate slice now passes, completing Gate-5b for every engine family.

## Acceptance criteria

| # | Criterion | Engine | Observed | Pass |
|---|---|---|---|---|
| 1 | Shimmer renders during prefetch | Readium (default EPUB) | DOM `loading:3` (feature-77-20260609.md) | ✅ |
| 2 | Transient — clears → translation | Readium | `loading:0, mock:3` | ✅ |
| 3 | Shimmer renders during prefetch | Legacy EPUB (paged + continuous) | DOM `loading:6` | ✅ |
| 4 | Transient — clears → translation | Legacy EPUB | `loading:0, mock:6` | ✅ |
| 5 | Shimmer renders during prefetch | Foliate (AZW3) | DOM `loading:4`, visual `EN↔中` shimmer | ✅ |
| 6 | Transient — clears → translation | Foliate (AZW3) | `blocks:4` → POST `loading:0, mock:4`; `[MOCK译]` interlinear rows render inline | ✅ (post-#334 fix) |

## Commands run

```bash
# Foliate slice on the merged build with the #334 fix (v3.59.32):
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62
xcrun simctl install "$SIM" "<BUILT_PRODUCTS_DIR>/vreader.app"
xcrun simctl launch "$SIM" com.vreader.app --uitesting --uitesting-no-seed \
  --mock-ai --mock-ai-translate-delay-ms=2000 --enable-ai
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=<azw3-key>"
xcrun simctl openurl "$SIM" "vreader-debug://seek?fraction=0.45"
xcrun simctl openurl "$SIM" "vreader-debug://bilingual?action=enable&lang=Danish"
xcrun simctl openurl "$SIM" "vreader-debug://eval?bridge=azw3&js=<base64 frame counter>"
# → {"blocks":4,"loading":0,"mock":4}
```

Readium + legacy EPUB commands are in `feature-77-20260609.md` (unchanged — those
engines passed on v3.59.30 and are not affected by the #334 fix).

## Observations

- The #334 fix (shared `bilingualLeafBlockElements` selector so the translate's
  paragraph count equals the enumerate's block count) was the only thing standing
  between the partial and complete Gate-5b. The shimmer-render half of Foliate was
  always correct; only the translation-replace half was broken.
- Verified on both a single-block page (`blocks:1 → mock:1`) and a multi-block body
  section (`blocks:4 → mock:4`) on the merged build.
- All three engine families now exhibit the full transient cycle: shimmer up during
  prefetch (`loading:N`), shimmer replaced by translation on land (`loading:0,
  mock:N`).

## Artifacts

- `artifacts/feature-77-foliate-B-shimmer-20260609.png` — Foliate shimmer (pre-fix render).
- `artifacts/bug-334-foliate-fixed-multiblock-20260609.png` — Foliate translations injected inline (post-fix).
