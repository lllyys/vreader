---
branch: feat/128-wi2-addedat-test-precision
threadId: run-codex-inline-wi2fix
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Gate-4 audit — #128 WI-2 addedAt connected-test precision fix

**Context:** the WI-2 live WebDAV round-trip (Gate-5) failed on
`WebDavRoundTripConnectedTest.authorSurvivesRoundTrip_overLiveWebDav:188` —
`addedAt survived the round-trip expected:<…261314> but was:<…261000>`. Root
cause: the backup manifest's `IsoInstantSerializer` (`android/identity/.../backup/BackupJson.kt:41`)
encodes timestamps with `.truncatedTo(ChronoUnit.SECONDS)` (iOS `.iso8601`
parity), so `addedAt` round-trips at **whole-second** precision by contract.
WI-2 did not change `addedAt` handling (identical `toEpochMilli()` before and
after), so this is a too-strict test assertion, not a product defect.

**Fix:** one line — the connected test now asserts `addedAt / 1000 ==
restored.addedAt / 1000` (second precision) instead of exact-millis equality,
with an explanatory comment citing the serializer.

**Codex verdict: ship-as-is.**
- (1) The fix correctly matches the serializer's seconds truncation.
- (2) Test-only; no production behavior change.
- (3) Coverage not weakened — `author` and `title` are still asserted exactly;
  only `addedAt` is relaxed to its contractual second precision.

**Re-verification:** the round-trip re-ran green from the worktree harness —
`RUN-WEBDAV-ROUNDTRIP RESULT: SUCCEEDED`, `tests="2" failures="0"` (both
`authorSurvivesRoundTrip_overLiveWebDav` and `backup_then_restore_overLiveWebDav`).
