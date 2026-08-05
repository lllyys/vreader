---
branch: feat/156-wi-3-azw3-justify
threadId: 019fd32e-61c5-74e0-a40a-0721b7981ae1
rounds: 3
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #156 WI-3 (AZW3 justify via the foliate CSS seam)

Auditor: Codex `gpt-5.5`, reasoning `high`, read-only sandbox, via `scripts/run-codex.sh` (rule 53).
Author/auditor separation preserved (rule 48): the implementing session never marked its own work.

| Round | Session id | Findings | Verdict |
| --- | --- | --- | --- |
| 1 | `019fd306-559d-7243-a219-64bf404a6d54` | 1 High, 1 Medium, 3 Low | — |
| 2 | `019fd31a-f1cf-7500-8114-db70887870bf` | 1 Medium, 1 Low (round-1 High/Medium closed) | block-recommended |
| 3 | `019fd32e-61c5-74e0-a40a-0721b7981ae1` | 2 Low (round-2 Medium/Low closed) | **follow-up-recommended** |

Zero Critical across all three rounds. Every High/Medium was fixed and re-verified on the emulator;
the round-3 Lows were also fixed rather than accepted, so nothing is left open.

## Round 1

**High — the control arm was not guaranteed to be "production CSS minus one rule."**
It was rebuilt from `ReaderSettings().foliateDisplayCss()`, which equals the injected CSS *only* when
the persisted display settings happen to be the defaults. Under any other settings the control would
also have changed font size, margin, line-height and family — and those change **line breaking**, so
the index-wise line comparison between the two arms would have been differencing two different
layouts while reporting the result as a justification delta.
*Fixed*: the probe now returns every injected `<style>` element's text; the control is derived from
the **live** blob. Re-measured — the numbers are byte-identical, which confirms the settings were in
fact defaults here, but the test no longer depends on that being true.

**Medium — the heading half of AC-7 could pass with zero headings.** The loop over `headings` never
required a non-empty list, so a section with no `h1..h6` satisfied "headings do not justify" without
reading a single computed style. *Fixed*: asserts at least one heading was measured (observed: 1).

**Low — the CSS guards were case-sensitive.** CSS attribute matching is case-sensitive without the
` i` flag, so `style="TEXT-ALIGN:center"` / `class="Center"` — real shapes in converted Kindle markup
— would have been force-justified. *Fixed*: every value guard carries ` i`; `[align]` stays a bare
presence check (no value to case-fold). Single quotes keep the blob free of the double quotes
`cssHasNoInjectionBreakers_fromSettingsDerivedValues` pins.

**Low — file size.** Geometry + live-CSS helpers moved to `Azw3ProbeSupport.kt`; the probe is 299
lines. `Azw3JustifyConnectedTest.kt` remains large; round 2 explicitly judged that "defensible as a
focused connected evidence harness" (repo precedent: WI-1's 796-line `TxtJustificationConnectedTest`).

**Low — dead code** in the screenshot harness (an unread `polls` counter, and `tapNextZone`/`preTaps`
once AZW3 capture settled on zero taps). *Fixed*: removed, and the two navigation limits are now
stated in the file rather than implied.

## Round 2 — the finding worth the whole audit

**Medium — `[class*='right']` also matches `copyright`.** Every `<p class="copyright">` was silently
exempted from justification: ordinary front-matter prose, left ragged, with nothing to indicate a
paragraph had been skipped. The defect is **inherited from the iOS #95 guard shape**, not introduced
here — the ` i` flag added in round 1 only made it legible.
*Fixed*: the right guard is a **token** match plus explicit alignment-shaped patterns
(`~='right'`, `text-right`, `align-right`, `right-align`). `center` deliberately stays a substring
match: no comparably common word contains it, so the asymmetry is a false-positive judgement rather
than an oversight. Proven in the **live engine** rather than asserted about the CSS string — the
guard probe now carries the counter-case alongside the shapes that must stay exempt.

**Low — the live blob was identified by a content signature**, which a publisher stylesheet could
imitate (making the helper throw, or select the book's blob instead of ours). *Fixed*: production
emits `VREADER_CSS_SENTINEL = /* vreader-display-css:v1 */`, an inert CSS comment, and
`liveVreaderCss()` selects on it requiring exactly one match. Round 3 confirmed a first-line comment
is safe with foliate — `setStyles` writes the string into a `<style>` via `textContent`, so it
changes neither parse behaviour, cascade order, determinism, nor JS escaping.

## Round 3

**Low — no-hyphen right-alignment classes were under-exempted** (`alignright` / `rightalign`, as
plain HTML/CSS exports emit). *Fixed*: both added to the guard set and to the live probe.

**Low — a stale unused `ReaderSettings` import.** *Fixed*.

Round 3 explicitly cleared the remaining questions it was asked: no realistic blocking false positive
from the `center` substring; no new stale/absent/zero-glyph false-green path, because the connected
test requires settled arm state, non-empty computed values, the same element across arms, line-count
equality, per-column right-edge collapse, and a Latin movement control.

## Guard state after the audit — measured in the live Chromium DOM on the real book

| Probe paragraph | Computed `text-align` | Meaning |
| --- | --- | --- |
| plain prose | `justify` | the feature |
| `class="copyright"` | **`justify`** | the round-2 fix; a substring guard left this `start` |
| `style="text-align:left"` | `left` | exempt |
| `style="TEXT-ALIGN:center"` | `center` | exempt — the ` i` flag |
| `align="center"` | `-webkit-center` | exempt |
| `class="center"` | `start` | exempt |
| `class="align-right"` | `start` | exempt |
| `class="alignright"` | `start` | exempt — the round-3 fix |

## Carried-forward limitation (unchanged by this audit)

The guards remain **heuristics**, exactly as iOS #95 shipped them and as plan R7 records: a paragraph
the book centres through a *stylesheet class whose name contains no alignment word* is still
force-justified. The real fixture exercises this — its centred front-matter class is `.yingwen`,
which no guard matches. Narrowing that would require reading the book's own cascade, which is out of
scope for #156.

## Verification after the final fix

- Connected `Azw3JustifyConnectedTest` — **3 tests, 0 failures, 0 skipped** (re-run after every
  audit-driven code change; four times in total).
- JVM `:app:testDebugUnitTest` — **2303 tests, 0 failures, 0 skipped**.
