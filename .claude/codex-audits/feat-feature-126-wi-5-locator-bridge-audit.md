---
branch: feat/feature-126-wi-5-locator-bridge
threadId: 019f117a-5809-7be0-aecf-511d20d07ab8
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-5 (Azw3LocatorBridge)

Codex (gpt-5.5/high). **No production correctness issues.** The auditor confirmed the
mapping is right (`azw3`, finite-only `progression`, non-blank `cfi`, `wrapLegacy` →
`epubWKWebView` with the identity-derived fingerprint), that omitting `textQuote` is
acceptable for the MVP (relocate carries no visible text), and that **NFC must stay
downstream** — normalizing the foliate CFI in the bridge would make platform-local exact
restore less faithful (so storing it verbatim is correct).

2 Low (test-only), both fixed in-branch:
- Added `outOfRangeFiniteFraction_isPreserved_notClamped` (-0.1 / 1.2 preserved — the
  shared Locator contract does not clamp).
- Added `canonicalJson_isDeterministic_andNfcNormalizesStrings` (an NFD CFI →
  `canonicalJson()` is stable + NFC-normalized; no combining mark retained).

Re-verification: `Azw3LocatorBridgeTest` **10/10** (`:app:testDebugUnitTest`).

**Verdict: follow-up-recommended** — Lows fixed; no production change needed.
