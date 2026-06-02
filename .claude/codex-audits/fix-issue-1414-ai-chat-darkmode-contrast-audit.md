---
branch: fix/issue-1414-ai-chat-darkmode-contrast
threadId: codex-exec (RUN-CODEX RESULT SUCCEEDED, see /tmp/fix1414-audit.txt)
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 Codex audit — Bug #310 / #1414 (AI Chat empty-state + placeholder Dark-Mode contrast)

Independent audit (Codex gpt-5.4, high effort, read-only) of the diff routing
the AI Chat empty-state + input placeholder from system `.secondary` to the
designed `ReaderThemeV2.subColor` via a testable `AIChatView.secondaryContentColor(for:)`
seam. One round; author=this session, auditor=Codex (rule-48 separation).

## Findings & resolutions

| # | file:line | severity | issue | resolution |
|---|---|---|---|---|
| 1 | `AIChatView.swift:220` | Medium | The empty `TextField("")` drops the field's only semantic label; the overlay placeholder is `accessibilityHidden`, so VoiceOver would hit an unlabeled field. | **FIXED** — added `.accessibilityLabel(inputPlaceholder)` to the TextField. |
| 2 | `AIChatViewContrastTests.swift:1` | Medium | The new test file was not referenced in `project.pbxproj`, so `-only-testing` ran ZERO tests (false green). | **FIXED** — `xcodegen generate` globbed it into the `vreaderTests` target (4 pbxproj refs); re-ran and verified real execution: "Test run with **2 tests** in 1 suite passed". |
| 3 | `AIChatView.swift:96` | Low | The loading-state "Thinking…" caption still used `.secondary` on the cream sheet — same dark-mode trap. | **FIXED** — routed through `Self.secondaryContentColor(for: theme)`. |

## Verified by the auditor (no change needed)

- No correctness regression in the ZStack placeholder: same font + shared
  padding + `axis:.vertical` + `lineLimit(1...5)` + `allowsHitTesting(false)`
  preserve layout/focus/submit.
- No Rule-51 issue — restore-to-designed token on an existing surface, no new UI.
- No Swift 6 / `@MainActor` issue in the static seam (pure token lookup).
- The only remaining `.secondary` uses are the orange error-banner text/icon
  (out of scope — different background).

## Verdict

`ship-as-is` — all findings fixed (a11y label; test-target membership verified by
real execution; loading-caption routed to the seam). `AIChatViewContrastTests`
(2 tests) + `AIChatMessageRowTests` green.
