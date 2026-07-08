---
branch: feat/feature-130-wi-2-contracts
threadId: 019f4252-2b18-7242-b8e0-9da21ac29a55
rounds: 2
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #130 WI-2 (contracts)

Auditor: cc-suite runner, gpt-5.5, read-only sandbox. Round 1 on thread
`019f4252-2b18-7242-b8e0-9da21ac29a55` (high effort); the round-2 resume
stalled at its 900s deadline (thread-replay cost), so round 2 ran as a FRESH
focused verification on thread `019f43f2-45fb-7490-842c-8d0ad8998fe2` per the
cc-suite no-verbatim-retry protocol.

## Round 1 — block-recommended

- **High**: `awk -F'|'` treated escaped `\|` pipes as delimiters — real rows
  (bugs #342-area, features row near line 132) shift Status/Notes fields; a
  dep edge could resolve against the wrong column. → Fixed (`9b1e5817`):
  sentinel-escaped splitting (`\|`→`\001`→restore), `ROW_NF_MIN=8` shape
  guard, asked-row malformed = exit 1 fail-closed, dep-row malformed =
  blocked. The stricter parser surfaced TWO real malformed tracker rows
  (features #78 missing Priority, bugs #210 missing Severity) — repaired;
  both trackers lint clean (rc=0).
- **High**: rule 55 lacked the normative HANDOFF JSON Schema → embedded
  (draft 2020-12, additionalProperties:false, enums, allOf conditionals).
- **High**: rule-48 cwd preamble referenced, not embedded → embedded verbatim.
- **High**: features.md Cross-links still mandated prose-only
  `Blocked by bug #N` (bypasses the dispatch gate) → now requires
  `Deps:[bug:#N]` at Notes head; prose demoted to commentary.
- **Mediums**: lint exit 3 on unreadable target; strict tokens (`Deps:[]`,
  trailing/double commas — IFS drops trailing empties, caught structurally);
  fixture coverage (+8 cases: escaped pipe, short row, empty/trailing-comma
  tokens, 29-vs-129 prefix isolation, gh-unavailable → BLOCKED UNKNOWN,
  non-numeric id, missing lint target). **Lows**: numeric-id guard (exit
  64); test harness mktemp guard. All fixed.

## Round 2 (fresh thread) — follow-up-recommended → closed

Verified resolved with citations: escaped-pipe parsing, schema, preamble,
all mediums/lows. Zero NEW Critical/High in the targeted sweep (sentinel
round-trip, `,,` guard, RESULT-line pattern). The single follow-up item was
that features.md sat outside the auditor's requested read scope — closed
here with the diff hunk from `9b1e5817`:

> `- …use TODO status with note 'Blocked by bug #N'.`
> `+ …use TODO status with **Deps:[bug:#N] at the HEAD of the Notes cell**
>  (the machine-readable form the dispatch gate resolves…); optional
>  'Blocked by bug #N' prose may follow… but prose alone does NOT gate
>  dispatch.`

## Test evidence

`scripts/__tests__/deps-check.test.sh` — 23 cases ALL PASS; both real
trackers lint clean; all active rows resolve READY (mechanical recount in
the PR body).
