#!/usr/bin/env bash
# scan-untrusted-content.sh — flag prompt-injection / malware-lure patterns in untrusted text
# (GitHub issue/PR comments, web content, anything an agent might read but must NOT act on).
#
# Rule 54 (.claude/rules/54-untrusted-external-content.md): an agent processing an issue runs this
# over every non-collaborator comment BEFORE reading it for content; a non-zero exit means
# QUARANTINE — surface to the operator, never act on it (no downloads, no "install this build").
#
# Usage:   scripts/scan-untrusted-content.sh [FILE]            # or pipe text on stdin
#          OWNER=myorg scripts/scan-untrusted-content.sh FILE  # set the trusted repo owner
# Output:  one "FLAG <category>: <evidence>" line per finding.
# Exit:    0 = clean · 2 = at least one finding (quarantine) · 1 = usage error.
#
# Detection is intentionally high-recall (a false positive costs a human glance; a missed malware
# link can cost the machine). It NEVER fetches a URL — it only inspects text.
set -uo pipefail

OWNER="${OWNER:-$(git config --get remote.origin.url 2>/dev/null | sed -E 's#.*[:/]([^/]+)/[^/]+(\.git)?$#\1#')}"
OWNER="${OWNER:-lllyys}"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then sed -n '2,15p' "$0"; exit 1; fi

TEXT="$(cat "${1:-/dev/stdin}")"
findings=0
flag() { printf 'FLAG %s: %s\n' "$1" "$2"; findings=$((findings + 1)); }
lower() { printf '%s' "$1" | tr 'A-Z' 'a-z'; }

RISKY_EXT='apk|exe|dmg|msi|pkg|deb|rpm|jar|zip|tar\.gz|tgz|sh|bash|bat|cmd|ps1|scr|bin|app|ipa|run'

# 1) Direct links to installer / archive / script artifacts.
while IFS= read -r url; do
  [ -n "$url" ] && flag "binary-link" "$url"
done < <(printf '%s' "$TEXT" | grep -oiE "https?://[^ )\"'<>]+\.($RISKY_EXT)([?#][^ )\"'<>]*)?" | sort -u)

# 2) Release-download / raw user-content from a NON-trusted owner.
while IFS= read -r url; do
  [ -z "$url" ] && continue
  owner="$(printf '%s' "$url" | sed -E 's#https?://(www\.)?github\.com/([^/]+)/.*#\2#; s#https?://raw\.githubusercontent\.com/([^/]+)/.*#\1#')"
  [ "$owner" != "$OWNER" ] && flag "foreign-release" "$url (owner=$owner, trusted=$OWNER)"
done < <(printf '%s' "$TEXT" | grep -oiE "https?://(www\.)?github\.com/[^/ )\"'<>]+/[^ )\"'<>]+/releases/download/[^ )\"'<>]+|https?://raw\.githubusercontent\.com/[^ )\"'<>]+" | sort -u)

# 3) Markdown link-text claims a filename, but the URL points elsewhere (the deception this attack used).
while IFS= read -r link; do
  [ -z "$link" ] && continue
  text="${link%%](*}"; text="${text#[}"
  url="${link#*](}"; url="${url%)}"
  claimed="$(printf '%s' "$text" | grep -oiE "[A-Za-z0-9._-]+\.($RISKY_EXT)\b" | head -1)"
  [ -z "$claimed" ] && continue
  actual="$(printf '%s' "$url" | sed -E 's#[?#].*##; s#.*/##')"
  [ -n "$actual" ] && [ "$(lower "$claimed")" != "$(lower "$actual")" ] && \
    flag "link-deception" "visible \"$claimed\" -> actual \"$actual\" ($url)"
done < <(printf '%s' "$TEXT" | grep -oE '\[[^]]+\]\(https?://[^) ]+\)')

# 4) Pipe-to-shell / remote-code-exec one-liners.
if printf '%s' "$TEXT" | grep -qiE '(curl|wget|iwr|invoke-webrequest|fetch)[^|]*\|[[:space:]]*(sudo[[:space:]]+)?(sh|bash|zsh|fish|iex|python3?|node|ruby|perl)\b'; then
  flag "pipe-to-shell" "$(printf '%s' "$TEXT" | grep -ioE '(curl|wget|iwr)[^|]*\|[[:space:]]*(sh|bash|iex|python3?|node)\b' | head -1)"
fi

# 5) Prompt-injection / social-engineering phrasing aimed at an agent.
INJ='ignore (all |the |any )?(previous|prior|above) (instructions|prompts)|disregard (the |all |any )?(above|previous|prior) (instructions|messages|prompt)|you are now (a |an )|new instructions:|system prompt|developer message|install (this|the|my|our|that) (build|apk|package|binary|module|patch|fix)|(download|sideload|flash|install) (this|the|my|our) (build|apk|binary|module|patched)|side-?load|attached (the |my |a |our )?(build|apk|patched build|binary|module)|i (attached|uploaded|built) (my|the|a) (build|patch|apk|binary)'
if printf '%s' "$TEXT" | grep -qiE "$INJ"; then
  flag "injection-phrase" "$(printf '%s' "$TEXT" | grep -ioE "$INJ" | head -1)"
fi

# 6) Long opaque base64 blob (payload smuggling).
if printf '%s' "$TEXT" | grep -qE '[A-Za-z0-9+/]{220,}={0,2}'; then
  flag "base64-blob" "$(printf '%s' "$TEXT" | grep -oE '[A-Za-z0-9+/]{220,}={0,2}' | head -c 48)…"
fi

# 7) URL shorteners (hide the real destination).
if printf '%s' "$TEXT" | grep -qiE 'https?://(bit\.ly|tinyurl\.com|t\.co|goo\.gl|is\.gd|rb\.gy|cutt\.ly|rebrand\.ly|shorturl\.at|ow\.ly|buff\.ly)/'; then
  flag "url-shortener" "$(printf '%s' "$TEXT" | grep -ioE "https?://(bit\.ly|tinyurl\.com|t\.co|goo\.gl|is\.gd|rb\.gy|cutt\.ly|rebrand\.ly|shorturl\.at|ow\.ly|buff\.ly)/[^ )\"'<>]*" | head -1)"
fi

[ "$findings" -gt 0 ] && exit 2 || exit 0
