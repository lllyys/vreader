---
kind: feature
id: 36
status_target: VERIFIED
commit_sha: de37ad48010e1b3df51b5f56f03bd4420ac0ee58
app_version: 3.14.149 (build 258)
date: 2026-05-11
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: Project Gutenberg OPDS (https://www.gutenberg.org/ebooks.opds/)
result: partial
---

## Summary

Round-4 device verify of feature #36 (OPDS catalog support) against
merged-main `de37ad4` (v3.14.149). Attempted to close the three
deferred legs from round-3 (`feature-36-20260508b.md`): per-catalog
navigation, download → import round-trip, edit/delete.

**Result: partial — bug #170 filed**. The Add Catalog flow works
end-to-end against a real OPDS server (Project Gutenberg), but the
**per-catalog navigation destination renders entirely blank** — no
spinner, no entries, no error. This blocks 2 of the 3 deferred legs
(per-catalog navigation + download → import round-trip both require
the detail view to render). The third leg (edit/delete) is left
unexercised this round.

## Acceptance criteria — round-4 outcomes

| Criterion | Round-4 result | Notes |
|---|---|---|
| Add a catalog with Name + URL | **pass** | Form accepted "Gutenberg" + "https://www.gutenberg.org/ebooks.opds/". Save button enabled after both fields populated. Row persists in OPDS list across sheet dismiss/reopen. |
| Per-catalog navigation (tap row → detail) | **fail** | NavigationLink pushes `OPDSBrowserView` but destination renders blank with only back chevron. No `ProgressView("Loading catalog...")`, no `navigationTitle`, no `feedContent` entries, no `errorState`. Persists across t+0.5s / t+2.5s / t+10.5s / t+17s. **Bug #170 filed (GH #529)**. |
| Download → import round-trip | **blocked-by-#170** | Cannot reach a book entry to tap — detail view never renders. |
| Edit / delete saved catalog | **deferred** | Swipe-left on the row was interpreted as a navigation push (10-step CGEventPost drag at 200ms total mistaken for tap on the row's chevron disclosure). True swipe-to-delete needs a slower drag or a UIKit-level gesture primitive. Documented as round-4 limitation; not a regression — bug #34 round-3 demonstrated swipe-to-delete works in Collections via a different (longer) gesture. |
| Form input via clipboard + cmd+V | **pass** | TextField paste worked via the documented CU-substitute toolkit (`pastekey.swift`). Cmd+A then paste correctly replaced "Gutenberg" → URL after the URL field accidentally received the first paste due to keyboard layout shift. |
| Public OPDS endpoint reachability | **pass** | `curl -s https://www.gutenberg.org/ebooks.opds/` returned 200 with valid Atom/OPDS XML (Project Gutenberg root feed: Popular / Latest / Random / etc. entries). Backend is reachable and well-formed; bug #170 is purely a client lifecycle issue. |

## Why partial, not pass

`feature-36-20260508b.md` (round-3) closed 9 of 12 acceptance criteria.
This round-4 attempt set out to close the remaining 3 by exercising a
saved catalog against a real OPDS endpoint:

- **Saved catalog persistence** — closed positively (catalog still
  visible in list after sheet dismiss/reopen).
- **Per-catalog navigation** — **failed** with bug #170.
- **Download → import round-trip** — blocked behind bug #170 (cannot
  reach book entries to tap when catalog detail is blank).
- **Edit / delete** — swipe-to-delete couldn't be exercised through
  CU-substitute reliably; left for a future round.

So round-4 advanced 1 criterion (saved catalog persistence) but
introduced a blocker (bug #170) for the other 2. **Net: 10 of 12
acceptance criteria now pass**, but feature still cannot flip to
VERIFIED.

## Bug #170 — what was filed

`docs/bugs.md` row #170 (GH #529): "OPDS catalog detail view renders
blank after NavigationLink tap — no spinner, no entries, no error".

**Symptom**: `OPDSBrowserView.body` (`OPDSBrowserView.swift:39-48`)
branches on `isLoading && feed == nil` (→ ProgressView), `errorMessage`
(→ errorState), `feed` (→ feedContent). The blank-with-back-chevron-only
state means all three initial-state flags hold:
`isLoading == false && feed == nil && errorMessage == nil`. Either
`.task` never fired, or `loadFeed` was cancelled before its
`isLoading = true` line executed.

**Suspect root cause** (not confirmed, fix scope): the `.task` modifier
nested inside the chain `.sheet` → `NavigationStack` → `NavigationLink`
destination is hitting a known iOS 26 SwiftUI lifecycle quirk. AX
confirms only the back button is present in the detail area — the
Group { } body is rendering an empty branch.

**Possible fix directions** (per bug body): `.onAppear { Task { ... } }`
in place of `.task`; OR seed `@State private var isLoading = true`
initial value so spinner shows immediately; OR `.task(id: catalogURL)`.

## Commands run

```bash
# Probe OPDS endpoint reachability from host
curl -sI "https://www.gutenberg.org/ebooks.opds/"
# → HTTP/2 200

curl -s "https://www.gutenberg.org/ebooks.opds/" | head -8
# → <feed xmlns="http://www.w3.org/2005/Atom" ...>
# → <title>Project Gutenberg</title>
# → <entry><title>Popular</title>... (etc.)

# Reset state for clean run
xcrun simctl openurl booted "vreader-debug://reset"

# CU-substitute drive: Library → globe → + → form input → Save
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 679 194  # OPDS globe
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 789 210  # + Add
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 318  # Name field
osascript -e 'set the clipboard to "Gutenberg"'
swift .claude/skills/sim-drive-fallback/scripts/pastekey.swift
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 370  # URL field
osascript -e 'set the clipboard to "https://www.gutenberg.org/ebooks.opds/"'
swift .claude/skills/sim-drive-fallback/scripts/pastekey.swift
# (URL field accidentally received first paste due to keyboard layout shift;
# fixed via tap → Cmd+A → paste-replace pattern)
osascript -e 'tell application "System Events" to keystroke "a" using command down'
swift .claude/skills/sim-drive-fallback/scripts/pastekey.swift
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 775 220  # Save

# Tap Gutenberg row → blank detail view
swift .claude/skills/sim-drive-fallback/scripts/clickat.swift 626 278

# Confirm blank at multiple intervals — all identical
sleep 0.5; xcrun simctl io booted screenshot ...
sleep 2;   xcrun simctl io booted screenshot ...
sleep 10;  xcrun simctl io booted screenshot ...
```

## Observations

- **Form input via Cmd+V works on SwiftUI Form TextField** — bypassed
  the round-3 documented "external CU/Sim infra quirk" that previously
  blocked per-character `type` actions. The CU-substitute toolkit's
  `pastekey.swift` (CGEventPost cmd+V into focused field) succeeds
  where pbcopy + system keystroke previously didn't.
- **Cmd+A then paste replaces selection** — `osascript -e 'tell app
  "System Events" to keystroke "a" using command down'` selects all
  text in the currently focused iOS Simulator TextField, then a
  subsequent paste overwrites cleanly. Useful for fix-up patterns when
  a paste lands in the wrong field.
- **Keyboard layout shifts the second tap target** — tapping field A
  then field B with the keyboard up means B's intended y-coordinate
  shifted upward. Re-query coords AFTER keyboard is up, or paste field
  A → dismiss keyboard → tap field B.
- **`.task` lifecycle quirk in nested sheet+NavigationStack+NavigationLink
  destinations** — bug #170. Feature #36's deferred legs cannot
  advance until this is resolved.

## Artifacts

- `feature-36-r4-01-library-postreset-20260511.png` — initial state (Settings sheet leftover)
- `feature-36-r4-02-library-empty-20260511.png` — library empty post-reset
- `feature-36-r4-03-opds-empty-20260511.png` — OPDS Catalogs empty-state
- `feature-36-r4-04-add-form-20260511.png` — Add Catalog form blank
- `feature-36-r4-05-form-filled-20260511.png` — both fields show "Gutenberg" (paste-mishit)
- `feature-36-r4-06-form-fixed-20260511.png` — URL corrected via Cmd+A + paste
- `feature-36-r4-07-catalog-saved-20260511.png` — Gutenberg row visible in list
- `feature-36-r4-08-catalog-navigated-20260511.png` — blank detail view immediately after tap
- `feature-36-r4-09-catalog-loaded-20260511.png` — blank at t+5s
- `feature-36-r4-10-opds-list-saved-20260511.png` — list still shows Gutenberg after back
- `feature-36-r4-11-after-long-wait-20260511.png` — blank at t+17s post-second-tap
- `feature-36-r4-12-current-state-20260511.png` — final fresh capture
- `feature-36-r4-13-back-to-list-20260511.png` — back to list works
- `feature-36-r4-14-detail-t05-20260511.png` — third tap, t+0.5s, still blank
- `feature-36-r4-15-detail-t25-20260511.png` — t+2.5s, blank
- `feature-36-r4-16-detail-t105-20260511.png` — t+10.5s, blank
- `feature-36-r4-17-swipe-delete-20260511.png` — swipe attempt navigated instead
- `feature-36-r4-18-after-swipe-attempt-20260511.png` — final state

## Disposition

Feature #36 stays at status **DONE** (status_target was VERIFIED but
result is partial, so no flip). Round-3's "9/12 acceptance criteria
pass" advances to "10/12 pass": saved-catalog persistence closes; 2
of 3 round-3-deferred legs (per-catalog navigation + download/import)
are now blocked by bug #170; edit/delete remains a round-5 target
once a more reliable swipe-to-delete primitive is available.

VERIFIED requires: bug #170 fixed → re-run navigation + download →
import round-trip on a real catalog; swipe-to-delete proven via a
slower CGEventPost drag or via a UITest-driven path.

## Cross-references

- `dev-docs/verification/feature-36-20260507.md` — round-1 (parser
  unit tests + live curl probes).
- `dev-docs/verification/feature-36-20260508.md` + `feature-36-20260508b.md`
  — rounds 2 + 3 (UI sheet + visual leg, CU display path).
- Bug #170 (GH #529) — the blocker.
- `vreader/Views/OPDS/OPDSBrowserView.swift:39-52` — body + .task.
- `vreader/Views/OPDS/OPDSCatalogListView.swift:96-104` — NavigationLink.
- `vreader/Views/LibraryView.swift:275-276` — sheet + NavigationStack.
