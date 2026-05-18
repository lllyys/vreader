# Feature #65 — AI sheet tab-body re-skin — Summarize / Chat / Translate contents — implementation plan

- **Feature row**: `docs/features.md` #65 (TODO)
- **GH issue**: #823
- **Design source** (committed, rule 51 satisfied):
  `dev-docs/designs/vreader-fidelity-v1/project/vreader-panels.jsx` —
  `AISheet` (~446-510), `SummaryView` + `chipBtn` (~512-599),
  `ChatView` + `ChatBubble` (~601-709), `TranslateView` (~711-805).
- **Author**: feature-cron (Gate 1), 2026-05-18
- **Status**: v2 — revised after the Gate-2 round-1 Codex audit
  (thread `019e3b84`). The audit findings + resolutions are in §8.
- **Lineage**: v2 follow-on of feature #60 (VERIFIED). Component re-skin
  audit finding — #60 re-skinned the AI sheet *chrome* (WI-10) but never
  the three tab *bodies*.

## 1. Problem

The AI sheet's chrome is v2: `AIReaderPanel.swift` is wrapped in
`ReaderSheetChrome` + the custom `AIReaderPanelHeader` (feature #60
WI-10). But the **three tab bodies are still pre-v2 native UI**:

- **Summarize** (`AIReaderPanel.swift:152-318`) — a plain `sparkles`
  glyph + `.borderedProminent` button (idle); a bare `ScrollView { Text }`
  + native button (complete). No accent-bordered summary card, no
  Share/Regenerate chip footer.
- **Chat** (`AIChatView.swift`) — `ChatBubbleView` uses
  `Color.blue.opacity(0.15)` / `Color.secondary.opacity(0.1)` bubbles, a
  plain `TextField` + `arrow.up.circle.fill` send button. No accent user
  bubbles, no sparkle-avatar assistant rows, no pill input field.
- **Translate** (`TranslationPanel.swift` → `BilingualView.swift`) — a
  native menu `Picker` + `.borderedProminent` button; a plain-text
  `BilingualView`. No language pill rail, no accent-tinted translation
  card.

The committed design (`vreader-panels.jsx`) specifies the full v2
treatment. **This feature is a pure view-layer re-skin** — it changes no
request/response contract, no view model state, no persisted data. It
matches the design's visual treatment and *omits* the design's
unbacked controls per the established omit-don't-fake discipline (§2).

## 2. Scope — what the design shows vs what #65 ships

The committed design depicts several controls that have no production
backing. Per rule 51 and the feature-#63 precedent (which omitted the
"All books" scope toggle, "Recent searches", and syntax-hint chips
rather than ship fake controls), #65 **omits each unbacked control** and
files a follow-up rather than faking it. The Gate-2 audit confirmed
every omission below.

| Design element | Disposition |
|---|---|
| Summarize: accent-bordered summary card (sparkle label, serif body) | **IN — re-skin (WI-1)** |
| Summarize: Regenerate chip | **IN — re-skin of the existing re-run (WI-1)** |
| Summarize: Share chip | **IN — presents `ShareActivityView` with the summary text (WI-1)** |
| Summarize: idle / loading / error / disabled / consent / streaming states | **IN — re-skin to v2 tokens (WI-1)** |
| Summarize: scope chips (Section / Chapter / Book so far) | **OUT — see §2.1** |
| Summarize: Save chip | **OUT — no summary-persistence store (§2.2)** |
| Summarize: suggested-questions list | **OUT — no question-generation service (§2.2)** |
| Chat: accent user bubble / sparkle-avatar assistant row | **IN — re-skin (WI-2)** |
| Chat: pill input field | **IN — re-skin (WI-2)** |
| Chat: seeded greeting / quoted-context message | **OUT — behavior + a `ChatMessage.quoted` model change (§2.2)** |
| Translate: language pill rail | **IN — re-skin of the menu `Picker` (WI-3)** |
| Translate: original + accent-tinted translation cards | **IN — re-skin (WI-3)** |
| Translate: "Speak" button | **OUT — TTS-in-AI-sheet integration (§2.2)** |
| Translate: "Notes on the translation" card | **OUT — a second AI output / contract change (§2.2)** |

### 2.1 — Summarize scope chips — OMITTED, carved to a follow-up feature

`SummaryView` (jsx ~514-532) renders three scope chips (Section /
Chapter / Book so far). The Gate-2 audit established that making these
genuinely functional is a real behavior feature, **not a re-skin**:

- The current Summarize path has **no scope concept** —
  `AIAssistantViewModel.summarize(...)` takes no scope, and
  `AIContextExtractor` always extracts a fixed ~2500-char window around
  the locator.
- v1 of this plan proposed threading a scope string through
  `AIRequest.userPrompt`. The audit rejected this: both providers
  (`AIProvider.swift`) append `userPrompt` to the request body as a
  `Question: …` (QA-flavored) string, so a scope passed that way would
  corrupt the summarize request shape **and** still summarize the same
  text for all three chips — a chip that says "Book so far" but does not
  see the book is a dead/lying control.
- Doing it honestly means a scoped `AIContextExtractor` (Section = the
  current window; Book-so-far = a token-capped prefix of
  `loadedTextContent` up to the locator; Chapter = a chapter-bounded
  window, which needs TOC boundary data threaded into the AI path) plus
  a token-budget strategy for the larger scopes. That is a self-
  contained AI-context feature.

**Decision: #65 omits the scope-chip row.** The re-skinned
`AISummaryTabView` ships the summary card + states without the chips.
A new feature row — **"AI Summarize scope selector (Section / Chapter /
Book so far)"** — is filed for the scoped-extraction behavior; its UI is
already designed (the chips in `vreader-panels.jsx`), so it is
design-ready and only needs the behavior. WI-1 adds that row to
`docs/features.md`.

### 2.2 — Other omitted controls

- **Save chip** — VReader has no saved-summaries store; persistence is a
  new capability. Omitted. Follow-up `IDEA`: "AI Summarize — save
  summaries to a per-book collection".
- **Suggested-questions list** — the design's three questions are
  hardcoded sample strings; there is no question-generation service, and
  (audit finding) no free "hand off to Chat" path exists (`selectedTab`
  is private `@State`, `AIChatView.inputText` is private with no prefill
  API). Omitted. Follow-up `IDEA`: "AI Summarize — generated suggested
  questions".
- **Translate "Speak" button** — wiring TTS to speak an arbitrary
  translated string in an arbitrary language is a non-trivial
  integration, not a re-skin. Omitted. Follow-up `IDEA`.
- **Translate "Notes on the translation" card** — the translation
  contract returns one string; a notes field is a second AI output.
  Omitted. Follow-up `IDEA`.
- **Chat seeded greeting / quoted-context message** — `AIChatViewModel`
  starts with empty `messages`; `ChatMessage` has no `quoted` field.
  Seeding is behavior; `quoted` is a model change. Omitted; the re-skin
  keeps the existing empty-state and `messages`-driven list.

Everything #65 ships (the IN rows) is a pure view-layer re-skin, with
**one** small correctness change the re-skin's interaction model
requires: the Translate language rail fires translation on selection
(the design has no separate Translate button), so `AITranslationViewModel`
gains in-flight cancellation (§3, WI-3) — without it, rapid pill taps
race and a stale response can overwrite the newest selection.

## 3. Surface area — file by file

### New files

All new view files are `#if canImport(UIKit)`-gated (matching the
existing AI views). Each stays under the ~300-line guideline.
Symbol-collision check (Gate-2 confirmed): none of `AISummaryTabView`,
`AISummaryCard`, `AIChatMessageRow`, `TranslateLanguageRail`,
`TranslationResultCard` collide with an existing symbol.

- `vreader/Views/Reader/AISummaryTabView.swift` — the re-skinned
  Summarize tab body, extracted from `AIReaderPanel.swift`:
  ```swift
  /// The re-skinned Summarize tab body — design vreader-panels.jsx
  /// `SummaryView` (summary card + states; scope chips and
  /// suggested-questions omitted, plan §2).
  struct AISummaryTabView: View {
      @Bindable var viewModel: AIAssistantViewModel
      let locator: Locator
      let textContent: String
      let format: BookFormat
      let theme: ReaderThemeV2
      var onShare: (String) -> Void
      var body: some View { … }
  }
  ```
- `vreader/Views/Reader/AISummaryCard.swift` — the accent-bordered
  summary card: sparkle uppercase label, serif body text, a
  Share + Regenerate chip footer (Save omitted):
  ```swift
  struct AISummaryCard: View {
      let summaryText: String
      let theme: ReaderThemeV2
      var onRegenerate: () -> Void
      var onShare: () -> Void
      var body: some View { … }
  }
  ```
- `vreader/Views/AI/AIChatMessageRow.swift` — the two re-skinned chat
  bubble forms (accent user bubble with an asymmetric corner; sparkle-
  avatar + serif assistant/system row). Extracted to its own file so
  `AIChatView.swift` stays under the line guideline:
  ```swift
  struct AIChatMessageRow: View {
      let message: ChatMessage
      let theme: ReaderThemeV2
      var body: some View { … }
  }
  ```
- `vreader/Views/Reader/TranslateLanguageRail.swift` — the
  horizontally-scrolling target-language pill rail:
  ```swift
  /// The target-language pill rail — design vreader-panels.jsx
  /// `TranslateView`. A pill tap fires `onSelect(language)` on EVERY
  /// tap, including a re-tap of the already-selected language (so the
  /// default-preselected language is still requestable — Gate-2
  /// finding).
  struct TranslateLanguageRail: View {
      let languages: [String]
      let selected: String
      let theme: ReaderThemeV2
      var onSelect: (String) -> Void
      var body: some View { … }
  }
  ```
- `vreader/Views/Reader/TranslationResultCard.swift` — the stacked
  original + accent-tinted translation cards (Speak button and "Notes"
  card omitted):
  ```swift
  struct TranslationResultCard: View {
      let originalText: String
      let translatedText: String
      let targetLanguage: String
      let theme: ReaderThemeV2
      var body: some View { … }
  }
  ```

### Modified files

- `vreader/Views/Reader/AIReaderPanel.swift` (320 lines) — WI-1, WI-2,
  WI-3. WI-1: replace the inline Summarize subviews (`summarizeContent`
  switch + `idleView`/`loadingView`/`completeView`/`errorView`/
  `featureDisabledView`/`consentRequiredView`, lines 129-318) with a
  single `AISummaryTabView(...)` call + a `@State` share item +
  `.sheet { ShareActivityView(activityItems:) }`; this **net-reduces**
  the file by ~180 lines. WI-2/WI-3: pass `theme` into `AIChatView` and
  `TranslationPanel`. `AIReaderPanel.swift` is the shared integration
  point touched by all three WIs — the WIs are therefore **sequential on
  one feature branch**, not parallel (Gate-2 finding).
- `vreader/Views/AI/AIChatView.swift` (269 lines) — WI-2. Replace the
  private `ChatBubbleView` (lines 230-268) with `AIChatMessageRow`;
  replace the `inputBar` plain `TextField` + `arrow.up.circle.fill`
  (lines 180-209) with the design's pill input. Gains a
  `theme: ReaderThemeV2 = .paper` parameter (a default so the change is
  additive). Empty-state, error banner, auto-scroll, bug-#94 keyboard
  handling, and the `clearHistory` toolbar button are **preserved
  unchanged**.
- `vreader/Views/Reader/TranslationPanel.swift` (162 lines) — WI-3.
  Replace `languageBar` (`Text("Translate to:")` + menu `Picker` +
  `.borderedProminent` button) with `TranslateLanguageRail`. The rail's
  `onSelect` calls `viewModel.translate(...)` directly on every pill tap
  (no `.onChange`, so a re-tap of the default-preselected language still
  works — Gate-2 finding). Re-style idle/loading/error to v2 tokens.
  Renders `TranslationResultCard` on completion instead of
  `BilingualView`. Gains a `theme: ReaderThemeV2 = .paper` parameter.
- `vreader/ViewModels/AITranslationViewModel.swift` (119 lines) — WI-3.
  `translate(...)` gains **in-flight cancellation**: it holds the
  running `Task`, cancels it before starting a new one, and ignores a
  completed result if its task was cancelled. Required because the rail
  fires translation on every selection — without cancellation, rapid
  taps race and a stale response can overwrite the newest (Gate-2
  finding). This is the one non-view change; it is a correctness fix the
  re-skin's interaction model necessitates, behaviour-neutral for the
  single-request case.
- `vreader/Views/Reader/BilingualView.swift` (110 lines) — WI-3,
  **deleted**. Its sole caller is `TranslationPanel` (Gate-2 confirmed),
  which WI-3 migrates to `TranslationResultCard`. `project.yml` globs
  the `vreader/` source tree by folder, so the deletion needs no
  `project.yml` edit; `xcodegen generate` (run in WI-3's mandatory
  version-bump step) regenerates `project.pbxproj` without the file.
  WI-3 confirms the regenerated `pbxproj` diff drops `BilingualView`
  before committing.
- `docs/features.md` — WI-1 adds a new feature row for the carved-out
  "AI Summarize scope selector" (§2.1).

### Files explicitly OUT of scope

- `vreader/Services/AI/*` (`AIService`, `AIContextExtractor`, `AITypes`,
  `AIProvider`) — **untouched**. #65 changes no request/response
  contract and adds no scope to context extraction.
- `vreader/ViewModels/AIAssistantViewModel.swift`,
  `AIChatViewModel.swift` — **untouched** (the scope work is carved out;
  the Chat re-skin is pure view-layer).
- `vreader/Models/ChatMessage.swift` — **untouched** (no `quoted` field).
- `AIAssistantView.swift`, `AIConsentView.swift`, `AIProviderPicker.swift`,
  `AIReaderPanelHeader.swift`, `ReaderSheetChrome.swift` — separate
  surfaces / already-v2 chrome. Untouched.
- `ReaderContainerView+Sheets.swift` — `AIReaderPanel`'s public init is
  unchanged; its sole caller needs no edit.

## 4. Prior art / project precedent / rejected alternatives

- **Precedent — feature #63 search-panel re-skin** (`SearchStateViews.swift`):
  a v2 re-skin that extracts re-skinned sub-views into new
  `#if canImport(UIKit)` files, takes `theme: ReaderThemeV2`, uses
  `ReaderTypography.body(for:.sourceSerif4,size:)` for serif text and
  `Color(theme.…Color)` tokens, and **omits design elements with no
  production backing** rather than faking them. #65 follows it exactly.
- **Precedent — feature #60 WI-10 AI-sheet chrome** + **feature #66
  reader-settings re-skin**: re-skins that preserve every wiring and
  carve behavior changes out to follow-up rows. #65's §2.1 does the
  same.
- **Rejected — restyle the native `Picker` / bubbles in place**:
  SwiftUI exposes no API for the design's pill rail, accent
  asymmetric-corner bubbles, or accent-bordered cards. Custom views are
  required.
- **Rejected — scope chips via `AIRequest.userPrompt`** (v1's plan):
  the Gate-2 audit showed `userPrompt` is appended as a QA `Question:`
  string and would corrupt the summarize request without changing the
  summarized text. Omitted; carved to a follow-up feature (§2.1).
- **Rejected — keep `BilingualView`**: its only caller migrates to
  `TranslationResultCard`; keeping it leaves dead code. Deleted in WI-3.
- **Rejected — reuse `ShareSheet` for the summary text**: the Gate-2
  audit showed `ShareSheet` only accepts a `LibraryBookItem` and shares
  the book file. The summary Share chip uses `ShareActivityView(
  activityItems: [summaryText])` directly — the same generic
  `UIActivityViewController` wrapper `AnnotationsPanelView` already uses
  for its export flow.

## 5. Work-item sequencing

Each WI is one PR. Version-bump tier per the `/feature-workflow` skill:
behavioral-not-final → `patch`, final WI → `minor`.

| WI | Title | Tier | Final? | PR size | RED test |
|----|-------|------|--------|---------|----------|
| WI-1 | `AISummaryTabView` + `AISummaryCard` — re-skinned Summarize body; `AIReaderPanel` swap; Share via `ShareActivityView`; new follow-up feature row | behavioral | no | medium | `AISummaryCard.onRegenerate` re-invokes summarize; `onShare` is handed the summary text |
| WI-2 | `AIChatView` bubble + pill-input re-skin (`AIChatMessageRow`, `theme` param) | behavioral | no | medium | a `.user` `ChatMessage` renders the accent bubble form; a `.assistant` message renders the sparkle-avatar form |
| WI-3 | `TranslateLanguageRail` + `TranslationResultCard`; `TranslationPanel` swap; `AITranslationViewModel` cancellation; delete `BilingualView` | behavioral | **yes** | medium | selecting a rail language (incl. a re-tap of the preselected one) invokes `translate(...)`; an overlapping translate is cancelled |

- **WI-1 — Summarize body re-skin.** Build `AISummaryTabView` +
  `AISummaryCard`; wire Regenerate (existing re-run) and Share
  (`ShareActivityView`); re-skin idle/loading/error/disabled/consent/
  streaming states to v2 tokens; swap `AIReaderPanel`'s inline
  Summarize subviews for `AISummaryTabView` (net-reduces
  `AIReaderPanel.swift`). Add the carved-out scope-selector feature row
  to `docs/features.md` (§2.1). RED: `AISummaryCardTests`.
- **WI-2 — Chat body re-skin.** Replace `ChatBubbleView` with
  `AIChatMessageRow`'s two designed forms; replace the input bar with
  the pill field; add the `theme` parameter; preserve empty-state /
  error banner / auto-scroll / keyboard handling / clear button. RED:
  `AIChatMessageRowTests`.
- **WI-3 — Translate body re-skin (final WI).** Build
  `TranslateLanguageRail` + `TranslationResultCard`; swap them into
  `TranslationPanel`; the rail's `onSelect` fires `translate(...)` every
  tap; add in-flight cancellation to `AITranslationViewModel.translate`;
  re-skin idle/loading/error; delete `BilingualView`. RED:
  `TranslateLanguageRailTests` + an `AITranslationViewModel`
  cancellation test. Final WI → `minor`.
- **3 WIs, sequential.** All three touch `AIReaderPanel.swift` (the
  integration point), so they run on one feature branch in order; they
  are not parallelizable (Gate-2 finding). WI-2 and WI-3 do not depend
  on each other's logic but share that file.

## 6. Test catalogue

Swift Testing (`import Testing`, `@Suite`, `@Test`) is the default — the
existing AI suites already use it. SwiftUI views are tested for
composition/behavior (callbacks fire, bindings round-trip, the right
sub-view renders per input), not pixels.

- `vreaderTests/Views/Reader/AISummaryCardTests.swift` (WI-1) —
  `onRegenerate` fires when the Regenerate chip is tapped; `onShare` is
  invoked with the exact `summaryText`; the card renders the supplied
  text; the Save chip is absent.
- `vreaderTests/Views/Reader/AISummaryTabViewTests.swift` (WI-1) — the
  state switch routes `.idle`/`.loading`/`.streaming`/`.complete`/
  `.error`/`.featureDisabled`/`.consentRequired` to the right sub-view
  (a regression guard that the re-skin preserved every state).
- `vreaderTests/Views/AI/AIChatMessageRowTests.swift` (WI-2) — a
  `.user` `ChatMessage` renders the accent user-bubble form; a
  `.assistant`/`.system` message renders the sparkle-avatar row form.
- `vreaderTests/Views/Reader/TranslateLanguageRailTests.swift` (WI-3) —
  the rail renders one pill per language; tapping a pill calls
  `onSelect` with that language; **tapping the already-selected pill
  still calls `onSelect`** (the default-preselected-language fix).
- `vreaderTests/Views/Reader/TranslationResultCardTests.swift` (WI-3) —
  renders both `originalText` and `translatedText` with the
  `targetLanguage` label; composes for a CJK target without crashing.
- `vreaderTests/ViewModels/AITranslationViewModelTests.swift` (WI-3,
  extend the existing suite) — a second `translate(...)` call cancels
  the first; a cancelled translate's late result does not overwrite
  `translatedText`; a single translate still completes normally
  (regression).
- **Gate 5 verification UITest** —
  `vreaderUITests/Verification/Feature65AISheetTabBodyVerificationTests.swift`
  (WI-3): open a seeded book → open the AI sheet → assert each
  re-skinned body resolves (Summarize summary card after a stubbed
  summarize; Chat bubble forms; Translate language rail).
  DebugBridge-drivable, CU-free.
- **Existing tests** — `AIChatViewModelTests`, `AIChatGeneralTests`,
  `AITranslationTests`, `AIReaderIntegrationTests`,
  `AIAssistantViewModelTests` re-run as regression guards in every WI
  PR. Note: `vreaderUITests/AI/AIAssistantStateTests.swift` exists but
  its tests are currently skipped — it is not an active regression
  guard, so the re-skin's a11y-id preservation is a best-effort goal,
  not a hook-enforced one.

## 7. Backward compatibility

- **No schema change, no migration, no persisted state.** #65 is a
  view-layer re-skin; nothing is persisted.
- **No request/response contract change.** `AIService`,
  `AIContextExtractor`, `AITypes`, and the provider request shape are
  untouched. (v1's scope-via-`userPrompt` idea is dropped — §2.1.)
- **`AIChatView` / `TranslationPanel` `theme` parameter** is additive
  with a `.paper` default, so the change does not break the call site;
  `AIReaderPanel` is updated to pass the real `theme` it already holds.
- **`AITranslationViewModel.translate` cancellation** is behaviour-
  neutral for the single-request case (the only observable change is
  that an interrupted, superseded translate no longer overwrites a newer
  one — strictly an improvement). No caller outside `TranslationPanel`
  invokes `translate`.
- **`BilingualView` deletion** — one caller, migrated in WI-3. No test,
  preview, or other reference (Gate-2 confirmed). `xcodegen generate`
  regenerates `project.pbxproj` without it.
- **a11y identifiers** — the tab picker (`aiReaderTabPicker`) and panel
  (`aiReaderPanel`) ids are preserved; re-skinned state views keep their
  existing ids where the structure allows. No externally observable
  behavior changes beyond the visual re-skin.

## 8. Revision history / Gate-2 audit trail

| Version | Date | Change |
|---|---|---|
| v1 | 2026-05-18 | Initial draft (feature-cron, Gate 1). |
| v2 | 2026-05-18 | Gate-2 round-1 audit (Codex `019e3b84`) applied — see below. |

### Gate 2 — Independent plan audit — round 1 (Codex `019e3b84`)

Round 1 returned 4 High / 4 Medium / 1 Low. All are resolved in this v2
revision; none required escalation. The audit's clean checks confirmed
the `AIAssistantViewModel` / `AIRequest` / `AIChatView` / `TranslationPanel`
/ `BilingualView` / `ChatMessage` / `AITranslationViewModel` /
`ReaderTypography` / `ReaderThemeV2` model assumptions and the
no-symbol-collision check.

| # | Sev | Finding | Resolution in v2 |
|---|---|---|---|
| 1 | High | §2.1 premise wrong — `ReaderAICoordinator` already holds full-book text in `loadedTextContent`; `currentTextContent` is a 2nd-stage ~2500-char extraction. The plan overstated the plumbing need and understated how misleading a faked "Book so far" would be. | The scope chips are omitted entirely (§2.1) and carved to a follow-up feature. #65 no longer touches context extraction at all, so the premise is moot. |
| 2 | High | Threading scope through `AIRequest.userPrompt` is not neutral — both providers append `userPrompt` as a `Question: …` QA string for every action, corrupting the summarize request. | Dropped. No scope is threaded anywhere; the chips are omitted (§2.1). |
| 3 | High | Rail-only `.onChange(of: targetLanguage)` has a first-use bug — `targetLanguage` defaults to "Chinese", so Translate opens with Chinese preselected and unrequestable. | The rail's pill tap calls `translate(...)` **directly on every tap**, including a re-tap of the already-selected language (§2.2, §3, WI-3). No `.onChange`. A `TranslateLanguageRailTests` case pins it. |
| 4 | High | `BilingualView.swift` is listed in `project.pbxproj`; deleting the file without project cleanup breaks the build. | `project.yml` is folder-glob-based; WI-3 deletes the file and `xcodegen generate` (the mandatory version-bump step) regenerates `pbxproj` without it. WI-3 verifies the `pbxproj` diff before committing (§3, §7). |
| 5 | Med | Auto-translate-on-select races — `translate(...)` has no cancellation; rapid taps overlap and a stale result can overwrite the newest. | WI-3 adds in-flight cancellation to `AITranslationViewModel.translate` (§3); an `AITranslationViewModelTests` case pins it. |
| 6 | Med | `ShareSheet` only accepts a `LibraryBookItem` (shares the book file) — not a generic text-share surface. | WI-1's Share chip uses `ShareActivityView(activityItems: [summaryText])` directly (§3, §4). |
| 7 | Med | The suggested-questions "hand off to Chat" reuse is overstated — `selectedTab` is private, `AIChatView.inputText` is private with no prefill API. | The suggested-questions list is omitted outright (§2.2); the hand-off variant is dropped. |
| 8 | Med | WI-isolation claim too optimistic — every WI touches `AIReaderPanel.swift` (theme-param call-site edits), so the WIs are not parallel write scopes. | §3 and §5 now state `AIReaderPanel.swift` is the shared integration point and the 3 WIs are sequential on one branch. The new `theme` params take `.paper` defaults so the change is additive. |
| 9 | Low | `AIAssistantStateTests` is a UITest file but all its tests are skipped — it is not an active regression guard. | §6 corrected — a11y-id preservation is a best-effort goal, not a hook-enforced guard. |

**Gate 2 round 2 — clean (passed).** Codex `019e3b84` re-verified v2:
no remaining Critical/High/Medium findings, all 9 round-1 findings
resolved, no new contradiction against the codebase. `ShareActivityView`
(takes `activityItems:`), the `AITranslationViewModel` `@Observable
@MainActor` cancellation shape, the folder-glob `project.yml`, and the
no-symbol-collision check were independently confirmed. One
implementation note carried to WI-3: `translate(...)` must remain
`async` from the caller's perspective — existing tests `await` it and
expect settled state afterward. **Gate 2 passed — row → `PLANNED`,
Gate 3 begins.**
