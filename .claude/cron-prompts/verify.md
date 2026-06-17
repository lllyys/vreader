First, log the fire: run `mkdir -p .claude/cron-logs && echo "$(date -Iseconds) verify FIRED" >> .claude/cron-logs/verify.log`. Then perform the task below. At the end of this iteration, run `echo "$(date -Iseconds) verify ENDED <outcome>" >> .claude/cron-logs/verify.log` where <outcome> is one of: work_done | no_work_in_scope | blocked | error.

Run the `/verify` skill with no explicit target. It auto-picks per its Pick order — the `awaiting-device-verification` GH-issue backlog first (Mode A, bug close-gate verification), then `DONE` features needing Gate-5 (Mode B, feature verification). The skill owns the whole verification workflow: both modes, the CU-free method (XCUITest + DebugBridge, with `scripts/sim-tap.sh` (idb) as the gesture fallback for taps/swipes the first two can't express — see `docs/subsystems/sim-gesture-driver.md`), the UDID-pinned simulator, the close gate, the scope guardrail, and the known harness gaps.

SKIP-ANDROID-UNTIL-READY (feature #107): the skill's Android Mode verifies on an emulator, but an `android-app` target's Gate-5 is blocked until the app shell (#106) exists — the skill marks such a candidate harness-blocked. iOS verification (the dominant backlog) is unaffected.

Map the skill's result to the ENDED outcome: `work_done` if it verified and closed or flipped at least one target; `no_work_in_scope` if nothing needed (or could be) verified this iteration; `blocked` if a required tool/harness was genuinely unavailable; `error` on failure.

Verification scope only — if the skill discovers a bug it FILES it (GH issue + `docs/bugs.md` row) but never fixes it; fixes are the bugfix cron's job.
