---
branch: fix/issue-1540-epub-toc-sectionN
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-06-06
---

# Gate-4 audit — Bug #321 (GH #1540): EPUB TOC polluted with generic "Section N" entries

The Contents list interleaved the publisher's real chapters with one "Section N"
placeholder per un-nav'd spine item (~doubling the list; each "Section N" landed
mid-chapter). `EPUBParser.parseOPF` assigns `title: "Section \(index+1)"` as a
PLACEHOLDER (navTitles is empty at OPF-parse time — the nav doc is extracted +
resolved later). `EPUBMetadata.withResolvedTitles(navTitles)` then overwrote the
nav'd items with real titles but LEFT the un-nav'd items as "Section N"
(`return item`), and `TOCBuilder.fromSpineItems` (which skips nil/empty titles)
did not skip them → pollution.

## Manual fallback — why
The independent Codex runner wedged repeatedly this session (rule-53 ghost). Per
rule 47, manual fallback for this contained fix.

## Manual Audit Evidence
- **Root cause located correctly**: the fix is in `EPUBTypes.swift withResolvedTitles`,
  NOT `EPUBParser.parseOPF` — at parseOPF the OPF delegate's `navTitles` is empty
  (the nav doc hasn't been extracted yet), so the "Section N" there is a benign
  placeholder. The real pollution is `withResolvedTitles` keeping that placeholder
  for un-nav'd items.
- **Fix**: `withResolvedTitles` now returns a nil-titled `EPUBSpineItem` for an
  un-nav'd item (instead of `return item`, which kept "Section N"). This method is
  ONLY called when `navTitles` is non-empty (`EPUBParser` line 159 `if !navTitles.isEmpty`),
  so nil-ing un-nav'd items is exactly the bug-prescribed "only apply the Section N
  fallback when navTitles empty": a nav-LESS EPUB never calls `withResolvedTitles`,
  so ITS placeholders survive (TOC stays navigable) — verified by the unchanged
  flow at parseOPF + line 159.
- **Test** (RED→GREEN): `TOCProviderTests.withResolvedTitles_dropsSectionNPlaceholders_whenNavDocExists`
  — M=4 spine items with "Section N" placeholders, N=2 nav-doc entries (ch1, ch3);
  asserts `resolved.spineItems.map(\.title) == ["Prologue", nil, "Chapter Two", nil]`
  (un-nav'd → nil) AND end-to-end `TOCBuilder.fromSpineItems` → exactly 2 rows
  (= N nav entries, no "Section N"). The existing skip-untitled test stays green.
- **Edge** (nav-less EPUB): `withResolvedTitles` not called → placeholders survive →
  TOC navigable (no regression). **Out of scope** (separate same-screenshot defect,
  per the bug row): undecoded `&#39;` HTML entity in nav titles.

`ship-as-is`.
