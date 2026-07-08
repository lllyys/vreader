#!/usr/bin/env bash
# deps-check.sh — typed `Deps:[…]` token readiness resolution (feature #130 WI-2).
#
# The dispatch layer's hard gate (rule 48 hard rule 2 made mechanical): a work
# item is spawnable only when this says READY. Rows are grepped out of the
# trackers — the 499KB features.md is never read wholesale. Markdown cells are
# split with escaped pipes (`\|`) honored (real tracker rows contain them),
# and rows that don't have the expected column count FAIL CLOSED.
#
# Usage:
#   deps-check.sh {bug|feature} <id>
#       exit 0 READY (stdout: READY + info/warn lines)
#       exit 2 BLOCKED (stdout: BLOCKED + one line per blocker)
#       exit 1 malformed (bad token — empty/trailing-comma/bare #N — or a
#              malformed row shape for the asked row)
#       exit 3 row not found        exit 64 usage / non-numeric id
#   deps-check.sh --lint <tracker-file>
#       exit 0 clean; exit 1 malformed tokens/rows exist; exit 3 unreadable.
#       Legacy free-text dependency prose on non-terminal rows → WARN only
#       (migration-friendly; the rule-51 `BLOCKED: needs-design` marker is
#       sanctioned, never flagged).
#
# Edge grammar: bug:#N | feat:#N | gh:#N | design:#N   (comma-separated inside
# Deps:[…] at the HEAD of the Notes cell; bare #N inside the brackets is an
# ERROR — the 4-way-ambiguous plain #N is banned there; a mid-notes prose
# mention of Deps:[…] is NOT a token).
# Readiness: bug FIXED (WONT FIX/WONT DO/DUPLICATE/RECLASSIFIED ⇒ warn+resolve);
# feat DONE|VERIFIED (WONT DO/DUPLICATE ⇒ warn+resolve); gh issue CLOSED;
# design: its GH issue CLOSED and the checked row no longer carries
# `BLOCKED: needs-design (#N)`. Unknown ids, malformed dep rows, and
# unreachable gh ⇒ BLOCKED (conservative). Env overrides (tests):
# DEPS_BUGS_FILE, DEPS_FEATURES_FILE.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
BUGS="${DEPS_BUGS_FILE:-$ROOT/docs/bugs.md}"
FEATS="${DEPS_FEATURES_FILE:-$ROOT/docs/features.md}"

# Escaped-pipe-safe markdown cell access (Gate-4 High: awk -F'|' alone treats
# `\|` as a delimiter and shifts Status/Notes on real rows).
ESC="$(printf '\001')"

_row_field() { # $1=row line $2=field number → trimmed cell, \| restored
    printf '%s' "$1" | sed "s/\\\\|/$ESC/g" \
        | awk -F'|' -v n="$2" '{print $n}' \
        | sed "s/$ESC/\\\\|/g" | sed 's/^ *//;s/ *$//'
}

_row_nf() { # $1=row line → pipe-field count with \| honored
    printf '%s' "$1" | sed "s/\\\\|/$ESC/g" | awk -F'|' '{print NF}'
}

# Both trackers: | # | Summary | Area/File | Sev/Prio | Status | Notes | → NF 8
ROW_NF_MIN=8

row_line() { # $1=file $2=id → the summary-table row line ('' if absent)
    grep -m1 -E "^\| *$2 *\|" "$1" 2>/dev/null || true
}

row_status() { _row_field "$1" 6; }
row_notes()  { _row_field "$1" 7; }

has_token() { # $1=notes cell → 0 iff it BEGINS with Deps:[
    case "$1" in "Deps:["*) return 0 ;; *) return 1 ;; esac
}

token_contents() { # $1=notes cell → inside of Deps:[…] ('' if unclosed/empty)
    printf '%s' "$1" | sed -n 's/^Deps:\[\([^]]*\)\].*/\1/p'
}

edge_valid() {
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
        bug:*|feat:*)
            local file kind_ok kind_warn
            if [ "${edge%%:*}" = "bug" ]; then
                file="$BUGS"; kind_ok="FIXED"; kind_warn="WONT FIX|WONT DO|DUPLICATE|RECLASSIFIED"
            else
                file="$FEATS"; kind_ok="DONE|VERIFIED"; kind_warn="WONT DO|DUPLICATE"
            fi
            line="$(row_line "$file" "$n")"
            if [ -z "$line" ]; then echo "blocked $edge — unknown row"; return; fi
            if [ "$(_row_nf "$line")" -lt "$ROW_NF_MIN" ]; then
                echo "blocked $edge — malformed dep row (fail closed)"; return
            fi
            st="$(row_status "$line")"
            if printf '%s' "$st" | grep -qE "^($kind_ok)"; then
                :
            elif printf '%s' "$st" | grep -qE "^($kind_warn)"; then
                echo "warn: $edge is terminal-but-not-shipped ($st) — treated as resolved"
            else
                echo "blocked $edge — status ${st:-unparseable}"
            fi ;;
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

# validate_edges <token-contents>
# echoes the cleaned edges one per line; returns 1 on ANY malformation
# (empty contents, empty slot / trailing comma, bare #N, unknown type).
validate_edges() {
    local contents="$1" edge trimmed any=0
    if ! printf '%s' "$contents" | grep -q '[^ ]'; then
        return 1   # Deps:[] / whitespace-only
    fi
    # IFS word-splitting DROPS trailing empty fields, so 'bug:#10,' would
    # sail through the loop — catch empty slots structurally first.
    case ",$contents," in *,,*) return 1 ;; esac
    local IFS=','
    for edge in $contents; do
        trimmed="$(printf '%s' "$edge" | sed 's/^ *//;s/ *$//')"
        if [ -z "$trimmed" ]; then return 1; fi   # ',,' or trailing comma
        if ! edge_valid "$trimmed"; then return 1; fi
        echo "$trimmed"
        any=1
    done
    [ "$any" -eq 1 ]
}

check_row() { # $1=kind $2=id
    local kind="$1" id="$2" file line notes contents edges edge out blockers=""
    case "$kind" in
        bug) file="$BUGS" ;;
        feature) file="$FEATS" ;;
        *) echo "usage: deps-check.sh {bug|feature} <id> | --lint <file>" >&2; exit 64 ;;
    esac
    case "$id" in (''|*[!0-9]*)
        echo "deps-check: id must be numeric, got '$id'" >&2; exit 64 ;;
    esac
    line="$(row_line "$file" "$id")"
    if [ -z "$line" ]; then echo "row $kind #$id not found" >&2; exit 3; fi
    if [ "$(_row_nf "$line")" -lt "$ROW_NF_MIN" ]; then
        echo "row $kind #$id has a malformed shape (expected 6 cells) — fail closed" >&2
        exit 1
    fi

    # rule-51 marker blocks regardless of any token
    if printf '%s' "$line" | grep -qE 'BLOCKED: needs-design \(#[0-9]+\)'; then
        echo "BLOCKED"
        echo "  needs-design: $(printf '%s' "$line" | grep -oE 'BLOCKED: needs-design \(#[0-9]+\)' | head -1)"
        exit 2
    fi

    notes="$(row_notes "$line")"
    if ! has_token "$notes"; then
        echo "READY (no-deps-token)"
        exit 0
    fi
    contents="$(token_contents "$notes")"
    if ! edges="$(validate_edges "$contents")"; then
        echo "malformed Deps token on $kind #$id: '$(printf '%.60s' "$notes")' (empty/trailing edges and bare #N are banned; use bug:#N|feat:#N|gh:#N|design:#N)" >&2
        exit 1
    fi

    while IFS= read -r edge; do
        [ -z "$edge" ] && continue
        out="$(resolve_edge "$edge" "$line")"
        if [ -n "$out" ]; then
            case "$out" in
                warn:*) echo "$out" ;;
                blocked*) blockers="$blockers  ${out#blocked }"$'\n' ;;
            esac
        fi
    done <<< "$edges"

    if [ -n "$blockers" ]; then
        echo "BLOCKED"
        printf '%s' "$blockers"
        exit 2
    fi
    echo "READY"
    exit 0
}

lint_file() { # $1=tracker file
    local file="$1" bad=0 line id notes contents st
    if [ ! -r "$file" ]; then
        echo "error: cannot read tracker file '$file'" >&2
        exit 3
    fi
    while IFS= read -r line; do
        id="$(printf '%s' "$line" | sed -n 's/^| *\([0-9][0-9]*\) *|.*/\1/p')"
        [ -z "$id" ] && continue
        if [ "$(_row_nf "$line")" -lt "$ROW_NF_MIN" ]; then
            echo "error: row $id malformed row shape (expected 6 cells)"
            bad=1
            continue
        fi
        notes="$(row_notes "$line")"
        if has_token "$notes"; then
            contents="$(token_contents "$notes")"
            if ! validate_edges "$contents" >/dev/null; then
                echo "error: row $id malformed token '$(printf '%.40s' "$notes")'"
                bad=1
            fi
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
