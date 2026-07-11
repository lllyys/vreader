---
title: Audit findings — notable code facts
updated: 2026-07-11
status: proposed
---

# Audit findings — notable code facts

The most useful things the independent Codex audit surfaced while fact-checking this canon
against the actual code (2026-07-11). Each was found by comparing a documented claim to the
real implementation and finding a gap. **The canon pages have been corrected to describe the
true behavior** — but many of these are also genuine code issues worth a bug ticket, since
this exercise only rewrote documentation, it did not change any app code. Read this page
first if you want the surprising parts without reading every module.

## The dominant pattern: a described mechanism that production doesn't fully use

These are the highest-value findings — cases where a subsystem looks wired up but a live path
bypasses or ignores it.

- **`PersistenceActor` is not a single global serialized writer.** Many view files construct
  their own `PersistenceActor` instance from the shared container rather than using the
  injected one, so writes can run concurrently — the "all writes serialize through one actor"
  mental model does not hold in production. See [[Module — persistence and data model]].
- **The offset-map layer is built but unwired.** [[Module — text mapping]]'s conversion APIs
  have essentially no live consumers: TXT paths call the transform then discard the returned
  map, MD persists rendered coordinates with no mapping back, and the unified coordinator
  stores a map nothing reads. The primitives exist; the end-to-end wiring does not.
- **Reading-session crash recovery never runs.** `recoverStaleSessions()` is implemented but
  has no production call site, so stale sessions are not actually closed or recovered after a
  relaunch. See [[Module — reading stats]].
- **Book-source chapter caching never activates.** Every production pipeline is built with a
  nil cache, so the web-novel reading flow has no chapter cache or offline behavior despite
  the caching code existing. See [[Module — book sources]].
- **Library tag and series filters silently do nothing.** The filter returns true
  unconditionally for tag and series because those fields aren't present on the book item;
  only collection filtering actually works. See [[Module — library]].

## Discrete correctness gaps (candidate bug tickets)

- **Backup MOVE-412 race.** If a wrong-size blob already exists at the destination, the blob
  store uploads a correct temp object, gets a 412, deletes the temp object, and reports
  `.alreadyExists` — leaving the mismatched blob in place. It also proceeds with the MOVE when
  the PROPFIND size comes back nil. See [[Module — backup and WebDAV]].
- **Selective restore drops two sections.** Selective restore silently omits reading history
  and AI conversations, though restore-all handles both. See [[Module — backup and WebDAV]].
- **Diagnostics redaction misses single-quoted secrets.** The redactor only handles
  double-quoted values, so `api_key='secret'` can leak into exported or copied logs — a
  security-relevant gap. See [[Module — diagnostics]].
- **Empty search index blocks future reindexing.** Indexing a book with no text still inserts
  a metadata row, which a later reopen treats as a valid index and refuses to rebuild. Segment
  offset persistence is also racy. See [[Module — search]].
- **Reading-seconds accumulation can overflow.** Total seconds use an unchecked `Int64 +=`
  that can trap before the later clamp (pages and words use overflow-reporting addition; the
  duration path does not). See [[Module — persistence and data model]].
- **Per-book spacing is saved but never restored.** A per-book letter/CJK-spacing override is
  written but not re-applied on reader reopen; the Chinese-conversion toggle rewrites the file
  without persisting its own field. See [[Module — settings and preferences]].
- **MD position drifts after a find/replace edit.** Restore just clamps the old numeric offset
  to the new length with no re-derivation, so a length-changing rule shifts your place. See
  [[Module — MD reader]].
- **OPDS mixed feeds mis-render.** If any entry in a feed has an acquisition link, every row is
  rendered as an acquisition row, including navigation-only entries. See [[Module — OPDS]].
- **EPUB chapter labels need an exact TOC href.** Annotation cards only label an EPUB location
  when its href exactly matches a TOC entry — there is no nearest-preceding fallback, so many
  locations get no chapter label. See [[Module — annotations and highlights]].

## Dead or unwired code

- **`TOCProviding` is dead code.** The protocol has zero conformers and no consumer anywhere in
  the codebase — only a test comment mentions it. Remove it or document why it is reserved. See
  [[Module — locator]].

## Cross-platform divergence

- **iOS and Android disagree on invalid locators.** Swift's `Locator.canonicalJSON` omits a
  non-finite progression value; Kotlin's canonicalizer throws on the same input. They only
  agree if the caller validates first — a real parity gap in the identity contract. See
  [[Module — cross-platform contracts]].

## Doc-hygiene issues the audit corrected

- **Kindle DRM.** The native MOBI metadata/cover parsers do not actually check DRM state; they
  can return real data from readable header records even on encrypted books. See
  [[Module — Kindle AZW3 and libmobi]].
- **GitHub issue numbers cited as tracker rows.** Several pages referenced numbers like #1121,
  #1218, #1054 as local bug/feature rows when they are GitHub issue numbers — corrected across
  the affected dossiers.
- **`README.md` is stale.** It describes Android at the `android/v0.1.4`-era foundation stage
  and `SchemaV6`, while the app is actually at `android/v0.13.11` and `SchemaV10`. Flagged in
  [[Architecture — system overview]].

## How to use this page

Treat each item above as a starting point, not a verdict — open the linked module dossier for
the file-and-line detail, then confirm against the live code before acting, since the code
will keep changing after this audit. Nothing here has been fixed in the app; these are the
audit's observations, now accurately reflected in the canon.

**Sources.** [[session 014jggU2u3f3t6YRoPLS457u-audit · 2026-07-11]]
