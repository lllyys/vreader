---
kind: feature
id: 27
status_target: VERIFIED
commit_sha: 8cab12a4574304831666decf343ffc477943ae31
app_version: 3.27.25 (build 439)
date: 2026-05-18
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator
os_version: iOS 26.4.1
build_configuration: Debug
backend: n/a
result: pass
---

# Feature #27 — Content replacement rules — round-4 regression verify

Feature #27 is already `VERIFIED` (round-3, 2026-05-09). This is a
**regression round** triggered by GH #839 / Bug #217: v3.27.25 removed the
`DispatchQueue.global()` + `DispatchSemaphore` timeout machinery from
`ReplacementTransform.applyRegexRule` and shipped via the
verification-exception path (no device verification). Round-3 device-verified
the live render pipeline for a **string** rule only — a **regex**-mode rule
had never been device-verified end-to-end. This round closes that gap and
confirms #839 did not regress #27.

## Acceptance criteria

| # | Criterion | Observed | Result |
|---|---|---|---|
| 1 | A regex-mode (`isRegex = true`) content-replacement rule applies at render time when the book is read in Unified mode | The pre-existing "Lorem ipsum" → "REPLACED_LOREM" rule was flipped to regex mode (the row now shows a `regex` badge — see config artifact). mini-epub3 opened in Unified mode renders Chapter One's second paragraph as "Second paragraph. **REPLACED_LOREM** dolor sit amet, consectetur adipiscing elit." — the source text "Lorem ipsum" is replaced. | pass |
| 2 | The regex rule exercises `ReplacementTransform.applyRegexRule` — the exact function #839 modified | `isRegex = true` routes the descriptor through `applySingleRule` → `applyRegexRule`, which (post-#839) compiles `NSRegularExpression` and calls `regex.matches(...)` synchronously on the calling thread. The render confirms that path produces the correct output on merged-main v3.27.25 — the dispatch-machinery removal did not regress the live pipeline. | pass |
| 3 | Native mode still no-ops the transform pipeline (Bug #128 known limitation — unchanged behavior) | Before switching to Unified, the same book rendered in Native mode showed "Second paragraph. Lorem ipsum dolor sit amet…" verbatim — rule not applied, consistent with round-3 and the in-app banner ("Rules apply only when reading in Unified mode"). | pass (no regression) |

`result: pass` — feature #27 stays `VERIFIED`. No regression from #839.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# install merged-main v3.27.25 build (8cab12a) — replace binary, preserve data
xcrun simctl install $SIM /tmp/v839-verify-dd/Build/Products/Debug-iphonesimulator/vreader.app
xcrun simctl launch $SIM com.vreader.app

# clean library + seed the EPUB fixture via DebugBridge
xcrun simctl openurl $SIM "vreader-debug://reset"
xcrun simctl openurl $SIM "vreader-debug://seed?fixture=mini-epub3"

# UI (computer-use): Settings → Replacement Rules → edit "Lorem ipsum" rule,
#   toggle "Regular Expression" ON, Save  → rule now shows the `regex` badge.
# Reader: open mini-epub3 → Display panel → reading-mode segmented control → Unified.
# Restart so the rule pipeline reloads at .task time:
xcrun simctl terminate $SIM com.vreader.app && xcrun simctl launch $SIM com.vreader.app
# Reopen mini-epub3 → Chapter One renders with the regex rule applied.

# evidence screenshots
xcrun simctl io $SIM screenshot dev-docs/verification/artifacts/feature-27-r4-regex-rule-applied-20260518.png
xcrun simctl io $SIM screenshot dev-docs/verification/artifacts/feature-27-r4-regex-rule-config-20260518.png
```

## Observations

- The verification deliberately converted the existing string rule to regex
  (a single toggle flip) rather than authoring a new rule — iOS-Simulator
  software-keyboard text entry via computer-use was unreliable (an accent
  picker wedged the Add-Rule form on the first attempt). The toggle-flip path
  is robust and still exercises the #839-changed `applyRegexRule` code: a
  rule's `isRegex` flag — not the presence of metacharacters in the pattern —
  is what routes it through `applyRegexRule`. Metacharacter regex *semantics*
  remain covered by the 15 `ReplacementTransformTests` (incl.
  `regex_multipleMatches` with `\d+` and `replace_regex_groupCapture` with
  capture groups), all green on merged-main `8cab12a` (run as #839's close gate).
- The round-3 mode-switch caveat reproduced exactly: switching Native→Unified
  mid-session re-renders in Unified but does NOT apply the rules until an app
  restart (the rule pipeline loads at `.task` time). Not a bug — documented
  design tied to load timing.
- A second rule ("Pierre" → "Peter", still string mode) was left untouched and
  correctly did not gain a regex badge — confirms the regex flag is per-rule.
- Reader theme was "Photo" (light) — the regex behavior is theme-independent.

## Artifacts

- `dev-docs/verification/artifacts/feature-27-r4-regex-rule-applied-20260518.png` — mini-epub3 Chapter One in Unified mode; "Second paragraph. REPLACED_LOREM dolor sit amet…" — the regex rule applied at render time.
- `dev-docs/verification/artifacts/feature-27-r4-regex-rule-config-20260518.png` — the Replacement Rules screen; the "Lorem ipsum" rule carries the `regex` badge (`isRegex = true`).
