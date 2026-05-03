# PR Checklist — dev → main

## Summary

**Branch**: `dev` → `main`
**Commits**: 68 (+ uncommitted session fixes)
**Scope**: 325 files changed, ~52K insertions
**Date**: 2026-03-21

This PR delivers the complete V2 roadmap (Phases A–E) plus 78 bug fixes from integration testing.

---

## Feature Phases Delivered

### Phase A — Quick Wins
- [ ] WI-001: Persist library view preferences (sort order + view mode via PreferenceStore)
- [ ] WI-002: Visual feedback for bookmark toggle
- [ ] WI-003: Search highlight auto-dismiss

### Phase B — Reader Enhancements
- [ ] WI-B04: Unified TXT reflow engine (TextKit 2 scroll + paged)
- [ ] WI-B05: Unified MD reflow (attributed text pagination)
- [ ] WI-B07: Unified EPUB text-mode (strip HTML to attributed text)
- [ ] WI-B10: Auto page turning (timer-based)
- [ ] WI-B11: Page turn animations (none/slide/cover)
- [ ] WI-B13: Pagination cache invalidation

### Phase C — Collections & Annotations
- [ ] WI-C01: Collections / tags / series (SchemaV3)
- [ ] WI-C02: Annotation export (Markdown + JSON)
- [ ] WI-C03: Annotation import (VReader JSON round-trip)
- [ ] WI-C04: OPDS catalog (browse + download from OPDS 1.2 feeds)

### Phase D — Book Sources
- [ ] WI-D01: BookSource model + SwiftData + management UI
- [ ] WI-D02: HTTP client + encoding detection + rate limiting
- [ ] WI-D03: Rule engine (CSS selectors + regex + Legado syntax)
- [ ] WI-D04: Pipeline MVP (search → info → chapters → content)
- [ ] WI-D05: Legado JSON import/export + compatibility classification
- [ ] WI-D06: Chapter cache + offline reading
- [ ] WI-D07: Update detection + source sharing

### Phase E — Text Processing
- [ ] WI-E01: WebDAV backup and restore
- [ ] WI-E03+E04+E05: Text-mapping layer + simp/trad + replacement rules
- [ ] WI-E06: HTTP TTS (cloud voice synthesis)

---

## Bug Fixes (This Session — Uncommitted)

### Critical / High Severity
- [ ] #60 FIXED: Large TXT files (~15MB) slow to open — sample-based encoding detection
- [ ] #61 FIXED: Search slow in large TXT — persisted segment offsets restored on reopen
- [ ] #62 FIXED (v3): Content shifts on chrome toggle — custom ReaderChromeBar overlay replaces system nav bar
- [ ] #63 FIXED: Progress bar unresponsive — TapZoneModifier VStack with bottom exclusion zone
- [ ] #64 FIXED: All formats slow to load — deferred 5 eager .task blocks to on-demand
- [ ] #70 FIXED: Cannot scroll in native mode — removed TapZoneOverlay from native path
- [ ] #73 FIXED: Top bar behind Dynamic Island — UIWindowScene safe area lookup
- [ ] #74 FIXED: EPUB TOC shows "Section XXX" — parse nav.xhtml + toc.ncx for real titles
- [ ] #77 TODO: Cannot add highlight in native EPUB — code verified correct, needs on-device repro

### Medium Severity
- [ ] #65–#69 FIXED: 5 stale UI test expectations updated
- [ ] #71 FIXED: Reader top bar styling — 44pt, 20pt icons, theme colors
- [ ] #72 FIXED: Library nav bar flash during transition
- [ ] #75 FIXED: Sort preference not remembered — PreferenceStore wired
- [ ] #76 FIXED: Annotations tab order — Contents first
- [ ] #78 FIXED: Highlight visual persists after deletion — readerHighlightRemoved notification

---

## Pre-Merge Checklist

### Build & Tests
- [ ] `xcodebuild build` succeeds (no errors)
- [ ] Unit tests pass (`xcodebuild test -scheme vreader`)
- [ ] New tests pass:
  - [ ] `TXTServiceTests` — encodingFromName round-trip, sample detection
  - [ ] `SearchServiceOffsetTests` — restoreSegmentOffsets
  - [ ] `EPUBNavTOCTests` — nav.xhtml title extraction, NCX fallback, CJK titles
  - [ ] `LibraryViewModelPersistenceTests` — sort/viewMode survive recreation
  - [ ] `TapZoneModifierTests` — bottomInset, config preservation
- [ ] No compiler warnings in modified files

### New Files Added
- [ ] `vreader/Views/Reader/ReaderChromeBar.swift` — added to Xcode project + PBXGroup

### Manual Testing (on-device or simulator)
- [ ] **Library**: Sort order persists across app restart
- [ ] **Library**: View mode (grid/list) persists
- [ ] **Reader — All formats**: Content scrolls normally in native mode
- [ ] **Reader — Chrome**: Tap to show/hide toolbar — content doesn't shift
- [ ] **Reader — Chrome**: Top bar below Dynamic Island, matches bottom bar style
- [ ] **Reader — Chrome**: Library nav bar not visible during push transition
- [ ] **EPUB**: Open annotations panel → Contents tab shows real chapter titles
- [ ] **EPUB**: Highlight text → confirmation dialog appears → highlight persists
- [ ] **EPUB**: Delete highlight from panel → visual clears immediately
- [ ] **TXT**: Open 15MB CJK file — loads without excessive delay
- [ ] **TXT**: Search in large file — results appear on second open without re-index
- [ ] **TXT/MD**: Delete highlight from panel → visual updates
- [ ] **Annotations panel**: Tab order is Contents → Bookmarks → Highlights → Notes
- [ ] **All formats**: AI/Search/TOC only load when invoked (not on reader open)

### Regression Spots
- [ ] EPUB text selection still triggers highlight dialog (bug #77 — investigate if broken)
- [ ] PDF highlights still work (PDFAnnotationBridge unaffected by changes)
- [ ] TXT chunked reader still works for large CJK files
- [ ] Reading position restore still works across all formats
- [ ] Bookmarks save and navigate correctly
- [ ] Search results navigate to correct location

### Known Open Issues — Bugs
- [ ] Bug #77: EPUB native highlight — code verified correct, needs iOS 26 on-device repro

### Known Open Issues — Features (code committed but not working)
- [ ] Feature #21: Paginated mode — user reports "still scrolling"
- [ ] Feature #23: TXT TOC — user reports "cannot recognise"
- [ ] Feature #25: Tap zones — left/right not wired in native mode
- [ ] Feature #37: Per-book settings — affects all books instead of one

### Unimplemented Features (tracked in features.md)
- [ ] Feature #10: iCloud backup
- [ ] Feature #38: Hierarchical TOC display
- [ ] Feature #39: Custom background image

---

## Commit Plan

```bash
# Stage all changes
git add -A

# Commit with descriptive message
git commit -m "fix: 17 bug fixes (#60-#78) — performance, gestures, chrome, TOC, persistence

- #60: Sample-based encoding detection for large TXT (8KB sample before full decode)
- #61: Persist search segment offsets across sessions
- #62 v3: Custom ReaderChromeBar replaces system nav bar (no content shift)
- #63: TapZoneModifier bottom exclusion zone for progress bar
- #64: Defer AI/search/TOC/rules to on-demand (faster reader open)
- #65-#69: Update stale UI test expectations
- #70: Remove TapZoneOverlay from native reader path (fixes scrolling)
- #71: ReaderChromeBar styling (44pt, theme colors, 44x44 touch targets)
- #72: .toolbar(.hidden) for cleaner nav transition
- #73: UIWindowScene safe area for Dynamic Island
- #74: Parse EPUB nav.xhtml/toc.ncx for real TOC titles
- #75: Wire PreferenceStore into LibraryViewModel for sort/viewMode persistence
- #76: Annotations panel tab order (Contents first)
- #78: readerHighlightRemoved notification for visual cleanup on delete

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>"
```
