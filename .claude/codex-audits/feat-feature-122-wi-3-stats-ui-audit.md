---
branch: feat/feature-122-wi-3-stats-ui
threadId: 019f0405-f122wi3
rounds: 1
final_verdict: ship-as-is
date: 2026-06-28
---

# Feature #122 WI-3 — Codex audit (reading-stats Compose surfaces)

Files: `stats/InReaderTimePill.kt` (session pill + detail card), `stats/StatsDashboard.kt` (window bar +
hero + 14-day chart + per-book table); instrumented `StatsUiTest` (4).

## Round 1 — 2 Medium, 1 Low (all fixed)

| file | severity | issue | resolution |
|---|---|---|---|
| StatsDashboard DailyChart | Medium | empty `daily14` (no-data/initial state) lost the designed 14-day frame/baseline | FIXED — normalize to 14 slots (pad zeros when empty), last slot = today |
| StatsDashboard PerBookTable | Medium | the time hairline was broken (`height(3).padding(top=7)` left no usable height; no track behind the fill) | FIXED — `padding(top=7).height(3)` on a full-width clipped track + a clamped-fraction filled child |
| StatsDashboard chart/table | Low | fractions didn't clamp negative inputs (stateless UI callable directly) | FIXED — `coerceAtLeast(0)` on minutes + `coerceIn(0f,1f)` on fractions |

Codex confirmed `formatClock`/`formatMinutes` are correct for zero/negative/`<1h`/`h>0`/large, and that
`today == lastIndex` holds (the repo returns 14 chronological days ending today).

## Summary

2 Medium + 1 Low, all fixed; 4 instrumented Compose tests green on emulator-5554. **Verdict: ship-as-is.**
