# Feature #96 — In-app error/debug log capture + viewer/export

**Status**: Gate 1 (plan) → Gate 2 (audit pending)
**Row**: `docs/features.md` #96 (Medium)
**Slug**: diagnostics-log

## Problem

The app logs via OSLog `Logger` (subsystem `com.vreader.app`, ~75 sites) but those
entries go ONLY to the system unified log — no in-app way for the user to view or
export them on-device, no app-owned log file. When a bug happens on device the user
can't capture the runtime context to report it.

## Scope + WI split (rule 51 boundary)

The feature has a **pure-code capture layer** (no UI — rule 51 N/A, buildable now)
and a **user-facing viewer** (new UI — rule 51 needs-design, BLOCKED on #1597):

| WI | Tier | Rule 51 | Status |
|---|---|---|---|
| **WI-1** — capture/store/redact/export-text layer | foundational (no UI) | N/A (pure code) | **buildable now** |
| **WI-2** — Settings→Diagnostics entry + log viewer screen + export-trigger affordance | behavioral (new UI) | needs-design | **BLOCKED: needs-design (#1597)** |

This plan covers **WI-1**. WI-2 resumes when the #1597 design bundle lands; the
viewer then consumes WI-1's already-built, already-tested store + export.

## SCOPE CORRECTION (Gate-2 Critical) — current-session diagnostics only

`OSLogStore(scope: .currentProcessIdentifier)` reads ONLY the current process's
entries — it does NOT survive a relaunch, so there is **no prior-boot / pre-crash
trail**. WI-1 is therefore scoped to **in-session (current-process) diagnostics**:
the user can view + export what THIS run has logged so far. That satisfies the
feature's stated need ("record the info while running the app" — view runtime
context for the bug happening NOW). Cross-launch crash forensics is explicitly OUT
of scope; it would need an app-owned ring-buffer/file pipeline (a separate, larger
decision) — NOT this OSLogStore foundation.

## Surface area (WI-1, file-by-file)

New files under `vreader/Services/Diagnostics/`:

1. **`DiagnosticsLogEntry.swift`** — value type: `{ date: Date, level: DiagnosticsLevel,
   category: String, message: String }`. `DiagnosticsLevel` **mirrors `OSLogEntryLog.Level`
   exactly** (`undefined`/`debug`/`info`/`notice`/`error`/`fault`) — Gate-2 High: Swift
   `Logger.warning()` compiles down to `.error` in the SDK, so "warning" is NOT recoverable
   from historical entries; the enum does not invent a `warning` case (documented as a known
   lossy limitation of reading back the unified log). `Sendable`, `Equatable`.
2. **`DiagnosticsLogSource.swift`** — protocol `func recentEntries(since: Date?, limit: Int) async throws -> [DiagnosticsLogEntry]`.
   The testable seam — the store depends on the protocol, tests inject a mock.
3. **`OSLogDiagnosticsSource.swift`** — the real source, **nonisolated / off-main** (Gate-2
   Medium: `OSLogStore` enumeration is synchronous + blocking, so it must NOT run on `@MainActor`).
   Exact retrieval contract: `OSLogStore(scope: .currentProcessIdentifier)` → `store.position(date:)`
   → `store.getEntries(with:at:matching:)` with a `subsystem == "com.vreader.app"` `NSPredicate`
   → `compactMap { $0 as? OSLogEntryLog }` (category from `OSLogEntryWithPayload.category`,
   level from `OSLogEntryLog.level`). The OS boundary (mocked behind the protocol; not deeply
   unit-tested). No entitlement needed for `.currentProcessIdentifier` on iOS (target is 17.0).
4. **`DiagnosticsRedactor.swift`** — PURE, defense-in-depth. **Gate-2 High — privacy model:
   the FIRST-line secret barrier is the existing `privacy:` annotations** (OSLog redacts
   `.private` interpolations to undecodable `<private>`; public APIs cannot recover their
   cleartext). The redactor is the SECOND line for messages logged `.public`, static strings
   that embed a secret, or error descriptions / URLs / paths that were never privacy-tagged.
   **Context-driven first** (Gate-2 Medium), not blunt: redact `Authorization: Bearer …` /
   `Authorization: Basic …`, `access_token=` / `refresh_token=` / `apiKey=` / `password=` /
   `secret=` / `x-api-key:` values, JWTs (`aaa.bbb.ccc`), `user:pass@host` URL creds, and iOS
   container paths (`/private/var/mobile/Containers/…`, `/Users/…`, `file:///…` → `‹path›`).
   It does NOT blanket-redact long hex/base64 runs (those over-redact hashes/IDs); a keychain
   ACCOUNT LABEL like `com.vreader.ai.apiKey.<UUID>` is an identifier, not the secret, and is
   left intact. Fully unit-tested — the export-leak guard.
5. **`DiagnosticsLogStore.swift`** — `@MainActor @Observable` façade: `func load(limit:) async`
   awaits the off-main source, holds `entries: [DiagnosticsLogEntry]`, pure level/category
   filtering, and `exportText() -> String` that formats entries + runs each message through
   `DiagnosticsRedactor`. Bounded (cap entries + a time window). The viewer (WI-2) binds to this.

### Files OUT of scope (WI-1)

- Any SwiftUI view / Settings row (that's WI-2, needs-design).
- The DebugBridge (`vreader-debug://`) — DEBUG-only dev harness, distinct from this Release user feature.
- Changing any of the 75 existing `Logger` call sites (WI-1 reads them back as-is).

## Surface area (WI-2 — UNBLOCKED 2026-06-10, #1597 design landed)

Design source: `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`
+ `design-notes/diagnostics-log-viewer.md` (committed PR #1603). The viewer binds
to WI-1's already-built, already-tested `DiagnosticsLogStore` — no change to the
WI-1 capture/redact/export layer.

New files under `vreader/Views/Settings/Diagnostics/`:

1. **`DiagnosticsLevelStyle.swift`** — PURE (Foundation-only, render-free so it
   unit-tests without SwiftUI). `DiagnosticsLevelTint {error,info,neutral}` +
   `DiagnosticsLevel.viewerTint` (design `diagLevelColor`: error/fault→red,
   info→blue, else→sub); `DiagnosticsLevelFilter {all,errors,debug,info}` with a
   `matches(_:)` predicate (`errors` includes `.fault`); `DiagnosticsDaySection`
   + `DiagnosticsDayGrouper.sections(from:now:calendar:)` (newest-first day
   buckets, `now`/`calendar`-injected for deterministic tests).
2. **`DiagnosticsLogViewModel.swift`** — `@MainActor @Observable`. Owns the store
   + the level/category filter selection + the expanded-row identity. Derives
   `filteredEntries`, `daySections(now:)`, per-chip `count(for:)`, `categories`,
   `exportText()` (redacted, filter-narrowed), `exportFileName(now:)`
   (`vreader-log-YYYY-MM-DD.txt`), and `footerScope`. Changing a filter collapses
   the expanded row.
3. **`DiagnosticsLogRow.swift`** — one row (design `DiagLogRow`): mono timestamp ·
   colored uppercase level · category pill over a 3-line-clamped monospace
   message; tap expands + reveals a redacting "Copy entry". Carries the
   `Color(diagnosticsHex:)` helper + `DiagnosticsLevelTint.color(isDark:neutral:)`.
4. **`DiagnosticsFilterChips.swift`** — `DiagnosticsChip` (inverted-ink pill;
   Errors chip takes the error tint when active) + `DiagnosticsFilterBar` (level
   row with counts + scrollable category row).
5. **`DiagnosticsLogView.swift`** — the pushed screen (design `DiagLogViewer`):
   nav title "Diagnostics", trailing share button → writes the redacted export to
   a temp `.txt` and presents `ShareActivityView`; filter bar + day-grouped list +
   pinned "Capturing" footer; loading / empty / filtered-empty states
   (`DiagnosticsEmptyState`).

Modified:
- **`SettingsRowPalette.swift`** (Models) — add the `diagnostics` spec (steel
  `#5b6770`, `waveform.path.ecg`).
- **`SettingsView.swift`** — add a **Support** section at the bottom with the
  Diagnostics `NavigationLink` row pushing `DiagnosticsLogView`. `sectionsForTesting`
  / `rowPaletteKeysForTesting` extended.
- **`SheetSectionContract.swift`** — `appSettings.sections` gains "Support".

### Files OUT of scope (WI-2)

- The system share sheet itself (iOS chrome — design explicitly marks it
  not-designed-here; only its trigger is ours).
- The existing About rows (Help & Feedback / Version) — kept intact; Support is a
  new sibling group, not a teardown of About.

### Manual Audit Evidence (WI-2 — Gate-2 model-assumption check)

Author verified against the live codebase before/while implementing:
- **Symbols confirmed to exist**: `DiagnosticsLogStore.{entries,hasLoaded,load,
  filtered,categories,exportText}`, `DiagnosticsLevel.{exportTag,allCases}`,
  `DiagnosticsLogEntry` (Equatable), `DiagnosticsRedactor.redact`,
  `ReaderThemeV2.{inkColor,subColor,ruleColor,accentColor,isDark,
  sheetSurfaceColor}`, `SettingsRowSpec.background.color`, `SettingsIconRow`
  (detail+showsChevron init), `ShareActivityView(activityItems:)`,
  `SettingsSectionHeader`, `RGBComponents`.
- **Edge cases checked**: empty store (plain empty state, share hidden), filtered
  intersection empty (filtered-empty + Clear filters), `.fault` under the Errors
  chip, expand-collapse on filter change, temp-file write failure (no sheet),
  redaction applied to both export + Copy-entry, deterministic export filename.
- **Risks accepted**: none outstanding — the Gate-4 audit's row-identity and
  filtered-export findings were fixed (see below), not accepted.
- The Gate-4 per-PR Codex audit is the binding independent audit for this WI.

### Gate-4 audit (Codex) — findings + resolutions

Round 1 (`/tmp/feat96-wi2-audit.txt`): 2 High + 2 Medium + 1 Low — ALL fixed:
- **High** — export collapsed `Errors`→`.error`, dropping `.fault` → `DiagnosticsLogStore.exportText(entries:)` overload; the VM exports `filteredEntries`.
- **High** — `firstIndex(of:)` row-identity collision for value-equal rows → `IdentifiedDiagnosticsEntry{id,entry}` threaded through the grouper; the view expands by `item.id`.
- **Medium (rule 51)** — separate one-row Support + intact About → single "Support" group (Diagnostics + regrouped About rows) per the #1597 design.
- **Medium** — filtered footer missing the active-filter suffix → added.
- **Low** — synchronous main-actor export write + swallowed failure → off-main `writeExport` + `exportFailed` alert.

Round 2 (`/tmp/feat96-wi2-audit-r2.txt`): 3 of 5 confirmed RESOLVED; 2 new Mediums (footer + export-header scope text hardcoded in two places, and the design mock's "last 24 h" vs the real window) — fixed by single-sourcing `DiagnosticsLogStore.captureScopeLabel = "this session"` (used by BOTH the footer and the export header). **Decision: "this session" is the approved scope descriptor**, superseding the #1597 mock's illustrative "last 24 h" — WI-1's Gate-2 Critical correction scoped capture to `OSLogStore(scope: .currentProcessIdentifier)` (current process, not a 24-hour window), so "last 24 h" would be factually wrong. This is the documented source of truth.

## Prior art / precedent / rejected alternatives

- **`OSLogStore(scope: .currentProcessIdentifier)`** reads the app's OWN current-process
  `Logger` entries — reuses all 75 existing call sites with NO new logging code. (Gate-2
  Critical correction: it does NOT read prior launches — current-session only.)
- **Rejected: a custom in-memory ring buffer + on-disk file** — would require touching every
  `Logger` call site (or a logging wrapper). It IS the only way to get cross-launch/pre-crash
  forensics, but that's out of scope here; for current-session diagnostics OSLogStore is less code.
- **Redaction model** (Gate-2 High): `privacy:` annotations (rule 50 §7) are the PRIMARY barrier
  — OSLog redacts `.private` interpolations to undecodable `<private>` and public APIs can't
  recover them. `DiagnosticsRedactor` is defense-in-depth for `.public`/untagged messages only.

## Test catalogue (WI-1)

- `DiagnosticsRedactorTests` — the security core: API key (`sk-…`), `Bearer` token, `apiKey=` query,
  `https://user:pass@host`, absolute `/Users/…` path, `file:///…` URL each redacted; a clean
  message is untouched; CJK/Unicode message preserved; idempotent (redact∘redact == redact).
- `DiagnosticsLogStoreTests` — with a mock `DiagnosticsLogSource`: `load` populates `entries`;
  the bound caps the count; level/category filters select correctly; `exportText` formats every
  entry AND routes each message through the redactor (assert a planted secret is scrubbed in the
  export); empty-source → empty export with a header.
- `DiagnosticsLogEntryTests` — `OSLogEntryLog.Level` → `DiagnosticsLevel` mapping (parameterized).

## Risks + mitigations

- **Export leaking secrets** — the headline risk. Two layers: (1) the existing `privacy:`
  annotations keep `.private` values undecodable in the read-back (primary), (2) `DiagnosticsRedactor`
  scrubs `.public`/untagged messages on export (defense-in-depth) — pure + exhaustively unit-tested
  per secret shape; `exportText` runs EVERY message through it; a planted-secret export test is the
  regression guard.
- **OSLogStore throws / returns no entries** (Gate-2 Medium reword — NOT an entitlement issue on
  iOS for `.currentProcessIdentifier`) — treat as a normal runtime failure: the source is behind a
  protocol; `load` catches + surfaces an empty list (viewer shows empty state). No crash.
- **`warning` not distinguishable** (Gate-2 High) — `Logger.warning()` reads back as `.error`; the
  level enum mirrors `OSLogEntryLog.Level` and does not fabricate a `warning` case. Documented.
- **Current-session only** (Gate-2 Critical) — no prior-launch/pre-crash trail; documented in the
  scope + on the row. The user feature (view this run's runtime context) is still served.
- **Off-main blocking** (Gate-2 Medium) — the OSLogStore enumeration is synchronous; it runs in the
  nonisolated source off `@MainActor`, results published back into the `@MainActor @Observable` store.
- **WI-2 is design-blocked** — accepted; WI-1 ships independently as the foundation, fully tested,
  with no dead UI. The feature row stays `IN PROGRESS` (not `DONE`) until WI-2's design lands.

## Backward compat

Pure additive read-only capability over the existing unified log. No data/schema/format/persistence
change. Nothing migrated.

## Acceptance criteria

**WI-1 (this plan):**
1. `DiagnosticsLogStore.load()` reads back `com.vreader.app` `Logger` entries via the source.
2. `exportText()` produces a readable log with EVERY message redacted of API keys / tokens / creds / file paths.
3. Bounded (count + time window); resilient to a throwing/empty source (no crash, empty state).

**WI-2 (deferred, needs-design #1597):** Settings→Diagnostics entry opens a viewer with level/category
filters + share-sheet export; default/empty/loading states.

## Revision history

- v1 (2026-06-09) — initial plan (WI-1 buildable now; WI-2 design-blocked on #1597).
- v2 (2026-06-09) — Gate-2 Codex audit (`/tmp/feat96-planaudit.txt`): 1 Critical + 2 High + 4 Med + 2 Low. Fixes:
  - **Critical** — re-scoped WI-1 to CURRENT-SESSION diagnostics; dropped the false "prior-boot/pre-crash trail" claim (`.currentProcessIdentifier` is current-PID only).
  - **High** — privacy model corrected: `privacy:` annotations are the primary barrier (OS redacts `.private` to undecodable); the redactor is defense-in-depth for `.public`/untagged only.
  - **High** — level enum mirrors `OSLogEntryLog.Level` exactly (no `warning` — it folds to `.error` in the SDK); documented lossy.
  - **Medium** — exact retrieval contract stated (`position(date:)` + `getEntries(with:at:matching:)` + subsystem predicate + `compactMap as? OSLogEntryLog`); entitlement claim removed (none needed on iOS 17); redactor made context-driven (auth headers / `*_token=` / JWT / container paths) not blunt long-hex/base64, keychain label ≠ secret; source nonisolated off-main, store `@MainActor @Observable`.
  - **Low** — WI split confirmed correct; row note reframed (current-session foundation slice, not bundle-and-wait).
