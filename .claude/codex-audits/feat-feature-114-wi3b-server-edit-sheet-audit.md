---
branch: feat/feature-114-wi3b-server-edit-sheet
threadId: 019ee291-5158-7fa1-a623-051c500517c5
rounds: 3
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #114 WI-3b surface B (ServerEditSheet)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the add/edit server sheet (design
surface B from `vreader-backup-webdav.jsx` ServerEditSheet): `ServerEditSheet.kt`, the new
`AppSheet`/`AppAlert` primitives in `BackupScaffold.kt`, the `ServerEditState`/`ConnTest` model,
`ServerEditSheetTest.kt`.

## Round 1 — 1 High + 4 Medium + 1 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| **High** | the "sheet" was a full-screen flat surface, missing the design's scrim / bottom-rounded sheet / grabber / header / scroll | **Fixed**: added an `AppSheet` primitive (dim scrim, bottom 0.96-height top-rounded sheet, drag grabber, Cancel/title/Save header, `verticalScroll` body); `ServerEditSheet` uses it. |
| Medium | body not scrollable | **Fixed** (AppSheet's `verticalScroll`). |
| Medium | `AppAlert` not centered / no max-width / scrim-tap fallthrough | **Fixed**: `widthIn(max=300)` + centered text + a tap-consumer. |
| Medium | touch targets (Cancel/Save text-only, toggle, test) | **Fixed**: 48dp hit boxes; the Wi-Fi row is fully clickable. |
| Medium | test coverage gaps (field onChange, toggle, Cancel/Save, alert, promise text) | **Fixed**: +6 tests (name-field typing via `testTag`, wifi-row toggle, Cancel, Save fires/doesn't-fire, promise text). |
| Low | unused `assertEquals` import | **Fixed**. |

## Round 2 — 2 Medium (fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | `AppAlert` `clickable(enabled=false)` doesn't reliably consume taps | **Fixed**: an ENABLED no-op `clickable(indication=null, interactionSource=remember{…})` + a `removeConfirm_tappingTitle_doesNotDismiss` test. |
| Medium | Cancel/Save not guaranteed 48dp-wide hit targets | **Fixed**: `Modifier.sizeIn(minWidth=48.dp, minHeight=48.dp)` before `clickable`. |

## Round 3 — CLEAN

> "`AppAlert` card now uses an enabled no-op clickable consumer … `Cancel`/`Save` … now have
> 48 dp minimum hit targets … No remaining Critical, High, or Medium findings."

## Verdict

**ship-as-is.** 15 instrumented `ServerEditSheetTest` green on emulator-5554 (add/edit titles,
fields, test idle/testing/ok/fail, Test-Connection + Remove + Save/Cancel callbacks, the
"backups left untouched" promise, alert-body-tap-doesn't-dismiss, dark). Behavioral WI —
emulator Compose-test verified. This completes WI-3 (the server list + edit pair).
