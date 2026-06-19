# Feature #114 — Android backup & WebDAV restore UI

Status: Gate-2 audited (2026-06-20, Codex round 1 → revised; see Revision history). The
user-facing UI for backup/restore on Android, implementing the committed design
`dev-docs/designs/vreader-fidelity-v1/project/vreader-backup-webdav.jsx` (+ `design-notes/
android-phase3-issues.md`) — the surfaces design-gated as #1767 (now landed). Under the #110
Android Phase-3 driver.

## Problem

iOS has a full backup/restore UI. Android has the data-layer foundation (feature #113
backup-format DTOs) but no UI. This feature builds the five designed Compose surfaces, wired
to a `BackupViewModel` exposing the designed states behind a **`BackupService` interface** (the
seam to the future WebDAV client + restore pipeline — a SEPARATE backend feature; the design
note is explicit the backend "ships separately and isn't design-gated").

**Binding scope guard (Gate-2 High-1):** this feature ships the UI **reachable only via a
DEBUG launcher + instrumented tests** — it is NOT wired into a production user path, and the
production `AppContainer` does NOT inject preview/fake data. A `PreviewBackupService` (DEBUG /
test only) drives the designed states for verification. Shipping fake servers/backups as real
user functionality is explicitly prohibited; the production entry point lands only when (a) the
real `BackupService` backend exists AND (b) a committed Android **Settings entry-point** design
exists (neither is in #114's scope).

## Surface area (the 5 designed surfaces)

All new, under `android/app/.../backup/`:

- **`backup/BackupTokens.kt`** — a dedicated token provider (Gate-2 Low): a `BackupTokens` data
  class with the design's full set (`bg/ink/sec/ter/tint/green/red/sep/chipBg/placeholder/
  sheetBg/isDark`) for BOTH light + dark, populated EXACTLY from the jsx `UI.light`/`UI.dark`
  values + `SERIF/SANS/MONO`. Exposed via a `CompositionLocal` (`LocalBackupTokens`) chosen on
  `isSystemInDarkTheme()`. Does NOT mutate the light-only global `VReaderColors`.
- **`backup/BackupScaffold.kt`** — the reused Compose primitives: `NavScreen`/`BackupTopBar`
  (back + serif title, large/compact), `SettingsCard`/`SettingsRow`/`GroupHeader`/`GroupFooter`/
  `Tag`/`StatusDot`/`BackupToggle`/`AppAlert`.
- **`backup/BackupRestoreScreen.kt`** (surface C) — active-server header + **Back Up Now**
  (idle/`syncing`), Available-Backups list, states `idle`/`loading`/`empty`/`error`
  (401/404/offline/timeout, each its cause + one CTA).
- **`backup/RestoreFlow.kt`** (surface D) — the restore **confirm alert** + **RestoreProgress**
  (progress/success/partial/failed), each with its CTA; "Restore never deletes" copy.
- **`backup/WebDavServersScreen.kt`** (surface A+B) — saved-servers list (empty onboard /
  populated rows w/ status dot + exact failure / error), and **ServerEditSheet** (add/edit:
  name/base-URL/username/password + Wi-Fi-only toggle + **Test Connection** against the live
  form: idle/testing/ok/fail + Remove-Server confirm).
- **`backup/SelectiveRestoreSheet.kt`** (surface E) — per-book picker, row states
  `local`/`remote`/`downloading`/`failed` (lazy-on-tap), pinned selection-total footer.
- **State/VM/seam**: `backup/BackupUiState.kt` (the designed-state models), `backup/
  BackupViewModel.kt` (`StateFlow<…>` + one-shot event channel + intents), `backup/
  BackupService.kt` (the **UI-oriented** interface — see below), `backup/PreviewBackupService.kt`
  (**DEBUG/test only**), and a **`backup/BackupDebugActivity.kt`** (DEBUG-only launcher so the
  UI is reachable for emulator verification without a production entry point).

**`BackupService` (UI-oriented seam, Gate-2 Medium-2)** — no backend mechanics (no blob paths,
ZIP, PROPFIND/PUT, raw download) leak in:
```
suspend fun listServers(): List<ServerSummary>
suspend fun testConnection(draft: ServerDraft): TestResult        // ok / fail(httpCause)
suspend fun listBackups(serverId: String): BackupListResult        // ok(list) / error(cause)
fun startBackup(serverId: String): Flow<BackupProgress>            // done/total, terminal
suspend fun loadManifest(backupId: String): List<ManifestBook>
fun restore(backupId: String, selection: Set<String>): Flow<RestoreProgress> // book-by-book → result
suspend fun retryBook(backupId: String, bookId: String): BookRestoreResult
```

**Files OUT of scope**: real WebDAV networking / ZIP / restore-import pipeline / backup-collector
(a SEPARATE future backend feature behind `BackupService`); the iOS side; a **production
Settings entry point** (no committed Android Settings design — Gate-2 High-2; file a
`needs-design` issue if/when a production entry is wanted). #113 DTOs already exist.

## Prior art / project precedent / rejected alternatives

- **Precedent**: `TxtReaderActivity` (Compose `ComponentActivity` + theme + cream scaffold),
  `LibraryScreen` + `LibraryViewModel` (`StateFlow<UiState>` collected via
  `collectAsStateWithLifecycle` + a one-shot **event `Channel`** for transient effects). This
  feature follows that exact UDF shape (rule 50 §12).
- **Design source**: `vreader-backup-webdav.jsx` (committed) is pixel-authoritative; the plan
  maps its tokens + each component 1:1 to Compose, light AND dark.
- **Rejected — Material-default screens** (rule 51 + the design note: VReader's own vocabulary).
- **Rejected — building the WebDAV backend here** (design note scopes it separate; the
  `BackupService` interface + `PreviewBackupService` make the UI verifiable now).
- **Rejected — a production Settings entry + production preview data** (Gate-2 Highs: would ship
  fake functionality + invent an undesigned Settings surface).
- **Rejected — mutating `VReaderColors` into a mixed static/dynamic theme** (Gate-2 Low: a
  dedicated `BackupTokens`/`CompositionLocal` instead).

## Work items (Gate-2 Medium-1: 5 independently-testable WIs)

| WI | Scope | Tier |
|---|---|---|
| WI-1 | **Foundation**: `BackupTokens` (light+dark, `CompositionLocal`) + `BackupScaffold` primitives + `BackupUiState` models + `BackupService` interface + `PreviewBackupService` (DEBUG) + `BackupViewModel` skeleton (StateFlow + event channel, concurrency rules) + `BackupDebugActivity`. Tests: `BackupViewModelTest` (JVM, fake service) for the core state machine + a `BackupScaffoldTest` (a primitive renders light+dark). | foundational |
| WI-2 | **`BackupRestoreScreen`** (surface C): header + Back-Up-Now (idle/syncing via `startBackup` Flow), list, states idle/loading/empty/error·401/404/offline/timeout + the right CTA each. Compose tests per state. | behavioral |
| WI-3 | **`WebDavServersScreen`** (surface A) + **`ServerEditSheet`** (surface B): list empty/populated/error; add/edit + Test-Connection idle/testing/ok/fail (cancel on form-change) + Remove confirm. Compose tests. | behavioral |
| WI-4 | **restore flow** (surface D): confirm alert (merge copy) → `RestoreProgress` progress/success/partial/failed via `restore` Flow + Cancel/Retry/Done CTAs. Compose tests. | behavioral |
| WI-5 | **`SelectiveRestoreSheet`** (surface E): per-book local/remote/downloading/failed + lazy-on-tap (`retryBook`) + footer total; final acceptance pass across all surfaces light+dark. Compose tests + evidence file. | behavioral (final WI) |

## Concurrency rules (Gate-2 Medium-3 — encoded in `BackupViewModel`)

- **One active long job** at a time: a second `startBackup`/`restore` intent while one runs is
  ignored/coalesced (the button shows in-progress, not re-fired).
- **Test-connection is cancellable**: editing any server field or dismissing the sheet
  **cancels** the in-flight `testConnection` job; a stale result never overwrites newer state.
- **Request-id tagging**: each async result carries the intent's request id; the VM drops a
  result whose id != the current one (no stale-overwrite).
- **One-shot vs durable**: transient effects (a toast, "open server settings" nav) go through a
  one-shot event `Channel` (like `LibraryViewModel.events`), never the durable `StateFlow`.
- UI collects via `collectAsStateWithLifecycle`.
- Tests: rapid double `backUpNow` → one job; `testConnection` then immediate field-edit → the
  result is dropped; `StandardTestDispatcher` for determinism.

## Test catalogue

- WI-1 `BackupViewModelTest` (JVM `runTest` + fake `BackupService`): `backUpNow` → syncing →
  idle; `loadBackups` error → the right `BackupListState.Error(cause)`; concurrency (one job;
  stale-test-result dropped; double-tap coalesced). `BackupScaffoldTest`: a primitive renders
  in light + dark from `BackupTokens`.
- WI-2 `BackupRestoreScreenTest` (instrumented): each state renders its designed content +
  single CTA (401→"Open Server Settings", 404→"Back Up Now", offline/timeout→"Retry",
  empty→"No backups yet", loading→"Reading backups from server…", syncing→"Backing up… 8 / 12",
  idle→a row + "Latest").
- WI-3 `WebDavServersScreenTest` + `ServerEditSheetTest`: empty onboard CTA; populated rows show
  the status dot + exact failure (`401 — authentication failed`); test idle→testing→ok/fail
  inline; Remove confirm; Wi-Fi-only toggle.
- WI-4 `RestoreFlowTest`: confirm-alert "Nothing is deleted"; progress percent + book label +
  Cancel; success/partial[Retry 3 Books]/failed[library unchanged] + CTAs.
- WI-5 `SelectiveRestoreSheetTest`: the 4 row states + footer total "{n} books selected";
  toggle-book updates the count; final acceptance evidence.

## Risks + mitigations

- **R1 — shipping fake data as real (Gate-2 High-1).** `PreviewBackupService` is DEBUG/test
  only; production `AppContainer` never injects it; the UI is reachable only via
  `BackupDebugActivity` (DEBUG) + instrumented tests in #114. The production entry point is a
  later, separately-gated change.
- **R2 — undesigned Settings entry (Gate-2 High-2).** No production Settings nav in #114; if a
  production entry is later wanted, file a `needs-design` issue for the Android Settings surface.
- **R3 — dark-mode fidelity.** `BackupTokens` carries both palettes EXACTLY from the jsx
  `UI.light`/`UI.dark`; dark verified on the emulator in dark mode.
- **R4 — concurrency.** The VM rules above + their tests.
- **R5 — sheet host.** Compose `ModalBottomSheet` for `AppSheet`-style sheets; one
  `BackupDebugActivity` with internal Compose state for navigation between the pushed screens.

## Backward compat

Additive + DEBUG-isolated: new screens reachable only via a DEBUG launcher; production
`AppContainer` unchanged (no `BackupService` injected into any production path yet). No schema
change, no library/reader impact.

## Acceptance criteria

1. All five designed surfaces render in Compose matching `vreader-backup-webdav.jsx` (light +
   dark), in VReader's vocabulary.
2. Every designed STATE renders its content + correct single CTA (4 WebDAV errors, 4 restore
   results, 4 per-book states, test-connection states).
3. `BackupViewModel` drives state via `BackupService` with the concurrency rules (unit-tested:
   one job, stale-result-dropped, coalesced double-tap).
4. Compose UI tests pass on the emulator for every surface/state (via `BackupDebugActivity`);
   "Restore never deletes" appears in the confirm alert + footer + success.
5. **No production user path + no fake data in production**; no real WebDAV/restore networking;
   no library/reader regression.

## Revision history

- **v1** (2026-06-20) — Gate-1 draft.
- **v2** (2026-06-20) — Gate-2 audit round 1 (Codex `019ee117`). All findings addressed:
  - *(High)* fake-data-in-production → `PreviewBackupService` is DEBUG/test-only; UI reachable
    only via `BackupDebugActivity` + tests; production `AppContainer` injects nothing.
  - *(High)* undesigned Settings entry → removed production entry-point wiring; documented as a
    separate `needs-design` if ever wanted.
  - *(Medium)* WI-1/WI-3 too big → split into 5 independently-testable WIs.
  - *(Medium)* `BackupService` leaked backend mechanics → re-shaped UI-oriented
    (`Flow<BackupProgress>`/`Flow<RestoreProgress>`/`loadManifest`/`retryBook`; no blob/ZIP/
    PROPFIND).
  - *(Medium)* concurrency unplanned → added a Concurrency-rules section + tests (one job,
    cancel-on-form-change, request-id tagging, one-shot event channel).
  - *(Low)* don't mutate light-only `VReaderColors` → dedicated `BackupTokens` +
    `CompositionLocal`, both palettes exactly from the jsx.
  - Auditor confirmed: UI+VM+interface scope is correct (backend separate); model assumptions
    accurate; the jsx covers all the named states.
