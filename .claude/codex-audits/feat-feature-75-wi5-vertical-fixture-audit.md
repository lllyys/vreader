---
branch: feat/feature-75-wi5-vertical-fixture
threadId: codex-exec-readonly
rounds: 1
final_verdict: ship-as-is
date: 2026-05-31
---

# Codex audit — Feature #75 WI-5 (multi-page vertical fixture + device finding)

Read-only `codex exec` audit. Verdict: accept (one low-severity comment nit).

## Summary

Unblocks #75's vertical page-turn verification by authoring a multi-page
`writing-mode: vertical-rl` EPUB fixture (`mini-cjk-vlong`, one long chapter, 24
CJK paragraphs) + catalog entry + bundle-existence test. `EPUBPagedAxis.scrollOffset`
behavior is UNCHANGED (verticalRL still shares horizontal-RTL's negative sign);
a comment + the pinned test `verticalRL_currentSignMatchesRTL` document an OPEN
on-device finding: vertical-rl paged navigation (initial position + turn
direction) is incorrect under that sign and needs iterative tuning against the
new fixture.

## Findings

- Low: a comment-wording nit (accepted — not behavior-affecting).
- Confirmed: scrollOffset behavior unchanged (-magnitude for verticalRL);
  catalog entry well-formed; EPUB archive valid (mimetype first+stored, EPUB3
  opf/nav/spine); no importer/test breakage; pinning known-imperfect behavior
  with an explicit "current not desired" comment is acceptable.

## Verdict

ship-as-is. Tests: `EPUBPagedAxisTests` + `DebugFixtureCatalogTests` green
(19 + catalog). This is the WI-5 unblock (fixture) + a documented device finding;
the vertical-rl sign/tap/swipe fix is the remaining WI-5 work, now testable
against `mini-cjk-vlong`.
