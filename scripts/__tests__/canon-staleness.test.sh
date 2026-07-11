#!/usr/bin/env bash
# Contract tests for scripts/canon-staleness.sh — the bureau-canon drift
# detector. All fixtures live in a temp tree (CANON_ROOT/CANON_DIR/VERIFY_JSON
# overrides); never the real canon/ or repo.
#
# Run: bash scripts/__tests__/canon-staleness.test.sh

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../canon-staleness.sh"
fails=0
ok()   { echo "ok   — $1"; }
fail() { echo "FAIL — $1"; fails=$((fails+1)); }

if [ ! -f "$SCRIPT" ]; then
    echo "FAIL — $SCRIPT does not exist"; echo "1 FAILURE(S)"; exit 1
fi

sha() { python3 -c "import hashlib,sys;print(hashlib.sha256(open(sys.argv[1],'rb').read()).hexdigest())" "$1"; }

# Build a fresh fixture tree; echoes the root.
make_fixture() {
    local root; root="$(mktemp -d)"
    mkdir -p "$root/canon/modules" "$root/src" "$root/docs"
    # a code artifact + a soft provenance artifact
    printf 'let x = 1\n'      > "$root/src/foo.swift"
    printf '| feature rows |\n' > "$root/docs/features.md"
    local foohash feathash
    foohash="$(sha "$root/src/foo.swift")"
    feathash="$(sha "$root/docs/features.md")"
    # a verified dossier citing both
    cat > "$root/canon/modules/foo.md" <<EOF
---
title: Module — foo
updated: 2026-07-11
status: verified
---

# Module — foo

Body.

**Sources.** [[session x]]
**Verified.** 2026-07-11 — checked against: src/foo.swift, docs/features.md
EOF
    # a canonical dossier that must never be demoted
    cat > "$root/canon/modules/adr.md" <<EOF
---
title: ADR — untouchable
updated: 2026-07-11
status: canonical
---
# ADR
EOF
    cat > "$root/canon/_verify.json" <<EOF
{
 "Module — foo": {
  "verifiedAt": "2026-07-11",
  "checks": [
   {"artifact": "src/foo.swift", "hash": "$foohash", "claim": "c"},
   {"artifact": "docs/features.md", "hash": "$feathash", "claim": "c"}
  ]
 }
}
EOF
    echo "$root"
}

run() {  # run <root> [--apply] ; sets $OUT $RC
    local root="$1"; shift
    OUT="$(CANON_ROOT="$root" CANON_DIR="$root/canon" VERIFY_JSON="$root/canon/_verify.json" bash "$SCRIPT" "$@" 2>&1)"
    RC=$?
}

# 1. Nothing changed -> CLEAN, exit 0.
R="$(make_fixture)"
run "$R"
{ [ $RC -eq 0 ] && echo "$OUT" | grep -q 'RESULT: CLEAN'; } \
    && ok "unchanged canon is CLEAN (exit 0)" \
    || fail "unchanged should be CLEAN exit 0 — got rc=$RC: $(echo "$OUT" | tail -1)"
rm -rf "$R"

# 2. Code artifact changed -> STALE 1, exit 3.
R="$(make_fixture)"
printf 'let x = 2  // changed\n' > "$R/src/foo.swift"
run "$R"
{ [ $RC -eq 3 ] && echo "$OUT" | grep -q 'RESULT: STALE 1'; } \
    && ok "code drift -> STALE 1 (exit 3)" \
    || fail "code drift should be STALE 1 exit 3 — got rc=$RC: $(echo "$OUT" | tail -1)"
rm -rf "$R"

# 3. Only the soft provenance file changed -> CLEAN (advisory), exit 0.
R="$(make_fixture)"
printf '| feature rows |\n| new row |\n' > "$R/docs/features.md"
run "$R"
{ [ $RC -eq 0 ] && echo "$OUT" | grep -q 'RESULT: CLEAN' && echo "$OUT" | grep -q 'ADVISORY'; } \
    && ok "tracker-only drift is advisory, stays CLEAN (exit 0)" \
    || fail "tracker-only drift should be CLEAN+advisory exit 0 — got rc=$RC: $(echo "$OUT" | tail -1)"
rm -rf "$R"

# 4. Missing code artifact -> STALE.
R="$(make_fixture)"
rm -f "$R/src/foo.swift"
run "$R"
{ [ $RC -eq 3 ] && echo "$OUT" | grep -q 'missing: src/foo.swift'; } \
    && ok "missing code artifact -> STALE with 'missing:' reason" \
    || fail "missing artifact should be STALE — got rc=$RC: $(echo "$OUT" | tail -1)"
rm -rf "$R"

# 5. --apply demotes a hard-stale verified page to stale + adds marker; leaves
#    canonical untouched.
R="$(make_fixture)"
printf 'let x = 3\n' > "$R/src/foo.swift"
run "$R" --apply
foo_status="$(grep -m1 '^status:' "$R/canon/modules/foo.md" | sed 's/status: //')"
adr_status="$(grep -m1 '^status:' "$R/canon/modules/adr.md" | sed 's/status: //')"
{ [ "$foo_status" = "stale" ] && grep -q '\*\*Stale\.\*\*' "$R/canon/modules/foo.md" && [ "$adr_status" = "canonical" ]; } \
    && ok "--apply demotes verified->stale (+marker); canonical untouched" \
    || fail "--apply should demote foo to stale and leave adr canonical — foo=$foo_status adr=$adr_status"
rm -rf "$R"

# 6. Bad usage -> exit 2, ERROR result line.
run "$(mktemp -d)" --bogus
{ [ $RC -eq 2 ] && echo "$OUT" | grep -q 'RESULT: ERROR'; } \
    && ok "unknown arg -> ERROR (exit 2)" \
    || fail "unknown arg should ERROR exit 2 — got rc=$RC"

# 7. Missing _verify.json -> exit 2, ERROR.
EMPTY="$(mktemp -d)"; mkdir -p "$EMPTY/canon"
OUT="$(CANON_ROOT="$EMPTY" CANON_DIR="$EMPTY/canon" VERIFY_JSON="$EMPTY/canon/_verify.json" bash "$SCRIPT" 2>&1)"; RC=$?
{ [ $RC -eq 2 ] && echo "$OUT" | grep -q 'RESULT: ERROR'; } \
    && ok "missing _verify.json -> ERROR (exit 2)" \
    || fail "missing ledger should ERROR exit 2 — got rc=$RC"
rm -rf "$EMPTY"

echo
if [ "$fails" -eq 0 ]; then echo "ALL PASS"; exit 0; else echo "$fails FAILURE(S)"; exit 1; fi
