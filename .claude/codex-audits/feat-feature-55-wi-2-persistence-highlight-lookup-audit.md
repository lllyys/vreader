---
branch: feat/feature-55-wi-2-persistence-highlight-lookup
threadId: 019e3ead-426e-7ba0-b567-a817499f5ff8
rounds: 1
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #55 WI-2 (PersistenceActor single-highlight lookup)

## Scope

Files changed (3), diff = single commit HEAD vs merge-base `1ada88f`:
- `vreader/Services/PersistenceActor+Highlights.swift` (+31) — `highlight(withID:forBookWithKey:)` + `extension PersistenceActor: HighlightLookup {}`
- `vreaderTests/Services/PersistenceActor+HighlightLookupTests.swift` (new) — Swift Testing tests
- `vreader.xcodeproj/project.pbxproj` — xcodegen regen registering the new test file

## Round 1

Codex thread `019e3ead-426e-7ba0-b567-a817499f5ff8`, sandbox `read-only`.

| file:line | severity | issue | resolution |
|---|---|---|---|
| — | — | No findings — Critical / High / Medium / Low all clear | n/a |

Auditor confirmed:
- The fetch is a dedicated `FetchDescriptor<Highlight>` with the intended
  compound predicate `highlight.highlightId == highlightID && highlight.book?.fingerprintKey == bookKey`
  — scopes the lookup to `(highlightId, book.fingerprintKey)`, prevents
  cross-book leakage, and an orphaned highlight (`book == nil`) cannot match
  because the optional-chain comparison evaluates false.
- The captured locals (`let highlightID = id` / `let bookKey = key`) are the
  standard SwiftData / Swift 6-safe predicate-capture pattern.
- `fetchLimit = 1` keeps this on the single-row path — not materializing the
  whole book's highlight set (plan §2.4 / §6 R-1).
- Tests cover the WI's behavioral cases: found record, unknown id,
  non-existent book key, cross-book isolation (two books, same highlight id
  queried under the wrong key), nil-note round-trip, broader-palette colors,
  and the protocol-existential path.

Noted: the auditor did not run `xcodebuild test` in the read-only sandbox — this
is a source audit. The WI-2 test gate (`PersistenceActorHighlightLookupTests`,
7 tests / 9 cases) was run separately by the implementer and passed
(`TEST SUCCEEDED`).

## Verdict

**ship-as-is** — zero findings at any severity after 1 round.
