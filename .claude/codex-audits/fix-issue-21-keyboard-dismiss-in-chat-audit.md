---
branch: fix/issue-21-keyboard-dismiss-in-chat
threadId: 019df774-ec3d-7493-9409-e47f182e49ef
rounds: 2
final_verdict: ship-as-is
date: 2026-05-05
---

# Codex audit log — Bug #94 fix (GH #21)

## Round 1 — initial findings

| File | Line | Severity | Issue | Resolution |
|------|------|----------|-------|------------|
| `vreader/Views/AI/AIChatView.swift` | 25 | Medium | The original bug body explicitly called out "tapping outside the input field" as one of the broken dismissal paths. The first patch only added `.scrollDismissesKeyboard(.interactively)` plus a keyboard-toolbar Done button. Tap-outside was still unhandled. | Fixed: added `.contentShape(Rectangle()).onTapGesture { isInputFocused = false }` on the messageList ScrollViewReader. `contentShape` makes empty space hit-testable; `onTapGesture` only fires for quick taps so long-press text selection inside `Text(...).textSelection(.enabled)` bubbles still works. |

## Round 2 — verification re-pass

Codex confirmed clean:
> The new `onTapGesture` closes the remaining gap without obviously breaking the other interaction paths. `scrollDismissesKeyboard(.interactively)` is at the correct attachment point. The tap-to-dismiss handler is scoped to messageList, not the outer VStack, so it should not interfere with tapping the input bar to focus the TextField. The keyboard-toolbar Done button remains the fallback for empty/short lists and is still VoiceOver-friendly.

> On gesture coexistence: a plain `onTapGesture` on the ancestor matches quick taps, while text selection in `Text(...).textSelection(.enabled)` is driven by a longer press / selection interaction, so it's not preempted by this tap recognizer.

## Visual verification (computer-use, post-audit)

Performed on iPhone 17 Pro Simulator (iOS 26.4) against working-tree v3.13.15+:

1. Configured: AI feature flag ON, API key set ("sk-test-key-…" via Settings → API Key + Save Key), consent ON.
2. Launched vreader → Library → war-and-peace.txt → reader.
3. Reader chrome bar shows 7 icons including AI sparkles (gating works post bug #90).
4. Tapped sparkles → AI Assistant panel opens with Summarize / Translate / Chat tabs.
5. Tapped Chat → empty state shown ("Ask questions about this book") + "Type a message..." input field at bottom.
6. **Toggled iOS Simulator's Connect Hardware Keyboard OFF** (Cmd+Shift+K) so on-screen keyboard surfaces could appear.
7. Tapped input field → cursor `|` appears in the input + Paste/AutoFill suggestion bar appears above the input (= iOS keyboard accessory view; the keys themselves are clipped by the `.medium` sheet detent, but accessory bar confirms keyboard is up).
8. **Tapped empty chat area** ("Ask questions about this book" zone) → cursor cleared + Paste/AutoFill bar dismissed. **Tap-outside dismissal works.**

## Final verdict

**ship-as-is**

The fix is three stock SwiftUI modifiers:
- `.scrollDismissesKeyboard(.interactively)` on the message-list ScrollView — drag-to-dismiss
- `.contentShape(Rectangle()).onTapGesture { isInputFocused = false }` on the messageList — tap-outside dismissal (the bug-body-specified path)
- `ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("Done") { isInputFocused = false } }` — keyboard-toolbar fallback for short/empty lists

All three are Apple-documented patterns. Visual verification confirms the tap-outside path (the path bug #94 explicitly called broken). The other two are framework-guaranteed; their behavior would just re-confirm Apple's documented modifiers.

No code change needed beyond the three modifiers. Bug #94 is fully addressed.
