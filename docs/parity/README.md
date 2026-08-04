# iOS ↔ Android parity ledger

The running record of which vreader capabilities exist on each platform, seeded
with feature #106 (the Android foundation bar). iOS is the lead platform; Android
follows (ADR-0001). This ledger is the Phase-3 backlog source: each `Android: ✗`
row that matters becomes a tracked Android feature once the foundation bar is
complete.

> **The finite build queue lives in [`android-checklist.md`](android-checklist.md)** — the checkable
> definition of "Android parity" (feature #110). This ledger records per-capability status; the
> checklist distills it into a checkbox remaining-work list. Keep them in sync.

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
| AZW3 reader | ✓ | ✓ | feature #126 (`android/v0.12.9`, VERIFIED 2026-06-29) — WebView + a pinned security-patched foliate-js bundle (NO NDK), mirroring iOS's `FoliateSpikeView`. The earlier "libmobi NDK port" framing was wrong: iOS renders these with foliate-js too. Render/resume/page-turn/secure-bridge/backup verified on a real 6 MB CJK AZW3 (API-35). |
| PDF reader | ✓ | ✓ | feature #115 (`android/v0.7.0`, VERIFIED) — `PdfDocument` (PdfRenderer, Mutex-serialized) + `PdfReaderActivity` continuous-scroll page bitmaps + 'Page N of M' pill + resume by page; emulator-verified. (DEFERRED designed follow-ons: paged toggle, page-jump overlay, encrypted-unlock — platform/API constraints.) |

## Sync & backup (Phase 3)

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| Backup format model (sections + manifest, schema 3 / manifest 1) | ✓ | ✓ | feature #113 (`android/v0.6.1`, VERIFIED) — Kotlin `@Serializable` DTOs matching `contracts/identity/backup-format.md` (ISO8601 UTC dates, plain `Locator` locatorJSON); golden-vector conformance green both sides. |
| WebDAV client + backup/restore pipeline | ✓ | ✓ | feature #116 (`android/v0.7.7`, VERIFIED) — `WebDavClient` + content-addressed blob store + `BackupCollector`/`RestoreImporter` + `WebDavBackupService` (byte-for-byte the iOS materializing-restore layout); credentials in DataStore + AndroidKeyStore. Verified by a LIVE rclone round-trip on the emulator (`scripts/run-webdav-roundtrip.sh`). |
| Backup/restore + WebDAV-settings UI | ✓ | ✓ | feature #114 (`android/v0.6.0`, VERIFIED) — the 5 designed Compose surfaces (#1767): WebDAV server list, server edit + test-connection, backup&restore + every WebDAV error, restore confirm→progress→result, selective picker. DEBUG-reachable; production entry-point wiring is the remaining design-gated step. |

## Phase 3 complete — the queue moved to Phase 4

**See [`android-checklist.md`](android-checklist.md) for the authoritative, checkable queue.**

**Phase 3 (#110) is DONE as of 2026-07-15.** Every capability block A–F reached `VERIFIED`: reading
stats (#122), highlights & annotations (#123/#124/#125 + #132/#135), library collections + search
(#127/#128), bilingual interlinear (#131), reader display settings + layout (#129/#137/#138), reader
navigation chrome (#132/#133/#134/#135), and the AZW3 reader (#126, which turned out to need a
foliate-js WebView, not an NDK port).

**Phase 4 is the live queue.** A–F answered "does Android have this capability *at all*"; it did not
answer "do the two apps do the same things". A 2026-08-04 code-level sweep against the iOS VERIFIED
feature set found **31 remaining gaps**, filed as `docs/features.md` rows **#139–#171** and grouped
into boxes **G0–G8**:

- **G0 Reachability** (#171) — **the gating item.** `MainActivity` hosts only Library + Search; no
  Settings hub has ever existed on Android, so #114 (backup UI), #118 (AI chat + provider list),
  #120 (OPDS UI) and #122 (stats dashboard) ship UI with **zero production call sites** — verified
  2026-08-04 and demoted `VERIFIED`→`DONE`. Blocked on needs-design **#2018**. Detector:
  `scripts/check-orphan-surfaces.sh`.

- **G1 Contents/TOC** (#139–#141) — TXT/MD/AZW3 hide the Contents control entirely.
- **G2 Text interaction** (#142–#143) — AZW3 has no selection/highlighting; the popover lacks
  translate/define/Ask-AI.
- **G3 AI** (#144–#148) — no stop button, no conversation sessions, no tool-calling, fixed summary
  scope, narrow context.
- **G4 TTS** (#149–#151) — read-aloud is wired into the TXT host only; EPUB/AZW3/PDF are silent.
- **G5 Library** (#152–#155) — no real cover art, no sort, not registered as a document handler.
- **G6 Reader settings** (#156–#160) — no justification, fixed tap zones, no auto-turn, global-only
  settings.
- **G7 Bilingual** (#161–#163) — headings untranslated, no post-setup reconfiguration, no whole-book job.
- **G8 Diagnostics & portability** (#164–#166) — no in-app diagnostics, no annotation export/import.
- **Deferred**: PDF text-layer highlights (#167), book-source scraping (#168), RTL/vertical (#169).

Android parity = every phase-4 box `VERIFIED` (the three DEFERRED rows excepted, pending go/no-go).
