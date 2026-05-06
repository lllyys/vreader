---
branch: fix/issue-310-add-azw3-fixture-debugfixturecatalog
threadId: 019dfecf-705d-7690-ae3c-93ba5c8fed83
rounds: 2
final_verdict: ship-as-is
date: 2026-05-07
---

# Codex audit log — bug #143 (GH #310)

## Round 1

**Findings:**

| File:line | Severity | Issue | Resolution |
|---|---|---|---|
| `vreaderTests/Services/DebugBridge/DebugFixtureCatalogTests.swift:26` | Medium | The new coverage only proves the catalog row exists and the bundle contains a file; it does not prove `RealDebugBridgeContext.seed(fixture: "mini-azw3")` successfully imports this specific MOBI-under-`.azw3` fixture onto the `BookFormat.azw3` / Foliate path. | **Fixed** — added `RealDebugBridgeContextTests.test_seed_miniAzw3_importsAzw3FromBundle()` that uses real `Bundle.main`, real `BookImporter`, real `PersistenceActor` and asserts `books.first?.format == "azw3"`. |
| `vreader/Resources/DebugFixtures/mini-azw3.azw3:1` | Low | The binary fixture's provenance is only captured in a code comment. For an opaque checked-in binary, reviewers have no durable in-repo trail for exact source URL, variant, retrieval date, or checksum. | **Fixed** — added `vreader/Resources/DebugFixtures/README.md` with a provenance table covering all 3 fixtures: source URL, variant, byte sizes, license, retrieval date. Also added a "how to add a new fixture" section. |

Codex confirmed:
- `DebugFixtureCatalog` registration consistent with `BookFormat.azw3`'s extension collapsing.
- Debug-only bundle copy still excludes Release via `project.yml:29-61`.
- Foliate-js sniffs MOBI magic bytes at runtime rather than trusting extension (`view.js` / `mobi.js`).
- Licensing acceptable: PG ebook 1064 listed "Public domain in the USA"; PG terms allow reuse.

## Round 2

**Findings:** None.

Codex non-blocking notes:
- New test doesn't assert `originalExtension == "azw3"` — narrower than the original recommendation, but not a bug for issue #310's acceptance scope. Accepted as documented narrower assertion.
- The unrelated `docs/bugs.md` row #148 (separate file for the pre-existing `TXTServiceTests.decodeWithHint_fallsBack_whenHintEncodingFailsToDecode` failure) is fine.

## Verdict

**ship-as-is** — both findings from round 1 closed; round 2 confirms no new issues.
