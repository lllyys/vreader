#!/usr/bin/env bash
# deps-check.sh — typed `Deps:[…]` token readiness resolution (feature #130 WI-2).
#
# The dispatch layer's hard gate (rule 48 hard rule 2 made mechanical): a work
# item is spawnable only when this says READY. Rows are grepped out of the
# trackers — the 499KB features.md is never read wholesale.
#
# Usage:
#   deps-check.sh {bug|feature} <id>
#       exit 0 READY (stdout: READY + info/warn lines)
#       exit 2 BLOCKED (stdout: BLOCKED + one line per blocker)
#       exit 1 malformed Deps token (bare #N etc.)
#       exit 3 row not found        exit 64 usage
#   deps-check.sh --lint <tracker-file>
#       exit 0 clean; exit 1 malformed tokens exist.
#       Legacy free-text dependency prose on non-terminal rows → WARN only
#       (migration-friendly; the rule-51 `BLOCKED: needs-design` marker is
#       sanctioned, never flagged).
#
# Edge grammar: bug:#N | feat:#N | gh:#N | design:#N   (comma-separated inside
# Deps:[…] at the head of the Notes cell; bare #N inside the brackets is an
# ERROR — the 4-way-ambiguous plain #N is banned there).
# Readiness: bug FIXED (WONT FIX/WONT DO/DUPLICATE/RECLASSIFIED ⇒ warn+resolve);
# feat DONE|VERIFIED (WONT DO/DUPLICATE ⇒ warn+resolve); gh issue CLOSED;
# design: its GH issue CLOSED and the checked row no longer carries
# `BLOCKED: needs-design (#N)`. Unknown ids and unreachable gh ⇒ BLOCKED
# (conservative). Env overrides (tests): DEPS_BUGS_FILE, DEPS_FEATURES_FILE.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUGS="${DEPS_BUGS_FILE:-$ROOT/docs/bugs.md}"
FEATS="${DEPS_FEATURES_FILE:-$ROOT/docs/features.md}"

row_line() { # $1=file $2=id → the summary-table row line ('' if absent)
    grep -m1 -E "^\| *$2 *\|" "$1" 2>/dev/null || true
}

row_status() { # $1=row line → status column (5th data column, both trackers)
    printf '%s' "$1" | awk -F'|' '{gsub(/^ +| +$/,"",$6); print $6}'
}

extract_token() { # $1=row line → contents of Deps:[…] ('' if absent)
    # HEAD-of-Notes only (7th |-field): a prose MENTION of Deps:[…] later in
    # the cell is not a token (real false positive: feature #130's own row).
    printf '%s' "$1" | awk -F'|' '{print $7}' | sed -n 's/^ *Deps:\[\([^]]*\)\].*/\1/p'
}

edge_valid() { # $1=edge → 0 iff syntactically valid
    printf '%s' "$1" | grep -qE '^(bug|feat|gh|design):#[0-9]+$'
}

gh_state() { # $1=issue number → CLOSED | OPEN | UNKNOWN
    gh issue view "$1" --json state -q .state 2>/dev/null | tr -d ' \n' || echo UNKNOWN
}

# resolve_edge <edge> <checked-row-line>
# stdout: nothing (ok) | "warn: …" (ok) | "blocked <edge> — reason"
resolve_edge() {
    local edge="$1" row="$2" n st line state
    n="${edge#*:\#}"
    case "$edge" in
        bug:*)
            line="$(row_line "$BUGS" "$n")"
            if [ -z "$line" ]; then echo "blocked $edge — unknown bug row"; return; fi
            st="$(row_status "$line")"
            case "$st" in
                FIXED*) : ;;
                "WONT FIX"*|"WONT DO"*|DUPLICATE*|RECLASSIFIED*)
                    echo "warn: $edge is terminal-non-fixed ($st) — treated as resolved" ;;
                *) echo "blocked $edge — status $st" ;;
            esac ;;
        feat:*)
            line="$(row_line "$FEATS" "$n")"
            if [ -z "$line" ]; then echo "blocked $edge — unknown feature row"; return; fi
            st="$(row_status "$line")"
            case "$st" in
                DONE*|VERIFIED*) : ;;
                "WONT DO"*|DUPLICATE*)
                    echo "warn: $edge is terminal-non-done ($st) — treated as resolved" ;;
                *) echo "blocked $edge — status $st" ;;
            esac ;;
        gh:*)
            state="$(gh_state "$n")"
            case "$state" in
                CLOSED) : ;;
                *) echo "blocked $edge — issue state $state" ;;
            esac ;;
        design:*)
            if printf '%s' "$row" | grep -q "BLOCKED: needs-design (#$n)"; then
                echo "blocked $edge — row still carries BLOCKED: needs-design (#$n)"
                return
            fi
            state="$(gh_state "$n")"
            case "$state" in
                CLOSED) : ;;
                *) echo "blocked $edge — design issue state $state" ;;
            esac ;;
    esac
}

check_row() { # $1=kind $2=id
    local kind="$1" id="$2" file line token edge out blockers=""
    case "$kind" in
        bug) file="$BUGS" ;;
        feature) file="$FEATS" ;;
        *) echo "usage: deps-check.sh {bug|feature} <id> | --lint <file>" >&2; exit 64 ;;
    esac
    line="$(row_line "$file" "$id")"
    if [ -z "$line" ]; then echo "row $kind #$id not found" >&2; exit 3; fi

    # rule-51 marker blocks regardless of any token
    if printf '%s' "$line" | grep -qE 'BLOCKED: needs-design \(#[0-9]+\)'; then
        echo "BLOCKED"
        echo "  needs-design: $(printf '%s' "$line" | grep -oE 'BLOCKED: needs-design \(#[0-9]+\)' | head -1)"
        exit 2
    fi

    token="$(extract_token "$line")"
    if [ -z "$token" ]; then
        echo "READY (no-deps-token)"
        exit 0
    fi

    local IFS=','
    for edge in $token; do
        edge="$(printf '%s' "$edge" | sed 's/^ *//;s/ *$//')"
        [ -z "$edge" ] && continue
        if ! edge_valid "$edge"; then
            echo "malformed Deps token: '$edge' (bare #N is banned; use bug:#N|feat:#N|gh:#N|design:#N)" >&2
            exit 1
        fi
        out="$(resolve_edge "$edge" "$line")"
        if [ -n "$out" ]; then
            case "$out" in
                warn:*) echo "$out" ;;
                blocked*) blockers="$blockers  ${out#blocked }"$'\n' ;;
            esac
        fi
    done

    if [ -n "$blockers" ]; then
        echo "BLOCKED"
        printf '%s' "$blockers"
        exit 2
    fi
    echo "READY"
    exit 0
}

lint_file() { # $1=tracker file
    local file="$1" bad=0 line id token edge st
    while IFS= read -r line; do
        id="$(printf '%s' "$line" | sed -n 's/^| *\([0-9][0-9]*\) *|.*/\1/p')"
        [ -z "$id" ] && continue
        token="$(extract_token "$line")"
        if [ -n "$token" ]; then
            local IFS=','
            for edge in $token; do
                edge="$(printf '%s' "$edge" | sed 's/^ *//;s/ *$//')"
                [ -z "$edge" ] && continue
                if ! edge_valid "$edge"; then
                    echo "error: row $id malformed token edge '$edge'"
                    bad=1
                fi
            done
            unset IFS
        fi
        # legacy prose warning — non-terminal rows only; the rule-51 marker
        # is sanctioned and excluded
        st="$(row_status "$line")"
        case "$st" in
            TODO*|PLANNED*|"IN PROGRESS"*|DONE*)
                if printf '%s' "$line" | grep -vE 'BLOCKED: needs-design' | grep -qE 'Blocked by (bug|feature)? *#[0-9]+|Depends on (feature |bug )?#[0-9]+|HARD-BLOCKED'; then
                    echo "warn: row $id carries legacy dependency prose — migrate to Deps:[…]"
                fi ;;
        esac
    done < <(grep -E '^\| *[0-9]+ *\|' "$file" 2>/dev/null || true)
    exit "$bad"
}

case "${1:-}" in
    --lint) [ -n "${2:-}" ] || { echo "usage: deps-check.sh --lint <file>" >&2; exit 64; }
            lint_file "$2" ;;
    bug|feature) [ -n "${2:-}" ] || { echo "usage: deps-check.sh {bug|feature} <id>" >&2; exit 64; }
            check_row "$1" "$2" ;;
    *) echo "usage: deps-check.sh {bug|feature} <id> | --lint <file>" >&2; exit 64 ;;
esac
