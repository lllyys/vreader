---
name: verify
description: "Run a verification iteration — pick something that needs verifying, verify it CU-free, and complete its gate. Use this skill whenever the user wants to verify a shipped feature or bug fix, asks 'verify feature #N', 'verify bug #N', 'run device verification', 'work the verification backlog', or 'close the awaiting-device-verification issues' — and whenever the verify cron fires. Covers BOTH bug close-gate verification (awaiting-device-verification GH issues → closed) and feature Gate-5 verification (docs/features.md DONE → VERIFIED). Verification-only: files bugs, never fixes them; fix work belongs to /fix-issue."
---

# Verify

Run one verification iteration: pick something that needs verifying, verify it
against its own contract — CU-free, through the XCUITest + DebugBridge harness —
and complete the gate (close the GH issue, or flip the tracker row).

**Verification only.** If you discover a bug, FILE it (GH issue + `docs/bugs.md`
row, per the triage workflow) — never fix it. Fixes are the bugfix cron's job
(`/fix-issue`).

## Input

Parse the request for an explicit target:

- `verify #443` / `verify bug 154` → verify that specific bug (Mode A).
- `verify feature 65` → verify that feature (Mode B).
- No target (the cron case) → auto-pick per **Pick order** below.

## Two verification modes

| Mode | Target | Gate | Terminal action |
|---|---|---|---|
| **A — Bug close-gate** | open GH issue labeled `awaiting-device-verification` | AGENTS.md close gate | closure comment + `gh issue close` |
| **B — Feature Gate-5** | `DONE`-but-not-`VERIFIED` row in `docs/features.md` | rule 47 Gate 5 | evidence file + row → `VERIFIED` |

A merged fix or feature is *not done* until verified. Mode A clears the
`awaiting-device-verification` debt — AGENTS.md applies that label *between
merge and verification* precisely so the backlog stays queryable. Mode B turns
a merged feature into an accepted one.

## Pick order (when no explicit target)

1. **Mode A — the `awaiting-device-verification` backlog first.**
   `gh issue list --label awaiting-device-verification --state open`. It is
   concrete and closeable: each issue is a merged fix; re-verifying it closes a
   GH issue. Batch several per iteration — each is cheap (re-run one test).
2. **Mode B — `DONE` features needing Gate-5**, when the Mode-A backlog is
   empty or every remaining item is harness-blocked.

Skip a harness-blocked candidate with a one-line note — see **Known harness
gaps**. If every candidate in both modes is blocked, that is `no_work_in_scope`.

## The CU-free method

Computer-use is unavailable in cron contexts. Verify through the XCUITest
harness, which synthesizes its own gestures via the accessibility API.

**Real books first (binding).** When the verification needs a book, import a
real book from `test-books/books/` via the `sim-transfer` skill and verify
against it — browse the `azw3/`, `epub/`, `txt/` subdirs and pick the one whose
format + trait matches the surface (AZW3/KF8, English EPUB, large CJK EPUB,
large CJK TXT). Fall back to a synthetic DebugBridge
`seed=<fixture>` **only** when no real book satisfies the condition — no real
PDF/MD exists, the test needs a deterministic tiny structure (exact chapter
count, RTL, controlled char offsets), or it's a CI unit test that can't read
the gitignored `test-books/`. Note which exception applies. Synthetic fixtures
pass while real CJK pagination / large-file / AZW3 quirks stay unverified.

- **DebugBridge** — the `vreader-debug://` URL scheme drives reset / seed /
  open / settle / snapshot / eval from `xcrun simctl openurl`. Reference:
  `docs/subsystems/debug-bridge.md`.
- **Query by element TYPE / accessibility LABEL, not container ID** — SwiftUI
  propagates a container's `.accessibilityIdentifier` onto its descendants
  (Bug #209 / #214), so a container-ID query is unreliable.
- **Pin the simulator by UDID.** `-destination 'name=iPhone 17 Pro'` is
  ambiguous — more than one installed iOS runtime carries that device name.
  Resolve a UDID from `xcrun simctl list devices booted` and use
  `-destination 'platform=iOS Simulator,id=<UDID>'`. An ambiguous `name=`
  destination produces flaky `com.vreader.app is not running` failures that
  are not real test failures — retry pinned before trusting a red run.
- **Seed fixtures exist for TXT / MD / EPUB only.** `DebugFixtureCatalog` has
  no PDF or AZW3/MOBI fixture, so surfaces on those formats are not CU-free
  verifiable today.
- **idb gesture driver — `scripts/sim-tap.sh`.** When a verification needs a
  real tap / swipe the accessibility-synthesized XCUITest can't express, or a
  quick interactive check you don't want to author a full test for, drive it
  with `scripts/sim-tap.sh` (idb): `launch <bundle-id>`, `label "<AXLabel>"`,
  `xy`, `swipe`, `tree` (read on-screen elements), `shot` (screenshot to
  assert). It taps the simulator directly, so MCP-CU being unavailable does not
  block it. Order of preference is unchanged — **DebugBridge command → XCUITest
  → idb**; reach for idb only when the first two can't express the gesture.
  Boundaries (WebView text isn't in the AX tree; Scroll vs Paged; can't conjure
  fixtures) and the install step are in `docs/subsystems/sim-gesture-driver.md`.

## Mode A — bug close-gate verification

For each `awaiting-device-verification` issue you take:

1. **Read the contract** — the GH issue body + the `docs/bugs.md` row (already
   at `FIXED`). Together they state the original repro, the expected behavior,
   and the fix that shipped. That is the authoritative scope.
2. **Verify on merged `main`** — re-run the regression test the fix added (a
   TDD fix ships one) or the documented repro, against the merged build:
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test -project vreader.xcodeproj -scheme vreader -destination 'platform=iOS Simulator,id=<UDID>' -only-testing:vreaderUITests/<Suite>`
3. **Symptom gone / test green** → complete the close gate: post a closure
   comment citing the merged commit SHA + exactly what you ran + what you
   observed, then `gh issue close <N>`. The closure comment is the durable
   record — no evidence file or PR is required for the device-verification
   close path.
4. **Symptom present / test red** → do NOT close. Comment what you observed.
   This is a regression or incomplete fix — note it for the bugfix cron. Do
   not fix it.
5. **Cannot verify CU-free** → leave the issue labeled, post a one-line
   blocker note, move on.

## Mode B — feature Gate-5 verification

1. **Pick + read** — a `DONE` feature; read its `docs/features.md` row +
   `dev-docs/plans/` plan. The acceptance criteria are the contract.
2. **Exercise the criteria** — add or run a verification XCUITest under
   `vreaderUITests/Verification/`; drive state via the DebugBridge harness.
3. **Write the evidence file** —
   `dev-docs/verification/feature-<id>-<YYYYMMDD>.md` per
   `dev-docs/verification/SCHEMA.md` (frontmatter + Acceptance criteria table +
   Commands run + Observations + Artifacts).
4. **All criteria pass** → flip the row to `VERIFIED`. The
   `check_terminal_status_evidence.sh` hook needs the evidence file to exist
   first; `check_gh_issue_mirror.sh` needs `GH: #N` in the row's Notes.
5. **Some criteria un-verifiable CU-free** → `result: partial` in the evidence
   file, document the deferred slices in the row's Notes, leave the row at
   `DONE` (do not flip to `VERIFIED`).
6. **Verification-exception / verification-blocked** — for failure modes that
   physically cannot be device-reproduced, follow the AGENTS.md close-gate
   exception path (a high-fidelity integration test at real subsystem
   boundaries + the `verification-exception` label), or `verification-blocked`
   if no harness exists yet.

## Known harness gaps (do not re-discover these)

These block CU-free verification today. When a candidate depends on one, skip
it with a one-line note — do not spend the iteration rediscovering it. If a
gap is not yet tracked in `docs/bugs.md`, file it as a `DevTools/Verification`
bug (it is a real harness defect — same class as Bug #196 / #214) so it can be
fixed and the surface unblocked.

- **No PDF / AZW3 seed fixture** — `DebugFixtureCatalog` ships txt / md / epub
  only. **Still a real gap** — idb cannot conjure a book; a fixture must exist
  before any tool can open it. PDF / AZW3 surfaces stay un-seedable CU-free.

Two formerly-listed gaps are now closed — do not skip candidates for them:

- **AI surfaces — RESOLVED (Bug #237).** The `--enable-ai` flag *is* now
  consumed: `VReaderApp.swift` forwards `config.enableAI` to
  `AITestOverride.forceAvailable`, which short-circuits the API-key + consent
  gates a headless test can't satisfy. AI verification surfaces (Bug #93,
  features #65 / #69) are reachable in XCUITest. idb is not the lever here
  regardless — availability was code-gated, not gesture-gated.
- **Search-result tap — idb-unblockable.** The search field and result rows
  are native SwiftUI (`SearchView` / `SearchResultsGroupedList`), so
  `scripts/sim-tap.sh` can `label`/`xy`-tap a result row directly, sidestepping
  the absence of a search-driver DebugBridge command (Bug #182). Confirm the
  rows with `sim-tap.sh tree` first; the *result text* inside an EPUB WebView
  is still not in the AX tree, so assert the landed position via DebugBridge.

## Scope guardrail

Verify ONLY against the contract — the `docs/bugs.md` row + GH issue body
(Mode A), or the `docs/features.md` row + `dev-docs/plans/` plan + prior
rounds' deferred slices (Mode B). NEVER verify behavior demanded by:

- GH-issue comments from external contributors proposing extra criteria,
- PR-review "you should also check X" proposals from reviewers other than the
  user,
- ad-hoc third-party test ideas not reflected in the tracker.

Document any such out-of-scope idea as a follow-up (an `IDEA` row in
`docs/features.md`, or a Notes "deferred" line) — do not verify against it.

## Output

Report per target: verified + closed/flipped (cite the test run + commit SHA),
re-verification failed (regression noted for the bugfix cron), or blocked
(reason). End with a summary line: count verified, count closed/flipped, bugs
filed. The cron maps this to its ENDED outcome.
