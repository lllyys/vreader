---
branch: feat/138-wi5a-source-offset-jump
threadId: 019f6434-b3bb-7e71-9ffe-8924f8d8ad7f
rounds: 1
final_verdict: ship-as-is
---

# Gate-4 Codex audit — feature #138 WI-5a (TXT paged external-jump seam → SOURCE OFFSET)

Model: gpt-5.5, effort high. Diff audited: `origin/main..HEAD` over
`TxtReaderActivity.kt` + `TxtReaderBody.kt`. Full transcript:
`.reports/feat138-wi5a-audit.txt`.

## Scope reviewed

Behavior-preserving retype of the Android TXT paged reader's external jump seam
from a pre-computed PAGE to a raw SOURCE OFFSET, on the whole-doc (complete)
WI-4 index (synchronous resolution; no session/async — that is WI-5b).

## Verdict — round 1: ship-as-is (no Critical/High/Medium findings)

Codex confirmed:

- Bookmark / annotation / search / scrubber all route through `jumpToOffset(target)`;
  the paged branch stores a clamped SOURCE offset in `pagedJumpToSourceOffset`.
- `TxtPagedBody` consumes `jumpToSourceOffset`, calls the SYNCHRONOUS
  `navigator.jumpToOffset(offset)`, then scrolls to the pending target — still
  `pageContaining(offset)`. Jumps land exactly as today.
- TTS-follow uses `pagedTtsFollowTarget(...)` only as the no-yank GUARD, then
  raises `tts.charStart` / `spokenOffset` (the SOURCE offset), NOT a precomputed page.
- No remaining `pagedJumpRequest` / `jumpRequest` page-typed seam in the TXT paged path.
- Out-of-range behavior preserved: bookmark/search reject invalid offsets;
  scrubber/test seam clamp to `length - 1`; annotation clamps through the same
  offset seam; TTS relies on `pageContaining` clamping.
- `JumpResult.Succeeded` reworded to enqueued-not-landed at the TXT bookmark/search host sites.

## Findings

- **Low (fixed):** a body comment said the source→page conversion "moved OFF the
  host UI thread"; `LaunchedEffect` still runs on main by default, so the phrase
  was technically misleading. Reworded to "moved OUT of the host chrome callback
  into this body effect (both still run on main — the point is the seam no longer
  eagerly resolves the page)."

No other findings. Codex did not run Android tests (read-only sandbox); the lane
ran them separately — JVM `com.vreader.app.reader.paged.*` SUCCEEDED and the
connected `TxtPagedSourceOffsetJumpConnectedTest` (3/3), `TxtPagedBookmarkConnectedTest`
(3/3), `TxtPagedTtsFindConnectedTest` (4/4) all SUCCEEDED on emulator-5554.
