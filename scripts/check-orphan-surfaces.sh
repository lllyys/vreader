#!/usr/bin/env bash
# Purpose: Detect Android Compose UI surfaces that ship in the release APK but
# are UNREACHABLE — a top-level screen/sheet/panel that is implemented,
# instrumented-tested and marked VERIFIED, yet nothing in production source
# ever calls it.
#
# Why this exists: four Android features (stats dashboard, OPDS browser, AI
# chat/provider config, WebDAV backup+restore) passed every gate — unit tests,
# connected tests, Gate-4 audit, Gate-5 verification — while being dead code in
# a release build. Connected tests call a composable DIRECTLY via setContent,
# so an instrumented pass proves the surface RENDERS, never that a user can
# REACH it. Compilation proves nothing either: an uncalled public @Composable
# is perfectly valid Kotlin. This script closes that gap with the one check
# neither the compiler nor the test harness performs — "does production source
# call this surface at all?".
#
# What it does: scans main-source Kotlin for public @Composable declarations
# whose name carries a top-level-surface suffix (Screen/Sheet/Panel/...), then
# counts call sites in main source (excluding the surface's own defining file
# and its own declaration line). Zero main-source callers = the surface cannot
# be reached in a release build; callers only under src/debug/ are worse than
# useless (that source set is excluded from the release APK entirely).
#
# Pure grep/awk: no Gradle, no build, no new dependencies — cheap enough to run
# as a pre-merge gate.
#
# Usage:
#   scripts/check-orphan-surfaces.sh              # human-readable report
#   scripts/check-orphan-surfaces.sh --quiet      # only the final RESULT line
#   scripts/check-orphan-surfaces.sh --json       # JSON + final RESULT line
#
# Exit codes: 0 = OK (no un-allowlisted findings), 1 = FINDINGS, 2 = ERROR.
#
# Allowlist: scripts/.orphan-surfaces-allow — one bare symbol name per line,
# `#` comments allowed. For surfaces that are DELIBERATELY unwired (staged
# behind an unlanded entry point), so the gate can be adopted before the
# existing findings are fixed. An allowlist entry is debt, not an answer.
#
# Env overrides (used by scripts/__tests__/check-orphan-surfaces.test.sh so the
# test runs against a fixture tree, never the real android/ dir):
#   ORPHAN_MAIN_SRC, ORPHAN_DEBUG_SRC, ORPHAN_ALLOWLIST
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"

MAIN_SRC="${ORPHAN_MAIN_SRC:-$ROOT/android/app/src/main/kotlin}"
DEBUG_SRC="${ORPHAN_DEBUG_SRC:-$ROOT/android/app/src/debug}"
ALLOWLIST="${ORPHAN_ALLOWLIST:-$HERE/.orphan-surfaces-allow}"

# Tunable: a declaration is treated as a top-level *surface* only when its name
# ends with one of these. Broad enough to catch every entry-point shape the app
# uses today; narrow enough that leaf composables (rows, cards, chips) don't
# flood the report — those are legitimately called only by their own screen.
SURFACE_SUFFIXES="Screen Sheet Panel Dashboard Popup Popover Bar Dialog"

JSON=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --json)  JSON=1 ;;
    --quiet) QUIET=1 ;;
    -h|--help)
      grep '^# ' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *)
      echo "CHECK-ORPHAN-SURFACES RESULT: ERROR (unknown argument: $arg)"
      exit 2 ;;
  esac
done

say() { [ "$QUIET" -eq 1 ] && return 0; echo "$@"; }

if [ ! -d "$MAIN_SRC" ]; then
  echo "CHECK-ORPHAN-SURFACES RESULT: ERROR (main source tree not found: $MAIN_SRC)"
  exit 2
fi

# ---------------------------------------------------------------------------
# 1. Collect public @Composable declarations.
#
# The annotation buffer accumulates `@...` lines and survives blank/comment
# lines (KDoc between annotations and `fun` is legal Kotlin), then is consumed
# and cleared by the next real statement. `private`/`internal` declarations
# never match the `fun` pattern, so visibility filtering is structural rather
# than a second pass. @Preview-annotated functions are dropped explicitly.
# ---------------------------------------------------------------------------
DECLS="$(mktemp -t orphan-decls.XXXXXX)"
CALLS="$(mktemp -t orphan-calls.XXXXXX)"
trap 'rm -f "$DECLS" "$CALLS"' EXIT

find "$MAIN_SRC" -type f -name '*.kt' -print0 \
  | sort -z \
  | xargs -0 awk '
      FNR == 1 { ann = "" }
      {
        t = $0
        sub(/^[ \t]+/, "", t)
        if (t ~ /^@/)                                  { ann = ann " " t; next }
        if (t == "" || t ~ /^\/\// || t ~ /^\*/ || t ~ /^\/\*/) { next }
        if (t ~ /^(public[ \t]+)?fun[ \t]+[A-Z][A-Za-z0-9_]*[ \t]*\(/) {
          if (ann ~ /@(androidx\.compose\.runtime\.)?Composable/ && ann !~ /@Preview/) {
            name = t
            sub(/^(public[ \t]+)?fun[ \t]+/, "", name)
            sub(/[ \t]*\(.*/, "", name)
            print name "\t" FILENAME
          }
        }
        ann = ""
      }
    ' > "$DECLS"

# ---------------------------------------------------------------------------
# 2. Count call sites for one name in one tree.
#
# A "call site" is `Name(` preceded by a non-identifier character. Excluded:
# the surface's own defining file (whole file — a screen calling itself proves
# nothing), any *other* declaration of the same name, and comment lines.
# ---------------------------------------------------------------------------
count_calls() { # <dir> <defining-file> <name>
  local dir="$1" declfile="$2" name="$3"
  [ -d "$dir" ] || { echo 0; return 0; }
  grep -rn --include='*.kt' -E "(^|[^A-Za-z0-9_])${name}[[:space:]]*\(" "$dir" 2>/dev/null \
    | awk -v decl="$declfile" -v n="$name" '
        {
          path = $0
          sub(/:[0-9]+:.*$/, "", path)
          if (path == decl) next
          line = $0
          sub(/^[^:]*:[0-9]+:/, "", line)
          t = line
          sub(/^[ \t]+/, "", t)
          if (t ~ /^\/\// || t ~ /^\*/) next
          if (t ~ ("^(public[ \t]+|private[ \t]+|internal[ \t]+)?fun[ \t]+" n "[ \t]*\\(")) next
          c++
        }
        END { print c + 0 }
      ' || true
}

is_allowlisted() { # <name>
  [ -f "$ALLOWLIST" ] || return 1
  sed 's/#.*//' "$ALLOWLIST" | tr -d ' \t\r' | grep -qx -- "$1"
}

rel() { # <abs-path>
  case "$1" in
    "$ROOT"/*) printf '%s' "${1#"$ROOT"/}" ;;
    *)         printf '%s' "$1" ;;
  esac
}

matches_suffix() { # <name>
  local name="$1" suffix
  for suffix in $SURFACE_SUFFIXES; do
    case "$name" in *"$suffix") return 0 ;; esac
  done
  return 1
}

# ---------------------------------------------------------------------------
# 3. Classify.
# ---------------------------------------------------------------------------
orphaned=0
debug_only=0
allowed=0
reachable=0
findings=()
json_rows=()

while IFS=$'\t' read -r name file; do
  [ -n "$name" ] || continue
  matches_suffix "$name" || continue

  main_n="$(count_calls "$MAIN_SRC" "$file" "$name")"
  if [ "$main_n" -gt 0 ]; then
    status="REACHABLE"
    debug_n=0
    reachable=$((reachable + 1))
  else
    debug_n="$(count_calls "$DEBUG_SRC" "$file" "$name")"
    if [ "$debug_n" -gt 0 ]; then status="DEBUG-ONLY"; else status="ORPHANED"; fi
    if is_allowlisted "$name"; then
      allowed=$((allowed + 1))
      findings+=("ALLOWED  $name ($(rel "$file")) — $status, allowlisted in $(rel "$ALLOWLIST")")
      status="ALLOWED($status)"
    elif [ "$status" = "DEBUG-ONLY" ]; then
      debug_only=$((debug_only + 1))
      findings+=("DEBUG-ONLY $name ($(rel "$file")) — called only from $(rel "$DEBUG_SRC"), excluded from the release APK")
    else
      orphaned=$((orphaned + 1))
      findings+=("ORPHANED $name ($(rel "$file")) — no production call site")
    fi
  fi

  json_rows+=("$(printf '{"name":"%s","file":"%s","status":"%s","main_callers":%s,"debug_callers":%s}' \
    "$name" "$(rel "$file")" "$status" "$main_n" "$debug_n")")
done < "$DECLS"

total_findings=$((orphaned + debug_only))
if [ "$total_findings" -eq 0 ]; then result="OK"; else result="FINDINGS"; fi

# ---------------------------------------------------------------------------
# 4. Report.
# ---------------------------------------------------------------------------
if [ "$JSON" -eq 1 ]; then
  # The RESULT line is still printed LAST (repo convention). JSON consumers
  # read all but the final line, or use the "result" field below.
  {
    printf '{"result":"%s","orphaned":%d,"debug_only":%d,"allowlisted":%d,"reachable":%d,"surfaces":[' \
      "$result" "$orphaned" "$debug_only" "$allowed" "$reachable"
    sep=""
    for row in ${json_rows+"${json_rows[@]}"}; do printf '%s%s' "$sep" "$row"; sep=","; done
    printf ']}\n'
  }
else
  say "[check-orphan-surfaces] main=$(rel "$MAIN_SRC") debug=$(rel "$DEBUG_SRC") suffixes=($SURFACE_SUFFIXES)"
  for f in ${findings+"${findings[@]}"}; do say "$f"; done
  say "[check-orphan-surfaces] reachable=$reachable allowlisted=$allowed"
fi

echo "CHECK-ORPHAN-SURFACES RESULT: $result ($orphaned orphaned, $debug_only debug-only)"
[ "$total_findings" -eq 0 ] || exit 1
exit 0
