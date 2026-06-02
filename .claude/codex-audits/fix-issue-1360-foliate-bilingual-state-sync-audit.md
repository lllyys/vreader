---
branch: fix/issue-1360-foliate-bilingual-state-sync
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #305 (Foliate bilingual state-sync on reopen)

Runner: cc-suite via `scripts/run-codex.sh` (watchdog — SUCCEEDED, no ghost),
gpt-5.4, medium, read-only.

## Verdict: CLEAN — no findings.

- `ensureBilingualViewModel()` on every `.foliateSectionLoaded` is safe +
  idempotent: returns once `bilingualViewModel != nil`; exits cleanly if the
  coordinator isn't ready (retries on a later section-load).
- No spurious setup sheet on reopen: `needsSetupSheet` defaults false, set only
  inside `setEnabled(true)` when `!hasBeenConfigured`; `ensureBilingualViewModel`
  only reads it.
- `postDidChange()` on build is safe: an unconfigured book posts `isEnabled=false`
  → parent mirrors OFF + clears decorations (correct no-op, not a setup trigger).
- No ordering issue with `publishTranslateBookTextProviderIfReady()` just before:
  the early ON notification can't inject stale content (`injectIfCached` also
  needs isEnabled + locator + cached translations + enumerated blocks).

ship-as-is.
