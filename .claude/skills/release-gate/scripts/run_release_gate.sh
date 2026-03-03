#!/usr/bin/env bash
set -euo pipefail

LOG_PATH="${1:-}"

if [[ -n "$LOG_PATH" ]]; then
  pnpm check:all | tee "$LOG_PATH"
else
  pnpm check:all
fi
