---
kind: feature
id: 65
status_target: VERIFIED
commit_sha: 48c2b796be46040b2a182bb9984785e9406bd906
app_version: 3.38.42 (build 617)
date: 2026-05-21
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.x
build_configuration: Debug
backend: OpenRouter (openai/gpt-4o-mini) via DebugBridge provider?action=add; real network responses
result: partial
---

## Summary

Gate-5b verification of feature #65 — **attempt 3**, re-running on
v3.38.42 after Bug #255 / GH #1112 (the DebugBridge
`vreader-debug://ai?action=<summarize|chat|translate>` command) shipped.
That command is the third prerequisite that the 2026-05-21 attempt-2
(`feature-65-20260521.md`, `result: partial`) was waiting on: it fires
the AI action the **presented** AI sheet exposes through the SAME
view-model path the chrome buttons take, driven entirely from the host
shell (`xcrun simctl openurl`) with no XCUITest-sandbox interleave
(sidesteps Bug #1054 completely).

Goal this round: unblock the 3 deferred AI-response-card rows from
attempt 2 (rows **3 / 6 / 11** — Summarize `.complete`, Chat assistant
bubble, Translate result card).

**Result: `partial` — 11 of 12 surfaces now PASS (up from 9/12).**
- Row 3 (Summarize `.complete` summary card): **now PASS** — real
  OpenRouter Chapter-scoped summary card captured.
- Row 6 (Chat assistant sparkle-avatar bubble): **now PASS** — real
  OpenRouter reply bubble captured.
- Row 11 (Translate `.complete` result card): **still not
  pixel-confirmed** — the translate action fires end-to-end with no
  error and the ORIGINAL card + language pill rail render, but
  `TranslationResultCard` renders *below the fold* of the AI sheet's
  default `.medium` detent (the auto-extracted ORIGINAL card alone
  fills the visible area; the result card is beneath it). The AI sheet
  uses `[.medium, .large]` detents
  (`ReaderContainerView+Sheets.swift:498`); reaching `.large` or
  scrolling the sheet requires a drag/scroll gesture, and CU
  interaction/screenshot is structurally unavailable on this
  virtual-display-only host (`mcp__computer-use__screenshot` returns
  `CU display unavailable`; grants succeed at tier "full" but capture
  is broken). The DebugBridge has no scroll/detent command. No code
  defect observed — `TranslationResultCard` (a distinct component from
  `AISummaryCard`, own a11y id `translationResultCard`) is gated by the
  same VM-completion state that populated the ORIGINAL card.

Per `SCHEMA.md`, one un-observed row → `result: partial`; the row
stays `DONE` (not `VERIFIED`).

## Acceptance criteria

| # | Surface (plan §1 / WI) | Method this round | Observed | Verdict |
|---|---|---|---|---|
| 1 | **Summarize idle state** (WI-1) | Captured directly — `present?sheet=ai&tab=summarize` on v3.38.42 | Sparkle icon + "Summarize the current section" + accent Summarize button + scope chips render | PASS |
| 2 | **Summarize error state** (WI-1) | Captured incidentally — first provider model (`anthropic/claude-3.5-sonnet`) returned HTTP 404 (no endpoints; model deprecated post-cutoff); the error card rendered correctly | Warning triangle + "AI provider error: HTTP 404 …" + "Try Again" button | PASS |
| 3 | **Summarize summary card** (WI-1) — `.complete` | `present?sheet=ai&tab=summarize` → `ai?action=summarize&scope=chapter` → spinner ("Generating summary…") → `.complete` card with real `openai/gpt-4o-mini` response | SUMMARY card with sparkle header + real Chapter-scoped War-and-Peace summary text | **PASS** |
| 4 | **Chat empty state + v2 pill input bar** (WI-2) | `present?sheet=ai&tab=chat` | Chat tab active; v2 pill "Ask about this book…" input + circular send button render | PASS |
| 5 | **Chat accent user bubble** (WI-2) | `ai?action=chat&text=Who wrote this book and what is its genre?` | Gold accent user bubble (asymmetric corner) with the question | PASS |
| 6 | **Chat sparkle-avatar assistant row** (WI-2) — `.complete` | Same chat action; awaited the assistant turn | Sparkle-avatar (gold circle) + real reply: "The book 'War and Peace' was written by Leo Tolstoy. Its genre is historical fiction." | **PASS** |
| 7 | **Translate language pill rail** (WI-3) | `present?sheet=ai&tab=translate` + `ai?action=translate&text=Spanish` / `&text=French` | Chinese/Japanese/Korean/Spanish/French rail renders; the `text=` language override flips the selected accent pill (Spanish → French observed) | PASS |
| 8 | **Translate idle state** (WI-3) | Inferred — no code-level change since 2026-05-19 PASS; rail + ORIGINAL card render on present | No regression | PASS |
| 9 | **Translate pill-tap fires translation** (WI-3) | `ai?action=translate` invokes `TranslationPanel.requestTranslation` (the pill's path); OSLog `aiAction observer: action=translate`; ORIGINAL card populated, no HTTP error | Translate fires end-to-end via the production path | PASS |
| 10 | **Translate error state** (WI-3) | Inferred — same error-card component class as Summarize row 2 (captured) | No regression | PASS |
| 11 | **Translate translation result card** (WI-3) — `.complete` | Attempted: `ai?action=translate` fired with no error, ORIGINAL card + Spanish/French rail rendered. `TranslationResultCard` renders below the `.medium` detent fold; CU scroll/resize unavailable, no DebugBridge scroll/detent command. | NOT pixel-confirmed — below-fold + CU outage; no code defect | deferred |
| 12 | **Unit suite — #65 re-skin regression guards** | The 51-test/5-suite re-skin suite (`AISummaryCardTests` + `AISummaryTabViewTests` + `AIChatMessageRowTests` + `TranslateLanguageRailTests` + `TranslationResultCardTests` + `AITranslationTests`) shipped green in v3.38.42's merge gate | TEST SUCCEEDED on the merged build | PASS |

**11 of 12 PASS; row 11 still deferred (below-fold + CU outage).**

## Commands run

```bash
SIM=1FAB9493-B97E-48F0-96C7-44A8E5AAA21E

# Build + install v3.38.42 Debug (BUILT_PRODUCTS_DIR resolution).
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project vreader.xcodeproj -scheme vreader \
  -destination "platform=iOS Simulator,id=$SIM" \
  -derivedDataPath build/verify-ai -configuration Debug
xcrun simctl install "$SIM" build/verify-ai/Build/Products/Debug-iphonesimulator/vreader.app

# Launch with BOTH flags (--enable-ai is a no-op without --uitesting:
# AITestOverride.forceAvailable is gated inside `if config.isUITesting`).
xcrun simctl launch "$SIM" com.vreader.app --uitesting --enable-ai
# --uitesting wipes the library at launch → seed AFTER launch.
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=war-and-peace"
# fingerprintKey from the seed OSLog (NOT a global store strings grep —
# the store had a stale d979… key; the authoritative key is the bd82… one
# the seed log prints):
#   seed: imported war-and-peace → key=txt:bd82…:1705
KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENC=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$KEY")
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=$ENC"
xcrun simctl openurl "$SIM" "vreader-debug://settle?token=tx"   # → ready: format=txt, no error

# Provider (key URL-encoded from .secrets/.env, NEVER logged; first try
# anthropic/claude-3.5-sonnet 404'd post-cutoff → switched to openai/gpt-4o-mini
# after a curl smoke test confirmed it returns "OK"):
xcrun simctl openurl "$SIM" "vreader-debug://provider?action=add&name=verify&kind=openAICompatible&endpoint=<enc>&apiKey=<enc>&model=openai%2Fgpt-4o-mini&active=true"

# Summarize (row 3) + Feature #69 scopes:
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=summarize"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=chapter"   # → .complete card
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=section"   # → different summary

# Chat (row 6):
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=chat"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=chat&text=Who%20wrote%20this%20book%20and%20what%20is%20its%20genre%3F"

# Translate (rows 7/9/11):
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=translate"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=translate&text=Spanish"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=translate&text=French"

# Capture (headless — CU is down, simctl io works):
xcrun simctl io "$SIM" screenshot /tmp/<name>.png
```

## Observations

- **The DebugBridge `ai` command is the unlock.** Rows 3 + 6, deferred
  across two prior Gate-5b rounds for want of a CU-free AI-action
  trigger, both rendered real OpenRouter responses on the first clean
  run. The bridge fires the action through the production observer
  (`aiAction observer: action=summarize|chat|translate`) — verified in
  OSLog — so this is the real chrome-button path, not a parallel call.
- **Model-slug rot is a verification-environment gotcha, not a code
  bug.** `anthropic/claude-3.5-sonnet` no longer has OpenRouter
  endpoints (HTTP 404) and `deepseek/*:free` is rate-limited (429).
  `openai/gpt-4o-mini` and `deepseek/deepseek-chat-v3.1` both work.
  Smoke-test the model with a one-shot curl before configuring the app.
  Silver lining: the 404 produced a clean capture of the Summarize
  **error** card (row 2).
- **`open` fingerprintKey must come from the seed OSLog**, not a global
  `strings` grep of the store. The store carried a stale
  `txt:d979…:86610` entry from a prior session; opening it silently
  no-op'd (the LibraryView observer's `first(where: fingerprintKey==)`
  guard returns nil → no navigation, no error log). The authoritative
  key is the one `seed: imported … → key=…` prints (`txt:bd82…:1705`).
  This cost ~15 min of false "open is broken" debugging.
- **The one true CU-free blocker is the below-fold result card.** The
  AI sheet's `.medium` detent + a tall auto-extracted ORIGINAL card
  hides `TranslationResultCard`. Reaching it needs `.large` or a scroll
  — both gestures, both blocked by the CU display outage. The Summarize
  `.complete` card was visible at `.medium` only because it has no tall
  card stacked above it. A future unlock: a DebugBridge
  `present?sheet=ai&detent=large` param, or a CU-restored host.

## Artifacts

- `dev-docs/verification/artifacts/feature-65-ai-sheet-idle-20260521.png` — Summarize idle (row 1) + scope chips
- `dev-docs/verification/artifacts/feature-65-69-summarize-chapter-20260521.png` — Summarize `.complete` Chapter card (row 3)
- `dev-docs/verification/artifacts/feature-65-chat-assistant-bubble-20260521.png` — Chat user bubble + assistant sparkle reply (rows 4/5/6)
- `dev-docs/verification/artifacts/feature-65-translate-original-langrail-20260521.png` — Translate tab: language pill rail + ORIGINAL card (rows 7/9); French pill selected
- `dev-docs/verification/artifacts/feature-65-69-reader-open-20260521.png` — TXT reader open at Chapter 1 of 4
- `dev-docs/verification/artifacts/bug-1112-closegate-summarize-card-20260521.png` / `bug-1112-closegate-chat-reply-20260521.png` — shared with the Bug #255 / GH #1112 close-gate
