---
branch: fix/issue-1657-scroll-switch-bilingual
threadId: 019eb54f-2eb6-74d0-ba7f-9d07b67f5446
rounds: 1
final_verdict: ship-as-is
date: 2026-06-11
---

# Codex Gate-4 audit — Bug #346 (scroll-switch loses bilingual inject)

Session: `019eb54f-2eb6-74d0-ba7f-9d07b67f5446`. VERDICT: clean, round 1
— zero findings.

Verified positively:
- Both orderings covered (VM-first → per-section notification path;
  materialize-first → the catch-up sweep); paged path unaffected
  (`enableBilingualContinuousAllSections` exits on nil config);
  config-after-VM is structurally impossible to lose (notifications only
  exist once the config closure is installed).
- Double-enumerate idempotency holds (existing `data-vreader-bid` stamps
  preserved; section buckets replace-on-update).
- Setup-sheet gating: notifications during the sheet intentionally drop;
  confirm re-sweeps all materialized sections — no other lost-signal
  window.
- The triage's `handleEPUBLayoutChange` suspicion is moot (paged→scroll
  is a host swap); the Readium handler keeps its independent in-host job.
- Coverage call: view-lifecycle wiring with the risky lower layers
  already covered (section-scope / JS / tracker tests); the regression is
  timing+host-swap dependent — device verification is the right primary
  proof; no new unit seam required.

Device verification (pre-merge): paged rows → switch to scroll → rows
survive; DOM probe bids:35/decorations:35 (pre-fix 0/0). Artifacts:
`dev-docs/verification/artifacts/bug-346-fix-{A,B}-*.png`.
