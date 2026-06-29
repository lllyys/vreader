---
branch: feat/feature-126-wi-0-spike
threadId: 019f113e-1a12-7b93-982e-7553820cecc5
rounds: 1
final_verdict: follow-up-recommended
date: 2026-06-29
---

# Gate-4 audit — feature #126 WI-0 (AZW3 reader go/no-go security spike)

Codex (gpt-5.5/high) audited the hand-written spike files (NOT the vendored minified
`foliate-bundle.js`, which is the iOS bundle + a 2-line security patch documented in
`bundle-patch.md`). Verdict: **follow-up-recommended**. The auditor confirmed the GO
conclusion is trustworthy in the narrow sense ("removing `allow-scripts` blocks the
synthetic script escape and does not break the tested real reflowable AZW3 render"),
that the attack payload is well-formed (the positive control rules out a
malformed-payload false-pass), and that the main-thread WebView usage, `Assume` guard,
and `LinkedBlockingQueue`/`AtomicInteger` concurrency are sound.

## Findings + resolutions

| # | sev | finding | resolution |
|---|---|---|---|
| 1 | **High** | The security test uses its own synthetic blob iframe; it doesn't prove the patched bundle strips `allow-scripts` from EVERY real foliate section path → could false-pass on drift/partial patch. | **Fixed** — added `patchedBundle_hasNoAllowScriptsInAnySectionIframe()` asserting the shipped bundle contains **0** `allow-scripts` (covers reflowable + fixed-layout); guards drift. Running the payload through the REAL foliate fixed-layout section path is moved to WI-3's test (plan narrowed). |
| 2 | Medium | `pwnedHits()` only counted "PWNED"; didn't prove the 3 distinct paths or capture `isMainFrame`. | **Fixed** — `pwnedMarkers()` asserts the distinct set `{parent.vreaderHost, top.vreaderHost, parent.webkit}` in the control and records `isMainFrame` per hit. Result: all 3 report `isMainFrame=true` — empirically confirming `isMainFrame` alone is insufficient and the `allow-scripts` strip is load-bearing. |
| 3 | Medium | Navigation relocate was printed, not asserted (test could pass with `+nav=0`). | **Fixed** — added `assertTrue(total > afterInit)`. |
| 4 | Medium | Plan's WI-0 charter/test-catalogue claimed coverage (synthetic-large, peak memory, render-recovery, locator round-trip, fixed-layout hostile, passive exfil) not in the harness → internally inconsistent. | **Fixed** — plan WI-0 verdict adds an explicit "Scope proven by this spike" vs "Deferred to owning WIs (WI-3/WI-6/WI-7/WI-8)" note. |
| 5 | Low | Shell CSP uses `'unsafe-inline'` — fine for a throwaway spike, not the final posture. | **Accepted (spike)** — noted in the plan verdict; WI-1/WI-3 ship the nonce/hash shell CSP + section CSP. |

## Re-verification
After the fixes, `FoliateSpikeHarnessTest` (3 tests) runs green on emulator API 35:
`VERDICT: GO — sections=85, relocates=5`; `SECURITY: blocked=0, control=[(parent.vreaderHost,true),(top.vreaderHost,true),(parent.webkit,true)]`.

## Verdict
**follow-up-recommended.** All High/Medium findings fixed in-branch; the Low is an
accepted spike posture with the production fix scoped to WI-1/WI-3. The go/no-go = **GO**
is sound for the proven scope (reflowable AZW3 render + same-origin script-escape boundary
+ full-bundle patch coverage).
