---
branch: feat/feature-115-wi2-pdf-reader
threadId: 019ee3fb-07aa-7d90-89f5-ed883e67ec0e
rounds: 2
final_verdict: ship-as-is
date: 2026-06-20
---

# Gate-4 implementation audit — feature #115 WI-2 (PdfReaderActivity)

Codex (`scripts/run-codex.sh`, gpt-5.5, read-only) audited the PDF reader Activity:
`PdfReaderActivity.kt`, the `MainActivity` `pdf` route, the manifest entry, `PdfReaderActivityTest.kt`.

## Decision confirmed: drop synchronous `Bitmap.recycle()` (rely on GC)

Manual recycle at the composable boundary raced Compose's draw at teardown/recompose ("trying
to use a recycled bitmap"). The auditor **confirmed dropping it is sound for v1**: lazy
per-visible render + a 360dp width cap bounds memory; Compose owns the displayed bitmap's
lifetime. Noted limitation: large/complex PDFs may have transient bitmap pressure during rapid
scroll (no manual recycle re-added).

## Round 1 — 2 Medium + 2 Low (all fixed)

| severity | issue | resolution |
|---|---|---|
| Medium | the render test asserted `onAllNodesWithText("Page 1")` — matched the pill, not the page Image | **Fixed**: `onNodeWithContentDescription("Page 1")` (the rendered bitmap). |
| Medium | `DisposableEffect.onDispose` closed the doc via `runBlocking` on main → ANR risk behind an in-flight render | **Fixed**: `container.appScope.launch { doc.close() }`; the doc's `Mutex` stays the serialization boundary. |
| Low | back affordance was a ~20dp icon-only tap target | **Fixed**: one ≥48dp clickable Row (icon + "Library") with `onClickLabel`. |
| Low | stale "caller must recycle" comments | **Fixed**: `PdfDocument` KDoc + `PdfPage` comment updated. |

## Round 2 — Medium/High clean; one residual Low fixed

Round 2 found **no new Critical/High/Medium**; one residual Low (the file-header still said
"recycles on disposal") — **fixed** (header updated to "off-screen bitmaps left for GC").

## Verdict

**ship-as-is** (zero open Critical/High/Medium). 2 instrumented `PdfReaderActivityTest` green on
emulator-5554 (opens a synthetic 3-page PDF → chrome + "Page 1 of 3" pill + a rendered page
Image; corrupt → "Couldn't open this PDF") + the full `:app` unit suite green. State machine
(Loading/Protected/Corrupt/Empty/Loaded) + routing complete. Behavioral WI — emulator-verified.
Resume (save/restore page) is WI-3.
