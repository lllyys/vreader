---
branch: feat/feature-57-wi-3-readd-tts-capability
threadId: 019e3e9e-9c29-7de1-9734-98b99cff4c3a
rounds: 2
final_verdict: ship-as-is
date: 2026-05-19
---

# Codex Audit — feature #57 WI-3 (re-add the `.tts` capability for AZW3/MOBI)

Gate-4 implementation audit of the WI-3 diff (vs `origin/main`).

## Scope

WI-3 reverses the bug #176 / GH #602 cap-gate: `.tts` re-added to `FormatCapabilities.capabilities(for: .azw3)` now that feature #57's production TTS path (WI-1 extraction seam + WI-2 `startTTS()` branch) is merged. This makes the `ReaderMorePopover` "Read aloud" row visible for AZW3/MOBI again.

Files changed (final):
- `vreader/Models/FormatCapabilities.swift` — `.tts` in `case .azw3`; doc comment rewritten
- `vreaderTests/Models/FormatCapabilitiesTests.swift` — `azw3_doesNotSupportTTS()` → `azw3_supportsTTS()`
- `vreaderTests/Models/BookFormatAZW3Tests.swift` — 2 stale tests flipped to the post-#57 contract (audit Finding 1)
- `vreaderTests/Views/Reader/ReaderMorePopoverTTSGateTests.swift` — 4 stale tests updated + 1 added (audit Finding 2)
- `vreader/Views/Reader/ReaderMoreMenuRow.swift` — stale doc comment rewritten (audit Finding 3)
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` — stale comment rewritten (audit Finding 4)
- `vreader/Views/Reader/ReaderMorePopover.swift` — stale comment rewritten (audit round-2 Low residual)

## Round 1 — findings

| file:line | severity | issue | fix |
|---|---|---|---|
| BookFormatAZW3Tests.swift:102 / :155 | Medium | Two tests still hard-coded the pre-#57 contract (`#expect(!caps.contains(.tts))` and an "EPUB-parity except `.tts`" test) — they would fail after WI-3 and contradict the new capability behavior. **The plan §3.1's claim "no other test asserts azw3-lacks-tts" was wrong.** | Flip both: assert `.azw3.capabilities.contains(.tts)`; change the parity test to assert AZW3 == simple-EPUB directly. |
| ReaderMorePopoverTTSGateTests.swift:29 / :129 | Medium | The More-popover regression tests still expected AZW3 to *hide* `Read aloud` (`readAloud_absent_whenFormatLacksTTS`, `popover_resolvedRows_dropReadAloud_forFormatWithoutTTS`). After WI-3 production shows that row for AZW3 — these tests preserved the old bug-176 gate. | Move AZW3 to the positive path; keep PDF (still genuinely lacks `.tts`) on the negative path; add an AZW3 positive popover-wiring test. |
| ReaderMoreMenuRow.swift:80 | Low | `visibleRows(for:)` doc still said `FormatCapabilities.capabilities(for: .azw3)` excludes `.tts`. | Rewrite as a generic per-`.tts` gate; note AZW3 regained `.tts` in #57. |
| ReaderContainerView+Sheets.swift:291 | Low | `readerMorePopoverOverlay` comment still said "AZW3 / MOBI exclude `.tts`". | Rewrite to a generic per-capability gate description. |

The WI-3 changed files themselves (`FormatCapabilities.swift` + `FormatCapabilitiesTests.swift`) were correct; no production branch special-cases `.azw3` + `.tts` to keep TTS off.

## Resolutions

All 4 findings fixed (see Scope file list). The 2 Medium were real test breakage WI-3 introduced — both stale-test files updated to the post-#57 contract; PDF is now the canonical no-`.tts` format in the negative-path tests, AZW3 added to the positive paths. The 2 Low stale comments rewritten.

## Round 2 — verification

Re-reviewed the full diff. Verdict: **no remaining Critical/High/Medium.** All 4 prior findings resolved; no remaining test assertion pins "AZW3 lacks `.tts`". One Low residual found — a stale comment in `ReaderMorePopover.swift:100` ("AZW3/MOBI lack `.tts`", logic correct) — **fixed** in the same WI-3 commit (rewritten to a generic no-TTS-path description).

## Verdict

**ship-as-is.** Zero open Critical/High/Medium after 2 rounds; the round-2 Low residual fixed. Build succeeds; all 60 tests across `FormatCapabilitiesTests` + `BookFormatAZW3Tests` + `ReaderMorePopoverTTSGateTests` pass.
