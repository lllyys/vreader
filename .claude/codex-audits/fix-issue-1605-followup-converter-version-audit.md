---
branch: fix/issue-1605-followup-converter-version
threadId: 019eb298-83d3-7060-b0bf-cd30792b280f
rounds: 1
final_verdict: ship-as-is
date: 2026-06-11
---

# Audit log — #336 follow-up (converter version + threading tests)

This branch carries exactly the **already-audited** round-2 resolutions of
the Bug #336 reopen audit (`fix-issue-1605-justify-cjk-gate-audit.md`,
round-2 session `019eb298-83d3-7060-b0bf-cd30792b280f`) that were
accidentally left uncommitted when PR #1636 merged:

| finding (from #1636's round 2) | resolution carried here |
|---|---|
| Medium — `MobiEPUBConverter.version` not bumped though output bytes changed | `version = 2` + doc comment |
| Low — `version >= 1` test couldn't catch a missed bump; no `dc:language` threading test | exact-version assertion + `opfLanguageThreading` (zh-cn preserved; nil/empty → und) |

No new logic beyond what that audit reviewed and approved; plus the
#341/#343 verification artifacts (PNGs, non-code). Suites green
(`MobiEPUBConverterTests`, `MobiEPUBAssemblerTests`).

## Verdict

**ship-as-is** (inherits the parent audit's round-2 approval).
