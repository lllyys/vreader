---
kind: feature
id: 53
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude (verify-cron)
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4
build_configuration: Debug
backend: n/a (DebugBridge + --seed-md-toc / --seed war-and-peace fixtures)
result: partial
---

# Feature #53 round-7 — MD-format device verification (blocked on Bug #218)

## CORRECTION (2026-05-18, bugfix-cron — `/fix-issue #843`)

**Round-7's MD conclusion below is RETRACTED.** The observations are accurate;
the *interpretation* was wrong, and **Bug #218 / GH #843 — filed by this round
— is a misfile**, reclassified as a DUPLICATE of Bug #215 (GH #843 closed, "not
planned").

Round-7 concluded MD highlight *creation* has "no working UI affordance" and the
defect is "MD-container-specific". Bugfix-cron re-reproduced with the layout mode
controlled — `readerEPUBLayout=scroll` explicitly set before opening the book —
and MD body-text long-press **does** surface the feature-#60 `SelectionPopover`
(4 colour swatches + Note / Translate / Ask AI / Read), identical to TXT. MD
scroll mode routes body text through `TXTTextViewBridge`
(`MDReaderContainerView.swift:329`), the same producer (`editMenuForTextIn` swap,
`TXTTextViewBridgeCoordinator.swift:314-357`) and consumer
(`.selectionPopoverPresenter(theme:)`, `MDReaderContainerView.swift:107`) as TXT.
Feature-#60 WI-7c4's "producer shared implicitly" premise is **correct** for
scroll mode.

Why round-7 saw the bare system menu: the simulator carried
`readerEPUBLayout=paged` lingering from Bug #215's repro (round-7 did not reset
it). "Test Markdown TOC" therefore opened in **paged** mode
(`NativeTextPagedView`, `MDReaderContainerView.swift:66-70`), which renders body
text without a `TXTTextViewBridge` and so has no selection→popover producer. The
bare iOS system edit menu was MD *paged mode's* behavior — not a scroll-mode
regression. That missing-producer-in-paged-mode facet is a real gap, but it
belongs to **Bug #215** (MD paged mode `NativeTextPagedView` structurally
incomplete, `BLOCKED: needs-design #842`) and was appended to #215's row as a
scope facet.

Consequences for Feature #53:
- Criteria (a)/(b) for MD are **NOT blocked** — MD-scroll highlight creation
  works. The #53 MD slice IS verifiable in scroll mode; a future verify round
  should re-run it (open an MD book with `readerEPUBLayout=scroll`, create a
  highlight, tap it, confirm the inline Delete menu).
- The #53 `VERIFIED` flip is **NOT** gated on Bug #218. It remains gated on the
  MD-scroll re-verify + PDF device verify + Bug #199 (Foliate).

Lesson: verify-cron MD repros must explicitly set `readerEPUBLayout` before
observing selection / paging behavior — a layout mode left over from a prior
repro silently changes which renderer (and which producer wiring) is exercised.

*Everything below is the original round-7 record, preserved unchanged for the
audit trail. Its observations stand; its **conclusion** is superseded by this
CORRECTION.*

---

Round-4 (`feature-53-20260517-round4.md`) device-verified the **TXT** slice;
round-6 (`feature-53-20260518-round6.md`) verified the **EPUB** slice. Both
rounds left criterion (c) ("consistent across all 5 formats") open and listed
**MD** as deferred — "shares the TXT `HighlightableTextView` bridge ... not
separately exercised." This round picks up the MD slice.

The round-4/round-6 assumption that MD is covered "for free" by the shared TXT
bridge is **not borne out**. Verifying the MD slice surfaced a new bug — MD
highlight *creation* has no working UI affordance — which blocks #53's MD
criteria (a)/(b). Filed as **Bug #218 / GH #843**.

## Scope

MD format, criteria (a)/(b)/(d), using the `--seed-md-toc` TestSeeder launch
fixture (`DebugFixtureCatalog` ships no MD `seed` fixture — txt/epub/azw3 only).
Verification only: no code changed.

## Acceptance criteria

| # | Criterion | Result | Observed |
|---|-----------|--------|----------|
| (a) | Tapping a highlighted word shows a menu with at minimum a Delete option | **BLOCKED** | The precondition — an *existing* MD highlight — could not be created. Long-pressing MD body text (3× attempts, words "heading"/"first"/"extraction") selects the word but surfaces only the bare iOS system edit menu (Copy / Look Up / Translate / Search Web / Share). The feature-#60 `SelectionPopover` — which carries highlight creation — never appears. DebugBridge `highlightCount` stayed `0` throughout. With no MD highlight, the #53 tap-on-highlight path cannot be exercised. Filed as **Bug #218 / GH #843**. |
| (b) | Delete removes the highlight visually and from persistence | **BLOCKED** | Behind (a) — no MD highlight exists to tap or delete. |
| (c) | Consistent across all 5 formats | **NOT VERIFIED** | TXT passes (round-4); EPUB passes (round-6); **MD blocked by Bug #218**; PDF not exercised (`DebugFixtureCatalog` has no PDF fixture — harness gap); Foliate gated on Bug #199 / GH #733. |
| (d) | Tapping non-highlighted text preserves existing scroll/chrome-toggle behavior | **PASS** (#53-relevant assertion) | Tapped non-highlighted MD body text 3× → **no #53 inline menu appeared**. The #53-relevant assertion — a normal content tap must not spuriously surface the "Delete Highlight" menu — holds. (Observation, not a #53 verdict: the reader chrome did not visibly toggle on a content tap; MD's baseline tap-to-toggle behaviour was not separately characterised and is outside #53's scope — see Observations.) |

`result: partial` — criterion (d)'s #53-relevant assertion passes; criteria
(a)/(b) are **blocked** (not failed) by the newly-filed Bug #218; criterion (c)
remains open. Feature #53 stays `DONE`.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62   # iPhone 17 Pro, iOS 26.4

# merged-main v3.27.25 build (8cab12a) already installed (preserve data)
xcrun simctl terminate "$SIM" com.vreader.app
xcrun simctl launch    "$SIM" com.vreader.app --uitesting --seed-md-toc
xcrun simctl openurl   "$SIM" "vreader-debug://snapshot?dest=f53r7-library.json"

# UI (computer-use): open "Test Markdown TOC" → long-press body words ×3
xcrun simctl openurl   "$SIM" "vreader-debug://snapshot?dest=f53r7-final.json"
#   → highlightCount: 0  (no highlight created — SelectionPopover never appeared)

# Contrast check — TXT, same HighlightableTextView
xcrun simctl openurl   "$SIM" "vreader-debug://seed?fixture=war-and-peace"
# UI: open war-and-peace → Contents → Chapter 2 → long-press "Petersburg"
#   → the feature-#60 SelectionPopover appears (4 colours + Note/Translate/Ask AI/Read)

xcrun simctl io "$SIM" screenshot dev-docs/verification/artifacts/feature-53-r7-md-system-menu-no-popover-20260518.png
xcrun simctl io "$SIM" screenshot dev-docs/verification/artifacts/feature-53-r7-txt-selectionpopover-works-20260518.png
```

## Observations

- **The MD-vs-TXT contrast is the key finding.** Same build (8cab12a), same
  `HighlightableTextView`, same long-press gesture: TXT surfaces the feature-#60
  `SelectionPopover` (4 colour swatches + Note / Translate / Ask AI / Read, with
  the iOS system menu suppressed and the reader chrome hidden); MD surfaces the
  bare iOS system menu and no popover. So the defect is MD-container-specific,
  not a global `SelectionPopover` regression.
- Per the feature-#60 plan (`20260515-feature-60-visual-identity-v2.md`,
  WI-7c4), the MD `SelectionPopover` was "shipped v3.24.8 / PR #783" — WI-7c4
  attached `.selectionPopoverPresenter(theme:)` to `MDReaderContainerView` and
  assumed the producer-side `editMenuForTextIn` swap was "already shared via
  `TXTTextViewBridge` ... covered MD implicitly." The bare system menu shows
  that producer assumption is false for MD. Captured as Bug #218's root-cause
  hypothesis (for the fixer to confirm).
- WI-7c4 was an 8-line diff, Codex-audited (`019e2ef0`, 1 round) but — per the
  plan — device-verified only for TXT (WI-7c2's recipe), not for MD. This is
  exactly the gap a verification round exists to catch: a low-risk-looking WI
  whose "shares the bridge" assumption was never device-confirmed.
- Criterion (d) sub-note: the MD reader chrome did **not** visibly toggle on a
  single content tap. This is *not* classified as a #53 regression — #53
  (tap-on-existing-highlight) does not touch the normal-tap chrome path, and
  MD's intended baseline tap behaviour was not established this round (it may
  be by-design, or a separate issue). Not pursued — outside #53's scope and not
  confirmable without the MD reader's interaction design. A future MD-focused
  verification round should characterise it.
- This round did not exercise PDF (no DebugBridge fixture) or Foliate (Bug
  #199) — unchanged from round-6.

## Bug filed

- **Bug #218 / GH #843** — "Markdown reader — text selection shows the bare iOS
  system edit menu; the feature-#60 SelectionPopover never appears, so highlight
  / note / Translate / Ask-AI creation is impossible in the MD reader."
  `Reader/MD`, severity Medium, status `TODO`. Filed per the verify-cron
  discovered-bug protocol — **not fixed** this round; the bugfix cron owns the
  fix.

## Outcome

Feature #53 row stays **DONE**. The MD slice of criterion (c) is **blocked** on
Bug #218 (MD highlight creation has no working UI affordance — the precondition
for tapping an existing highlight cannot be established). Criterion (d)'s
#53-relevant assertion (no spurious menu on a normal tap) passes for MD.

The `VERIFIED` flip is now gated on: **Bug #218** (MD highlight creation) →
then MD device verify; **PDF** device verify (harness gap — no fixture);
**Bug #199 / GH #733** (Foliate inline-menu consumer wiring).

## Artifacts

- `dev-docs/verification/artifacts/feature-53-r7-md-system-menu-no-popover-20260518.png`
  — MD reader: long-press selects a word but shows only the bare iOS system
  edit menu; no `SelectionPopover`.
- `dev-docs/verification/artifacts/feature-53-r7-txt-selectionpopover-works-20260518.png`
  — TXT reader, same build/gesture: the feature-#60 `SelectionPopover` appears
  correctly (4 colour swatches + Note / Translate / Ask AI / Read). The
  expected behaviour MD is missing.
