# iOS ↔ Android parity ledger

The running record of which vreader capabilities exist on each platform, seeded
with feature #106 (the Android foundation bar). iOS is the lead platform; Android
follows (ADR-0001). This ledger is the Phase-3 backlog source: each `Android: ✗`
row that matters becomes a tracked Android feature once the foundation bar is
complete.

**Legend:** ✓ shipped · ◑ plumbing only (no user-visible surface yet) · ✗ not yet
· ⛔ design-gated (rule 51 — awaiting a `claude.ai/design` bundle) · — n/a.

## Identity & data contracts (`contracts/`, conformance-enforced)

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| `DocumentFingerprint` canonical key | ✓ | ✓ | Shared `:identity`; golden-vector conformance green both sides. |
| `Locator` / `VReaderLocator` envelope | ✓ | ✓ | Engine-neutral value types in `:identity`. |
| `CanonicalLocator` canonical JSON / hash | ✓ | ✓ | Byte-identical across platforms (conformance lane). |
| `ChapterTranslationRecord.lookupKey` (cache key) | ✓ | ✓ | Shared `Identity.lookupKey`. |
| Converted-Kindle = source-bytes identity | ✓ (#108) | — | iOS-only concern until Android gains Kindle import (Phase 3). |

## Library & persistence

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| Persistent book store | ✓ (SwiftData) | ✓ (Room) | `VReaderDatabase` v2 + `MIGRATION_1_2` scaffold. |
| Reading-position store (full envelope) | ✓ | ✓ | One `vreaderLocatorJSON` column; evolves independently of the schema. |
| EPUB import → local-artifact fingerprint | ✓ | ✓ | Android `BookImporter` + the SAF picker + Library list shipped (#106 WI-8, design reuse; #1744 closed). |
| Library list UI | ✓ | ✓ | Android Library screen shipped #106 WI-8 (reused the committed `vreader-fidelity-v1` design bundle; #1744 closed). |
| Content-hash dedup on import | ✓ | ✓ | Same key ⇒ identical bytes; `@Upsert` preserves the saved position. |

## Reader

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| EPUB open / parse (Readium) | ✓ | ✓ | Android `BookOpener` (Readium 3.3.0 shared+streamer) — emulator-verified open + metadata. |
| EPUB rendering (navigator screen) | ✓ (Readium/legacy) | ✓ | Android `ReaderActivity` hosts Readium's EpubNavigatorFragment (scroll) — emulator-verified incl. a real EPUB (WI-9, `android/v0.3.0`). |
| Resume (precise-first / canonical-fallback) | ✓ | ✓ | Android: `ReaderActivity` saves on locationDidChange (debounced + onStop flush) + restores precise-first via `ResumeResolver` (WI-9). |
| TXT reader | ✓ | ✓ | feature #111 (`android/v0.4.0`) — encoding-detected decode (UTF-16LE/CJK) + LazyColumn render + charOffsetUTF16 resume, emulator-verified incl. a real 14MB book. |
| Markdown (.md) reader | ✓ | ✓ | feature #112 (`android/v0.5.0`) — thin delta over the TXT reader: `MarkdownRenderer` (line-chunk → AnnotatedString, single-line CommonMark subset: headers/bold/italic/code/bullets) reusing the TXT decode/document/resume/chrome; `md` routes to the shared text reader. Emulator-verified (library-path render + TXT-renders-literally regression + md resume). |
| AZW3 reader | ✓ | ✗ | Phase 3 — DEFERRED on feasibility: Readium-Kotlin has no native AZW3/MOBI; iOS uses a libmobi C lib (large/HIGH-risk port). |
| PDF reader | ✓ | ✓ | feature #115 (`android/v0.7.0`, VERIFIED) — `PdfDocument` (PdfRenderer, Mutex-serialized) + `PdfReaderActivity` continuous-scroll page bitmaps + 'Page N of M' pill + resume by page; emulator-verified. (DEFERRED designed follow-ons: paged toggle, page-jump overlay, encrypted-unlock — platform/API constraints.) |

## Sync & backup (Phase 3)

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| Backup format model (sections + manifest, schema 3 / manifest 1) | ✓ | ✓ | feature #113 (`android/v0.6.1`, VERIFIED) — Kotlin `@Serializable` DTOs matching `contracts/identity/backup-format.md` (ISO8601 UTC dates, plain `Locator` locatorJSON); golden-vector conformance green both sides. |
| WebDAV client + backup/restore pipeline | ✓ | ✓ | feature #116 (`android/v0.7.7`, VERIFIED) — `WebDavClient` + content-addressed blob store + `BackupCollector`/`RestoreImporter` + `WebDavBackupService` (byte-for-byte the iOS materializing-restore layout); credentials in DataStore + AndroidKeyStore. Verified by a LIVE rclone round-trip on the emulator (`scripts/run-webdav-roundtrip.sh`). |
| Backup/restore + WebDAV-settings UI | ✓ | ✓ | feature #114 (`android/v0.6.0`, VERIFIED) — the 5 designed Compose surfaces (#1767): WebDAV server list, server edit + test-connection, backup&restore + every WebDAV error, restore confirm→progress→result, selective picker. DEBUG-reachable; production entry-point wiring is the remaining design-gated step. |

## Remaining Phase-3 backlog (the #110 driver's queue)

The foundation bar (#106) and the readers + backup capabilities above are
shipped. What's left, with why it isn't yet an autonomously-driven feature:

- **AZW3/MOBI reader** — DEFERRED on feasibility: Readium-Kotlin has no native
  AZW3/MOBI; iOS uses a libmobi C library (a large, HIGH-risk NDK port). Needs an
  explicit go/no-go, not an autonomous start.
- **TTS (read-aloud)** — **design-gated** (rule 51): no Android TTS control-bar
  surface exists in a committed `dev-docs/designs/...` bundle. Needs a
  `claude.ai/design` handoff before implementation.
- **AI translation / chat (bilingual)** — provider-credential-gated: the live
  path needs a user-configured AI provider; only a mock/integration path is
  autonomously testable.
- **Book sources / OPDS, reading stats, highlights/annotations UI,
  full library management (collections, search)** — not yet laddered into a
  tracked Android feature; each becomes its own row + (where it has UI) a
  design-bundle prerequisite when picked up.

Every item here is either feasibility-deferred or gated on a user input
(a design bundle or an AI credential) — there is no autonomously-completable
Android-parity capability open at this time.
