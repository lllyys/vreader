---
branch: feat/135-wi7-host-wiring
threadId: 019f520f-7e7d-7863-95dc-eefcb5442f29
rounds: 2
final_verdict: ship-as-is
date: 2026-07-11
---

# Feature #135 WI-7 — bookmark host wiring (Gate-4 audit)

Independent Codex audit (rule 53, `scripts/run-codex.sh`) of the per-host bookmark
wiring diff (the integrator that lights up create/toggle/list/jump on all 5 reader
hosts). Author = the WI-7 implementer session; auditor = an independent Codex
process (rule 48 author/auditor separation).

## Scope audited

`git diff origin/main..HEAD` — the 5 host files (ReaderActivity EPUB,
Azw3ReaderActivity, TxtReaderActivity, PdfReaderScreen/PdfReaderActivity) + the new
JVM host-helper suite (BookmarkHostWiringTest) + the per-host instrumented slices
(EpubBookmarkNavTest, TxtPdfBookmarkTest). Audit prompts asked for: per-host jump
correctness (EPUB toReadium→navigator.go; AZW3 goTo + render-death carry-across;
TXT scroll; PDF page; all out-of-range → Failed), toggle/presence keyed by the
canonical locator (profileKeyFor equality) + refresh after toggle, the
observeBookmarks→BookmarkPresentation list build with a BookmarkTocIndex built once
per host + TXT's preview provider, coroutine/lifecycle leaks, rule-51 (no invented
error UI on Failed), and no modification of the merged WI-1..WI-6 files.

## Round 1 — block-recommended (1 High)

**High — TXT at/past-EOF offsets incorrectly succeed.** `txtBookmarkScrollTarget`
clamped every `offset >= textLength` to `textLength - 1` and returned `Succeeded`,
so a corrupt / cross-file-restored bookmark would dismiss the sheet — contradicting
its own doc ("at/past EOF is out of range") and the plan's out-of-range → Failed
posture (and diverging from the PDF-page analog `pdfBookmarkPageTarget`, which
rejects `page >= pageCount`).

**Fix applied:** `txtBookmarkScrollTarget` now returns `null` when
`offset >= textLength` (→ `JumpResult.Failed`, the sheet stays open — rule 51). The
test codifies `offset == length` and `offset > length` both → `null`. All other
reviewed wiring was confirmed to match the requested architecture.

## Round 2 — ship-as-is (clean)

No remaining Critical/High/Medium findings. The auditor confirmed the R1 High is
"correctly and completely fixed" and re-scanned the whole diff:

- EPUB reconstructs canonical locators through `toReadium`, calls `navigator.go`,
  and fails without dismissing when reconstruction or navigation fails.
- AZW3 validates target-validity synchronously before dismissing, launches the
  awaited `goTo` in a composition-scoped coroutine, and carries the pending target
  across render-process recreation (`takePendingGoTo` → `run(pendingGoTo=)`).
- TXT and PDF validate bounds before launching composition-scoped scrolls.
- Bookmark collectors are lifecycle- or composition-scoped (no leak).
- `Failed` produces no invented error UI; the sheet simply stays open.
- No WI-1..WI-6-owned file was modified; the diff contains only host files + the
  new WI-7 tests.

## Test gate

`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `:app:compileDebugKotlin`
`:app:compileDebugAndroidTestKotlin` `:app:testDebugUnitTest` (both source sets
compile; the JVM host-helper suite BookmarkHostWiringTest = 14/0). Per-host
instrumented slices compile; live connected runs ride WI-9 acceptance (the
#132/#134 precedent).

## Verdict

**ship-as-is** (2 rounds).
