---
branch: triage/bug-179-txt-dynamic-island-content-obscured
bug: 179
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #179 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `TXTViewConfig.swift:19`: `textInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)` — hardcoded, not DI-aware.
- `TXTTextViewBridge.swift:51`: `textView.textContainerInset = config.textInset` — no safe-area compensation.
- `EPUBWebViewBridgeJS.swift:34-64`: `applySafeAreaTopInset` + `applyInitialContentOffset` provide the EPUB fix for bug #163 — confirmed no equivalent exists for UITextView in the TXT bridge.
- Same symptom confirmed at GH #487 (EPUB bug #163); TXT was not part of that fix.

## Verdict

ship-as-is — documentation only, no code risk.
