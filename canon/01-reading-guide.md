---
title: Reading guide — vreader canon
updated: 2026-07-11
status: proposed
---

# Reading guide — vreader canon

A plain-language index for humans. One or two sentences per dossier, grouped by area,
so you can skim the whole canon here and open only the pages you actually need. For a
question-and-answer path instead of reading, use `bureau:query`. For the relationship
map (who calls whom), see [[Architecture — system overview]]. For the surprising things
the independent audit turned up, see [[Audit findings — notable code facts]].

## Start here

- [[Architecture — system overview]] — what vreader is (two native apps, iOS + Android,
  sharing an identity/backup contract), and the hub that links every page below.

## How the app is built (architecture)

- [[Architecture — app layer and concurrency model]] — how the app boots and wires its
  services together, and the Swift 6 concurrency rules (actors, `@MainActor`) it follows.
- [[Architecture — notification bus]] — the `NotificationCenter` message bus that reader
  and UI components use to talk to each other (the app has ~80 named notifications).
- [[Architecture — reader dispatch and format hosts]] — how opening a book picks the
  right reader for its format (EPUB, TXT, MD, PDF, Kindle).
- [[Architecture — schema migration history]] — how the on-disk database has evolved
  across ten schema versions without losing anyone's data.

## The library and its data

- [[Module — persistence and data model]] — the SwiftData database: every entity (books,
  positions, highlights, notes, sessions, collections) and how it is read and written.
- [[Module — import pipeline]] — turning a picked file into a deduplicated library book:
  format check, encoding detection, content fingerprint, sandbox copy.
- [[Module — library]] — the bookshelf screen: sorting, filtering, collections, covers.
- [[Module — locator]] — the universal "where am I in this book" position model that
  works across every format and survives cross-device sync.

## The readers (one per format)

- [[Module — TXT reader]] — plain-text books, including huge CJK novels and chapter
  detection.
- [[Module — MD reader]] — Markdown books, rendered natively without a web view.
- [[Module — EPUB reader]] — EPUB books, rendered in a web view (two engines: a legacy
  custom bridge and Readium).
- [[Module — Foliate AZW3 reader]] — Kindle-format books, rendered with the Foliate-js
  engine in a web view.
- [[Module — PDF reader]] — PDF books via PDFKit.
- [[Module — text mapping]] — the offset-tracking layer that keeps positions correct when
  displayed text differs from source text (find/replace rules, Chinese conversion).

## Reading features that cut across formats

- [[Module — annotations and highlights]] — creating, editing, and displaying highlights,
  bookmarks, and notes.
- [[Module — bilingual translation]] — AI translation shown line-by-line beneath the
  original, plus whole-book translation.
- [[Module — TTS]] — read-aloud (device voices and cloud voices) with sentence tracking.
- [[Module — search]] — full-text search inside a book and across the library.
- [[Module — reading stats]] — the reading-time dashboard and per-book statistics.
- [[Module — export]] — exporting annotations to JSON or Markdown.

## Getting books in and out

- [[Module — backup and WebDAV]] — the shipping backup path: metadata plus book files to
  a self-hosted WebDAV server, and materializing restore on a fresh device.
- [[Module — sync]] — the dormant CloudKit sync scaffolding (built, feature-flagged off,
  not the path users actually use).
- [[Module — book sources]] — scraping web-novel sites (Legado-compatible rule engine).
- [[Module — OPDS]] — browsing and downloading from OPDS catalog servers.

## AI, Kindle conversion, and settings

- [[Module — AI providers and tools]] — provider profiles, chat, tool-calling, and how
  keys are stored and resolved.
- [[Module — Kindle AZW3 and libmobi]] — converting Kindle files to EPUB on import (the
  vendored libmobi C library) and parsing their metadata/covers.
- [[Module — settings and preferences]] — every user preference: themes, typography,
  page-turn, per-book overrides.
- [[Module — diagnostics]] — the in-app diagnostics log and its export.

## The Android app and shared contracts

- [[Module — Android port]] — the second native app (Kotlin + Compose), what it ships,
  and how it is structured.
- [[Module — cross-platform contracts]] — the specs that force iOS and Android to agree
  on identity, positions, and backup format, plus a runnable conformance check.

## Developer tooling and process

- [[Module — debug bridge]] — the DEBUG-only URL scheme that lets scripts drive the app
  for automated verification.
- [[Module — automation and tooling]] — the repo's agent operating system: test/verify
  watchdog scripts, locks, ghost sweepers, and enforcement hooks.
- [[Module — test architecture]] — how the test suites are organized (694 unit-test
  files, 73 UI-test files).

## Decisions and history

- [[Decision — Android port strategy]] — why Android is a native port in a monorepo, not
  a cross-platform rewrite.
- [[Decision — six-gate workflow and lane dispatch]] — the binding process every change
  goes through, and how parallel agent work is orchestrated.
- [[Decision — composite dossier schema]] — the rule this canon itself runs on (one page
  per module, page-level trust tier).
- [[Timeline — feature delivery history]] — what shipped, in what order, across seven eras.
- [[Timeline — bug history and recurring classes]] — the recurring defect patterns and
  their root causes, worth remembering before touching the same areas.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u · 2026-07-10]] · [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
