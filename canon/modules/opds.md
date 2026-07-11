---
title: Module — OPDS
updated: 2026-07-10
status: verified
---

# Module — OPDS

## Purpose

OPDS 1.2 (Atom XML) catalog support: users save catalog servers (name + URL + optional basic-auth), browse navigation and acquisition feeds with pagination, and download books straight into the library. iOS shipped as feature #36; the Android port re-implemented the same surface as features #117 (backend) and #120 (UI), acceptance-verified by `scripts/run-opds-roundtrip.sh`.

## Key files and types

- `vreader/Services/OPDS/OPDSModels.swift` — value types: `OPDSFeed` (computed `kind: OPDSFeedKind` = `.acquisition` iff any entry has an acquisition link, else `.navigation`; `nextPageURL` from `rel == "next"`; `searchURL` from `rel == "search"` + type containing `opensearchdescription`; `static func deduplicated(_:)` dedups entries by id, first wins), `OPDSEntry` (`coverURL(against:)` matches rel containing `http://opds-spec.org/image` or `/image/thumbnail`; `acquisitionLinks`; `navigationURL(against:)` heuristics incl. `subsection`, sort/popular, sort/new, or `atom+xml` non-acquisition), `OPDSLink` (`isAcquisition` = rel `hasPrefix("http://opds-spec.org/acquisition")`; `formatLabel` EPUB/PDF/MOBI from MIME; `resolvedHref(against:)` short-circuits absolute URLs), `OPDSSavedCatalog` (Codable, `id: UUID`), `OPDSParserError` (`invalidXML`/`emptyData`/`networkError`/`httpError`/`invalidURL`, LocalizedError).
- `vreader/Services/OPDS/OPDSParser.swift` — `enum OPDSParser` with `static func parse(data:baseURL:) throws -> OPDSFeed` over Foundation `XMLParser` (SAX). The private delegate `OPDSXMLDelegate` (`NSObject, XMLParserDelegate, @unchecked Sendable`) builds entries from `entry`/`title`/`id`/`author><name`/`summary|content`/`updated`/`link` events. No external XML dependency; `shouldResolveExternalEntities` is left at Foundation's default (never enabled).
- `vreader/Services/OPDS/OPDSClient.swift` — `final class OPDSClient: Sendable`. `fetchFeed(url:credentials:)` sends `Accept: application/atom+xml;q=0.9, application/xml;q=0.8, */*;q=0.1`, 30s timeout, then parses. `downloadBook(url:credentials:)` uses `session.download(for:)`, 120s timeout, returns the temp URL. `OPDSCredentials.authHeaderValue` builds the `Basic` header — credentials go in the Authorization header, never URL-embedded.
- `vreader/Views/OPDS/OPDSCatalogListView.swift` — saved-catalog CRUD. Metadata persists in `UserDefaults` under `"opds.savedCatalogs"`; passwords live in Keychain via `KeychainService(serviceIdentifier: "com.vreader.opds")`, keyed by catalog UUID (bug #133). `loadCatalogs()` one-time-migrates legacy plaintext passwords into Keychain and rewrites UserDefaults stripped; `deleteCatalog` also deletes the Keychain entry so removed catalogs don't leak secrets.
- `vreader/Views/OPDS/OPDSBrowserView.swift` — feed browser with NavigationStack drill-down. Row type is decided **once for the whole feed** via `feed.kind` (`if feed.kind == .navigation { navigationRow } else { acquisitionRow }` inside the entries `ForEach`), not per entry — since `feed.kind` is `.acquisition` iff *any* entry has an acquisition link, a mixed feed renders **every** entry (including navigation-only ones) as an `acquisitionRow` pushing `OPDSEntryView`; only an all-navigation feed renders `navigationRow` pushing another `OPDSBrowserView`. This is a live rendering bug for mixed feeds, not per-entry routing. Also: cover thumbnails via `AsyncImage`, error state with explicit Retry, and "Load More" pagination that merges + re-dedups entries. Bug #170 / GH #529 hardening: `isLoading` seeded `true` so the spinner renders on first body evaluation, and the initial fetch fires once via a `hasStartedInitialLoad` flag flipped synchronously in `.onAppear` — `.task` was firing-and-immediately-cancelling on iOS 26 in the nested `.sheet → NavigationStack → NavigationLink` chain, leaving a blank view.
- `vreader/Views/OPDS/OPDSEntryView.swift` — book detail with one download button per acquisition link. On download: moves the temp file to `temporaryDirectory/<entry.title>.<ext>` (extension from MIME, URL path, else "epub") and posts `Notification.Name("opdsBookDownloaded")` (`.opdsBookDownloaded`, userInfo `["url": URL, "title": String]`).
- `vreader/Views/Library/LibraryViewSheets.swift` — presents `OPDSCatalogListView` in a sheet (`isShowingOPDSCatalogs`) and observes `.opdsBookDownloaded`, calling `viewModel.importFiles([url])` — the handoff into the import pipeline (see [[Module — import pipeline]] and [[Module — library]]).
- `scripts/run-opds-roundtrip.sh` — feature #117 WI-2 / #120 WI-4 live Gate-5 harness for the **Android** lane: stands up a throwaway `python3 -m http.server` (started directly, not in a subshell, so `$!` is the real server pid — rule 49) serving a static acquisition feed plus a real EPUB from `test-books/books/epub/` (or a generated minimal ZIP-magic EPUB), then runs `OpdsRoundTripConnectedTest` + `OpdsUiRoundTripConnectedTest` on the emulator against `http://10.0.2.2:$PORT/feed.xml` through `run-android-verify.sh`; prints one `RUN-OPDS-ROUNDTRIP RESULT:` line and cleans up by exact PID + port-scoped pkill.
- Android mirror (see [[Module — Android port]]): `android/app/src/main/kotlin/com/vreader/app/opds/` — `OpdsModels`, `OpdsParser`, `OpdsClient`, `OpdsSourceStore`, `OpdsAcquisitionService`, plus `ui/` ViewModels. Per `docs/architecture.md`, the Android side adds `xml.SafeXml` (hardened SAX for untrusted feeds) and restricts auto-import to `generic` + `open-access` acquisition kinds.

## Dependencies

Internal: `KeychainService` (`vreader/Services/KeychainService.swift`), the library import path (`LibraryViewModel.importFiles` via notification — OPDS never touches `BookImporter` directly). External: Foundation `XMLParser`, `URLSession`, SwiftUI `AsyncImage`. No SwiftData — saved catalogs are deliberately UserDefaults + Keychain, not `@Model`.

## Data flow

Library sheet → `OPDSCatalogListView` (loads saved catalogs, hydrates passwords from Keychain) → `OPDSBrowserView.loadFeed` → `OPDSClient.fetchFeed` → `OPDSParser.parse` → `OPDSFeed` → navigation drill-down or `OPDSEntryView` → `OPDSClient.downloadBook` → named temp file → `.opdsBookDownloaded` notification → `LibraryViewSheets` → `viewModel.importFiles` → normal import pipeline (fingerprinting, dedup, shelf).

## Security posture

- Basic-auth only via the `Authorization` header; passwords stored in Keychain since bug #133 (previously plaintext JSON in UserDefaults — a High-severity finding from feature #36 verification). UserDefaults only ever sees a password-stripped copy.
- Feeds are untrusted external XML parsed with Foundation's SAX parser; the parser never enables external entity resolution. The Android port formalized this with `SafeXml` and acquisition-kind allow-listing (reject buy/borrow/sample/indirect).
- Downloads land in the temp directory and go through the standard import path (format sniffing, fingerprinting) rather than being trusted by filename.

## Edge cases and invariants

- Empty response body → `OPDSParserError.emptyData`; XML errors surface the parser's description.
- Entries dedup by `id` both at parse time and again when paginating ("Load More" merges old + new then re-dedups), so a server repeating entries across pages cannot duplicate rows.
- Relative hrefs resolve against the feed URL; absolute hrefs (with scheme) pass through. Protocol-relative `//host/path` hrefs have no explicit special case in `OPDSLink.resolvedHref`, but aren't excluded either: lacking a scheme, they fall through to `URL(string:relativeTo:)`, whose RFC 3986 relative resolution treats a leading `//` as a network-path reference and resolves it against the base URL's scheme — so they typically still resolve when a base URL is available.
- A feed whose entries have no acquisition links renders as navigation; entries without a resolvable navigation URL render as non-tappable secondary text.
- Retry after error is explicit-button-only — `.onAppear` never auto-retries, preventing infinite retry loops on a permanently broken catalog URL.
- Download `fileExtension(for:)` defaults to "epub" when neither MIME nor URL extension helps.

## History

- Feature #36 "OPDS catalog support" — VERIFIED; parser slice 2026-05-07 (`feature-36-20260507.md`, 24 parser unit tests + 3 live curl probes against Project Gutenberg's `/ebooks.opds/`), catalog-sheet leg 2026-05-08 via `vreaderUITests/Library/OPDSCatalogListTests`.
- Bug #133 (High) — OPDS passwords plaintext in UserDefaults; fixed with the Keychain routing described above.
- Bug #170 / GH #529 (Medium) — blank `OPDSBrowserView` after NavigationLink tap; root cause `.task` cancellation on iOS 26 in the nested presentation chain; fixed with `.onAppear` + fire-once flag + seeded `isLoading`.
- Bug #193 — feature #36 XCUITest element-class mismatches; bug #152 — `TestSeeder` didn't clear UserDefaults across `--uitesting` launches, affecting OPDS state.
- Features #117 / #120 — Android OPDS backend + UI, both VERIFIED (2026-06-26 UI round-trip on emulator-5554 with a real 13M EPUB); tags in the `android/vX.Y.Z` namespace (WI-1 `android/v0.8.1`).
- Tests: `vreaderTests/Services/OPDS/OPDSParserTests.swift`, `vreaderUITests/Library/OPDSCatalogListTests.swift`, `vreaderUITests/Verification/Feature36OPDSVerificationTests.swift`; live-server tests XCTSkip unless `CI_OPDS_URL` is set (per `docs/architecture.md`).

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]

**Verified.** 2026-07-11 — checked against: vreader/Services/OPDS/OPDSModels.swift, vreader/Services/OPDS/OPDSParser.swift, vreader/Services/OPDS/OPDSClient.swift, vreader/Views/OPDS/OPDSCatalogListView.swift, vreader/Views/OPDS/OPDSBrowserView.swift, vreader/Views/OPDS/OPDSEntryView.swift, vreader/Views/Library/LibraryViewSheets.swift, vreader/Services/KeychainService.swift, vreader/ViewModels/LibraryViewModel.swift, vreader/Services/BookSource/LegadoCompatibility.swift, vreader/Services/BookSource/HTMLHelper.swift, vreader/Services/BookSource/LegadoRuleParser.swift, scripts/run-opds-roundtrip.sh, android/app/src/main/kotlin/com/vreader/app/opds/OpdsModels.kt, android/app/src/main/kotlin/com/vreader/app/opds/ui/ (directory listing), docs/features.md, docs/bugs.md, docs/architecture.md, vreaderTests/Services/OPDS/OPDSParserTests.swift, vreaderUITests/Library/OPDSCatalogListTests.swift, vreaderUITests/Verification/Feature36OPDSVerificationTests.swift, dev-docs/verification/feature-36-20260507.md, dev-docs/verification/feature-120-20260626.md, canon/modules/import-pipeline.md, canon/modules/library.md, canon/modules/android-port.md
