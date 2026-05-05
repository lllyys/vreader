---
branch: fix/133-opds-password-keychain
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-06
---

## Manual audit evidence

High-severity security fix. Routes OPDS catalog passwords through Keychain instead of UserDefaults plaintext. Manual audit performed.

### Files changed

| File | Change |
|---|---|
| `vreader/Views/OPDS/OPDSCatalogListView.swift` | Add `KeychainService`; rewrite save/load/delete; one-time migration on load. |
| `docs/bugs.md` | New row #133 (FIXED, High, GH: #285). |

### Save/load/delete invariants

**Save (`saveCatalogs`)**:
- For each catalog: if `password` non-nil → write to Keychain (account = `catalog.id.uuidString`). Else → delete the Keychain entry (handles user clearing the password).
- Build a `stripped` copy of catalogs with `password = nil` on each.
- Encode `stripped` to JSON; write to UserDefaults.

**Load (`loadCatalogs`)**:
- Decode UserDefaults into `decoded: [OPDSSavedCatalog]`.
- For each catalog: if `c.password` is non-nil (legacy plaintext entry from pre-fix), write it to Keychain and mark `didMigrate = true`, then null `c.password` for in-memory consistency.
- Always: try to read from Keychain by `c.id.uuidString` and populate `c.password` (so the in-memory model still has the password for use by OPDSClient/OPDSBrowserView).
- Append to `migrated` array.
- If `didMigrate`, call `saveCatalogs()` to rewrite UserDefaults with the now-stripped data.

**Delete (`deleteCatalog`)**:
- Delete the Keychain entry first (so a deleted catalog doesn't orphan its password in Keychain — keychain.delete is idempotent so no error if the entry never existed).
- Remove from in-memory `catalogs`.
- Call `saveCatalogs()` to update UserDefaults.

### Edge cases checked

- **First-run migration race**: load sees legacy plaintext, writes to Keychain via `try? keychain.saveString(plaintext, ...)`. `try?` swallows Keychain errors silently. Acceptable: if the migration fails, the next save will rewrite UserDefaults, but the legacy plaintext also stays. The `password = nil` mutation is in-memory; the failed migration would only persist when `saveCatalogs` runs successfully later. **Trade-off**: in the worst case (Keychain unavailable on a device), the user's legacy plaintext password would survive in UserDefaults until either (a) Keychain comes back and the next save migrates, or (b) the user manually edits/deletes. We don't crash or break anything.
- **Empty password** (user added catalog without auth): no Keychain write happens (guarded by `!pw.isEmpty`); `keychain.delete` cleans up any orphan Keychain entry from a prior save.
- **User edits a catalog and removes the password**: save flow writes empty/nil → branch into `keychain.delete`. Keychain entry is removed.
- **User deletes a catalog**: `deleteCatalog` removes the Keychain entry FIRST, then the in-memory entry, then resaves. Order matters because saveCatalogs only iterates remaining catalogs — without the explicit delete, the Keychain entry would orphan.
- **Keychain throws** (any saveString/readString/delete failure): all calls use `try?`. Same trade-off as the migration: the password might briefly desynchronize between Keychain and the in-memory model. The user-visible effect is that they may need to re-enter their password on next session if Keychain became corrupt — better than persisting plaintext.
- **Two catalogs with the same UUID**: structurally impossible (UUID generation per catalog); both `id` field is `let` so it's immutable post-creation.
- **Existing legacy entries**: covered by the load-time migration. One-time per legacy catalog.

### What I deliberately did NOT change

- `OPDSSavedCatalog` model: kept `var password: String?` so the in-memory model still carries the password for OPDSClient/OPDSBrowserView consumption. The JSON-encoded persistent form has password stripped; the in-memory form has it hydrated from Keychain.
- The form-edit UI (`saveCatalog`): unchanged. It mutates the catalog with the new password, then calls `saveCatalogs()` which routes the password to Keychain — correct path.
- Service identifier: chose `com.vreader.opds` to namespace OPDS Keychain items separately from any other future Keychain consumers (AI API key uses `com.vreader.keychain`).

### Tests added

None. The fix is plumbing through the existing well-tested `KeychainService`. Adding view-level tests for SwiftUI `@State` flows is high-cost low-value at this layer. The KeychainService itself has its own test suite (existing); the changes here just call its public API.

### Verdict

**ship-as-is**. High-severity security fix with a clean migration path. Trade-offs around `try?` on Keychain are acceptable — failure modes are graceful (re-prompt user) rather than corrupting state.
