---
branch: triage/bug-178-md-chinese-conversion-unwired
bug: 178
date: 2026-05-14
final_verdict: ship-as-is
---

## Scope

Docs-only triage commit: adds Bug #178 row + detail entry to `docs/bugs.md`.
No Swift source changes. No test changes.

## Audit

No logic to audit. The tracker entry is grounded in code-read evidence:
- `MDReaderContainerView.swift` and `MDReaderViewModel.swift` confirmed to have
  zero references to `SimpTradTransform`, `chineseConversion`, or `TextMapper.apply`.
- `TXTReaderContainerView.swift` wires `SimpTradTransform` at 8 call sites — the
  missing pattern for MD is unambiguous.
- `ReaderSettingsPanel.chineseConversionDisableReason` line 513 enables the picker
  for MD, confirming the discoverability is there but the implementation is absent.

## Verdict

ship-as-is — documentation only, no code risk.
