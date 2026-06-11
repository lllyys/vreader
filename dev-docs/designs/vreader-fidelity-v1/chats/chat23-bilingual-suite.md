# Vreader Bug Fixes

_Started 2026-06-11 01:46 UTC_

---

## User

https://github.com/lllyys/vreader/issues/1650 https://github.com/lllyys/vreader/issues/1646 https://github.com/lllyys/vreader/issues/1641 https://github.com/lllyys/vreader/issues/1640

## Assistant

_[tool: list_files]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: web_search]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_fetch]_

_[tool: web_search]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: web_fetch]_

_[tool: grep]_

_[tool: grep]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: read_file]_

_[tool: update_todos]_

_[tool: grep]_

_[tool: grep]_

_[tool: write_file]_

_[tool: write_file]_

_[tool: write_file]_

Now the artboards + canvas root file.

_[tool: write_file]_

_[tool: show_html]_

_[tool: write_file]_

_[tool: done]_

_[tool: fork_verifier_agent]_

_[tool: snip]_

_[tool: update_todos]_

**VReader Bilingual Suite Canvas.html** covers all four issues, one section each, with committed decisions written up in `design-notes/bilingual-suite-issues.md`:

- **#1650 heading translation** — canonical: a *centered echo* row (heading vocabulary — centered, tracked CJK serif, no border), with numeral/front-matter/long-heading edge cases, a loading shimmer, and the bordered treatment shown as rejected.
- **#1646 sentence granularity** — per-sentence rows one step lighter than the paragraph row (0.85×, 40-alpha border, tighter gaps) so the ¶ still reads as one block; side-by-side paragraph comparison, partial/loading states, plus the designed *disabled Sentence* control as the per-format fallback.
- **#1640 re-entry** — a "Translation settings" row in a tinted bilingual cluster in the More menu (canonical) + tappable pill (secondary), reopening the setup sheet edit-framed with cache badges, cost strips (new vs cached language, granularity), and the confirmed re-translating banner with the pill flipped to 日.
- **#1641 total reading time** — the trailing metrics label becomes a tap-to-cycle readout ("12m read · 6h 40m total"), with first-session/41h/narrow-width variants and Book-details rows as the always-on home. No new chrome.

Verifier is running in the background; caveat: cost figures (~$0.31) and time values are illustrative placeholders.

## User

Found issues — fixing…

## Assistant

_[tool: str_replace_edit]_

_[tool: str_replace_edit]_

_[tool: done]_

_[tool: fork_verifier_agent]_

Fixed all three: H4 artboard now 990px tall so the rejected H-C row is fully visible, the sheet title and context strip are forced to single lines, and the E5 banner's "p. 3 →" no longer wraps. Directed verifier is re-checking those spots now — I'll follow up if it flags anything.

## User

No issues found

## Assistant

Verified clean — all three fixes confirmed.

**VReader Bilingual Suite Canvas.html** is done: 22 artboards across four sections (#1650 heading echo, #1646 sentence rows, #1640 settings re-entry, #1641 reading time), with decisions documented in `design-notes/bilingual-suite-issues.md`. Only caveat: cost/time figures (≈$0.31, 6h 40m) are illustrative placeholders.

