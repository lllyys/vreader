---
branch: feat/137-wi1-layout-setting
threadId: 019f60e4-1dd4-7410-ae46-f3064dc5da95
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 audit — feature #137 WI-1 (Android ReaderLayout setting + store mirror)

Independent Codex audit (rule 53 via `scripts/run-codex.sh`, read-only sandbox,
gpt-5.6-sol). Full transcript: `.reports/wi1-audit.txt`.

## Scope audited

The diff on branch `feat/137-wi1-layout-setting`:

- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettings.kt`
  — added `enum class ReaderLayout { Paged, Scroll }` + `val layout: ReaderLayout
  = ReaderLayout.Scroll` field on `ReaderSettings`.
- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt`
  — mirrored the THEME wiring for LAYOUT: `ReaderSettingsState.layout: String =
  ReaderLayout.Scroll.name`, `Field.LAYOUT`, `setLayout(value, order)` via the
  shared `update()` path, `toSettings()` decode via `ReaderLayout.valueOf(layout)
  .getOrDefault(ReaderLayout.Scroll)`.
- `android/app/src/test/kotlin/com/vreader/app/reader/settings/ReaderSettingsStoreTest.kt`
  — 6 new RED-first tests (default Scroll, round-trip, flow, unknown-name→default,
  latest-wins stale-drop, per-field high-water independence).

## Findings

- **Critical**: none.
- **High**: none.
- **Medium**: none.
- **Low**: none.

## Verification summary (from the auditor)

- Per-field latest-wins sequencing uses `Field.LAYOUT`, `committedSeqByField`, and
  the shared `Mutex` — exactly the THEME mechanism.
- Writes go through the atomic DataStore `update()` path.
- `ReaderLayout.name` is persisted and decoded with `ReaderLayout.valueOf`.
- Missing or unknown persisted values safely default to `ReaderLayout.Scroll`
  (forward-compat; not a throw).
- Existing stored JSON without `layout` receives the serialization default,
  preserving scroll behavior on upgrade (iOS parity, no behavior change).
- Other settings (theme/fontFamily/fontSizeSp/lineSpacing/marginDp) remain
  preserved by the existing read-copy-normalize-write operation — no regression.
- Tests cover defaulting, round-trip, flow emission, garbage fallback, stale-write
  rejection, and independent per-field sequencing.

The auditor could not execute the Gradle test wrapper under the read-only sandbox
(it needs to write a temp log/sentinel); static inspection found no compilation or
behavioral concern. The lane ran the wrapper itself:
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` (JUnit XML: tests=15 skipped=0 failures=0
errors=0 — 9 pre-existing + 6 new LAYOUT tests).

## Final verdict

**ship-as-is** — 1 round, zero open findings.
