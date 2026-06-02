---
branch: fix/issue-1359-bilingual-interlinear-css
threadId: codex-exec-gpt-5.4
rounds: 1
final_verdict: ship-as-is
date: 2026-06-02
---

# Codex audit — Bug #304 (bilingual interlinear CSS on modern engines)

Runner: cc-suite via `scripts/run-codex.sh` (watchdog — SUCCEEDED, no ghost),
gpt-5.4, medium, read-only.

## Round 1: NEEDS ATTENTION (1 Medium) → fixed

| file | sev | issue | resolution |
|---|---|---|---|
| ReadiumEPUBHost+BilingualDriver.swift:224 | Medium | `setStyle` ran only on inject; the bilingual surface didn't observe `settingsStore.theme`, so a theme switch WHILE bilingual was already rendered kept the old accent/sub colors (the comment over-claimed live-theme update). | **FIXED.** Added `.onChange(of: settingsStore.theme)` on the bilingual surface (mirrors the existing `epubLayout` hook) — when bilingual is enabled it re-calls `bilingualCommander.setStyle(theme.bilingualBlockCSSRule())`, matching the legacy bridge's reinject-on-theme-change parity. |

## Clean (no change needed)

- `bilingualStyleJS` escapes correctly for a single-quoted JS string
  (`FoliateJSEscaper.escapeForJSString`), writes via `textContent` (not HTML),
  uses a correct idempotent `getElementById`/`createElement` update — no
  duplicate `<style>`.
- Foliate `themeCSS` append (`compactMap` + `joined`) preserves the existing
  font-size/line-height CSS; harmless when no bilingual content (selector
  matches nothing).
- Readium inject ordering: `setStyle` before `inject`; both no-op when
  unbound; `setStyle` no-ops on empty CSS.
- The `.vreader-bilingual[data-vreader-decoration]` selector matches both
  engines' inject contract.

ship-as-is (Medium fixed; everything else clean).
