---
kind: feature
id: 65
status_target: VERIFIED
commit_sha: 6ae94729d1485ea531490033724f86556a374204
app_version: 3.38.41 (build 616)
date: 2026-05-21
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.5
build_configuration: Debug
backend: OpenRouter (openai/gpt-4o-mini) via DebugBridge provider command
result: partial
---

# Feature #65 — AI sheet tab-body re-skin (Gate-5b, round 3)

Third Gate-5b attempt, now using the **`vreader-debug://present` command**
(Bug #253, shipped v3.38.41) to drive the AI sheet host-side — the unblock
that lets the AI-sheet rendered content be observed CU-free. This round
**upgrades the Summarize-tab-body evidence from unit-inferred to
host-driven-visible**, but the AI-response-card states (rows 3 / 6 / 11)
remain DEFERRED behind a newly-isolated harness gap (Bug #255 / GH #1112).

## Acceptance criteria

| # | Surface (plan §1 / WI) | Method this round | Observed | Verdict |
|---|---|---|---|---|
| 1 | **Summarize idle state** (WI-1) | **Host-driven visible** — `present?sheet=ai&tab=summarize` after `--uitesting --enable-ai` + host-configured provider; `simctl io screenshot`. | AI sheet presents; Summarize idle renders v2: sparkle glyph + "Summarize the current section" serif headline + accent "Summarize" pill button + v2 header (sparkle avatar, "AI Assistant"/"with this book's context", `verify-openrouter` provider picker, close X). Matches design `vreader-panels.jsx` SummaryView. | PASS |
| 2 | **Summarize error state** (WI-1) | Unit-pinned (`AISummaryTabViewTests`) — no code change since 2026-05-19 PASS | No regression on v3.38.41 | PASS |
| 3 | **Summarize summary card** (WI-1) — `.complete` state | Attempted: present AI sheet host-side (works), but no `vreader-debug://` command triggers the Summarize action; the idle state needs a manual `aiSummarizeButton` tap, and CU (down) / XCUITest (Bug #1054, can't pair host provider) can't tap it. | NOT reached — no host-side AI-action trigger. Filed **Bug #255 / GH #1112**. | DEFERRED |
| 4 | **Chat empty state + v2 pill input bar** (WI-2) | XCUITest (`Bug93GeneralChatPersistenceVerificationTests`, same `AIChatView` component) — PASS on v3.38.29; no code change since | Chat input + send button render via v2 pill design | PASS |
| 5 | **Chat accent user bubble** (WI-2) | XCUITest (`chatBubble-user` AX id) — PASS; no code change since | User bubble renders | PASS |
| 6 | **Chat sparkle-avatar assistant row** (WI-2) | Attempted — requires a successful AI response (chat send). Same trigger gap as row 3. | NOT reached — Bug #255 / GH #1112 | DEFERRED |
| 7 | **Translate language pill rail** (WI-3) | Unit-pinned (`TranslateLanguageRailTests`); no code change since 2026-05-19 PASS | No regression | PASS |
| 8 | **Translate idle state** (WI-3) | Unit-pinned; no code change | No regression | PASS |
| 9 | **Translate pill-tap fires translation** (WI-3) | Unit-pinned (`AITranslationTests`); no code change | No regression | PASS |
| 10 | **Translate error state** (WI-3) | Unit-pinned; no code change | No regression | PASS |
| 11 | **Translate translation result card** (WI-3) — `.complete` state | Attempted — requires a successful translate action. Same trigger gap as row 3. | NOT reached — Bug #255 / GH #1112 | DEFERRED |
| 12 | **Unit suite — #65 re-skin regression guards** | `xcodebuild test` (`AISummaryCardTests` + `AISummaryTabViewTests` + `AIChatMessageRowTests` + `TranslateLanguageRailTests` + `TranslationResultCardTests` + `AITranslationTests`, 51 tests) — PASS, no change since | TEST SUCCEEDED | PASS |

**9 of 12 PASS; rows 3 / 6 / 11 DEFERRED** (the three AI-response-card
states). Per `SCHEMA.md`, any deferred row makes `result: partial`. Row stays
`DONE` (not `VERIFIED`).

### Net change vs the 2026-05-21 (round 2) evidence
- Rows 1 (and the scope-chip rendering) are now **host-driven visible** in the
  real presented sheet — the prior round could only infer them from unit tests
  / no-code-change. The present command (Bug #253) is what enabled this.
- Rows 3 / 6 / 11 — the blocker was previously stated as "the hybrid
  host-driver / XCUITest harness gap." This round **isolates the precise
  missing piece**: present opens the sheet but there is no AI-**action**
  trigger command. Filed as Bug #255 / GH #1112 with a concrete fix direction
  (`vreader-debug://ai?action=summarize|chat|translate`).

## Commands run

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E
APP=build/verify-sheets/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl install "$SIM" "$APP"     # v3.38.41 build 616

# Configure a real OpenRouter provider (key sourced from .secrets/.env,
# NEVER logged; openai/gpt-4o-mini confirmed HTTP 200 via a curl smoke test).
set -a; source /Users/ll/workspace/vreader/.secrets/.env; set +a
EP=$(printf '%s' "https://openrouter.ai/api/v1" | jq -sRr @uri)
K=$(printf '%s' "$OPENROUTER_API_KEY" | jq -sRr @uri)
M=$(printf '%s' "openai/gpt-4o-mini" | jq -sRr @uri)

# --uitesting is REQUIRED to trip the DEBUG block that consumes --enable-ai
# (AITestOverride.forceAvailable lives inside `if config.isUITesting {` in
# VReaderApp). --uitesting wipes the library at launch, so re-seed + re-add
# provider AFTER launch.
xcrun simctl launch "$SIM" com.vreader.app --uitesting --enable-ai
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=mini-epub3"
xcrun simctl openurl "$SIM" "vreader-debug://provider?action=add&name=verify-openrouter&kind=openAICompatible&endpoint=${EP}&apiKey=${K}&model=${M}&active=true"
KEY="epub:f284fd074ccd1d3c1a78985464d9e1be27975f4029f3c2ddef8428ca10684af4:2198"
ENC=$(printf '%s' "$KEY" | jq -sRr @uri)
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=${ENC}"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=ai5"

# Present the AI sheet — Summarize tab renders v2 (header + chips + idle).
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=summarize"
xcrun simctl io "$SIM" screenshot feature-65-05-ai-summarize-final-20260521.png
```

## Observations

- **The `--enable-ai` consumption is gated behind `--uitesting`.** In
  `VReaderApp`, `AITestOverride.forceAvailable = config.enableAI` is inside the
  `#if DEBUG / if config.isUITesting {` block. `simctl launch --enable-ai`
  alone (without `--uitesting`) sets `enableAI=true` but never runs the block,
  so the AI gate stayed closed and the present was a silent no-op. Adding
  `--uitesting` fixed it — at the cost of `--uitesting` wiping the library at
  launch (re-seed via DebugBridge after launch). Confirmed `--force-light`
  applied to prove args reach the process, ruling out an arg-passing issue.
- **The provider is configured host-side and the gate passes** — but the AI
  sheet's idle state still needs a button tap to produce a response, and no
  host-side trigger exists. This is the precise, narrowed gap (Bug #255).
- The AI sheet's v2 re-skin (header + Summarize idle + scope chips) is visibly
  correct against the design — no code defect observed in any reached state.
- DebugBridge OSLog (`category == "DebugBridge"`) did not surface in
  `simctl spawn log show/stream` on this sim (level filtering); screenshots
  were the reliable assertion channel.

## Artifacts

- `dev-docs/verification/artifacts/feature-65-05-ai-summarize-final-20260521.png` — AI sheet presented, Summarize tab v2 (header + provider picker + Section/Chapter/Book-so-far chips + idle state + accent Summarize button).
- `dev-docs/verification/artifacts/feature-65-04-ai-summarize-uitesting-20260521.png` — the `--uitesting` empty-library state (diagnostic, pre-reseed).
- `dev-docs/verification/artifacts/probe-force-light-20260521.png` — proves launch args reach the process (`--force-light` applied).
