# Manual Testing Guide

Open vreader's manual testing checklist and help the user verify features.

## Instructions

1. Read `docs/manual-test-checklist.md` (the live checklist).
2. Present a summary of test categories to the user.
3. If the user specifies a category, show those specific tests.
4. Help track test results if requested.

## Categories (current)

The categories track what the live checklist covers — read it for the authoritative list:

- **Library** — import, sort, view modes, collections, covers
- **Reader (TXT/MD)** — open, position restore, TOC, highlights, bookmarks, font/theme
- **Reader (EPUB)** — render, highlights, navigation, CFI persistence, footnotes
- **Reader (AZW3/MOBI)** — Foliate-js render, CFI, chrome toggle, highlights
- **Reader (PDF)** — page navigation, annotations, search
- **TTS** — playback, sentence highlight, auto-scroll
- **AI** — summarize, chat, translation
- **Search** — FTS5, CJK tokenization, navigation to result
- **Settings** — per-book overrides, theme backgrounds
- **Backup** — WebDAV import/export
- **Real-device only** — anything that needs iCloud / haptics / audible TTS

## Quick Start

Ask the user which category they want to test, then:

1. Show the relevant test cases from the checklist.
2. Help drive the simulator if the app is running. For tests that don't need real touch (state setup, snapshot assertion), prefer the DebugBridge: `xcrun simctl openurl booted vreader-debug://...` (see `docs/subsystems/debug-bridge.md`).
3. Record results.

## Files

- Live checklist: `docs/manual-test-checklist.md`
- DebugBridge reference: `docs/subsystems/debug-bridge.md`
- Bug tracker: `docs/bugs.md`
- Feature tracker: `docs/features.md`

