---
branch: feat/feature-115-wi3-pdf-resume
threadId: 019ee406-64fe-7423-97f1-3456339c0758
rounds: 1
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #115 WI-3 (PDF resume by page index)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the resume slice (the final WI):
`PdfReaderActivity.kt` (the save channel + `computeInitialPage` + the snapshotFlow save),
`PdfResumeTest.kt` (Robolectric), `PdfReaderActivityTest.kt` (instrumented).

## Round 1 — NO correctness findings; 1 Low (fixed)

> "No implementation correctness findings. The cache-first read mirrors TXT, the clamp is valid
> for the non-empty loaded path, the conflated channel plus single consumer preserves
> serialized latest-wins saves, `drop(1)` avoids initial overwrite, and the PDF document close
> path does not share state with the save consumer."

| file:line | severity | issue | resolution |
|---|---|---|---|
| `PdfReaderActivityTest.kt` resume | Low | the resume test primed `cachePage` → proved the cache fast-path but not the durable Room fallback | **Fixed**: added `resumesFromDurableRoom_withoutCachePrime` — a distinct fixture (`sample-resume-room.pdf`), saves `Locator(page=5)` with NO cache prime, asserts "Page 6" (exercises `loadPosition → ResumeResolver → Canonical → page`). |

## Verdict

**ship-as-is** (zero Critical/High/Medium — none even at round 1). The resume mirrors the proven
TXT pattern with `page` for `charOffsetUTF16`. 1 Robolectric `PdfResumeTest` + **4** instrumented
`PdfReaderActivityTest` (render, cache-resume to page 6, durable-Room-resume to page 6, corrupt)
green on emulator-5554 + the full `:app` unit suite green. Final WI — completes feature #115.

Test-isolation note: same-content PDFs share the fingerprintKey + the process-singleton
`cachePage` + the Room position, so each resume test uses a DISTINCT fixture; the resume
fixtures are 8 pages so the content exceeds the viewport (a short doc clamps the initial scroll
index to 0).
