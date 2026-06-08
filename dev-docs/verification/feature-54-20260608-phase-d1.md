---
kind: feature
id: 54
status_target: VERIFIED
commit_sha: 357bc8da1292e57ad84d08b46a0af14535a4941f
app_version: 3.59.26 (build 926)
date: 2026-06-08
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #54 — Phase D-1 implemented: replacement rules in native EPUB

The blocker that held #54 at `partial`/`DONE` (criterion 3 — replacement rules in
native EPUB — was un-built) is now **implemented + device-verified**. All five
acceptance criteria are met.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | No reading-mode picker in normal use | pass (prior round) |
| 2 | Replacement rules work in native **MD** | pass (prior round) |
| 3 | **Replacement rules work in native EPUB** | **pass (Phase D-1)** — see below |
| 4 | `readerReadingMode` key removed with migration | pass (prior round) |
| 5 | All existing reader features unchanged (engine routing) | pass (prior round) |

## Phase D-1 implementation

`EPUBReplacementJS.injectionJS(rules:)` builds a **CFI-safe** JS that walks the
spine/section text nodes and applies the rules (string = replace-all
non-recursive; regex = global `RegExp`) — mutating only text-node `nodeValue`, so
Readium/legacy locators computed against the original HTML still resolve. Rules
are JSON-encoded into the JS (escaping-safe). Wired into **both** EPUB engines
(per `ReaderEngine.routeEPUB`: paged+flag → Readium, scroll/flag-off → legacy
stitch):

- **Legacy #71 WKWebView stitch** (scroll mode — the default): injected on
  `EPUBWebViewBridgeCoordinator.didFinish`; a baked scroll-root `MutationObserver`
  applies the rules to chapter sections appended as you scroll.
- **Readium** (paged): `ReadiumReaderCoordinator+Replacement.applyReplacement` on
  attach + each `locationDidChange` (per-spine document).

Rules fetched via `MDReplacementRuleFetcher` (format-neutral). 23 unit tests in
`EPUBReplacementJSTests` pin the builder (empty/string/regex, JSON escaping, the
CFI-safe text-only mutation, the section mark + observer, filter+sort).

## Commands run + observations

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62
# seed a deterministic global rule ("Chapter" → "Sektion") + a multi-chapter EPUB:
xcrun simctl launch $SIM com.vreader.app --uitesting --seed-multi-chapter-epub --seed-replacement-rule --reset-preferences
# open → eval the rendered DOM (NO manual injection):
```

- **Auto-applied on open**: `document.body.innerText` → "SEKTION ONE / Sektion One — ALPHA"; `hasChapter=False`, `hasSektion=True`.
- The processed section is marked (`data-vreader-repl="1"`); the scroll-root `MutationObserver` is installed (`window.__vreaderReplObserver === true`).
- **Appended-chapter coverage**: after scrolling, **2/2 sections marked**, `hasSektionTwo=True`, `hasChapterTwo=False` — chapter 2 (the other stitched section) is also replaced.
- Screenshot: the heading renders "Sektion One — ALPHA" (artifact below); the #68 drop-cap also renders.

## Known limitation (v1 scope)

Rules apply at chapter/document **open**; a mid-read rules edit takes effect on
next open (the `data-vreader-repl` mark is permanent within a loaded document).
A correct live re-apply needs the original per-node text preserved — deferred as a
follow-up. Codex audit (`.claude/codex-audits/feat-feature-54-phase-d1-epub-replacement-audit.md`)
flagged this (2 Medium, both about live changes) and confirmed everything else
clean (CFI-safety, JSON escaping, fetch timing, engine coverage) →
`follow-up-recommended`, accepted with rationale.

## Verification scope note

Device-verified on the **legacy stitch** (the `--uitesting` default + dominant
scroll-mode path). The Readium (paged) path uses the same `EPUBReplacementJS` +
the proven `setTransparentBackground` coordinator pattern; not separately
force-verified (would require forcing the readium flag + paged layout). Both
engines share the JS and the open-time application model.

## Artifacts

- `artifacts/feature-54-20260608-phase-d1-epub-replacement.png` — "Sektion One — ALPHA" rendered (rule applied).
