---
branch: fix/triage-bug-266-bilingual-paragraph-misalignment
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-25
---

## Scope

Docs-only triage filing. Adds one new summary row + one Open-Bug-Details
entry to `docs/bugs.md` for **Bug #266** (bilingual translation misaligned
to the wrong paragraph, High). Touches `docs/bugs.md` only, plus
`project.yml` / `project.pbxproj` (version bump 3.39.10/631 → 3.39.11/632).

**No Swift source files changed.** The audit-gate hook fires on
`project.pbxproj` — false positive of the Swift-file heuristic. Manual
mini-audit.

## Manual audit evidence

### Investigation done at triage time

1. **Bilingual pipeline mapped end-to-end**: enumerate
   (`EPUBBilingualJS.bilingualEnumerateJS`) → `bilingualEnumerate` message
   → `EPUBBilingualPipeline.parseEnumerateMessage` → `[BilingualBlock]` →
   `EPUBBilingualOrchestrator.buildInjectJS(translatedSegments:)` →
   `EPUBBilingualPipeline.translationsByBid` → `bilingualInjectJS`.
2. **The match is a blind positional index-zip** — `translationsByBid`
   (`EPUBBilingualPipeline.swift`): `for i in 0..<min(blocks.count,
   segments.count) { map[blocks[i].bid] = segments[i] }`. Confirmed the
   `text` field on `BilingualBlock` is carried "for parity/debugging only"
   and is NOT used to anchor.
3. **Enumerate segmentation** — `EPUBBilingualJS` walks
   `document.body.getElementsByTagName('*')` keeping
   `BLOCK_TAGS = {p, li, blockquote, pre, dd, dt}` in DOM order. Because it
   walks ALL descendants, nested block tags (`blockquote>p`, `li>p`,
   `dd>p`) double-count: both the container and its child match and are
   pushed as separate blocks (each has non-empty `textContent`).
4. **Translation segmentation** — `ChapterTranslationService.swift:123`:
   `segments = ChapterSegmenter.paragraphs(in: sourceText)` on the
   EXTRACTED PLAIN TEXT — does not double-count nested containers.
5. **No enforced 1:1 contract** — the only count check
   (`ChapterTranslationService.swift:133`,
   `sourceParagraphCount == segments.count`) compares the segmenter to
   itself for cache staleness; it never compares against the enumerate
   block count. The `BLOCK_TAGS` set's "keeps the enumerate/segment counts
   aligned" comment is a hand-tuned approximation that nesting defeats.
6. **Reported +2 drift is consistent**: a leading epigraph
   `<blockquote><p>…</p></blockquote>` or a leading 2-item structure the
   DOM enumerate splits into 2 extra blocks but the text segmenter merges
   yields exactly "para-1 translation → para-3 position".
7. **Cross-format check**: every format consumes the same
   `ChapterSegmenter` segments via the VM and zips against its own
   render enumerate — EPUB (`EPUBBilingualPipeline`), AZW3/MOBI
   (`FoliateSpikeView` bilingual), TXT (`TXTReaderContainerView+Bilingual`),
   MD (`MDReaderContainerView+Bilingual`). The user's "other formats may
   have similar issues" is architecturally well-founded.

### Correctness checks

1. **Bug-vs-feature** — feature #56 bilingual reading IS implemented and
   ships; the alignment is wrong. Implemented-but-broken → **bug**, not a
   feature.
2. **No duplicate** — no existing row covers bilingual paragraph
   misalignment. Related rows are about TOC/nav (#262/#1136), position
   (#265), or font (#261), not translation↔paragraph anchoring.
3. **One-issue-per-triage** — the user reported one concrete symptom
   (EPUB) plus a cross-format hypothesis. Filed ONE bug for the confirmed
   EPUB defect; the cross-format risk is recorded inside it (code-read
   confirms shared root cause) rather than fabricating speculative
   per-format rows for formats not yet reproduced. The eventual fix
   addresses the shared contract.
4. **Severity** — High. Systematic correctness defect; any chapter with
   nested block structure misaligns, and a wrong translation under a
   paragraph is misleading (worse than absent). Row notes the explicit
   option to downgrade to Medium if bilingual is treated as niche.
5. **Rule 51** — the fix is a logic/anchoring change to existing wiring
   (no new UI surface) → not design-blocked.
6. **GH mirror** — #1152 (`bug` + `severity:high`) created; stamped in
   Notes (hook `check_gh_issue_mirror.sh` passed on the edit).
7. **Bug ID** — max on the branch base was 265; 266 is next free. No
   collision.
8. **No fix attempted** — classification + root-cause + fix direction only.
9. **Version bump** — 3.39.11 / build 632 (patch — docs / tracker triage).
   `xcodegen generate` + `xcodebuild build` SUCCEEDED on iPhone 17 Pro
   Simulator (Debug).

## Verdict

ship-as-is — documentation only, one bug filing, no code risk. Manual
fallback used because there is nothing to send to Codex.
