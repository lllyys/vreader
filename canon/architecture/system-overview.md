---
title: Architecture — system overview
updated: 2026-07-11
status: proposed
---

# Architecture — system overview

## Purpose

A hub page linking every module and architecture dossier in this canon, so a reader can navigate from "what is vreader" down to any subsystem's detail page. This page is interpretive synthesis (it re-derives relationships already documented per-module elsewhere) and stays `status: proposed` by design — it is not itself independently fact-checked claim-by-claim; each linked page carries its own verification tier.

## What vreader is

A native ebook reader shipped as two independently-shippable apps sharing an identity/locator/backup contract layer but not code: a mature iOS app (Swift 6, SwiftUI/UIKit, SwiftData, ~305K LOC) at the repo root, and a newer native Android app (Kotlin/Compose) under `android/` (see [[Decision — Android port strategy]]). It reads EPUB, TXT, MD, PDF, and Kindle AZW3/MOBI/PRC; backs up over WebDAV; and layers AI-assisted bilingual translation, chat, and TTS on top of the reading experience.

**Known doc drift.** `README.md`'s Android callout and Tech Stack table are stale relative to this: it describes Android at the `android/v0.1.4`-era foundation-plumbing stage and cites `SwiftData (SchemaV6)`, `~90 unit-test methods`, `52 done` features, and `211 fixed` bugs, while the repo is actually at `android/v0.13.11` (TXT/MD/PDF/AZW3/WebDAV/OPDS/AI/TTS/stats/highlights/collections all shipped), `SchemaV10`, 119 VERIFIED features, and 353 FIXED bugs — see [[Timeline — feature delivery history]] for the authoritative counts.

## Layer map

- **App layer** — bootstrap, DI/environment wiring, launch-flag test seams: [[Architecture — app layer and concurrency model]].
- **Cross-component messaging** — the `NotificationCenter` bus every UIKit/SwiftUI boundary crosses through: [[Architecture — notification bus]].
- **Persistence** — SwiftData primarily via `PersistenceActor` (with named exceptions — see Concurrency model below), schema evolution: [[Module — persistence and data model]], [[Architecture — schema migration history]].
- **Import** — file → validated, fingerprinted, deduplicated library row: [[Module — import pipeline]], [[Module — Kindle AZW3 and libmobi]].
- **Reader dispatch** — routes an opened book to its per-format host: [[Architecture — reader dispatch and format hosts]].
- **Per-format readers** — [[Module — TXT reader]], [[Module — MD reader]], [[Module — EPUB reader]], [[Module — Foliate AZW3 reader]], [[Module — PDF reader]], underpinned by [[Module — text mapping]] and [[Module — locator]].
- **Cross-cutting reader features** — [[Module — bilingual translation]], [[Module — annotations and highlights]], [[Module — TTS]], [[Module — search]], [[Module — reading stats]], [[Module — export]].
- **Remote/sync surfaces** — [[Module — backup and WebDAV]] (the shipping path), [[Module — sync]] (dormant CloudKit scaffolding), [[Module — book sources]], [[Module — OPDS]].
- **AI** — [[Module — AI providers and tools]].
- **Cross-cutting app services** — [[Module — settings and preferences]], [[Module — library]], [[Module — diagnostics]]. The production entry/library-UI files sitting directly under `vreader/Views/` (`ContentView.swift`, `LibraryView.swift`, `BookCardView.swift`, `BookCoverArtView.swift`, `BookRowView.swift`, `GenerativeCoverView.swift`/`GenerativeCoverMetrics.swift`, `LibraryCardTokens.swift`, `LibraryProgressRing.swift`, `ScreenSpaceDemo.swift`) live under [[Module — library]], except `ContentView.swift`, which belongs to app bootstrap.
- **Developer/verification tooling** — [[Module — debug bridge]] (DEBUG-only, in-app), [[Module — automation and tooling]] (repo-level scripts/hooks/crons), [[Module — test architecture]].
- **Android + cross-platform** — [[Module — Android port]], [[Module — cross-platform contracts]].
- **Process** — [[Decision — six-gate workflow and lane dispatch]], [[Decision — composite dossier schema]] (this canon's own schema decision).
- **History** — [[Timeline — bug history and recurring classes]], [[Timeline — feature delivery history]].

## Relationship classes (the canon's edge taxonomy)

Six classes of cross-module relationship recur throughout the per-module dossiers; `canon/_edge-ledger.json` tracks them mechanically:

1. **Notification producer/consumer** — one module posts a `Notification.Name`, another observes it. The catalog lives in [[Architecture — notification bus]]; almost every reader/service dossier cites specific names it posts or observes.
2. **Protocol conformance and injection seams** — boundary protocols (`LibraryPersisting`, `BookImporting`, `HighlightPersisting`, `BackupProvider`, `ChapterTextProviding`, …) that let one module depend on an interface rather than a concrete type, per `.claude/rules/00-engineering-principles.md`.
3. **Actor hops and persistence access** — which modules call into `PersistenceActor` (and the sibling `ChapterTranslationStore` actor) and how data crosses those `await` boundaries as value-type records.
4. **WKWebView JS bridge channels** — EPUB, Foliate/AZW3, and bilingual JS injection all route through named script-message handlers and `FoliateJSEscaper`/equivalent escaping.
5. **`contracts/` surfaces** — the iOS↔Android identity/locator/cache-key/backup-format contract, where a Swift type and a Kotlin type must serialize identically; see [[Module — cross-platform contracts]].
6. **Build/target dependencies** — `project.yml` targets, the one SPM package (Readium), the vendored libmobi C library and Foliate-js bundle, and the Android Gradle module graph.

## Format-host dispatch (the reader's central seam)

`ReaderContainerView` reads a book's `DocumentFingerprint.format` (not the parallel `Book.format` string column — hardened by bug #246/GH #1072) and routes to one of five hosts: `TXTReaderHost`, `MDReaderHost`, `EPUBReaderHost` (WKWebView + custom bridge or Readium navigator), `FoliateBilingualContainerView` wrapping `FoliateSpikeView` for AZW3/MOBI/PRC, and `PDFReaderHost` (PDFKit). See [[Architecture — reader dispatch and format hosts]] for the full table and the "live-container capability drop" regression class this dispatch point has repeatedly produced (documented in [[Timeline — bug history and recurring classes]]).

## Identity model (threading through import, persistence, backup, and Android)

Converted Kindle books deliberately carry **two** identities (feature #108, `contracts/identity/DECISION.md`). `Book.fingerprintKey = DocumentFingerprint.canonicalKey = "{format}:{contentSHA256}:{fileByteCount}"` is always computed from the bytes actually stored on this platform — for a converted Kindle book that means the CONVERTED-EPUB bytes, not the original AZW3/MOBI/PRC bytes. This platform-local key drives rendering, the `Book.fingerprintKey` unique constraint in [[Module — persistence and data model]], dedup in [[Module — import pipeline]], and content-addressed blob paths in [[Module — backup and WebDAV]]. Separately, `Book.sourceCanonicalKey = "azw3:{sourceSHA256}:{sourceByteCount}"` stores the SHA-256 of the ORIGINAL Kindle-format bytes and exists solely for cross-platform (Swift↔Kotlin) dedup in [[Module — cross-platform contracts]] — it is nil for native (non-Kindle) imports and for books imported before #108, whose source bytes were discarded. Native imports have no such split: `fingerprintKey` alone serves as both local and cross-platform identity.

## Concurrency model

Swift 6 strict concurrency throughout the iOS app: actors for stateful services (`PersistenceActor`, `TXTService`, `ImportJobQueue`, sync actors, …), `@MainActor @Observable` for ViewModels and UI-facing stores. `PersistenceActor` is the dominant SwiftData-write pattern and the one that crosses actor boundaries via value-type record DTOs, but it is not a strict invariant: `SwiftDataSessionStore` creates and saves `ModelContext`s directly (not actor-isolated), `ChapterTranslationStore` is a second actor writing SwiftData independently of `PersistenceActor`, and `BookSourceListView`/`ReplacementRulesView` mutate directly through the environment `ModelContext` from SwiftUI. See [[Architecture — app layer and concurrency model]] for the concrete inventory of actors, `@MainActor` types, and the narrow `MainActor.assumeIsolated` call sites. The Android port's coroutine/`StateFlow` conventions are the platform analog (`.claude/rules/50-codebase-conventions.md` §12), documented per-surface inside [[Module — Android port]].

## Process and history

Every non-trivial change to this codebase moves through the six-gate workflow (Plan → Independent audit → TDD → Implementation audit → Verification → Merge, [[Decision — six-gate workflow and lane dispatch]]), tracked in `docs/bugs.md`/`docs/features.md` and summarized in [[Timeline — bug history and recurring classes]] / [[Timeline — feature delivery history]]. This canon itself (the `bureau` workspace under `canon/`) was compiled by that same disciplined process turned inward: a multi-lane survey pass, a hostile multi-wave verification pass, and (pending) an independent Codex audit — see [[Decision — composite dossier schema]] for the compile-time schema decision this canon runs on.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
