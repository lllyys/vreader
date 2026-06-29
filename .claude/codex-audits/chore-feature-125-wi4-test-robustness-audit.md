---
branch: chore/feature-125-wi4-test-robustness
threadId: 019f1282-1276-7bf3-8966-43364fee0d98
rounds: 1
final_verdict: ship-as-is
date: 2026-06-29
---

# Gate-4 audit — feature #125 WI-4 test robustness (follow-up)

The WI-4 acceptance PR (#1867) merged the `MdReaderHighlightUiTest` but the Gate-4
audit log + the two test-robustness fixes were committed locally and not pushed
before the squash-merge, so they did not land on `main`. This follow-up restores
them.

Independent Codex audit (gpt-5.5, high reasoning, read-only sandbox, thread
`019f1282`) of `MdReaderHighlightUiTest` found no Critical/High; 1 Medium + 1 Low,
both applied here:

| file | severity | issue | resolution |
|---|---|---|---|
| `MdReaderHighlightUiTest.kt` (`mdSeededHighlight…`) | Medium | The wash test only asserted the line text is displayed — it would pass even if washes were disabled / the wash map were empty. | **Fixed.** Now computes `TxtWashMapper.washesByChunk(doc, highlights, MarkdownChunkTextMapper(doc))` for the seeded highlight and asserts a non-empty rendered wash span before the live render. (The exact span `[0,4)` is additionally pinned by `MdHighlightConnectedTest`.) |
| `MdReaderHighlightUiTest.kt` (`styledLineSourceRange`) | Low | Offsets were computed from the hardcoded `mdContent` while the test imports `sample-note.md`; fixture drift could seed the wrong source range. | **Fixed.** Reads the imported asset content + a `check(content == mdContent)` drift guard. |

No production code changes; test-only. `:app:compileDebugAndroidTestKotlin` is clean.

## Verdict

ship-as-is. Restores the WI-4 audit artifact + the two test-robustness fixes onto
`main` (feature #125 is already VERIFIED at `android/v0.13.0`).
