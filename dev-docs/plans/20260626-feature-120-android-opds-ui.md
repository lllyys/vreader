# Feature #120 — Android OPDS catalog UI

**Status:** Gate 1 (plan). Part of the #110 Android Phase-3 driver. Implements the OPDS UI design
(`dev-docs/designs/vreader-fidelity-v1/project/vreader-opds.jsx`, needs-design #1799 closed) on the
already-shipped #117 backend (`OpdsClient`/`OpdsParser`/`OpdsAcquisitionService`).

## Problem

The OPDS backend (feed parse + HTTP + acquisition→import) shipped design-free (#117), but a user
can't reach it — there's no UI to save catalogs, browse feeds, or download. This feature adds the 4
designed surfaces + the saved-catalog store, wired to #117.

## Surface area (all new, under `android/app/.../opds/ui/` + a store)

- **`OpdsSourceStore.kt`** — saved catalogs in DataStore (id/name/url/requiresAuth/username) + the
  password via `KeystoreSecretCipher` (reuse the #116 `WebDavServerStore` DataStore+cipher pattern).
  CRUD + `password(profile)`. `OpdsSource(id, name, url, requiresAuth, username, encryptedPassword)`.
- **`OpdsClient` auth extension** (#117) — add an OPTIONAL Basic-auth credential (the v1 client was
  no-auth): `OpdsClient(..., username?, password?)` sets `Authorization: Basic …` when present.
  Keeps the https-or-loopback note out of scope (OPDS catalogs are public http often — but the auth
  header only goes when the user explicitly configured it; document the cleartext-auth caveat).
- **`OpdsViewModel.kt`** — `StateFlow`s: the source list (from store.observe), the add/edit form +
  test-connection (`OpdsClient.fetchFeed`), and the browse state (fetch a feed → nav rows +
  acquisition entries, with per-entry download state local/remote/downloading/failed). `download(entry)`
  → `OpdsAcquisitionService.importEntry` → flip the entry to in-library; tracks which local
  fingerprintKeys are already imported (the in-library state).
- **UI (Compose, per the design, reusing the #114 form vocabulary):**
  - `OpdsSourceListScreen` — `OpdsSourceList`: empty onboarding (suggested catalogs) / saved rows
    with a status dot + host-or-reason + tap-to-browse.
  - `OpdsAddSheet` — `OpdsAddSheet`: Name · URL · a Requires-sign-in toggle revealing username/
    password · Test Connection (idle/testing/ok/fail) · edit-mode Remove.
  - `OpdsBrowseScreen` — `OpdsBrowse`: navigation rows (folder + count, drill in) + acquisition
    entries (`AcquisitionEntry`: cover tile + title/author + EPUB + Get/downloading-radial/In-Library);
    loading shimmer / empty / the error views.
  - `OpdsErrorView` — `OpdsError`: offline (Retry) / 401 (Edit sign-in) / 404 (Edit URL).

### Files OUT of scope

The OPDS search (OpenSearch) flow (the browse's Search affordance is shown but not wired in v1); a
production Settings/Library entry point is wired (the source list is reachable) but cover-image
loading stays a tonal tile (the design's `MiniCover`, no remote image fetch).

## Prior art / precedent

- #117 OPDS backend (`OpdsClient`/`OpdsParser`/`OpdsModels`/`OpdsAcquisitionService`).
- #116 `WebDavServerStore` + `KeystoreSecretCipher` (the saved-source + credential pattern).
- #118 `AiProviderListScreen`/`AiProviderEditSheet`/`AiSettingsViewModel` (the list+editor+test
  pattern this mirrors) + the #114 form vocabulary (`NavScreen`/`AppSheet`/`SettingsCard`/etc).

## Work items

| WI | Scope | Tier |
| --- | --- | --- |
| WI-1 | `OpdsSourceStore` (DataStore + cipher) + `OpdsClient` optional Basic-auth. JVM tests. | foundational |
| WI-2 | `OpdsViewModel` + `OpdsSourceListScreen` + `OpdsAddSheet` (test-connection wired). VM JVM tests + instrumented Compose tests. | behavioral |
| WI-3 | `OpdsBrowseScreen` (nav rows + acquisition entries + download states) + `OpdsErrorView`. Browse VM logic + instrumented Compose tests. | behavioral |
| WI-4 | Connected acceptance: against the live local OPDS feed (reuse/extend `run-opds-roundtrip.sh`), save a source → browse → download an entry → in-library, on the emulator. Evidence → VERIFIED. | behavioral (final) |

## Test catalogue

- `OpdsSourceStoreTest` (Robolectric): CRUD, password-as-cipher-token, keep-existing-key, auth-off
  clears creds.
- `OpdsClientAuthTest` (JVM ServerSocket): the Basic-auth header is sent when configured, absent when not.
- `OpdsViewModelTest` (Robolectric): source list, test-connection ok/401/offline mapping, browse →
  nav+acquisition split, download → in-library, error mapping.
- Compose: `OpdsSourceListScreenTest`, `OpdsAddSheetTest`, `OpdsBrowseScreenTest` (states), `OpdsErrorViewTest`.
- `OpdsUiRoundTripConnectedTest` (androidTest): live feed → save → browse → download → in-library.

## Risks + mitigations

- **Auth'd catalog over cleartext http** — the user's catalog is often plain http (Calibre on LAN).
  The Basic-auth header would go in cleartext. Mitigation: send it only when the user explicitly
  enabled sign-in; document the caveat (mirrors the design's optional-auth toggle). NOT the
  https-only guard the AI key uses (OPDS catalogs are commonly LAN http and the credential is the
  user's own catalog login, not a paid API key).
- **Browse state machine** — nav vs acquisition feed, per-entry download status. Mitigation: reuse
  the #117 `OpdsFeed.kind` + `acquisitionLinks`; track imported keys via `LibraryRepository`.
- **Download → import** — reuse `OpdsAcquisitionService` verbatim (magic-checked, idempotent).

## Backward compat

Purely additive (new store + UI; no entity/schema change). Nothing to migrate.

## Acceptance criteria

1. Save/edit/remove an OPDS catalog (DataStore + Keystore for the optional password) — JVM.
2. `OpdsClient` sends Basic-auth only when configured — JVM.
3. Source list + add/edit sheet + test-connection (per the design) — Compose.
4. Browse a feed (nav rows + acquisition entries) + download an entry → in-library; the 3 error
   states render — Compose.
5. **Connected**: against a live local OPDS feed, save → browse → download → in-library on the
   emulator. Evidence file.

## Audit fixes applied (Gate-2, Codex)

- **(High) Scope Basic auth to the catalog ORIGIN** — the credential is sent ONLY when the request
  URL is same-origin (scheme+host+port) with the saved catalog's base URL. On a redirect, auth is
  preserved only for a same-origin `Location` and DROPPED on a cross-origin redirect; an acquisition
  download sends catalog creds only when the resolved acquisition URL is same-origin with the base.
  Tests: same-origin redirect (keeps auth), cross-origin redirect (drops auth), cross-origin
  acquisition (no auth).
- **(High) Cleartext-auth policy** — allow UNauthenticated http catalogs freely; allow Basic auth
  only over **https OR a local/private host** (loopback / `10.0.2.2` / RFC-1918 LAN). Refuse to send
  the password over cleartext to a public http host (`OpdsError`/typed config error). Release stays
  HTTPS-only at the manifest level; the LAN-http allowance for an authed catalog is an explicit,
  documented decision (debug network-security-config already permits `10.0.2.2`).
- **(Medium) In-library detection is BEST-EFFORT** — pre-download an entry is `remote` UNLESS a
  resolved acquisition URL matches an existing `Book.sourceUri` (`opds://…`); after import use the
  returned `Book.fingerprintKey`. No promise of universal pre-download duplicate detection (OPDS
  entries carry no content fingerprint before download).
- **(Medium) Mixed feeds** — browse builds rows PER ENTRY: `entry.navigationUrl(baseUrl)` → a folder
  row, `entry.acquisitionLinks` → acquisition rows, independently. `feed.kind` is only a hint /
  empty-state label, NOT the branching source of truth. Test: a feed with both nav + acquisition entries.
- **(Medium) Pagination** — WI-3 adds a `nextPageUrl` state: a "load more" affordance → loading-next →
  append-with-dedup (by entry id) → error-on-next. VM + Compose tests.
- **(Medium) Download single-flight** — a keyed in-flight map by the resolved acquisition URL:
  duplicate taps for the same key are ignored; different entries download independently; a stale
  completion after a source/feed change is dropped (a browse generation token). Tests: rapid-tap +
  two-entry concurrent.
- **(Low) Distinct keystore alias** — OPDS creds use `KeystoreSecretCipher("vreader.opds.password")`,
  not the WebDAV alias.
- **(Low) VM split** — `OpdsSourcesViewModel` (WI-2: source list + add/edit + test) and
  `OpdsBrowseViewModel` (WI-3: browse + download), so test ownership is clean.

Confirmed: `OpdsClient.fetchFeed`/`download` (no-auth today), `OpdsAcquisitionService.importEntry`
(returns `Book`), relative-href/`nextPageUrl`/`searchUrl`/acquisition-filtering all in #117. The
browse Search affordance renders **visibly inert** in v1 (OpenSearch deferred).

## Revision history

- **v1** (2026-06-26) — Gate-1 draft.
- **v2** (2026-06-26) — Gate-2 Codex audit (2 High + 4 Medium + 2 Low), all folded in. The
  backend-assumptions + the 4-surface scope confirmed; the WI VMs are split source-vs-browse.
