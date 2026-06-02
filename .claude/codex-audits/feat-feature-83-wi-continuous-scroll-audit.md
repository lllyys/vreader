---
branch: feat/feature-83-wi-continuous-scroll
threadId: 019e88b3-1e26-7793-9b37-8650b207b686
rounds: 2
final_verdict: ship-as-is
date: 2026-06-02
---

# Gate-4 implementation audit — Feature #83 (Readium cross-chapter continuous scroll)

Codex gpt-5.5 / high, read-only (via `scripts/run-codex.sh`). Audited the boundary
auto-advance impl (model + observer + weak proxy + coordinator wiring) against the
plan. WI-1 feasibility spike already PROVED the JS boundary signal on device
(round-1 thread `019e889e-3c8e-79c2-9c7b-99231e37d0a2`).

## Verdict

Round 1: **block-recommended** — 1 High + 1 Medium. Round 2: **ship-as-is** — both
RESOLVED, no new issues. Auditor confirmed clean: edge math/direction, scroll-layout
gating, fixed JS string injection (no app interpolation), weak-proxy retention shape,
paged-mode gate, and the locationDidChange-driven bilingual/TTS/position paths.

## Findings + resolutions

| Round | File | Severity | Issue | Resolution |
|---|---|---|---|---|
| 1 | `ReadiumEPUBHost+ContinuousScroll.swift` | High | 0.7s per-proxy debounce only — a slow transition / long-held drag could let the stale outgoing spread post again → double-advance / chapter-skip | Added coordinator-owned `continuousScrollAdvancing` in-flight guard: set before `goForward`/`goBackward`, cleared in the same Task after the navigation await settles + on `locationDidChange` / `detach()` / layout change. Gates out stale-spread messages across spreads. |
| 1 | `ReadiumEPUBHost+ContinuousScroll.swift` | Medium | `handleContinuousScrollBoundary` captured `boundNavigator` before the async Task → could drive a torn-down navigator after detach | Task now re-reads the weak navigator inside (`[weak self] guard let navigator = self.boundNavigator`), mirroring `+Navigation`; `detach()` nils it. |

## Tests + device verification

- `ReadiumContinuousScrollModelTests` (9): edge math, direction, scroll-layout gate,
  debounce tolerance, zero-geometry.
- WI-1 device spike: the `setupUserScripts` boundary observer fires reliably
  (`window.scrollY`/`scrollHeight`/`innerHeight` valid + monotonic in Readium scroll).
- Device acceptance: scrolling past ALPHA's bottom auto-advanced to BRAVO (Chapter Two)
  and continued scrolling — the #309 cross-chapter continuity, restored (auto-advance,
  honest seam per Gate-2).
