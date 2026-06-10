#!/usr/bin/env bash
# Bug #329 round-3 harness: drive the EPUB continuous-scroll stitch 1px at a
# time from inside the page (setTimeout stepper, synthetic scroll dispatch),
# recording [tick, scrollTop, visibleSpine, intraPx, scrollHeight] per tick and
# the materialized-window section list on change. Pulls the recording out via
# the DebugBridge eval channel for offline monotonicity analysis.
#
# Usage: scripts/b329-1px-sweep.sh <out.json> [target_vsi] [max_ticks]
set -euo pipefail

UDID="${TEST_UDID:-61149F0E-DC18-4BE2-BB37-52659F1F4F62}"
OUT="${1:?usage: b329-1px-sweep.sh <out.json> [target_vsi] [max_ticks]}"
TARGET_VSI="${2:-6}"
MAX_TICKS="${3:-40000}"

APP_DATA=$(xcrun simctl get_app_container "$UDID" com.vreader.app data)
EVAL_JSON="$APP_DATA/Library/Caches/DebugBridge/eval-epub.json"

evaljs() { # evaljs <js> -> prints eval-epub.json content
  local js="$1"
  local b64
  # Percent-encode the base64: '+' would URL-decode to a space and corrupt the
  # payload ('/' and '=' encoded too, belt-and-braces).
  b64=$(printf '%s' "$js" | base64 | tr -d '\n' | sed -e 's/+/%2B/g' -e 's,/,%2F,g' -e 's/=/%3D/g')
  rm -f "$EVAL_JSON"
  xcrun simctl openurl "$UDID" "vreader-debug://eval?bridge=epub&js=$b64" >/dev/null
  for _ in $(seq 1 40); do
    [ -s "$EVAL_JSON" ] && break
    sleep 0.25
  done
  cat "$EVAL_JSON" 2>/dev/null || echo '{"error":"no eval output"}'
}

# 1. Install + start the recorder. Minified: the eval URL path drops payloads
#    past ~1.7KB of base64, so the recorder must stay compact.
#    rec rows: [tick, scrollTop, visibleSpine, intraPx, scrollHeight];
#    wins rows: [tick, "materialized,spine,indexes"]. Stops at MAX ticks, at
#    TARGET visible spine, or at the document end.
START_JS="(function(){var r=document.getElementById('vreader-scroll-root');if(!r)return'no-root';var s={rec:[],wins:[],done:!1,t:0,reason:''};window.__b329=s;var M=$MAX_TICKS,T=$TARGET_VSI,w='';function V(){var L=r.querySelectorAll('[data-vreader-spine-index]'),p=r.scrollTop,v=-1,o=0,a=[];for(var i=0;i<L.length;i++){var e=L[i],x=parseInt(e.getAttribute('data-vreader-spine-index'),10);a.push(x);if(e.offsetTop<=p){v=x;o=Math.round(p-e.offsetTop)}}return{v:v,o:o,w:a.join(',')}}function K(){if(s.done)return;var b=r.scrollTop;r.scrollTop=b+1;try{r.dispatchEvent(new Event('scroll'))}catch(e){}var q=V();s.rec.push([s.t,Math.round(r.scrollTop),q.v,q.o,Math.round(r.scrollHeight)]);if(q.w!==w){s.wins.push([s.t,q.w]);w=q.w}s.t++;var E=(r.scrollTop+r.clientHeight)>=(r.scrollHeight-1);if(s.t>=M){s.done=!0;s.reason='max';return}if(q.v>=T){s.done=!0;s.reason='target';return}if(r.scrollTop===b&&E){s.done=!0;s.reason='end';return}setTimeout(K,16)}setTimeout(K,16);return'started'})()"
echo "[harness] starting recorder (target vsi=$TARGET_VSI, max=$MAX_TICKS)…"
evaljs "$START_JS" | python3 -c "import sys,json; print('[start]', json.load(sys.stdin).get('result'))"

# 2. Poll progress until done.
while :; do
  sleep 6
  P=$(evaljs "(function(){var s=window.__b329; if(!s) return 'gone'; return JSON.stringify({t:s.t, done:s.done, reason:s.reason, n:s.rec.length, last:s.rec[s.rec.length-1]||null});})()")
  echo "[poll] $(echo "$P" | python3 -c "import sys,json; print(json.load(sys.stdin).get('result'))")"
  DONE=$(echo "$P" | python3 -c "import sys,json; r=json.load(sys.stdin).get('result','{}'); print(json.loads(r).get('done', False) if isinstance(r,str) else False)" 2>/dev/null || echo False)
  [ "$DONE" = "True" ] && break
done

# 3. Pull the recording in chunks (the rec array can be large).
echo "[harness] pulling recording…"
N=$(evaljs "(function(){return window.__b329.rec.length;})()" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")
WINS=$(evaljs "(function(){return JSON.stringify(window.__b329.wins);})()" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")
REASON=$(evaljs "(function(){return window.__b329.reason;})()" | python3 -c "import sys,json; print(json.load(sys.stdin)['result'])")
echo "[harness] rec entries: $N, reason: $REASON"
CHUNK=4000
echo '{"wins":' > "$OUT.tmp"
printf '%s' "$WINS" >> "$OUT.tmp"
printf ',"reason":"%s","rec":[' "$REASON" >> "$OUT.tmp"
i=0
FIRST=1
while [ "$i" -lt "$N" ]; do
  end=$((i + CHUNK)); [ "$end" -gt "$N" ] && end=$N
  PART=$(evaljs "(function(){return JSON.stringify(window.__b329.rec.slice($i, $end));})()" | python3 -c "import sys,json; r=json.load(sys.stdin)['result']; print(r[1:-1])")
  if [ -n "$PART" ]; then
    if [ "$FIRST" = "1" ]; then FIRST=0; else printf ',' >> "$OUT.tmp"; fi
    printf '%s' "$PART" >> "$OUT.tmp"
  fi
  i=$end
  echo "[pull] $i / $N"
done
printf ']}' >> "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
echo "[harness] wrote $OUT"
