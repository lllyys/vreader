---
branch: feat/feature-79-wi1-placeholders
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, /tmp/feat79-implaudit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-03
---

# Gate-4 Codex audit — Feature #79 (provider-editor Base URL/Model placeholders)

Independent impl audit (Codex gpt-5.4, high, read-only) of the diff implementing
Variant A (add-mode empty fields + kind-default placeholder + "Default" tag +
effective-value validate/persist/test, add-mode-only). One round; author=this
session, auditor=Codex (rule-48 separation).

The auditor confirmed the add-mode Base URL gating is consistent across `canSave`,
`save()`, `runTest()`, and the live `baseURLError` path; the Default-tag /
placeholder gating is add-mode + empty-only; kind changes leave blank add-mode
fields blank while the placeholder follows `kind`; and no Swift-6 actor-isolation
issue in the new pure statics.

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `AIProviderEditSheet.swift:156` (`effectiveModel`) | Medium | The helper trimmed `model` in BOTH modes; since `save()`/`runTest()` consume it, an EDIT-mode profile with a whitespace-padded model would be silently normalized on an unrelated save — contradicting the "edit-mode raw, no silent change" contract (pre-#79 `save()` persisted `model` untrimmed). | **FIXED** — `effectiveModel` now returns the RAW `typed` value in edit-mode (`guard isAddMode else { return typed }`); the blank→`kind.defaultModel` fallback (trim-checked) stays add-mode-only. Added regression test `effectiveModel_editMode_preservesRawWhitespace_noNormalization` (`"  gpt-x  "` / `"   "` preserved verbatim in edit-mode). |

## Verified by the auditor (no change needed)
- `effectiveBaseURLText` trimming matches pre-#79 (`save()` already trimmed the URL),
  so no edit-mode URL regression.
- Default tag / placeholder gating add-mode + empty-only; Rule-51 satisfied (the
  tag is in the committed canvas).
- No dead code; statics are pure + test-callable.

## Verdict

`ship-as-is` — the single Medium (edit-mode model normalization) fixed + regression-
tested. Suites green: `AISettingsViewModelEditorTests` (37 incl. the new #79 helper
tests), `AIProviderEditSheetSaveSuccessTests` (4).
