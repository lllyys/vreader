#!/usr/bin/env bash
set -euo pipefail

rg -n "invoke\(|emit\(|listen\(" src src-tauri || true
