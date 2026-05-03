# Feature #47 — Integration Test Runbook (rclone WebDAV)

End-to-end manual verification for the lazy-load + selective-restore
backend shipped in v3.11.18..v3.11.27. The picker UI lands in WI-6;
this runbook covers what's exercisable today against a real WebDAV
server.

## Why rclone, not Docker

Earlier plans referenced a Docker WebDAV container (`bytemark/webdav`).
The actual local WebDAV used during development is set up via
**rclone**:

```sh
rclone serve webdav ~/vreader-webdav-data \
  --addr :8080 \
  --user vreader \
  --pass 123456
```

That sets up an authenticated WebDAV endpoint at `http://localhost:8080`
backed by `~/vreader-webdav-data`. Tailscale exposes it across the
`*.ts.net` interface for on-device verification.

> **Auth caveat.** macOS HTTP proxies (ClashX/Surge) intercept Tailscale
> traffic and surface as 502 unless `*.ts.net` and `100.64.0.0/10` are
> in the bypass list. See `docs/tasks.md` triage record from 2026-05-03
> if connections fail with 502 over Tailscale.

## Pre-requisites

- iPhone 17 Pro Simulator booted
- `vreader` installed (latest tag v3.11.27 or later)
- rclone WebDAV running per the snippet above
- vreader configured with: server `http://<host>:8080`, user `vreader`,
  password `123456` (or your equivalent)

## Verification matrix

The matrix below is a **subset** — picker-driven selective restore
needs WI-6 to integration-test. Today's runbook covers the back-end
pieces that already work end-to-end against a real server.

### Test 1 — Backup round-trip with manifest

**Goal:** confirm backups still emit `library-manifest.json` and
restore-all still works after the WI-3..WI-5 refactors.

1. Import 2-3 books into vreader.
2. Settings → Backup → "Back up now". Wait for completion.
3. SSH to the rclone host: `ls -lh ~/vreader-webdav-data/VReader/backups/`.
   Should see a fresh `*.vreader.zip`.
4. `unzip -l ~/vreader-webdav-data/VReader/backups/<latest>.zip`. Confirm
   `library-manifest.json` is present alongside the metadata sections.
5. `unzip -p <zip> library-manifest.json | jq .` — should show
   `schemaVersion:1` and one `books[]` entry per imported book with
   `fingerprintKey`, `sha256`, `byteCount`, `blobPath`.
6. Wipe app data via DebugBridge (`vreader-debug://reset`).
7. Settings → Backup → restore the same backup ID. Library should
   refill with the original books.

**Expected:** all books materialize as `.local`, reading positions
restore.

### Test 2 — Catalog decode against real backup ZIP

**Goal:** confirm `RemoteBookCatalog.loadEntries(fromBackupZIP:)` works
on a backup produced by the live server.

```sh
# Compile a tiny Swift script that reads a real backup ZIP from disk:
cat > /tmp/test_catalog.swift << 'EOF'
import Foundation

// (Replace with actual import of @testable vreader for use in
// xcodebuild test runs; this stub shows the shape.)
let path = NSString(string: "~/vreader-webdav-data/VReader/backups/<latest>.zip")
    .expandingTildeInPath
let data = try Data(contentsOf: URL(fileURLWithPath: path))
print("ZIP size: \(data.count) bytes")
EOF
```

Or, more practically: re-run the unit test against a real-world ZIP by
copying the backup into `vreaderTests/Fixtures/` and adding a one-shot
test that loads it.

### Test 3 — LazyDownloadCoordinator reattach (manual, simulator)

**Goal:** confirm crash recovery flips orphaned `.downloading` rows to
`.failed` on next launch.

This test currently requires manual setup since WI-6's enqueue path
isn't wired:

1. Use the unit-test pattern from `LazyDownloadReattachTests` to
   manually seed a `.downloading` row in the simulator's SwiftData
   store via DebugBridge eval (future addition — TBD).
2. Force-quit + relaunch.
3. Confirm the row is now `.failed` and shows the "Retry" badge.

**Defer to WI-7-real:** this is hard to integration-test without
WI-6's enqueue. Unit tests cover the logic exhaustively (13 tests in
`LazyDownloadReattachTests`), so the integration gap is bounded.

### Test 4 — Wi-Fi-only policy on real network

**Goal:** confirm `WebDAVNetworkPolicy.shouldStart()` returns the
expected truth-table value across simulator network changes.

Simulator + cellular is hard to model — verify on a real device:

1. Toggle device Wi-Fi off → confirm `currentInterface` flips to
   `.cellular` (via DebugBridge snapshot field, TBD WI-6).
2. With `wifiOnly = true` (default), `shouldStart()` should return
   false. Verify via the Wi-Fi toggle in Settings (lands in WI-6).
3. Flip `wifiOnly = false`. `shouldStart()` should return true.

**Defer to device verification log** once WI-6 ships the toggle UI.

## What's blocked until WI-6

- Picker-driven selective restore (no UI, no `WebDAVProvider.restoreSelectively`)
- Lazy-download enqueue end-to-end (no auth'd `URLRequest` builder)
- Wi-Fi toggle observable from settings UI

## What's already integration-tested via unit harness

Unit-only paths cover (50+ tests across 9 backup test suites):

- `BookFileMaterializer` round-trip (in-memory blob → SHA → import → fingerprint)
- `BookFileImportFinalizer` SHA / ext / fingerprint validation paths
- `RemoteBookCatalog` decode + every error path
- `LazyDownloadCoordinator` reattach + reconcile + race scenarios
- `LazyDownloadTaskMeta` schema + format gate
- `BackgroundDownloadSessioning` mock-driven reattach
- `VReaderAppDelegate` background-event handler storage
- `WebDAVNetworkPolicy` truth-table + persistence
- `PersistenceActor+RemoteOnly` query/mutation/idempotence
- `LibraryBookItem` file-state helpers + projection

## Bumping this runbook

When WI-6 lands, update the "What's blocked" section above with
new test recipes and convert deferred tests into actionable steps.
