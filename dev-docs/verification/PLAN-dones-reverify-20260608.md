# Verification plan — every bug + every DONE-not-VERIFIED feature (2026-06-08)

Goal: *"make plans for every bugs and features verification. verify the bugs and
features according to the plans."* This is the master plan; per-feature execution
evidence lands in sibling `feature-<id>-20260608.md` files.

## Inventory (commit b6c74591, v3.59.23)

- **Bugs** — `docs/bugs.md`: 98 FIXED + 1 WONT FIX. **0 open GH issues, 0
  `awaiting-device-verification`.** Every bug that had a GH mirror was verified
  and closed per the close gate. **→ No bug verification debt. Plan for bugs =
  confirm-clean (done): the absence of open issues / awaiting-verification labels
  IS the standing evidence that the bug close-gate cleared every row.**
- **Features** — `docs/features.md`: 83 VERIFIED, **5 DONE-not-VERIFIED**
  (#5, #45, #54, #68, #77), 2 DUPLICATE, 1 WONT DO, 1 DEFERRED. The 5 DONE rows
  are the verification debt; plans + dispositions below.

## Per-feature plans + dispositions

| # | Feature | Prior | Disposition | Method |
|---|---|---|---|---|
| 5 | Search highlight auto-dismiss | fail (2026-05-13) | **Verifiable now** | Prereq bugs #153/#154 FIXED+closed but never re-verified since. `search?query=&index=` driver fires synchronously (no model round-trip → defeats the old screenshot-timing artifact). Open TXT, search an in-viewport term, screenshot the yellow highlight + confirm dismiss-on-new-search/scroll. |
| 45 | Verification harness sweep | partial (round6) | **Verifiable (evidentiary)** | The device-verification backlog the harness targeted is now empty (every downstream feature independently VERIFIED). Only gap: no `result:pass` file. Run the `Verification` xctestplan GREEN; 2 env-gated (WebDAV/OPDS) + 2 manual (TTS-quality, iCloud) items are documented accepted-scope, not blockers. |
| 54 | Remove reading-mode toggle | partial | **BLOCKED — not a tooling gap** | Acceptance criterion "replacement rules in native EPUB" (plan Phase D-1) was **never built**. The #42 dependency that blocked it is now resolved (Readium default), so it's buildable-but-unbuilt. A verification pass re-produces `partial`. Needs a USER DECISION: implement Phase D-1 (a feature slice, out of verify scope) OR descope the EPUB half. **Cannot flip to VERIFIED by verification alone.** |
| 68 | Chapter-start typography | partial (2026-05-27) | **9/10 verifiable now** | Bug #272 (which blocked MD/TXT page-1 capture) is FIXED → criteria #3/#9/#7-MD newly unblocked via `simctl io screenshot`. #6 (AZW3 positive drop-cap visual) blocked by a missing flat-top-level-`<p>` AZW3 fixture (`mini-azw3` first `<p>` is section-wrapped = documented safe-miss; the rule is unit-pinned + confirmed identical-correct on EPUB via eval). |
| 77 | Bilingual loading shimmer | never verified | **Verifiable (primary surfaces)** | `--mock-ai` removes the API-key wall. Structural `eval` of the live Readium-EPUB + Foliate-AZW3 WebView DOM for `.vreader-bilingual-loading[data-vreader-decoration]` + 2 shimmer bars + resolved `vreaderBilingualShim` animation, during an in-flight prefetch, then the land→translate handoff. Legacy WI-4/5 (Readium-OFF) verifiable only if the engine flag is CU-free flippable; else unit-covered + named deferral. |

## Execution order (single simulator → serialize, rule 52)

1. **#5, #68, #77** — interactive sim-driven (eval + screenshot), main UDID `61149F0E-DC18-4BE2-BB37-52659F1F4F62`.
2. **#45** — the `Verification` UITest plan run LAST (it drives the sim itself; nothing else may touch the UDID while it runs).
3. **#54** — no sim work; document the blocked criterion + surface the scope decision to the user.

Evidence files: `dev-docs/verification/feature-{5,45,54,68,77}-20260608.md`. Row flips
to VERIFIED only where `result: pass` (PreToolUse hook enforces evidence presence).
All edits on branch `verify/dones-reverify-20260608` → PR (main is protect-from-direct-commit).

## Execution outcomes (2026-06-08)

| # | Result | Action taken |
|---|---|---|
| **5** | **pass → VERIFIED** | The yellow search highlight renders in-viewport (`simctl io screenshot` captured what the prior CU rounds couldn't); bug #154's fix confirmed on device. Row flipped. |
| **45** | **pass → VERIFIED** | Backlog retired (14 downstream features all VERIFIED) + fresh harness subset GREEN (0 product failures). Row flipped. |
| **54** | partial → stays DONE | Criterion 3 (native-EPUB replacement rules) is **un-built** (Phase D-1; the #42 blocker is resolved but the work was never done). Not a verification gap — **needs a user scope decision**: implement Phase D-1, or descope the EPUB half. |
| **68** | partial → stays DONE | MD drop-cap+heading newly confirmed (pass). **Defect found**: EPUB drop-cap is absent in continuous-scroll mode — `body > p:first-of-type` doesn't match the #71 stitch's DIV-wrapped DOM (eval-proven). Logged to `docs/tasks.md` for triage → bugfix. |
| **77** | partial/blocked → stays DONE | Bilingual mode enables but no translations/loading decorations render under `--mock-ai` + a seeded mock-provider; the inline-bilingual prefetch needs a real provider profile+key and a Swift-side trigger. **Harness gap** (recommend a DebugBridge enable-bilingual + force-prefetch + readiness-readout command). Structural path unit-tested.

**Net:** 2 features VERIFIED; 1 needs a user scope decision (#54); 1 bug to triage
(#68 EPUB drop-cap); 1 harness gap to build before #77 is CU-free verifiable.
Bug side confirmed clean (0 open issues, 0 awaiting-verification).
