---
kind: feature
id: 69
status_target: VERIFIED
commit_sha: 7c2f6930e3818cec9c733977565314a034061aa9
app_version: 3.39.7 (build 628)
date: 2026-05-22
verifier: claude
device_or_simulator: iPhone 17 Pro Simulator (61149F0E-DC18-4BE2-BB37-52659F1F4F62)
os_version: iOS 26.x
build_configuration: Debug
backend: OpenRouter (openai/gpt-4o-mini) via DebugBridge provider?action=add; real network responses
result: pass
---

# Feature #69 — AI Summarize scope selector (Gate-5b, round 4 attempt — VERIFIED)

Fourth Gate-5 attempt, on v3.39.7 (`7c2f6930`). The two blockers that
kept the prior three rounds at `partial` are both lifted this session:

1. **Bug #257 (open?position seek)** is FIXED + verified — `open?bookId=…&position=N`
   now genuinely moves the TXT reader. `snapshot.position` reads back `949`
   after `position=1000` (page-top of the page containing offset 1000 in
   the small war-and-peace fixture), exactly as `debug-bridge.md` documents.
   This makes a **non-zero reading position** reachable CU-free, which is
   what `extractBookSoFar` needs to produce a *populated* (non-empty)
   Book-so-far summary.
2. **Bug #255 (ai?action=summarize&scope=…)** shipped earlier this session —
   the DebugBridge fires the Summarize action through the production
   `runSummarize` → `AIContextExtractor` path at the selected scope, CU-free.

With both in place, all 8 acceptance criteria are now exercised
end-to-end against a real OpenRouter (`openai/gpt-4o-mini`) backend.
**Criterion 8 — a *populated* Book-so-far summary distinct from Section —
is now observed** (the gap that held the prior three rounds at `partial`).

## Acceptance criteria

| # | Criterion | Method this round | Observed | Verdict |
|---|---|---|---|---|
| 1 | `SummaryScope` enum exists with the three cases + design-matching `displayName` strings | Unit (`SummaryScopeTests`) green in v3.39.7 merge gate (re-run this round) | No regression; chip labels "Section / Chapter / Book so far" render verbatim in the live sheet | PASS |
| 2 | `SummaryScopeResolver` resolves a locator → containing chapter's `ChapterBounds`; preamble → `[0, firstStart)`; empty/non-anchored TOC → `nil` | Unit (`SummaryScopeResolverTests`) re-run green | No regression | PASS |
| 3 | `AIContextExtractor` scoped extraction (`.section` == legacy; `.chapter` slice; `.bookSoFar` prefix; surrogate-pair-safe) | Unit (`AIContextExtractorScopedTests`) re-run green **+ observed**: at offset 949 the three scopes produce three different populated summaries (different input extents) | No regression; runtime behavior matches — `.bookSoFar` prefix at offset 949 is populated, `.section` window + `.chapter` slice differ | PASS |
| 4 | `AIAssistantViewModel` carries `selectedScope` + `setScope`; `summarize` forwards `scope`/`chapterBounds`/`fullText`; non-summarize actions unaffected | Unit (`AIAssistantViewModelScopeTests`) re-run green | No regression | PASS |
| 5 | `AISummaryTabView` renders the chip strip; chip tap = selection-only (no auto-fire); `runSummarize` forwards `selectedScope` + `fullTextContent` + `chapterBounds`; in-flight guard; stable `aiSummaryScopeChip.*` AX IDs | Unit (`AISummaryTabViewScopeTests`) re-run green **+ observed**: chip strip renders in the live sheet; each `ai?action=summarize&scope=` flips the active accent chip (Section → Chapter → Book-so-far) without re-firing other tabs | No regression; chip strip + accent transitions observed | PASS |
| 6 | `aiSheet` threads the full book text + TOC-derived `ChapterBounds` into the panel | Code path (`ReaderContainerView+Sheets.swift` `aiSheet`); TXT reader open at offset 949; **observed**: Chapter scope produced a chapter-bounded summary (Chapter 2 drawing-room) distinct from the Section window, confirming bounds are threaded end-to-end | Wiring confirmed by the Chapter-vs-Section output delta | PASS |
| 7 | End-to-end: open the AI sheet, select the Chapter chip, observe a chapter-scoped summary render | `present?sheet=ai&tab=summarize` → `ai?action=summarize&scope=chapter` → loading → `.complete` Chapter SUMMARY card with real `openai/gpt-4o-mini` text ("Chapter 2 describes Anna Pavlovna's drawing room … Helene, dressed for a ball … Princess Bolkonskaya, noted for her allure.") | Chapter-scoped summary card rendered, Chapter chip active | **PASS** |
| 8 | End-to-end: the Book-so-far chip produces a *different* (populated) summary than Section for the same position | At offset 949 (set via `open?position=1000`, Bug #257 seek): `ai?action=summarize&scope=book` rendered a **populated** `.complete` SUMMARY card ("In Chapter 1 of 'War and Peace' … Anna Pavlovna Scherer … opposition to Napoleon Bonaparte, whom she labels as 'Antichrist' … 'la grippe' …") — the prefix `[0, 949)` covering the opening Antichrist/la-grippe exchange that the Section + Chapter cards omit. Visibly distinct from both Section and Chapter. | **Populated Book-so-far summary, distinct from Section, observed** | **PASS** |

**8 of 8 PASS.** `result: pass` — row may flip `DONE` → `VERIFIED`.

## Commands run

```bash
SIM=61149F0E-DC18-4BE2-BB37-52659F1F4F62

# 1. CLEAN build into a fresh derivedDataPath (Bug #259 — incremental
#    build drops the vreader-debug URL scheme), install from the worktree's
#    own BUILT_PRODUCTS_DIR (never a global `find` — that picks sibling
#    worktree builds).
rm -rf build/verify-69
xcodebuild build -project vreader.xcodeproj -scheme vreader -configuration Debug \
  -destination "platform=iOS Simulator,id=$SIM" -derivedDataPath build/verify-69 clean build
APP=$(xcodebuild ... -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR =/{print $2; exit}')/vreader.app
xcrun simctl install "$SIM" "$APP"

# 2. Launch with BOTH flags (--enable-ai is a no-op without --uitesting:
#    AITestOverride.forceAvailable is gated inside `if config.isUITesting`).
xcrun simctl launch "$SIM" com.vreader.app --uitesting --enable-ai

# 3. VERIFICATION-ENVIRONMENT SETUP — enable the production AI gate.
#    `--enable-ai` only sets AITestOverride.forceAvailable, which gates the
#    *UI visibility* (AIReaderAvailability.isAvailable) — it does NOT satisfy
#    the production `AIService.sendRequest` path, which independently checks
#    `FeatureFlags.aiAssistant` (default false) AND `AIConsentManager.hasConsent`
#    (default false). Both are UserDefaults-backed (no DebugBridge command sets
#    them), so the CU-free equivalent of "user enables AI in Settings + grants
#    consent" is to write the two keys before launch. This is environment setup,
#    NOT a code change — see Observations.
DATA=$(xcrun simctl get_app_container "$SIM" com.vreader.app data)
PLIST="$DATA/Library/Preferences/com.vreader.app.plist"
xcrun simctl terminate "$SIM" com.vreader.app
/usr/libexec/PlistBuddy -c "Add :com.vreader.featureFlags.aiAssistant bool true" "$PLIST"
/usr/libexec/PlistBuddy -c "Add :com.vreader.ai.consentGranted bool true" "$PLIST"
xcrun simctl spawn "$SIM" launchctl stop com.apple.cfprefsd.xpc.daemon   # force plist re-read
xcrun simctl launch "$SIM" com.vreader.app --uitesting --enable-ai

# 4. Re-seed (--uitesting wipes the library) + open + SEEK to a mid-book offset.
xcrun simctl openurl "$SIM" "vreader-debug://seed?fixture=war-and-peace"
# fingerprintKey from the seed OSLog (NOT a global strings grep — stale-key trap):
#   seed: imported war-and-peace → key=txt:bd82…:1705
KEY="txt:bd8285a80f01df96dedd20a02178043afb85c0b499127e300baf57b7f1ed7508:1705"
ENC=$(printf '%s' "$KEY" | jq -sRr @uri)
xcrun simctl openurl "$SIM" "vreader-debug://open?bookId=${ENC}&position=1000"
xcrun simctl openurl "$SIM" "vreader-debug://snapshot?dest=relaunch-seek.json"
#   → snapshot.position: "949"  (Bug #257 seek — reader genuinely moved off the title page)

# 5. Configure the provider (key URL-encoded from .secrets/.env, NEVER logged).
set -a; source /Users/ll/workspace/vreader/.secrets/.env; set +a
xcrun simctl openurl "$SIM" "vreader-debug://provider?action=add&name=verify&kind=openAICompatible&endpoint=<enc>&apiKey=<enc>&model=openai%2Fgpt-4o-mini&active=true"

# 6. Present the Summarize tab, fire all three scopes at the SAME offset (949).
xcrun simctl openurl "$SIM" "vreader-debug://present?sheet=ai&tab=summarize"
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=section"  # → .complete (opening-chapters overview)
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=chapter"  # → .complete (Chapter 2 drawing-room) — DIFFERENT
xcrun simctl openurl "$SIM" "vreader-debug://ai?action=summarize&scope=book"     # → .complete POPULATED prefix [0,949) — DIFFERENT

# 7. Headless captures (CU unused this run; simctl io works).
xcrun simctl io "$SIM" screenshot dev-docs/verification/artifacts/feature-69-round3-0X-*.png

# 8. Re-run the 5 feature-#69 unit suites on this build (criteria 1-5 backing):
xcodebuild test ... -only-testing:vreaderTests/SummaryScopeTests \
  -only-testing:vreaderTests/SummaryScopeResolverTests \
  -only-testing:vreaderTests/AIContextExtractorScopedTests \
  -only-testing:vreaderTests/AIAssistantViewModelScopeTests \
  -only-testing:vreaderTests/AISummaryTabViewScopeTests
#   → Test run with 77 tests in 5 suites passed. ** TEST SUCCEEDED **
```

OSLog confirmation (all three actions through the production observer, none `.featureDisabled`):

```
[DebugBridge] provider.add: name=verify kind=openAICompatible model=openai/gpt-4o-mini active=true replaced=true
[DebugBridge] present observer: sheet=ai tab=summarize
[DebugBridge] aiAction observer: action=summarize scope=section text=nil
[DebugBridge] aiAction observer: action=summarize scope=chapter text=nil
[DebugBridge] aiAction observer: action=summarize scope=bookSoFar text=nil
```

## Observations

- **Why the prior three rounds couldn't reach criterion 8, and why this
  one can.** Two independent gaps had to close: (a) a *non-zero reading
  position* (Bug #257 — the seek now moves the TXT reader; `position`
  reads back `949`), and (b) the *production AI gate* being satisfied so
  `AIService.sendRequest` doesn't throw `.featureDisabled`. Both are now
  satisfiable CU-free.

- **The production `sendRequest` gate is separate from the UI-visibility
  gate — this is by design, not a bug.** `--enable-ai` →
  `AITestOverride.forceAvailable` only short-circuits
  `AIReaderAvailability.isAvailable` (which decides whether the AI sheet
  *presents*). The actual request path (`AIService.sendRequest`,
  `vreader/Services/AI/AIService.swift:100-104`) independently re-checks
  `FeatureFlags.aiAssistant` (default `false`,
  `FeatureFlags.swift:179-180`) and `AIConsentManager.hasConsent` (default
  `false`, `AIConsentManager.swift:30-31`). Both are UserDefaults-backed
  (`com.vreader.featureFlags.aiAssistant` and `com.vreader.ai.consentGranted`)
  and intentionally have **no** DebugBridge command — they model a real
  user action (toggling AI on in Settings + granting outbound-call
  consent). On a fresh sim install neither key exists, so `sendRequest`
  correctly throws `.featureDisabled` → the Summarize tab shows the
  "AI features are currently disabled" card. The first attempt this round
  hit exactly that (`feature-69-round3-01-section` was originally the
  disabled card before the gate was set). **This is not a regression** —
  it is the production consent/feature-flag boundary working as written.
  The prior `feature-69-20260521-VERIFIED.md` round (which DID get real
  summaries on v3.38.42) must have run on a sim where these keys were
  already persisted from an earlier in-app toggle; that round's recipe
  did not document the step, which is why this round re-derived it.

- **Setting the two UserDefaults keys is legitimate verification-environment
  setup, equivalent to the in-app flow.** Writing
  `com.vreader.featureFlags.aiAssistant=true` + `com.vreader.ai.consentGranted=true`
  before launch is the headless equivalent of a user opening Settings,
  enabling AI, and tapping "Grant Consent" — the same UserDefaults keys
  the production `FeatureFlags.setOverride` / `AIConsentManager.grantConsent`
  write. No production code was touched. `cfprefsd` was bounced so the
  app re-reads the plist at the next launch.

- **The three scopes produce genuinely distinct input extents at offset
  949** — the strongest proof of the feature's intent:
  - **Section** (the ~current-window legacy extent): an opening-chapters
    overview naming Helene + Bolkonskaya as the notable guests.
  - **Chapter** (the chapter-bounded slice via threaded `ChapterBounds`):
    a Chapter-2 drawing-room summary ("Helene, dressed for a ball …
    Princess Bolkonskaya, noted for her allure").
  - **Book-so-far** (the prefix `[0, 949)`): a Chapter-1 summary capturing
    the Antichrist/Napoleon exchange + the "la grippe" line — content the
    other two scopes omit, proving the prefix slice is materially larger
    *and* anchored to the book start, not the reading window.

- **`open` fingerprintKey must come from the seed OSLog**, not a global
  `strings` grep of the store (stale-key trap documented in the prior
  #65 round). The authoritative key is the `seed: imported … → key=…`
  line: `txt:bd82…:1705`.

## Artifacts

- `dev-docs/verification/artifacts/feature-69-round3-00-ai-idle-20260522.png` — AI Summarize tab idle: Section / Chapter / Book-so-far chip strip renders, Section active.
- `dev-docs/verification/artifacts/feature-69-round3-01-section-20260522.png` — Section scope `.complete` SUMMARY card (opening-chapters overview) at offset 949.
- `dev-docs/verification/artifacts/feature-69-round3-02-chapter-20260522.png` — Chapter scope `.complete` SUMMARY card (Chapter-2 drawing-room), Chapter chip active — distinct from Section (criterion 7).
- `dev-docs/verification/artifacts/feature-69-round3-03-booksofar-20260522.png` — Book-so-far scope `.complete` SUMMARY card (populated Chapter-1 prefix, Antichrist/la-grippe), Book-so-far chip active — distinct from Section (criterion 8).
