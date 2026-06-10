#!/usr/bin/env python3
# Bug #329 round-3: analyze a 1px sweep recording for monotonicity violations.
# rec entries: [tick, scrollTop, visibleSpine, intraPx, scrollHeight]
# wins entries: [tick, "comma,separated,materialized,spines"]
import json, sys

path = sys.argv[1]
data = json.load(open(path))
rec, wins = data["rec"], data["wins"]
print(f"reason={data.get('reason')} ticks={len(rec)} window-changes={len(wins)}")
if not rec:
    sys.exit("empty recording")

# 1. Content-position monotonicity: (vsi, off) lexicographic, ignoring ticks
#    where vsi == -1 (no section above scrollTop — transient during mutations).
viol = []
prev = None
for t, st, vsi, off, sh in rec:
    if vsi < 0:
        continue
    cur = (vsi, off)
    if prev is not None and cur < prev[1]:
        viol.append((t, prev[1], cur, st))
    prev = (t, cur)
print(f"\n== content-position backward jumps: {len(viol)}")
for t, was, now, st in viol[:30]:
    dvsi = now[0] - was[0]
    doff = now[1] - was[1]
    print(f"  tick {t}: ({was[0]},{was[1]}px) -> ({now[0]},{now[1]}px)  Δvsi={dvsi} Δoff={doff} scrollTop={st}")
if len(viol) > 30:
    print(f"  … and {len(viol)-30} more")

# 2. Stalls: scrollTop unchanged for >=120 consecutive ticks (~2s) while the
#    recorder kept stepping (not document-end — the recorder stops there).
stalls = []
run_start, run_len = None, 0
for i in range(1, len(rec)):
    if rec[i][1] == rec[i-1][1]:
        if run_start is None:
            run_start = rec[i-1][0]
        run_len += 1
    else:
        if run_len >= 120:
            stalls.append((run_start, run_len, rec[i-1][1]))
        run_start, run_len = None, 0
if run_len >= 120:
    stalls.append((run_start, run_len, rec[-1][1]))
print(f"\n== stalls (scrollTop pinned >=120 ticks): {len(stalls)}")
for s, n, st in stalls[:10]:
    print(f"  tick {s}: pinned at scrollTop={st} for {n} ticks (~{n*16/1000:.1f}s)")

# 3. Window thrash: A->B->A transitions in the materialized window.
thrash = 0
for i in range(2, len(wins)):
    if wins[i][1] == wins[i-2][1] and wins[i][1] != wins[i-1][1]:
        thrash += 1
print(f"\n== window transitions: {len(wins)-1}, A->B->A thrash count: {thrash}")
for t, w in wins[:40]:
    print(f"  tick {t}: [{w}]")
if len(wins) > 40:
    print(f"  … and {len(wins)-40} more")

# 4. scrollTop discontinuities (compensations / jumps): |Δ| > 5 between ticks.
jumps = [(rec[i][0], rec[i-1][1], rec[i][1]) for i in range(1, len(rec))
         if abs(rec[i][1] - rec[i-1][1]) > 5]
print(f"\n== scrollTop discontinuities (|Δ|>5px): {len(jumps)}")
for t, a, b in jumps[:20]:
    print(f"  tick {t}: {a} -> {b} (Δ{b-a:+d})")

# 5. scrollHeight changes (extends/evicts/image growth).
shc = [(rec[i][0], rec[i-1][4], rec[i][4]) for i in range(1, len(rec))
       if rec[i][4] != rec[i-1][4]]
print(f"\n== scrollHeight changes: {len(shc)}")
for t, a, b in shc[:20]:
    print(f"  tick {t}: {a} -> {b} (Δ{b-a:+d})")

# 6. Net progress.
first = next((r for r in rec if r[2] >= 0), rec[0])
print(f"\n== progress: start (vsi={first[2]}, off={first[3]}) -> end (vsi={rec[-1][2]}, off={rec[-1][3]}) over {len(rec)} ticks")
print(f"verdict: {'FAIL' if (viol or stalls) else 'PASS'} — {len(viol)} backward jumps, {len(stalls)} stalls, thrash={thrash}")
