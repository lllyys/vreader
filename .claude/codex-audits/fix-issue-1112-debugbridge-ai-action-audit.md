---
branch: fix/issue-1112-debugbridge-ai-action
threadId: 019e487f-a043-7542-9b72-9a6cc9f8a295
rounds: 2
final_verdict: ship-as-is
date: 2026-05-21
---

# Codex audit — Bug #255 / GH #1112: DebugBridge `ai` action command

DEBUG-only verification-harness change adding `vreader-debug://ai?action=<summarize|chat|translate>[&scope=<section|chapter|book>][&text=<...>]`
so the AI-response-card render states (Feature #65 rows 3/6/11, Feature #69
criteria 7-8) become CU-free verifiable. The command fires the SAME view-model
path the production chrome buttons take — no parallel AI call.

## Files audited

- vreader/Services/DebugBridge/DebugCommand.swift (`.aiAction` case + `AIActionKind` + `parseAICommand` helper)
- vreader/Services/DebugBridge/DebugBridge.swift (protocol method + dispatch arm)
- vreader/Services/DebugBridge/DebugBridgeNotifications.swift (`.debugBridgeAIAction`)
- vreader/Services/DebugBridge/RealDebugBridgeContext+AIAction.swift (handler)
- vreader/Views/Reader/DebugAIActionEffect.swift (pure effect mapper)
- vreader/Views/Reader/AIReaderPanel.swift (DEBUG observer modifier; `selectedTab` private→internal)
- vreader/Views/Reader/AIReaderPanel+DebugBridgeAIAction.swift (observer + handler)

## Round 1 findings

| file:line | severity | issue | resolution |
|---|---|---|---|
| AIReaderPanel+DebugBridgeAIAction.swift (`.chat` arm) | **High** | Chat handler bypassed `AIChatView`'s send gate (Send disabled while `isLoading`). `AIChatViewModel.sendMessage` does not coalesce, so two rapid `ai?action=chat` fires could start overlapping requests the chrome button can't trigger — violating "same path / no parallel AI call". | **FIXED** — added `guard !chatViewModel.isLoading else { return }` before the send Task, mirroring `canSend`. Added regression test `chatNoOpWhileLoading` (GatedChatProvider pins `isLoading`; second fire leaves `streamCallCount == 1`). |
| DebugCommand.swift | Low | File is 679 lines, past the ~300-line guideline. | **PARTIAL / accepted** — extracted the `ai` arm into `parseAICommand(_:)` to trim the switch. The file's >300-line size is **pre-existing** (every command family — reset/seed/open/theme/settle/snapshot/eval/tts/search/highlight/provider/present — lives in one unified parser switch; the `ai` arm added ~57 lines, now factored out). A full split into per-command files touches every arm and is a drive-by refactor out of scope for this bug fix. Accepted with rationale per Gate-4 (Low findings may be accepted with rationale). |

## Round 2 verification

Codex re-reviewed the fixes on the same thread:

- Chat `isLoading` guard correctly closes the overlap hazard and preserves the empty-message no-op (`sendMessage` trims/ignores empties) + the single-fire happy path. ✔
- The regression test genuinely exercises the guard: `GatedChatProvider` holds the first stream open, `awaitEntered()` proves the first request started, `isLoading` is asserted true, the second fire leaves `streamCallCount == 1`. ✔
- `parseAICommand(_:)` extraction is behavior-preserving — same action validation, summarize-only `scope` rules, `book → .bookSoFar` mapping, chat `text` requirement intact. ✔
- **No new** concurrency / Sendable / crash / DEBUG-leak issues in the new test stubs (ImmediateChatProvider / GatedChatProvider / ChatGateState / CallCounter) or observer wiring. ✔
- Only remaining finding: the pre-existing 686-line `DebugCommand.swift` (same Low, accepted above).

## Manual confirmation (DEBUG-gating / fidelity)

- **Release-clean**: every new symbol (`AIActionKind`, `.aiAction`, `.debugBridgeAIAction`, `RealDebugBridgeContext+AIAction`, `DebugAIActionEffect`, `AIReaderPanel+DebugBridgeAIAction`) is inside `#if DEBUG` whole-file gates. In `AIReaderPanel.swift` (a Release file), the `selectedTab` access change introduces no DEBUG symbol, and `debugAIActionObserver` returns `EmptyModifier()` in Release (`#else`), so `ReaderDebugBridgeAIActionObserver` is never referenced in Release. Matches the `scripts/verify-release-no-debugbridge.sh` posture.
- **Fidelity (no parallel AI call)**: the observer invokes `viewModel.summarize(...)` with the same args + in-flight guard as `AISummaryTabView.runSummarize`, `chatViewModel.sendMessage(...)` with the `isLoading` gate as `AIChatView.sendCurrentMessage`, and `translationViewModel.translate(...)` as `TranslationPanel.requestTranslation`. The observer lives on `AIReaderPanel` (which holds locator / fullText / chapterBounds / format / targetLanguage), so it's a no-op when no AI sheet is mounted — the same posture as the Bug #253 `present` command.

## Verdict

**ship-as-is.** Zero open Critical/High/Medium. One pre-existing Low (file size) accepted with rationale.
