#!/usr/bin/env bash
# Bug #329 round 4: REAL-gesture probe. idb pans (finger-down drags through the
# HID channel) with a position sample after each — the eviction-invariant
# (vsi, intraPx) must never move backward while panning forward.
set -uo pipefail
export PATH="$HOME/Library/Python/3.9/bin:/opt/homebrew/bin:$PATH"
UDID="${TEST_UDID:-61149F0E-DC18-4BE2-BB37-52659F1F4F62}"
N="${1:-40}"; DUR="${2:-0.8}"; OUT="${3:-/tmp/b329-gesture.jsonl}"
APP_DATA=$(xcrun simctl get_app_container "$UDID" com.vreader.app data)
EVAL_JSON="$APP_DATA/Library/Caches/DebugBridge/eval-epub.json"
JS='(function(){var r=document.getElementById("vreader-scroll-root");if(!r)return"no-root";var L=r.querySelectorAll("[data-vreader-spine-index]"),p=r.scrollTop,v=-1,o=0,a=[];for(var i=0;i<L.length;i++){var e=L[i],x=parseInt(e.getAttribute("data-vreader-spine-index"),10);a.push(x);if(e.offsetTop<=p){v=x;o=Math.round(p-e.offsetTop)}}return JSON.stringify({v:v,o:o,st:Math.round(p),sh:Math.round(r.scrollHeight),w:a.join(",")});})()'
B64=$(printf '%s' "$JS" | base64 | tr -d '\n' | sed -e 's/+/%2B/g' -e 's,/,%2F,g' -e 's/=/%3D/g')
sample() {
  rm -f "$EVAL_JSON"
  xcrun simctl openurl "$UDID" "vreader-debug://eval?bridge=epub&js=$B64" >/dev/null
  for _ in $(seq 1 20); do [ -s "$EVAL_JSON" ] && break; sleep 0.2; done
  python3 -c "import sys,json;d=json.load(open('$EVAL_JSON'));print(d.get('result','{}'))" 2>/dev/null || echo '{}'
}
: > "$OUT"
echo "{\"pan\":0,\"s\":$(sample)}" >> "$OUT"
for i in $(seq 1 "$N"); do
  idb ui swipe --udid "$UDID" --duration "$DUR" 200 620 200 150 >/dev/null 2>&1
  sleep 0.7
  echo "{\"pan\":$i,\"s\":$(sample)}" >> "$OUT"
done
python3 - "$OUT" <<'PY'
import sys, json
rows=[json.loads(l) for l in open(sys.argv[1])]
viol=[]; prev=None
for r in rows:
    s=r.get("s") or {}
    if isinstance(s,str):
        try: s=json.loads(s)
        except: s={}
    v,o=s.get("v",-2),s.get("o",0)
    if v is None or v<0: continue
    cur=(v,o)
    if prev and cur<prev[1]: viol.append((r["pan"],prev[1],cur,s.get("st")))
    prev=(r["pan"],cur)
print(f"pans={len(rows)-1} backward-jumps={len(viol)}")
for p,was,now,st in viol[:15]:
    print(f"  pan {p}: ({was[0]},{was[1]}px) -> ({now[0]},{now[1]}px) scrollTop={st}")
last=rows[-1].get("s"); 
if isinstance(last,str):
    try: last=json.loads(last)
    except: last={}
print(f"end: vsi={last.get('v')} intraPx={last.get('o')} win=[{last.get('w')}]")
PY
