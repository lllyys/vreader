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
| EPUB import → local-artifact fingerprint | ✓ | ◑ | Android `BookImporter` is the UI-free seam; the SAF picker + Library list are ⛔ #1744. |
| Library list UI | ✓ | ⛔ | Android: design-needed #1744. |
| Content-hash dedup on import | ✓ | ✓ | Same key ⇒ identical bytes; `@Upsert` preserves the saved position. |

## Reader

| Capability | iOS | Android | Notes |
| --- | --- | --- | --- |
| EPUB open / parse (Readium) | ✓ | ✓ | Android `BookOpener` (Readium 3.3.0 shared+streamer) — emulator-verified open + metadata. |
| EPUB rendering (navigator screen) | ✓ (Readium/legacy) | ✓ | Android `ReaderActivity` hosts Readium's EpubNavigatorFragment (scroll) — emulator-verified incl. a real EPUB (WI-9, `android/v0.3.0`). |
| Resume (precise-first / canonical-fallback) | ✓ | ✓ | Android: `ReaderActivity` saves on locationDidChange (debounced + onStop flush) + restores precise-first via `ResumeResolver` (WI-9). |
| TXT reader | ✓ | ✓ | feature #111 (`android/v0.4.0`) — encoding-detected decode (UTF-16LE/CJK) + LazyColumn render + charOffsetUTF16 resume, emulator-verified incl. a real 14MB book. |
| Markdown (.md) reader | ✓ | ✓ | feature #112 (`android/v0.5.0`) — thin delta over the TXT reader: `MarkdownRenderer` (line-chunk → AnnotatedString, single-line CommonMark subset: headers/bold/italic/code/bullets) reusing the TXT decode/document/resume/chrome; `md` routes to the shared text reader. Emulator-verified (library-path render + TXT-renders-literally regression + md resume). |
| AZW3 / PDF readers | ✓ | ✗ | Phase 3 — filed per-capability under the #110 driver as prioritized. |

## Out of scope for the foundation bar (Phase 3)

AI translation / chat, TTS, book sources / OPDS, backup & WebDAV restore, the
visual-identity design system, full library management. Each becomes its own
Android feature row once #106's bar (one EPUB: import → open → resume) is
end-to-end on an emulator.
