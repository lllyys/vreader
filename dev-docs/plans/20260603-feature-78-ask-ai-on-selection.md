# Feature #78 — Ask-AI (and Read) on text selection

Wire the two dead selection-popover actions (`.askAI`, `.read`) — currently
`.deferredNotYetWired` on every reader engine — to real consumers.

## Problem

`SelectionPopoverView` surfaces "Ask AI" and "Read" buttons on every engine
(designed in `vreader-reader.jsx`), but `SelectionPopoverActionRouter.route`
returns `.deferredNotYetWired(action)` for `.askAI` and `.read` — the buttons
render but do nothing. Users select text, tap "Ask AI", and nothing happens.
Expected: "Ask AI" opens the AI panel's Chat tab seeded with the selected text;
"Read" reads the selection aloud via TTS.

## Surface area (file-by-file)

### WI-1 — Router wiring + notifications (foundational)
- `vreader/Views/Reader/ReaderNotifications.swift` — add
  `static let readerAskAIRequested = Notification.Name("vreader.readerAskAIRequested")`
  and `static let readerReadAloudRequested = Notification.Name("vreader.readerReadAloudRequested")`.
- `vreader/Views/Reader/SelectionPopoverActionRouter.swift` — `.askAI` →
  `post(.readerAskAIRequested, object: selection, userInfo: token)` →
  `.dispatched(.readerAskAIRequested)`; `.read` → `post(.readerReadAloudRequested, …)`
  → `.dispatched(.readerReadAloudRequested)`. Update the "Deferred actions" doc
  block (no longer deferred). No more `.deferredNotYetWired` is returned by
  `route` — but KEEP the `Result.deferredNotYetWired` case (still the honest
  fallback shape, and removing an enum case is a breaking churn with no gain).

### WI-2 — Ask-AI consumer: open AI Chat seeded with the selection (behavioral)
- `vreader/ViewModels/AIChatViewModel.swift` — add `var seededInput: String?`
  (an `@Observable` one-shot field) + `func seedInput(_ text: String)`. Seeds the
  INPUT (does NOT auto-send). Mirrors `AITranslationViewModel.originalText`.
- `vreader/Views/AI/AIChatView.swift` — consume `seededInput` via a single
  `applySeedIfPossible()` invoked from BOTH `.onAppear` AND on change
  (`.task(id: viewModel.seededInput)` or an `.onChange`) — **Gate-2 round-2 High:
  the seed is set BEFORE `AIChatView` mounts and `AIReaderPanel` only selects
  `.chat` on `onAppear` (`AIReaderPanel.swift:97,160`), so an `.onChange`-only
  consumer misses the FIRST seed and the panel opens on Chat with an empty
  input.** `applySeedIfPossible()` (Gate-2 Medium-4 — active-draft case): if
  `seededInput` is non-nil and the local `inputText` is empty → set
  `inputText = seededInput` + focus; if a draft already exists → DROP the new
  seed (don't clobber the draft). **Either branch clears `viewModel.seededInput = nil`
  immediately** so a pending seed can never linger and inject later.
- `vreader/Views/Reader/ReaderContainerView.swift` — add the
  `.onReceive(.readerAskAIRequested)` observer **INLINE** (Gate-2 Medium-1: do
  NOT copy `ReaderOpenAITranslateObserver`, which snapshots the optional VM by
  value *before* `ensureAIReady()` and would drop the seed on a cold first tap).
  - **AI available**: `ensureAIReady()`, THEN read `resolvedAICoordinator.chatViewModel?.seedInput(info.selectedText)`
    (fetch AFTER ensureAIReady so the just-created VM is seeded), `aiInitialTab = .chat`,
    `showAIPanel = true`.
  - **AI NOT available** (Gate-2 High-2 — preserve the seed across readiness):
    store host state `pendingAskAIText = info.selectedText`, set `aiInitialTab = .chat`
    BEFORE presenting readiness, then `pendingOpenAIPanelAfterReadiness = true` /
    `showAIReadiness = true`. The readiness `onDismiss` path opens the panel; the
    Ask-AI seed is applied when the panel opens / the chat VM is created — add a
    `pendingAskAIText` drain at panel-open (`onChange(of: showAIPanel)` true →
    `ensureAIReady()` → `chatViewModel?.seedInput(pendingAskAIText)`; clear it).
  - New host state: `@State var pendingAskAIText: String?` in ReaderContainerView.
  - **Gate-2 round-2 Medium — `pendingAskAIText` must not linger**: (a) on the
    AI-available path, set `pendingAskAIText = nil` defensively before seeding the
    fresh request; (b) in the readiness `.sheet(onDismiss:)` (currently only
    handles `pendingOpenAIPanelAfterReadiness`, `ReaderContainerView.swift:370`),
    clear `pendingAskAIText` whenever the dismissal does NOT hand off to the panel
    (readiness abandoned) — so a stale seed can't be drained into a later manual
    AI open or override a fresh selection. The panel-open drain consumes-then-nils.
    **(Gate-2 round-3 Medium, accepted + incorporated)**: on that same non-handoff
    readiness dismissal, ALSO restore `aiInitialTab = .summarize` — otherwise the
    `.chat` tab set before readiness lingers and a later manual AI open lands on
    Chat instead of the default Summarize. (The host only resets the tab on
    AI-sheet dismissal, which doesn't fire for an abandoned readiness flow.)
  - If the body's type-inference budget is hit, extract a `ViewModifier` that
    takes a `() -> AIChatViewModel?` **closure** (resolved post-`ensureAIReady`),
    NOT an optional snapshot.

### WI-3 — Read consumer: TTS from the selection (behavioral, final)
- **No new TTS API** (Gate-2 Medium-3): `TTSService` already exposes
  `startSpeaking(text:fromOffset:)` for an arbitrary string; its pinned behavior
  is "starting while speaking restarts," so a selection read **preempts any
  in-progress book-reading TTS with no resume** — accept this explicitly (it's
  the existing contract) and test it; do NOT add session/resume work in this WI.
- `vreader/Views/Reader/ReaderContainerView+Sheets.swift` (the existing TTS
  host) — observe `.readerReadAloudRequested` → `ttsService.startSpeaking(text: info.selectedText, fromOffset: 0)`.

### Engines / surfaces OUT of scope (Gate-2 High-1)
- **PDF (`PDFReaderContainerView`), Foliate-AZW3 (`FoliateSpikeView+Selection`),
  and MD *paged* mode are NOT on the `SelectionPopoverPresenter` pipeline at all**
  — they do not surface the shared popover, so `.askAI`/`.read` cannot ride this
  wiring there. Migrating those selection UIs onto `SelectionPopoverPresenter` is
  a separate prerequisite feature, NOT part of #78. #78 covers the engines
  already on the pipeline: **TXT, MD (scroll), legacy native EPUB, Readium-EPUB.**

### Files OUT of scope
- The per-engine long-press → popover plumbing for the in-scope engines (already
  routes through `SelectionPopoverActionRouter` for `.highlight/.note/.translate`
  — `.askAI/.read` ride the same path once the router posts).
- `SelectionPopoverView` / `SelectionPopoverActionRow` (buttons already exist).
- The AI readiness flow internals (#82, reused as-is).
- Bug #303 (the Note half / Readium regression) — separate.

## Prior art / precedent / rejected alternatives
- **Precedent**: `.translate` → `.readerTranslateRequested` → ReaderContainerView
  consumer that seeds `translationViewModel.originalText` + opens the panel. WI-2
  is the same shape onto the Chat tab. The `.readerOpenAITranslate` ViewModifier
  is the precedent for keeping the body under the type-inference budget.
- **Rejected — auto-send the question**: seeding + auto-`sendMessage` would fire
  an AI call the user didn't confirm (cost + intent). Seed the INPUT only.
- **Rejected — a bespoke "ask about selection" sheet**: the design routes Ask-AI
  to the existing AI Chat tab; no new surface (Rule-51 clean).
- **Rejected — removing the `Result.deferredNotYetWired` case**: churn with no
  gain; it stays as the honest fallback shape.

## Work-item sequencing
- **WI-1** (foundational) — router + notifications + router tests. ~small PR.
- **WI-2** (behavioral) — Ask-AI consumer + chat seed + view pre-fill. ~medium PR.
- **WI-3** (behavioral, final) — Read/TTS consumer. ~small-medium PR.

WI-2 and WI-3 are independent consumers; either could be the final WI. Sequence
WI-3 last (it completes both popover actions).

## Test catalogue
- `SelectionPopoverActionRouterTests` — extend: `.askAI` dispatches
  `.readerAskAIRequested` (was deferred); `.read` dispatches
  `.readerReadAloudRequested`; token rides `userInfo` when present.
- `SelectionPopoverPresenterTests` (Gate-2 Medium-2) — the existing tests pin
  `.deferredNotYetWired(.askAI/.read)` as "keep the sheet open" via
  `SelectionPopoverDismissPolicy`. Update them: `.askAI`/`.read` now `.dispatched`
  → the dismiss policy dismisses the sheet like the other dispatched actions.
  This is the REAL consumer of `Router.Result`, not a "not-wired affordance".
- `AIChatViewModelTests` — `seedInput` sets `seededInput`; seeding does NOT
  auto-send; consumption clears `seededInput` (one-shot).
- `AIChatView` seed consumption (Gate-2 Medium-4 + round-2 High) — seed applies
  when `inputText` is empty; a seed arriving with a non-empty draft is DROPPED
  (draft preserved) AND `seededInput` is cleared either way; **and a seed already
  set BEFORE the Chat view first appears is consumed on mount** (`.onAppear` /
  `.task(id:)`, not `.onChange`-only) so the first Ask-AI doesn't open on an empty
  Chat.
- `pendingAskAIText` lifecycle (Gate-2 round-2 Medium + round-3 Medium) —
  abandoning the readiness sheet (dismiss without handoff) clears `pendingAskAIText`
  AND restores `aiInitialTab = .summarize`, so a later manual AI open lands on
  Summarize with no stale seed; the AI-available path nils `pendingAskAIText`
  before seeding fresh. (Test: `Ask AI → readiness shown → dismiss without ready
  → later manual AI open lands on Summarize, empty input`.)
- Ask-AI consumer behavior: `.readerAskAIRequested` with AI available seeds the
  chat (VM fetched AFTER `ensureAIReady` — cold-first-tap, Gate-2 Medium-1) +
  targets `.chat`; with AI UNavailable stores `pendingAskAIText`, targets `.chat`
  before readiness, and drains the pending seed when the panel opens (Gate-2
  High-2 — seed survives the readiness handoff).
- TTS (Gate-2 Medium-3): `.readerReadAloudRequested` calls
  `startSpeaking(text:fromOffset:)`; **a selection read while a book TTS session
  is active preempts it and does NOT resume** (pin the existing contract).
- Edge cases: empty selection (no-op), whitespace-only, very long selection
  (whole seed), CJK selection, rapid double-tap (one-shot seed clears).

## Risks + mitigations
- *Risk*: SwiftUI body type-inference budget in ReaderContainerView (already near
  the limit — note the existing `.modifier(ReaderOpenAITranslateObserver)`).
  *Mitigation*: extract the Ask-AI observer into its own `ViewModifier`.
- *Risk*: `.read` TTS-from-selection conflicting with an in-progress book-reading
  TTS session. *Mitigation*: scope the selection read as a one-shot utterance;
  if a session is active, define precedence (pause/resume or ignore) in WI-3 and
  test it.
- *Risk*: seeding the chat input while a conversation already has messages.
  *Mitigation*: seed the INPUT field only (never the history); only when the
  input is empty.

## Backward compat
Pure additive wiring — two new notifications + one new `@Observable` field. No
schema, persistence, or migration. Older callers of `route(...)` that switched on
`.deferredNotYetWired` for `.askAI/.read` will now see `.dispatched` — but the
only caller is `SelectionPopoverPresenter`, which uses the result to show a
"not wired" affordance; that affordance now correctly never fires for these two.

## Acceptance criteria (from the row + plan)
1. Tapping "Ask AI" on a selection — on the engines already on the
   `SelectionPopoverPresenter` pipeline (**TXT, MD-scroll, legacy native EPUB,
   Readium-EPUB**; PDF / Foliate-AZW3 / MD-paged are out of scope per Gate-2
   High-1) — opens the AI panel's **Chat** tab with the selected text seeded into
   the input (not auto-sent).
2. With AI unconfigured, "Ask AI" routes to the readiness sheet AND the selected
   text survives the handoff (seeded into Chat once the panel opens) — no silent
   drop, no lost seed (Gate-2 High-2).
3. Tapping "Read" reads the selected text aloud via TTS, preempting any active
   book-reading TTS (no resume — the existing `startSpeaking` contract).
4. The router no longer returns `.deferredNotYetWired` for `.askAI`/`.read`; the
   dismiss policy dismisses the popover for both (Gate-2 Medium-2).
5. No regression to `.highlight`/`.note`/`.translate` routing.

## Revision history
- **v1** (2026-06-03) — initial plan.
- **v2** (2026-06-03) — Gate-2 Codex audit round 1 (`/tmp/feat78-planaudit.txt`,
  `RUN-CODEX RESULT: SUCCEEDED`): **2 High + 4 Medium, all addressed.**
  - High-1 (scope overclaim — PDF/Foliate/MD-paged not on the popover pipeline) →
    narrowed acceptance #1 + added an explicit "Engines OUT of scope" section.
  - High-2 (unconfigured Ask-AI loses the seed across readiness) → added
    `pendingAskAIText` host state + `.chat` tab before readiness + a panel-open
    drain.
  - Medium-1 (`ReaderOpenAITranslateObserver` value-capture drops the seed on
    cold tap) → inline observer / closure that fetches the VM AFTER `ensureAIReady`.
  - Medium-2 (Result consumer is `SelectionPopoverDismissPolicy`, not a "not-wired
    affordance") → added `SelectionPopoverPresenterTests`/dismiss-policy coverage.
  - Medium-3 (TTS already has `startSpeaking(text:)`, preempts no-resume) → WI-3
    uses it + pins the preempt-no-resume contract; no new API/resume work.
  - Medium-4 (draft-collision / lingering seed) → explicit one-shot consumption
    (drop on active draft, always clear `seededInput`).
- **v3** (2026-06-03) — Gate-2 round 2 (`/tmp/feat78-planaudit-r2.txt`): round-1's
  6 findings → 4 resolved, **2 new refinements** raised + addressed in v3:
  - round-2 High (the seed is set before `AIChatView` mounts; `.onChange`-only
    misses the first seed) → consume via `applySeedIfPossible()` from `.onAppear`
    + change (`.task(id:)`), with a "seed set before first appear" test.
  - round-2 Medium (`pendingAskAIText` lingers if readiness is abandoned) → clear
    it on non-handoff readiness dismissal + nil-before-fresh-seed, with a lifecycle
    test.
- **v4 / Gate-2 CLOSED** (2026-06-03) — Gate-2 round 3 (`/tmp/feat78-planaudit-r3.txt`):
  both round-2 items confirmed resolved; **1 new Medium** (stale `aiInitialTab = .chat`
  on readiness-abandon). Round-3 cap reached → per rule 47 disposition = **accept +
  incorporate** (a one-line corollary of the v3 abandon-cleanup: also reset
  `aiInitialTab = .summarize`; folded into the same block + a lifecycle test). The
  finding sequence converged cleanly (6 → 2 → 1, each a smaller corollary of the
  prior fix), and the residual is mechanical, not a design impasse — so it is
  accepted into the plan rather than escalated. **Gate 2 passes: 0 Critical / 0
  High / 0 genuinely-open Medium (the last accepted + incorporated).**
