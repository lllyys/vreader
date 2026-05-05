# DebugBridge — feature #44

DEBUG-only `vreader-debug://` URL scheme that drives the app from outside (e.g. an AI agent or CI test) for autonomous reproduction, verification, and debugging. Compiled out of Release builds.

## When to use it

- Reproducing bugs without a 30-step manual UI sequence.
- Driving the verification harness in feature #45.
- Asserting on app state in JSON instead of pixels.

If you're writing user-facing code, this isn't your file.

## Quick start

```bash
# Resolve UDID of the booted simulator. The `(Booted)` suffix is the LAST
# token; UDID is the second-to-last. Strip the parentheses around it.
SIM_ID=$(xcrun simctl list devices booted | awk '/Booted/ {print $(NF-1); exit}' | tr -d '()')

# One-time per fresh simulator: pre-grant the URL-scheme approval so iOS
# does not present an "Open in 'vreader'?" alert on the first call.
# See "iOS scheme-approval prompt" below for why this is needed.
scripts/grant-debug-scheme-approval.sh "$SIM_ID"

# Wipe library, seed a fixture, set theme.
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl openurl "$SIM_ID" "vreader-debug://theme?mode=dark&fontSize=22"

# Compute the seeded book's fingerprint key from the imported file name.
# Importer stores files as `<format>_<sha>_<bytes>.<ext>`; the bridge's
# bookId format is `<format>:<sha>:<bytes>`.
DATA=$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)
FILE=$(ls "$DATA/Library/Application Support/ImportedBooks/" | head -1)
KEY=$(echo "$FILE" | sed -E 's/^([a-z0-9]+)_([0-9a-f]+)_([0-9]+)\..*/\1:\2:\3/')
ENCODED=$(printf '%s' "$KEY" | sed 's/:/%3A/g')

# Open the book, settle, then snapshot.
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED"
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=ready"
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=state.json"

# Read the state JSON from the app container.
cat "$DATA/Library/Caches/DebugBridge/state.json"
```

## URL grammar

All commands are scheme `vreader-debug://`. Host names the command. Trailing `/` is allowed; any deeper path segment is rejected.

| Command    | Required params                    | Optional params                       | Effect                                                                                                                                                              |
| ---------- | ---------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reset`    | —                                  | —                                     | Wipe every book from the library. Idempotent.                                                                                                                       |
| `seed`     | `fixture=<name>`                   | —                                     | Import a bundled fixture book by catalog name.                                                                                                                      |
| `open`     | `bookId=<key>`                     | `position=<str>` (currently rejected) | Verify the book exists in persistence; LibraryView pushes it onto its `NavigationStack`.                                                                            |
| `theme`    | `mode=dark\|light`                 | `fontSize=<int>`                      | Persist theme + optional font size to `UserDefaults`. Effect on next reader open.                                                                                   |
| `settle`   | `token=<basename>`                 | —                                     | Wait for the active reader to settle, then write `Caches/DebugBridge/ready-<token>.json`. Bridge enforces a 30s timeout — a hung probe still produces the sentinel. |
| `snapshot` | `dest=<basename>`                  | —                                     | Build a `DebugSnapshot` and write it to `Caches/DebugBridge/<dest>`.                                                                                                |
| `eval`     | `bridge=<basename>`, `js=<base64>` | —                                     | Run JS in the active reader's webview; write result/error to `Caches/DebugBridge/eval-<bridge>.json`.                                                               |

### Parameter validation

- `token`, `dest`, `bridge`: `[A-Za-z0-9._-]{1,64}` and not dot-only (`.` / `..` / `...` rejected). Path-traversal-safe.
- `fixture`: must match a catalog entry (`DebugFixtureCatalog`). Currently `war-and-peace` only; the catalog grows as fixtures are bundled.
- `mode`: literal `dark` or `light`. Anything else throws `parse.invalidParam: mode`.
- `fontSize`: integer.
- `js`: standard base64 of UTF-8 source.
- Duplicate query keys throw `parse.invalidParam: <name>: duplicate parameter`.

## Output files

All output lives in the app container at `Library/Caches/DebugBridge/`. Read from the host via:

```bash
DATA=$(xcrun simctl get_app_container <udid> com.vreader.app data)
cat "$DATA/Library/Caches/DebugBridge/<file>"
```

### `snapshot` → `<dest>`

```json
{
  "schemaVersion": 1,
  "ts": "2026-05-02T13:32:20Z",
  "currentBookId": "txt:ab02...:1708",
  "format": "txt",
  "position": null,
  "selection": null,
  "theme": "dark",
  "fontSize": 24,
  "highlightCount": 0,
  "renderPhase": "idle",
  "lastError": null,
  "partial": ["selection"]
}
```

- Sorted keys, pretty-printed, explicit `null` for nil.
- `schemaVersion`: bump on field add/remove/semantics-change. Pin a known version in CI.
- `partial`: field names whose nil value means "not yet implemented". Empty/absent ⇒ every nil is authoritative. Currently always contains `"selection"`; without an active reader also contains `"currentBookId"`, `"format"`, `"position"`.
- `lastError`: stable category prefix, not Swift enum spelling. See "Error codes" below.

### `settle` → `ready-<token>.json`

Happy path:

```json
{
  "fingerprintKey": "txt:ab02...:1708",
  "format": "txt",
  "position": null,
  "token": "demo",
  "ts": "2026-05-02T12:58:58Z"
}
```

Timeout path:

```json
{
  "fingerprintKey": "...",
  "format": "...",
  "position": null,
  "token": "demo",
  "ts": "...",
  "error": "settle timeout",
  "phase": "unknown"
}
```

### `eval` → `eval-<bridge>.json`

Always written, even on error. `result` is the raw JSON value returned by the JS expression, not a string-encoded JSON.

Happy path:

```json
{
  "bridge": "foliate",
  "fingerprintKey": "...",
  "format": "epub",
  "result": 3,
  "ts": "..."
}
```

Error path:

```json
{
  "bridge": "foliate",
  "fingerprintKey": "...",
  "format": "txt",
  "error": "eval unsupported for format: txt",
  "ts": "..."
}
```

## Error codes

Error reporting comes in two flavors:

**`snapshot.lastError`** uses stable `category.kind: detail` strings produced by `DebugBridge.stableErrorMessage`. Pin on the prefix, not the detail:

| Prefix                                      | Meaning                                        |
| ------------------------------------------- | ---------------------------------------------- |
| `parse.invalidScheme`                       | URL scheme isn't `vreader-debug`               |
| `parse.unknownCommand: <host>`              | Host isn't a known command name                |
| `parse.missingParam: <name>`                | Required parameter absent or empty             |
| `parse.invalidParam: <name> (<reason>)`     | Parameter failed validation                    |
| `bridge.unknownFixture: <name>`             | `seed` got a name not in the catalog           |
| `bridge.fixtureResourceMissing: <basename>` | Catalog entry exists but bundle file is absent |
| `bridge.notImplemented: <command>`          | Path not yet wired (e.g. `open.position`)      |
| `bridge.bookNotFound: <bookId>`             | `open` received an unknown fingerprint key     |
| `bridge.noActiveReader`                     | `eval` ran with no reader presented (NOT `settle` — see below) |
| `bridge.settleTimeout`                      | `settle` gave up after 30s                     |
| `bridge.evalUnsupported: <format>`          | Active reader doesn't support JS eval          |
| `bridge.evalFailed: <msg>`                  | JS execution threw                             |

**`error`**\*\* field in ****`ready-<token>.json`**** and \*\***`eval-<bridge>.json`** is currently a plain English string written directly by the handler. **Do not pin assertions on these strings** — they may change. Possible values today:

| File                 | Possible `error` values                                                                |
| -------------------- | -------------------------------------------------------------------------------------- |
| `ready-<token>.json` | `"settle timeout"` (with `phase: "unknown"`), `"no active reader"` (bug #125 — also with `phase: "unknown"`; probe-shaped fields `fingerprintKey`/`format`/`position` are absent on this path) |
| `eval-<bridge>.json` | `"no active reader"`, `"eval unsupported for format: <fmt>"`, raw JS error description |

For `settle` specifically: the no-active-reader case is reported via the sentinel file (`error: "no active reader"`), NOT via `snapshot.lastError`. `settle` does not throw on this path, so the bridge's `lastError` stays clear. Verification harnesses must poll `ready-<token>.json` regardless of reader state.

For `eval` and the rest of the failure space, assert on the snapshot's `lastError` after running the failing command — it uses the stable prefixes and is the recommended assertion surface.

## Architecture

```
xcrun simctl openurl
        │
        ▼
.onOpenURL (VReaderApp, #if DEBUG only)
        │
        ▼
DebugBridge.handle(url)        ← serializes commands; records lastError
        │
        ▼
DebugCommand.parse(url)         ← path/scheme/param validation
        │
        ▼
RealDebugBridgeContext           ← real handlers
        ├─ persistence (PersistenceActor)        for reset/seed/open/snapshot
        ├─ importer (BookImporting)              for seed
        ├─ ReaderSettingsStore (UserDefaults)    for theme
        └─ DebugReaderRegistry.shared            for settle/eval/snapshot
                │
                ▼
        DebugReaderProbe (weak ref)              ← ReaderContainerView
                                                    registers on .onAppear
```

### Active-reader registry

`DebugReaderRegistry.shared` holds a weak reference to the currently-presented reader. `ReaderContainerView` creates a `DebugReaderProbeAdapter` in `@State`, registers on `.onAppear`, unregisters on `.onDisappear`.

The probe protocol exposes:

- `fingerprintKey: String`
- `format: String`
- `currentPositionString: String?`
- `func awaitSettle(timeout:) async throws`
- `func evaluateJavaScript(_:) async throws -> Data` (raw JSON bytes)

Default adapter:

- `awaitSettle`: sleeps 100ms (placeholder until per-format hooks land — Foliate `relocate` event, TextKit layout completion).
- `evaluateJavaScript`: throws `evalUnsupported(format:)`. EPUB/AZW3 readers will plug a real evaluator into `jsEvaluator` once the active webview is exposed.

## Repro recipes

Each recipe drives the simulator to a known reproduction state for a tracker entry. Use the snapshot/ready files to assert on outcome.

### Bug #107 — Cover images with light edges look like padding (Library)

```bash
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl io "$SIM_ID" screenshot /tmp/library-edges.png
# Visual inspection: the war-and-peace card is a TXT with no cover so this
# specific bug needs an EPUB/AZW3 fixture with a white-edged cover. Add the
# fixture to DebugFixtureCatalog when sourced.
```

Status: **partial** — needs an EPUB fixture with a white-edged cover. Recipe blocked on fixture sourcing.

### Bug #108 — AZW3/Foliate reader: center tap doesn't toggle chrome

```bash
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=sample-azw3"   # NOT YET IN CATALOG
ENCODED_KEY="..."
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED_KEY"
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=open"

# Center-tap requires a real touch — DebugBridge can't dispatch UIEvents.
# Use computer-use after settle to click the screen center, then snapshot
# and check theme.fontSize / a chrome-visible flag.
```

Status: **needs ********`sample.azw3`******** fixture and a chrome-visible probe field**. Center-tap itself is computer-use territory.

### Generic verification recipe (template for feature #45)

```bash
# 1. Clean state
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"

# 2. Seed required fixture
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"

# 3. Set known theme/font
xcrun simctl openurl "$SIM_ID" "vreader-debug://theme?mode=light&fontSize=18"

# 4. Open the book
ENCODED_KEY="txt%3A<sha>%3A<bytes>"
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED_KEY"

# 5. Wait for render
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=ready"

# 6. (Optional) Drive any user actions via computer-use here.
#    Then snapshot to capture state for assertions.
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-action.json"

# 7. Read + assert
DATA=$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)
jq '.theme == "light" and .currentBookId != null' \
   "$DATA/Library/Caches/DebugBridge/after-action.json"
```

## Acceptance gate

`scripts/verify-release-no-debugbridge.sh` checks:

1. `Info.plist` does not declare the `vreader-debug` URL scheme.
2. No `DebugFixtures` directory in the bundle.
3. No catalog fixture filenames in the bundle.
4. No DebugBridge-named files in the bundle.
5. No DebugBridge-related strings in bundle resources.
6. No DebugBridge-related strings in the main binary.

Run after a Release build:

```bash
xcodebuild build -configuration Release -derivedDataPath /tmp/vreader-release-build
./scripts/verify-release-no-debugbridge.sh
```

Exits 0 only if all six checks pass.

`scripts/verify-debug-has-debugbridge.sh` is the inverse for Debug builds: confirms the URL scheme is wired into the Info.plist of the freshest Debug build. Catches regressions of bug #121 (DebugBridge.plist orphaned from Info.plist).

## iOS scheme-approval prompt (bug #123)

When `simctl openurl` (running as `CoreSimulatorBridge`) opens `vreader-debug://` on a simulator that has no prior approval entry, iOS LaunchServices presents a one-shot **"Open in 'vreader'?"** alert from `lsd`. The alert is the standard third-party scheme-approval prompt. Until someone taps **Open**, the URL is held by `lsd` and never reaches `.onOpenURL` — `simctl openurl` exits 0 because LaunchServices accepted the request, not because the app received it.

After approval, the grant is persisted in:

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist
```

with key:

```
"com.apple.CoreSimulator.CoreSimulatorBridge-->vreader-debug" = com.vreader.app
```

The key tells you the exact scope of the approval: source app `CoreSimulatorBridge` opening the `vreader-debug` scheme on this simulator. Other source apps (e.g. another iOS app calling `UIApplication.open`) would have their own approval entries. The grant survives reinstalls of the app bundle. It does *not* survive `simctl erase`.

For automated verification (no human to tap **Open**), pre-grant the approval before the first `openurl`:

```bash
scripts/grant-debug-scheme-approval.sh         # uses booted device
scripts/grant-debug-scheme-approval.sh <UDID>  # specific device
```

The script writes the plist entry directly. Idempotent — safe to run on every harness setup.

In practice the prompt only appears on a freshly-erased simulator, because `lsd` retains the approval across plist edits, lsd restarts, and app reinstalls. The grant script is defense-in-depth: cheap to run, prevents the rare case where the harness lands on a fresh simulator and would otherwise hang on the first command.

## Adding a new fixture

1. Drop the file in `vreader/Resources/DebugFixtures/<name>.<ext>`.
2. Add a row to `DebugFixtureCatalog.entries`.
3. Confirm `EXCLUDED_SOURCE_FILE_NAMES` on the Release build configuration still globs `*/DebugFixtures/*` (it should — set once in pbxproj).
4. `test_all_entriesResolveInTheTestBundle` should pass without modification.
5. Re-run `scripts/verify-release-no-debugbridge.sh` to confirm the fixture stays out of Release.

## Future work

- Per-format settle hooks: Foliate `relocate` event for EPUB/AZW3, TextKit layout-completed for TXT/MD, PDFKit `viewDidLoad` for PDF.
- Real `evaluateJavaScript` evaluator on the EPUB/AZW3 reader (currently the bridge plumbing is complete but no reader supplies one — eval against EPUB books returns `error: "eval unsupported for format: epub"`).
- `selection` snapshot field: probe field that exposes the active reader's text selection.
- `position` parameter in `open` (currently throws `bridge.notImplemented: open.position`). Resolve string → Locator before pushing the reader.
- Additional fixture books: `alice.epub`, `sample.azw3`, `sample.pdf`. Catalog grows when files are sourced.
- `phase` reporting in `settle` timeout sentinel (currently always `"unknown"`).

## File reference

| File                                                          | Purpose                                     |
| ------------------------------------------------------------- | ------------------------------------------- |
| `vreader/Services/DebugBridge/DebugBridge.swift`              | Orchestrator — parse + dispatch + lastError |
| `vreader/Services/DebugBridge/DebugCommand.swift`             | URL grammar + parameter validation          |
| `vreader/Services/DebugBridge/DebugSnapshot.swift`            | JSON shape for snapshot output              |
| `vreader/Services/DebugBridge/RealDebugBridgeContext.swift`   | Production handlers                         |
| `vreader/Services/DebugBridge/DebugReaderRegistry.swift`      | Active-reader registry + probe protocol     |
| `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift`  | Default probe used by ReaderContainerView   |
| `vreader/Services/DebugBridge/DebugBridgeNotifications.swift` | DEBUG-only notification names               |
| `vreader/Services/DebugBridge/DebugFixtureCatalog.swift`      | Fixture name → bundle resource map          |
| `vreader/SupportingFiles/DebugBridge.plist`                   | Partial Info.plist (Debug build only)       |
| `vreader/Resources/DebugFixtures/`                            | Bundled fixture books (Debug build only)    |
| `scripts/verify-release-no-debugbridge.sh`                    | Release-build acceptance gate               |

