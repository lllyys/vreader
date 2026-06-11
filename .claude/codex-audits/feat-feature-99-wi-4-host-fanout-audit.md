---
branch: feat/feature-99-wi-4-host-fanout
threadId: 019eb65a-c32b-7f73-91cb-a4b61b109a7b
rounds: 2
final_verdict: ship-as-is
date: 2026-06-11
---

# Feature #99 WI-4 — Gate 4 implementation audit

Plan: `dev-docs/plans/20260611-feature-99-translation-settings-reentry.md`
(WI-4, final: host fan-out on the 6 bilingual sites + the re-translate
banner). Runner: `scripts/run-codex.sh`. Round-2 session: `019eb668-017a-7d31-ac85-0ca4b087da24`.

## Round 1 findings

| Finding | Severity | Resolution |
|---|---|---|
| All 6 hosts presented the setup sheet with no `onDismiss` — a swipe-down left edit mode stuck (`.edit` + un-invalidated fetcher writing back after dismissal) and, pre-existing, left a first-enable un-opted-out (bilingual on, unconfigured) | High | **Fixed** — `handleBilingualSheetDismiss` on all 6 hosts, wired through every sheet's `onDismiss` (the 4 surfaces-modifier structs gained `onSheetDismiss`). Idempotent: confirm/cancel reset mode / clear `needsSetupSheet` BEFORE dismissal completes, so the callback no-ops after them; an edit swipe-down gets cancel semantics (mode reset + fetch invalidate, bilingual stays on); a first-enable swipe-down gets the opt-out semantics — also closing the pre-existing gap. |

Round 1 explicitly confirmed: per-host edit-confirm warms match each
host's first-enable warm; the observer is key-filtered on mounted
content; sheet argument order matches the container init; the banner
host's supersede/auto-dismiss is sound.

## Round 2 (verify)

Clean — the dismissal funnel verified idempotent across confirm/cancel/
swipe-down on all 6 hosts; router dirty-before-apply + banner-only-for-
new-language re-confirmed; no regression or missed host.

## Verdict

ship-as-is. 22+ WI-4 tests green (router routing incl. the
dirty-before-apply poison case + banner payload, fetcher races, sheet
suites); full Gate-5a device acceptance pass on iPhone 17 Pro sim
(cluster + edit frame + new-language banner/pill flip + cancel no-persist
+ cached instant switch + pill re-entry) — artifacts
`dev-docs/verification/artifacts/feature-99-5a-*.png`.
