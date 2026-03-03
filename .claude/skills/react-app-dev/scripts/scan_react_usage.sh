#!/usr/bin/env bash
set -euo pipefail

echo "== Store usage in components/hooks/pages =="
rg -n "use[A-Za-z]+Store" src/components src/hooks src/pages || true

echo "== Potential store destructuring patterns =="
rg -n "const \{[^}]+\} = use[A-Za-z]+Store" src/components src/hooks src/pages || true

echo "== Shortcut/keymap references =="
rg -n "keymap|shortcut|accelerator|Cmd\+|Ctrl\+|F[0-9]+" src || true
