---
branch: fix/issue-594-ai-provider-row-tap-no-edit
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-05-14
---

# Bug #174 — AI provider row tap UX + sheet-state race (audit log)

## Context

GH #594 / bugs.md row #174. Two coupled root causes identified in the
filed bug body:

1. **Discoverability**: row tap calls `setActive` only; edit lives
   behind a leading-edge swipe with no visual hint. New users have no
   way to find the edit form.
2. **State race**: `.sheet(isPresented: $showEditor)` paired with a
   separately-mutated `editingProfile: ProviderProfile?` has no
   guaranteed ordering between the two writes. Rapid swap of edit
   targets (or an Add-after-Edit sequence) can present the wrong
   form because SwiftUI captures `editingProfile` at sheet body
   evaluation time, not at the moment of `editingProfile = X`
   followed by `showEditor = true`.

## Codex availability

Codex MCP unavailable this session (manual fallback per rule 47).

## Fix shape

Two-part change to `vreader/Views/Settings/AIProviderListView.swift`:

1. **Add visible Edit affordance**: per-row trailing pencil button,
   44x44 hit area, `.foregroundStyle(.blue)`. The outer row content
   is restructured from a single `Button` (whole row = setActive)
   to an `HStack` containing two sibling buttons with
   `.buttonStyle(.borderless)` — left button (radio + text) sets
   active, right button (pencil) opens editor.
2. **Atomic sheet state**: introduce `AIEditorContext` (Identifiable,
   Equatable, Sendable) with `profile: ProviderProfile?` payload and
   `id: String` derived from `profile?.id.uuidString ?? "new"`.
   Replace `.sheet(isPresented:)` with `.sheet(item:)` driven by a
   single `editorContext: AIEditorContext?` state. The two call sites
   that previously set `editingProfile` + `showEditor` now do a single
   assignment (e.g. `editorContext = .edit(profile)` or
   `editorContext = .add()`).

Leading-swipe Edit and trailing-swipe Delete are preserved (power
users + iOS standard gestures). Empty-state Add CTA migrated to the
same single-assignment shape.

## Files audited

| File | Purpose | Audit |
|---|---|---|
| `vreader/Views/Settings/AIProviderListView.swift` (modified, 237 LOC total, +97/-46) | List view + new `AIEditorContext` wrapper at file top | reviewed |
| `vreaderTests/Views/Settings/AIEditorContextTests.swift` (new, ~100 LOC) | 11 tests on the wrapper struct | reviewed |
| `docs/bugs.md` row #174 | Tracker flip TODO → FIXED with FIXED note | reviewed |

## Manual audit evidence

### Files read

- `vreader/Services/AI/ProviderProfile.swift` (full, 46 LOC) — confirmed `Codable + Sendable + Equatable + Identifiable` (NOT Hashable; that's why `AIEditorContext` is `Equatable` not `Hashable`).
- `vreader/Views/Settings/AIProviderEditSheet.swift` (head, ~50 LOC) — confirmed `init(viewModel:existing:)` signature; `existing: ProviderProfile?` (nil = add, non-nil = edit). The fix maps `context.profile` directly into this.
- `vreader/Views/Settings/AIProviderListView.swift` (full, pre-edit 187 LOC) — confirmed all entry-point call sites for the sheet (toolbar Add button line 52-58, empty-state Add CTA line 97-108, leading-swipe Edit line 175-184).
- `vreaderTests/ViewModels/AIProviderPickerViewModelTests.swift` (existence check only) — no overlap with the new test file; the picker viewmodel is a different surface.

### Symbols verified

- `AIProviderEditSheet` accepts `existing: ProviderProfile?` ✓
- `AISettingsViewModel.setActive(_:)` `deleteProfile(_:)` `loadProfiles()` `profiles` `activeID` `listError` ✓ — all still called the same way.
- `ProviderKind.openAICompatible` ✓ (used in test fixture).
- `.sheet(item:)` requires `Identifiable & Sendable` payload — `AIEditorContext: Identifiable, Sendable` satisfies (Equatable is for tests + clarity, not required by SwiftUI).
- `.buttonStyle(.borderless)` on List row inner buttons ✓ — verified against SwiftUI documentation that this prevents the system from treating two buttons as a single row-level tap target. Without it, both buttons collapse into one row-tap behavior (defeats the fix).
- `.contentShape(Rectangle())` on the inner label ✓ — keeps the entire visual area tappable for the leading button even though `Spacer(minLength: 0)` is the rightmost element.

### Edge cases checked

1. **Add → Edit sequence**: `editorContext = .add()` sets id `"new"`. Then `editorContext = .edit(profile)` sets id to profile's UUID. SwiftUI sees id change → dismisses + recreates sheet with new body. **Fixed**: was previously vulnerable when `editingProfile` cleared lagged the sheet body capture.
2. **Edit-A → Edit-B without intermediate dismiss**: same `id` change mechanism applies. Different UUIDs → sheet body recreates.
3. **Edit → Cancel → Edit same row**: state goes context → nil → context. Same id; SwiftUI presents the sheet again with fresh body state (the sheet body owns its own form-state @State).
4. **Empty state Add CTA**: collapsed to `editorContext = .add()` — same single-assignment shape as toolbar Add. Round-1 audit comment from feature #50 WI-6a (clearing stale editingProfile) is no longer needed; the wrapper makes it impossible.
5. **Multi-row pencil concurrent tap (unlikely but trivially safe)**: two simultaneous taps on different rows' pencil buttons would write `editorContext` twice. Last write wins. SwiftUI's `.sheet(item:)` is animation-driven; mid-presentation second write triggers smooth swap. No race because the state IS the single source of truth.
6. **Profile renamed in store while editor open**: `AIEditorContext` carries `profile` by value (ProviderProfile is a struct). The open sheet sees the snapshot taken at the moment of `editorContext = .edit(profile)`, not the live store value. Test `editContextSnapshotsProfileAtCreation` asserts this.
7. **Empty state → Add → save first profile → list re-renders to non-empty branch**: SwiftUI replaces the `emptyState` view with `profileList`, but `editorContext` @State is owned by the outer Group's parent `body`, so the sheet stays presented across the layout swap. Safe.
8. **Accessibility regression check**: the row's `.accessibilityIdentifier("providerProfileRow_<uuid>")`, `.accessibilityLabel(profile.name)`, `.accessibilityValue(...)`, `.accessibilityAddTraits([.isSelected, .isButton])` are preserved on the leading button. The pencil button gets its own `accessibilityIdentifier("editProviderProfileButton_<uuid>")` + label "Edit <name>" + hint. VoiceOver will announce both elements; the pencil button is a distinct focus target.
9. **`deleteProviderProfile_<uuid>` and `editProviderProfile_<uuid>` accessibility identifiers** (swipe buttons) remain — XCUITest tests targeting the leading-swipe Edit button keep working.

### Concurrency / Swift 6

- `AIEditorContext` is `Sendable` via auto-synthesis (all stored properties are Sendable value types).
- All state writes happen on `@MainActor` (SwiftUI views) — no cross-actor crossings.
- No `Task` / `await` introduced for the new code (only the existing `Task { await viewModel.setActive(...) }` / `Task { await viewModel.deleteProfile(...) }` patterns are preserved).
- Clean build under `SWIFT_STRICT_CONCURRENCY: complete`.

### VReader compliance

- Swift 6 strict concurrency: clean.
- `@MainActor` correctness: view body remains MainActor-implicit (SwiftUI).
- File size: AIProviderListView.swift went 187 → 237 LOC. Still under 300.
- Bridge safety: not applicable.
- DEBUG gating: not applicable.

### Risks accepted

- **Two-button row pattern in a List**: the `HStack` of two `.buttonStyle(.borderless)` buttons inside a List row is documented SwiftUI usage but less common than single-button rows. Mitigated by `.contentShape(Rectangle())` on the leading button's label and explicit `frame(width: 44, height: 44)` on the pencil's tap target. iOS HIG recommends 44pt minimum tap target — satisfied.
- **No XCUITest added**: the bug is fundamentally a UX-discoverability + presentation-correctness fix. Unit tests on `AIEditorContext` cover the race-fix invariant; XCUITest for the visible pencil button is verification-territory (post-merge `awaiting-device-verification` label per close-gate). Adding XCUITest here would be premature inside the fix PR.
- **Leading-swipe Edit kept**: marginal accessibility win (preserves muscle memory for power users), no cost. If user feedback later says it's confusing alongside the visible pencil, can be removed in a follow-up.

### Tests added

- `vreaderTests/Views/Settings/AIEditorContextTests.swift` — 11 tests:
  - `addContextHasStableNewID` — Add contexts share id `"new"`.
  - `editContextIDMatchesProfileUUID` — edit context id = profile UUID string.
  - `editContextsForDifferentProfilesHaveDifferentIDs` — distinct profiles → distinct ids (the race-fix invariant).
  - `addAndEditHaveDistinctIDs` — add vs edit distinguishable.
  - `addContextHasNilProfile` — payload nil when add.
  - `editContextCarriesProfileByValue` — payload populated when edit.
  - `editContextSnapshotsProfileAtCreation` — value-type snapshot semantics (mutation of source after wrap doesn't propagate).
  - 4 Equatable conformance tests.

All 11 pass under `xcodebuild test -only-testing:vreaderTests/AIEditorContextTests`.

## Findings

| # | Severity | Issue | Resolution |
|---|---|---|---|
| 1 | n/a | none — fix implements both root causes from the bug body; tests cover the race-fix invariant; build clean; existing accessibility identifiers preserved | n/a |

## Final verdict

**ship-as-is** — the fix addresses both filed root causes with the
minimum reasonable footprint. New `AIEditorContext` wrapper is 14 LOC
+ two factory methods, all covered by 11 tests. View change adds one
trailing button per row and swaps `.sheet(isPresented:)` for
`.sheet(item:)`. Existing tests for the viewmodel surface remain green.
