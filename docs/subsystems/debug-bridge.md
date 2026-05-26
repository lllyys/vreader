# DebugBridge — feature #44

DEBUG-only `vreader-debug://` URL scheme that drives the app from outside (e.g. an AI agent or CI test) for autonomous reproduction, verification, and debugging. Compiled out of Release builds.

## When to use it

- Reproducing bugs without a 30-step manual UI sequence.
- Driving the verification harness in feature #45.
- Asserting on app state in JSON instead of pixels.

If you're writing user-facing code, this isn't your file.

## Quick start

```bash
# Resolve UDID of the booted simulator. The `(Booted)` suffix is the LAST
# token; UDID is the second-to-last. Strip the parentheses around it.
SIM_ID=$(xcrun simctl list devices booted | awk '/Booted/ {print $(NF-1); exit}' | tr -d '()')

# One-time per fresh simulator: pre-grant the URL-scheme approval so iOS
# does not present an "Open in 'vreader'?" alert on the first call.
# See "iOS scheme-approval prompt" below for why this is needed.
scripts/grant-debug-scheme-approval.sh "$SIM_ID"

# Wipe library, seed a fixture, set theme.
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl openurl "$SIM_ID" "vreader-debug://theme?mode=dark&fontSize=22"

# Compute the seeded book's fingerprint key from the imported file name.
# Importer stores files as `<format>_<sha>_<bytes>.<ext>`; the bridge's
# bookId format is `<format>:<sha>:<bytes>`.
DATA=$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)
FILE=$(ls "$DATA/Library/Application Support/ImportedBooks/" | head -1)
KEY=$(echo "$FILE" | sed -E 's/^([a-z0-9]+)_([0-9a-f]+)_([0-9]+)\..*/\1:\2:\3/')
ENCODED=$(printf '%s' "$KEY" | sed 's/:/%3A/g')

# Open the book, settle, then snapshot.
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED"
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=ready"
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=state.json"

# Read the state JSON from the app container.
cat "$DATA/Library/Caches/DebugBridge/state.json"
```

## URL grammar

All commands are scheme `vreader-debug://`. Host names the command. Trailing `/` is allowed; any deeper path segment is rejected.

| Command    | Required params                    | Optional params                       | Effect                                                                                                                                                              |
| ---------- | ---------------------------------- | ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `reset`    | —                                  | —                                     | Wipe every book from the library. Idempotent.                                                                                                                       |
| `seed`     | `fixture=<name>`                   | —                                     | Import a bundled fixture book by catalog name.                                                                                                                      |
| `open`     | `bookId=<key>`                     | `position=<str>`                      | Verify the book exists; LibraryView pushes it onto its `NavigationStack`. When `position` is supplied (Bug #257), after the reader registers + settles the bridge **seeks** it via the production `.readerNavigateToLocator` path (the same notification TOC / search / restore drive — no parallel seek). `snapshot.position` then reflects the landing offset. Per-format grammar in Parameter validation below. |
| `theme`    | `mode=dark\|light\|paper\|sepia\|oled\|photo` | `fontSize=<int>`           | Persist theme + optional font size to `UserDefaults`. Effect on next reader open. `light` is a backward-compatible alias for `paper`.                                |
| `settle`   | `token=<basename>`                 | —                                     | Wait for the active reader to settle, then write `Caches/DebugBridge/ready-<token>.json`. Bridge enforces a 30s timeout — a hung probe still produces the sentinel. |
| `snapshot` | `dest=<basename>`                  | —                                     | Build a `DebugSnapshot` and write it to `Caches/DebugBridge/<dest>`.                                                                                                |
| `eval`     | `bridge=<basename>`, `js=<base64>` | —                                     | Run JS in the active reader's webview; write result/error to `Caches/DebugBridge/eval-<bridge>.json`.                                                               |
| `tts`      | `action=start\|stop`               | —                                     | Drive `TTSService` from outside the play-button tap (Feature #45 WI-4c-b). XCUITest's gesture path cannot reliably activate `AVSpeechSynthesizer`'s audio session, so verification tests fire this URL after opening a book. No-op when no reader is presented. |
| `search`   | `query=<str>`                      | `index=<int>`                         | Drive the in-reader search sheet (Bug #238). Opens the search sheet, sets `SearchViewModel.query` to `query`, and — when `index` (0-indexed, ≥0) is supplied — taps result N once results arrive (re-fires `.readerNavigateToLocator` then dismisses the sheet, mirroring the real-user tap path). Used by the verify harness to reproduce search-result-tap repros (e.g. Bug #182 cross-chapter EPUB search highlight) CU-free. No-op when no reader is presented. |
| `highlight`| `start=<int>`, `end=<int>`         | `color=<yellow\|pink\|green\|blue>`   | Create a highlight at UTF-16 range `[start, end)` in the active TXT/MD/EPUB reader (Bug #237 TXT/MD; Bug #220 EPUB). Bypasses the long-press → SelectionPopoverView gesture path (XCUITest cannot synthesize it on iOS 26). The TXT/MD observer builds a format-correct `Locator` via `LocatorFactory` (extracting `textQuote` + context from source) and calls `HighlightCoordinator.create(...)`. The EPUB observer evaluates `EPUBDebugBridgeHighlightJS.buildResolveRangeJS(...)` in the active WKWebView to walk visible text nodes (skipping bilingual `data-vreader-decoration` siblings) and map `[start, end)` UTF-16 offsets to a DOM `EPUBSerializedRange`, snaps surrogate-pair boundaries, then calls the same `HighlightCoordinator.create(...)` with `AnnotationAnchor.epub(...)`. Either path is byte-identical to a gesture-created highlight at the same offsets (`canonicalHash` matches, so dedupe works correctly). PDF / AZW3 don't register the observer; the URL is silently a no-op for them. |
| `provider` | `action=add\|remove\|clear` (plus action-specific params, see below) | — | Configure AI provider profiles for autonomous AI-feature verification (Bug #243). `action=add` inserts (or replaces by display name) a `ProviderProfile` in `ProviderProfileStore.shared` and saves its API key to the per-profile Keychain account (`add` requires `name`, `kind=<openAICompatible\|anthropicNative>`, `endpoint=<http(s) URL>`, `apiKey`; optional `model=<id>`, `active=<true\|false>`). Re-running an `add` URL with the same `name` reuses the existing UUID + keychain account — the operation is idempotent so `remove(name:)` always has a deterministic target. `action=remove` deletes the profile with the given display `name` + its keychain entry. `action=clear` wipes every profile + every per-profile keychain entry + the active selection. The handler auto-promotes the first added profile to active (so a single `add` URL leaves the harness in a usable state). All three sub-actions are idempotent and unlock CU-free AI-feature verification (Feature #56 b/d, Feature #65/#69, Bug #93) regardless of CU availability. |
| `present`  | `sheet=toc\|highlights\|ai\|settings\|bookmarks` | `tab=<...>`, `detent=medium\|large` (`ai` only) | Present a reader sheet so its rendered content becomes CU-free verifiable via `snapshot` + `eval` (Bug #253). Posts `.debugBridgePresentSheet`; the active reader's observer maps `(sheet, tab, detent)` to the **same** `@State` / `annotationsRoute` / `presentationDetents(selection:)` binding the chrome buttons + a user drag set (no parallel presentation logic), so the harness drives the real presentation path. `sheet=toc` presents `TOCSheet` (Contents/Bookmarks); `sheet=highlights` presents `HighlightsSheet` (All/Highlights/Notes/Bookmarks review); `sheet=ai` presents `AIReaderPanel` (Summarize/Translate/Chat) — gated on `resolvedAICoordinator.isAIAvailable` (configure a provider first via `provider?action=add`), and a `tab=translate` open resets stale Translate-tab state to match the production selectionless-translate path; `sheet=settings` presents the reader settings panel; `sheet=bookmarks` is a top-level alias for the `TOCSheet` Bookmarks tab. The `tab` param selects a sub-tab (see Parameter validation). The `detent` param (Bug #256, `ai`-only) sets the AI sheet's active detent — `detent=large` reveals the Translate-tab `.complete` result card (`translationResultCard`) that renders below the `.medium` fold beneath the tall auto-extracted ORIGINAL card, so a follow-up `snapshot`/`eval` captures it without a drag/scroll gesture. No-op when no reader is presented (mirrors `tts` / `search` / `highlight`). |
| `ai`       | `action=summarize\|chat\|translate` | `scope=section\|chapter\|book` (summarize only), `text=<str>` | Fire the AI action the **presented** AI sheet exposes (Bug #255). `present?sheet=ai` opens the panel; this fires the action the chrome buttons trigger, so the **AI-response-card** render states (Summarize `.complete` card, Chat assistant bubble, Translate result card) become CU-free verifiable. Posts `.debugBridgeAIAction`; `AIReaderPanel`'s observer invokes the **same** view-model path the button does — `AISummaryTabView.runSummarize` (incl. its in-flight guard) / `AIChatView.sendCurrentMessage` (incl. the `isLoading` gate) / `TranslationPanel.requestTranslation` — no parallel AI call. `action=summarize` runs the Summarize tab's summary at the selected `scope` over the full book text; `action=chat` sends `text` (the message) on the Chat tab; `action=translate` runs the Translate tab's translation (`text` overrides the target language; absent → the panel's current target). The observer also switches the panel to the action's tab so a follow-up `snapshot` reflects the right surface. No-op when no AI sheet is presented (mirrors `present`). Requires a configured provider (`provider?action=add`) and the AI-availability gate satisfied (which `present?sheet=ai` already enforces). |
| `seed-sessions` | `book=<fingerprintKey>`        | `seconds=<int>`                       | Seed synthetic `ReadingSession` rows so the reading dashboard (Feature #58) renders non-zero per-window totals CU-free (Bug #263). The dashboard reads `ReadingSession` records, but `seed?fixture=…` seeds only books — so without this the dashboard is always all-zero. Inserts a deterministic **6-session spread** attached to `book`, one per bounded time band (today = midpoint of the elapsed local day; then `now − {3d, 15d, 60d, 120d, 300d}`), each lasting `seconds` (default 600). Because the dashboard windows nest, the per-window totals come out **strictly increasing** (today < 7d < 30d < 90d < 180d < all), so the 7-window render + per-book table + sort all have distinct, deterministic data to assert on. Rows are inserted through the real `PersistenceActor`/`ReadingSession`/`ModelContext` path (the `seedSyntheticReadingSessions` seam — same path as `SwiftDataSessionStore.saveSession`, no parallel store), and the book's `ReadingStats` aggregate is refreshed for Library-sort parity. Every `endedAt` is clamped to `now` (no future `lastReadAt`). **NOT idempotent** — each call adds another 6-session spread, so `reset` first. Unlike `open`/`present`/`ai`, this needs **no** active reader (the dashboard reads persisted state). `book` need not match a live `Book` row — an orphan key surfaces as the dashboard's "(deleted)" row. |
| `seek`     | `fraction=<0...1>`                 | —                                     | Drive the active **Foliate** (AZW3/MOBI) reader to a fractional reading position (Bug #267). Posts `.debugBridgeSeekFraction`; the live `FoliateBilingualContainerView`'s DEBUG observer re-posts `.foliateRequestSeekFraction` with the active book's `fingerprintKey` injected (the spike's seek observer filters by key), and the spike evaluates `readerAPI.goToFraction(<fraction>)` — the same channel the bottom-chrome scrubber uses. Lets the harness reach a **distinguishable non-start position** (e.g. `seek?fraction=0.5` on `mini-azw3` moves section 0 → section 4) so a save→reopen→restore round-trip can be told apart from a default open-at-start. `fraction` is clamped to `0...1`; non-finite is rejected. No-op when no Foliate reader is loaded (mirrors `present`/`tts`). |
| `scroll-sheet` | `to=top\|bottom`               | —                                     | Scroll the active presented sheet's scrollable content to an end (Bug #271). `detent=large` (Bug #256) reveals the larger AI sheet, but on the Translate tab the tall auto-extracted ORIGINAL card alone exceeds even the `.large` height, so the accent translation card (`translationTranslatedCard`) stays below the fold; `to=bottom` drives `TranslationResultCard`'s `ScrollViewReader` to its bottom anchor so `simctl io screenshot` captures the translation card, `to=top` returns to the ORIGINAL card. Posts `.debugBridgeScrollSheet`; the card's observer maps the target to `proxy.scrollTo(_:anchor:)` (no `withAnimation` — deterministic/instant), no parallel scroll logic. **Order-independent**: a scroll requested *before* the result card mounts (the card only exists once translation completes) is recorded in `DebugBridgeScrollSheetState` and replayed on the card's `.onAppear`; the buffer is cleared on `reset` and on every fresh `ai?action=translate` so a stale target never replays onto a later card. No-op when no scrollable sheet observes it (mirrors `present`/`tts`). Issued **after** `ai?action=translate` completes. |

### Parameter validation

- `token`, `dest`, `bridge`: `[A-Za-z0-9._-]{1,64}` and not dot-only (`.` / `..` / `...` rejected). Path-traversal-safe.
- `fixture`: must match a catalog entry (`DebugFixtureCatalog`). Currently `war-and-peace` only; the catalog grows as fixtures are bundled.
- `position` (`open`): optional per-format seek target (Bug #257). **TXT / MD** → a non-negative UTF-16 character offset (e.g. `position=800`); **PDF** → a 1-based page number (e.g. `position=3`, mapped internally to the 0-based `Locator.page`); **AZW3** (azw/mobi/prc) → a non-empty Foliate CFI string (e.g. `position=epubcfi(/6/12!/4/3)`). **EPUB is rejected** with `bridge.seekUnsupportedForFormat: epub <position>` — its navigate handler resolves the spine by `href`, not raw CFI, so a CFI-only seek would silently no-op; the bridge fails loudly *before* opening the book rather than landing at the wrong place. Invalid shapes (negative offset, page < 1, empty CFI) throw `parse`/`bridge.invalidPosition`. After a valid seek, `snapshot.position` reports where the reader actually landed — for paged TXT this is the **page-top** offset of the page containing the requested offset (so e.g. `position=1000` in the small war-and-peace fixture reads back as `949`), not the exact requested value; continuous-mode books land on the requested offset.
- `mode`: literal `dark` or `light`. Anything else throws `parse.invalidParam: mode`.
- `fontSize`: integer.
- `js`: standard base64 of UTF-8 source.
- `query` (`search`): non-empty UTF-8 string. Percent-encode CJK / spaces / etc. before passing — `URLComponents` decodes it back before the parser sees it.
- `index` (`search`): non-negative integer; rejected if empty, non-integer, or negative. Without `index`, the URL runs the query and leaves the sheet open.
- `start` / `end` (`highlight`): non-negative integers with `end > start`. A zero-length range (`start == end`) is rejected — the user gesture path requires `selectedRange.length > 0` too.
- `color` (`highlight`): one of `yellow` / `pink` / `green` / `blue` (the four `NamedHighlightColor` rawValues). Unknown or empty values rejected; omit the parameter to default to `yellow`.
- `action` (`provider`): one of `add` / `remove` / `clear`. Anything else throws `parse.invalidParam: action`.
- `name` (`provider`): non-empty display name. Required for `add` + `remove`; ignored for `clear`. The name (not the UUID) is the key for `remove` because the harness produces names — UUIDs aren't useful at the URL boundary.
- `kind` (`provider` `add`): one of `openAICompatible` / `anthropicNative`. Maps 1:1 to `ProviderKind`.
- `endpoint` (`provider` `add`): an absolute URL with a host. Mirrors the production add-provider preflight (`AISettingsViewModel.validateBaseURL`): HTTPS-only except `http://localhost` / `http://127.0.0.1`. Empty / opaque (`https:foo`) / scheme-less / non-localhost-HTTP values rejected at parse so the handler doesn't insert a profile whose URL would fail at request time.
- `apiKey` (`provider` `add`): non-empty string. Trimmed of leading/trailing whitespace + newlines before save (mirrors `AISettingsViewModel.addProfile`). Saved to Keychain under the per-profile account (`com.vreader.ai.apiKey.<UUID>`).
- `model` (`provider` `add`): optional model id. When omitted, defaults to `kind.defaultModel` (e.g., `gpt-4o-mini` for `openAICompatible`).
- `active` (`provider` `add`): optional `true` / `false`. When `true`, the new profile is set active (even if another profile already is). When `false` or omitted, the handler auto-promotes to active only when no profile is currently active.
- `sheet` (`present`): one of `toc` / `highlights` / `ai` / `settings` / `bookmarks`. Anything else (or empty) throws `parse.invalidParam: sheet` (empty throws `parse.missingParam: sheet`).
- `tab` (`present`): optional sub-tab, validated against the sheet's vocabulary — `toc`: `contents` / `bookmarks`; `highlights`: `all` / `highlights` / `notes` / `bookmarks`; `ai`: `summarize` / `translate` / `chat`. `settings` and `bookmarks` take **no** `tab` (`bookmarks` is itself the Bookmarks-tab selector) — passing one throws `parse.invalidParam: tab`. An out-of-vocabulary or empty `tab=` is rejected. Omit `tab` to open each sheet on its default tab (`toc`→Contents, `highlights`→All, `ai`→Summarize).
- `detent` (`present`): optional AI-sheet detent (Bug #256) — one of `medium` / `large`. **`ai`-only**: only `AIReaderPanel` declares `presentationDetents`, so a `detent` on `toc` / `highlights` / `settings` / `bookmarks` throws `parse.invalidParam: detent`. Unknown or empty `detent=` is rejected. When supplied, the observer sets the AI sheet's `presentationDetents(_:selection:)` binding (the SAME binding a user drag reaches) — `detent=large` exposes the larger detent so the Translate-tab below-`.medium`-fold result card becomes capturable. Omit to leave the default `.medium` presentation untouched. (Each fresh `present?sheet=ai` open without `detent` resets the binding to `.medium`, so a prior `detent=large` never carries over.)
- `action` (`ai`): one of `summarize` / `chat` / `translate`. Anything else (or empty) throws `parse.invalidParam: action` (empty throws `parse.missingParam: action`).
- `scope` (`ai`): summarize-**only** sub-scope — one of `section` / `chapter` / `book`. The URL-friendly `book` maps to `SummaryScope.bookSoFar` (`section` / `chapter` map 1:1); the notification payload + observer carry the `SummaryScope` rawValue (`bookSoFar`). Passing `scope` on `chat` / `translate` throws `parse.invalidParam: scope` (it's meaningless there). Empty / unknown values rejected. Omit to keep the panel's current scope chip (defaults to Section on first open).
- `text` (`ai`): **required** for `chat` (the message to send — empty throws `parse.missingParam: text`, mirroring the chrome's non-empty `canSend` gate); **optional** for `translate` (overrides the target language, e.g. `text=Spanish`; absent → the rail's pre-selected language). Ignored for `summarize` (the `scope` chip drives the summary). Percent-encode spaces / CJK / `?` before passing — `URLComponents` decodes it back before the parser sees it.
- `book` (`seed-sessions`): a canonical fingerprint key (`<format>:<sha256>:<byteCount>`, e.g. the value `seed`/`open` log + the dashboard reads). Required and non-empty (empty throws `parse.missingParam: book`). A non-canonical value can't materialize a `DocumentFingerprint`, so the handler throws `bridge.invalidFingerprintKey: <key>` (visible in `snapshot.lastError`) and seeds nothing. Percent-encode the `:` separators before passing (`URLComponents` decodes them back).
- `seconds` (`seed-sessions`): optional per-session `durationSeconds`; defaults to `600`. Must be a positive integer — empty / non-integer / `< 1` values throw `parse.invalidParam: seconds`. Every seeded session uses this duration, so the per-window totals are exact multiples of it (today = 1×, 7d = 2×, … all = 6×).
- `to` (`scroll-sheet`): one of `top` / `bottom`. Required and non-empty (empty throws `parse.missingParam: to`); anything else throws `parse.invalidParam: to`.
- Duplicate query keys throw `parse.invalidParam: <name>: duplicate parameter`.

## Driving the bridge from a verification flow

The bridge can be driven from two places. They are NOT interchangeable — pick the right one for the surface you control.

### HOST-driven (primary, works) — the verify cron pattern

Every verification driver under `dev-docs/verification/<feature-or-bug>/` invokes `xcrun simctl openurl` from a host-side bash script (outside any iOS sandbox). The simulator host receives the URL, the app routes it via `.onOpenURL`, and the bridge runs. The DebugBridge commands shipped 2026-05-20 (`search`, TXT/MD/EPUB `highlight`) all work via this path. This is the canonical pattern — use it for new verification flows.

```bash
# Resolve the booted simulator UDID (host-side; no sandbox in the way).
SIM_ID=$(xcrun simctl list devices booted | awk '/Booted/ {print $(NF-1); exit}' | tr -d '()')

# Drive the bridge from the host. The simulator's CoreSimulatorService
# accepts the openurl XPC call and forwards it into the app.
xcrun simctl openurl "$SIM_ID" "vreader-debug://highlight?start=40&end=1500"

# Read assertion state back from the app container — also host-side.
DATA=$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)
cat "$DATA/Library/Caches/DebugBridge/state.json"
```

### In-runner via `VerificationDebugBridgeHelper.openURL(...)` — DOES NOT WORK (bug #1054)

Calling `xcrun simctl openurl` from **inside** an XCUITest binary (e.g. via `VerificationDebugBridgeHelper.openURL(...)`) exits 72 with stderr:

```
Failed to load CoreSimulatorService — running with a sandbox profile
NSPOSIXErrorDomain code 61 ("Connection refused")
```

The XCUITest runner sandbox does not have a path to the host's `CoreSimulatorService` XPC endpoint, so the URL never reaches the simulator host and the app never sees it. This is **structural to the XCUITest sandbox** — it is not a vreader-specific bug and there is no flag to flip. The bridge URL handlers themselves work; they just cannot be reached from inside the runner.

This bit the F#11 / F#64 verification XCUITest modernization (PR #1053, GH #1049) when the new `vreader-debug://highlight?...` command was assumed callable in-runner — see bug #240 / bug #242 in `docs/bugs.md`.

### `XCTSkipUnless(bridgeReachable())` — the in-runner workaround (PR #1053)

When an XCUITest needs to assert something the bridge produces but the bridge can't be reached from inside the runner, the runner probes reachability up front and skips with an explicit reason:

```swift
// Inside an XCUITest method that depends on a vreader-debug:// URL.
let bridge = VerificationDebugBridgeHelper(app: app)
try XCTSkipUnless(
    bridge.bridgeReachable(),
    "vreader-debug:// is unreachable from the XCUITest runner sandbox " +
    "(NSPOSIX 61). HOST-driven verification covers this assertion via " +
    "the bash driver in dev-docs/verification/..."
)
```

This preserves the regression net that the XCUITest provides for any non-bridge-dependent gate (e.g. accessibility identifiers, layout, navigation) while letting the host-driven layer carry the bridge-dependent assertions.

**Choosing between the two paths**: if the assertion needs CoreSimulator (open a URL, write to the app container), use the HOST-driven path. If it's a UI / AX / layout assertion, the XCUITest in-runner path is fine. If it's both, do the bridge driving from the host driver and let the XCUITest assert only on what's observable through XCUITest's own API.

## Driving AI-feature verification (Bug #243)

AI features (Feature #56 bilingual mode b/d criteria, Feature #65 AI sheet re-skin, Feature #69 AI Summarize scope selector, Bug #93 chat sessions) all require a configured `ProviderProfile`. Before Bug #243's fix the only way to configure a provider was Settings → AI driven through computer-use; that's fragile when CU is flapping (Bug #1054 sandbox + display-state issues), so AI-feature verification couldn't run autonomously.

The `provider` URL family closes that gap. The typical flow:

```bash
# 1. Wipe library + provider state.
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://provider?action=clear"

# 2. Configure an OpenRouter-backed OpenAI-compatible provider. Reads the
#    free-tier key from .secrets/.env (gitignored). The active flag tells
#    the handler to set this as the active profile so AI requests resolve
#    against it immediately.
set -a; source .secrets/.env; set +a
ENDPOINT_ENC=$(printf '%s' "https://openrouter.ai/api/v1" | jq -sRr @uri)
KEY_ENC=$(printf '%s' "$OPENROUTER_API_KEY" | jq -sRr @uri)
xcrun simctl openurl "$SIM_ID" "vreader-debug://provider?action=add&name=OpenRouter&kind=openAICompatible&endpoint=${ENDPOINT_ENC}&apiKey=${KEY_ENC}&model=mistralai%2Fmistral-7b-instruct&active=true"

# 3. Seed a fixture book, open it, and start exercising the AI feature.
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED_KEY"
# ... feature-specific driving (e.g. UI taps for the AI sheet) ...

# 4. Tear down for the next iteration so providers don't leak across runs.
xcrun simctl openurl "$SIM_ID" "vreader-debug://provider?action=clear"
```

Key properties:

- **API key never logs**: the URL is opaque to the harness operator, and the handler logs only `kind` / `model` / `active`, never the key.
- **Mutations propagate naturally**: the handler writes to `ProviderProfileStore.shared`, which posts `.providerProfilesDidChange` itself. Any in-app picker / Settings VM resyncs without a bridge-specific notification — the production code path is exercised end-to-end.
- **First-add auto-active**: omitting `active=` on the first `add` URL still leaves the harness with an active profile, so single-provider flows can drop the flag.
- **`remove` keys on display name**: the harness produces names, so the URL boundary uses names instead of UUIDs.
- **`clear` is the right teardown**: leaves the next iteration with a known-empty `ProviderProfileStore`; also drops the per-profile Keychain entries.

## Driving sheet-content verification (Bug #253)

Several visible-verification close-gates need a reader sheet **open** so its
rendered content can be inspected — but computer-use can't tap the chrome
button on the virtual-display host, and (before Bug #253) no `vreader-debug://`
command presented a sheet. The `present` family closes that gap. The sheet is
presented through the same `@State` / `annotationsRoute` the chrome buttons set
(no parallel presentation logic), so what you observe is the real sheet.

```bash
SIM_ID=<udid>

# 1. Seed + open a book (the present command is a no-op with no reader open).
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
# (resolve the seeded book's fingerprintKey from a snapshot, then:)
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=<key>"

# 2. Present the Contents (TOC) sheet — e.g. to verify Bug #248's
#    auto-scroll + current-chapter highlight.
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=toc&tab=contents"

# 3. Snapshot / eval to inspect the now-presented sheet's content.
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-present.json"

# Other sheets:
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=highlights&tab=notes"
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=ai&tab=summarize"   # needs a provider configured
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=settings"
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=bookmarks"          # TOC sheet → Bookmarks tab
```

### Drive an AI action (Bug #255) — the AI-response-card close-gate

`present?sheet=ai` only shows the **idle** AI sheet — the response cards
(Summarize `.complete`, Chat bubble, Translate result) need the action to
actually fire, which used to require a chrome-button tap CU can't reach. The
`ai` command fires that action through the same view-model path the button
takes, so the response card renders against the host-configured provider.

```bash
SIM_ID=<udid>

# 0. Configure a provider + present the AI sheet first (the gate + the panel
#    must exist — `ai` is a no-op otherwise). `present?sheet=ai` enforces the
#    AIReaderAvailability gate.
xcrun simctl openurl "$SIM_ID" "vreader-debug://provider?action=add&name=OR&kind=openAICompatible&endpoint=https://openrouter.ai/api/v1&apiKey=<key>&active=true"
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=ai&tab=summarize"

# 1. Fire the Summarize action at the Chapter scope (Feature #69 criteria 7-8).
xcrun simctl openurl "$SIM_ID" "vreader-debug://ai?action=summarize&scope=chapter"

# 2. Snapshot / eval once the response streams in to inspect the summary card.
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-summarize.json"

# Other AI actions (Feature #65 rows 6 + 11):
xcrun simctl openurl "$SIM_ID" "vreader-debug://ai?action=chat&text=who%20is%20the%20narrator%3F"  # chat send
xcrun simctl openurl "$SIM_ID" "vreader-debug://ai?action=translate&text=Spanish"                  # translate, language override
xcrun simctl openurl "$SIM_ID" "vreader-debug://ai?action=summarize&scope=book"                    # Book-so-far scope

# Translate result card below the fold (Bug #256 / Feature #65 row 11): on the
# Translate tab the tall ORIGINAL card fills the visible .medium area, pushing
# `translationResultCard` below the fold. Re-present the AI sheet on .large to
# reveal it for snapshot/eval (no drag/scroll gesture needed):
xcrun simctl openurl "$SIM_ID" "vreader-debug://present?sheet=ai&tab=translate&detent=large"
xcrun simctl openurl "$SIM_ID" "vreader-debug://ai?action=translate&text=Spanish"
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-translate-large.json"  # now captures the result card
```

Key properties:

- **Real presentation path**: `present` sets the exact `annotationsRoute` /
  `showAIPanel` / `showSettings` the Contents / Notes / AI / Display chrome
  buttons set. A `DebugPresentSheetEffect` resolver pins this — its default
  `toc`/`highlights` routes derive from `AnnotationsSheetRoute.route(forChromeButton:)`.
- **AI gate honored**: `sheet=ai` is a no-op when no provider is configured
  (matches the chrome's AI gate). Configure one first with `provider?action=add`.
  A `tab=translate` open resets stale Translate-tab state, matching the
  production selectionless-translate path.
- **No-op without a reader**: like `tts` / `search` / `highlight`, the URL is
  silently a no-op when no book is open (the observer only fires on a mounted
  reader).
- **Unblocks**: Bug #248 (TOC scroll+highlight), Feature #65 (AI sheet
  re-skin), Feature #69 (AI Summarize scope chips), the future Bug #249
  (HighlightsSheet delete).

## Driving reading-dashboard verification (Bug #263)

The reading dashboard (Feature #58) reads `ReadingSession` records, but
`seed?fixture=…` seeds only books — so the dashboard renders all-zero data
CU-free until sessions exist. `seed-sessions` fills that gap with a
deterministic spread:

```bash
SIM_ID=<udid>

# 1. Clean state + seed a book; capture its fingerprint key.
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"

# The key is logged by `seed` (and is the war-and-peace fixture's stable
# SHA). Read it back from the SwiftData store if you don't have it:
STORE="$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)/Library/Application Support/default.store"
KEY=$(sqlite3 "$STORE" "SELECT ZFINGERPRINTKEY FROM ZBOOK LIMIT 1;")

# 2. Seed sessions (percent-encode the ':' separators).
ENCKEY=$(python3 -c "import urllib.parse,sys;print(urllib.parse.quote(sys.argv[1],safe=''))" "$KEY")
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed-sessions?book=$ENCKEY"          # 600s/session (default)
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed-sessions?book=$ENCKEY&seconds=1800"  # or a custom duration

# 3. Assert the seeded rows (the dashboard aggregator reads exactly these):
sqlite3 "$STORE" "SELECT COUNT(*) FROM ZREADINGSESSION;"   # 6 per seed-sessions call
sqlite3 "$STORE" "SELECT ZTOTALREADINGSECONDS, ZSESSIONCOUNT FROM ZREADINGSTATS;"  # 3600, 6 (at 600s)
```

Key properties:

- **Real persistence path**: rows go through the `seedSyntheticReadingSessions`
  seam on `PersistenceActor` (same `ModelContext`/`ReadingSession` path as
  `SwiftDataSessionStore.saveSession`), and the book's `ReadingStats` aggregate
  is refreshed — so both the dashboard (which reads sessions) and the Library
  reading-time sort (which reads stats) reflect the seed. No parallel store.
- **Strictly-increasing windows**: the 6 bands nest, so the dashboard's
  per-window totals are `today < 7d < 30d < 90d < 180d < all` — distinct,
  deterministic numbers for asserting the 7-window pill bar + per-book table.
- **Midnight-safe + no future timestamps**: the today band anchors at the
  midpoint of the elapsed local day (never slips past midnight), and every
  `endedAt` is clamped to `now`.
- **No reader needed**: unlike `present` / `ai`, the dashboard reads persisted
  state, so seeding alone is enough — no book has to be open.
- **NOT idempotent**: each call adds another 6-session spread, so `reset` first
  for a clean baseline.
- **Unblocks**: Feature #58 Gate-5b criteria b (all-7-windows-render), c
  (per-book table + sort), d (sort persists).

## Output files

All output lives in the app container at `Library/Caches/DebugBridge/`. Read from the host via:

```bash
DATA=$(xcrun simctl get_app_container <udid> com.vreader.app data)
cat "$DATA/Library/Caches/DebugBridge/<file>"
```

### `snapshot` → `<dest>`

```json
{
  "schemaVersion": 1,
  "ts": "2026-05-02T13:32:20Z",
  "currentBookId": "txt:ab02...:1708",
  "format": "txt",
  "position": null,
  "selection": null,
  "theme": "dark",
  "fontSize": 24,
  "highlightCount": 0,
  "renderPhase": "idle",
  "lastError": null,
  "partial": ["selection"]
}
```

- Sorted keys, pretty-printed, explicit `null` for nil.
- `schemaVersion`: bump on field add/remove/semantics-change. Pin a known version in CI.
- `partial`: field names whose nil value means "not yet implemented". Empty/absent ⇒ every nil is authoritative. Currently always contains `"selection"`; without an active reader also contains `"currentBookId"`, `"format"`, `"position"`.
- `lastError`: stable category prefix, not Swift enum spelling. See "Error codes" below.

### `settle` → `ready-<token>.json`

Happy path:

```json
{
  "fingerprintKey": "txt:ab02...:1708",
  "format": "txt",
  "position": null,
  "token": "demo",
  "ts": "2026-05-02T12:58:58Z"
}
```

Timeout path:

```json
{
  "fingerprintKey": "...",
  "format": "...",
  "position": null,
  "token": "demo",
  "ts": "...",
  "error": "settle timeout",
  "phase": "unknown"
}
```

### `eval` → `eval-<bridge>.json`

Always written, even on error. `result` is the raw JSON value returned by the JS expression, not a string-encoded JSON.

Happy path:

```json
{
  "bridge": "foliate",
  "fingerprintKey": "...",
  "format": "epub",
  "result": 3,
  "ts": "..."
}
```

Error path:

```json
{
  "bridge": "foliate",
  "fingerprintKey": "...",
  "format": "txt",
  "error": "eval unsupported for format: txt",
  "ts": "..."
}
```

## Error codes

Error reporting comes in two flavors:

**`snapshot.lastError`** uses stable `category.kind: detail` strings produced by `DebugBridge.stableErrorMessage`. Pin on the prefix, not the detail:

| Prefix                                      | Meaning                                        |
| ------------------------------------------- | ---------------------------------------------- |
| `parse.invalidScheme`                       | URL scheme isn't `vreader-debug`               |
| `parse.unknownCommand: <host>`              | Host isn't a known command name                |
| `parse.missingParam: <name>`                | Required parameter absent or empty             |
| `parse.invalidParam: <name> (<reason>)`     | Parameter failed validation                    |
| `bridge.unknownFixture: <name>`             | `seed` got a name not in the catalog           |
| `bridge.fixtureResourceMissing: <basename>` | Catalog entry exists but bundle file is absent |
| `bridge.notImplemented: <command>`          | Path not yet wired (e.g. `open.position`)      |
| `bridge.bookNotFound: <bookId>`             | `open` received an unknown fingerprint key     |
| `bridge.noActiveReader`                     | `eval` ran with no reader presented (NOT `settle` — see below) |
| `bridge.settleTimeout`                      | `settle` gave up after 30s                     |
| `bridge.evalUnsupported: <format>`          | Active reader doesn't support JS eval          |
| `bridge.evalFailed: <msg>`                  | JS execution threw                             |

**`error`**\*\* field in ****`ready-<token>.json`**** and \*\***`eval-<bridge>.json`** is currently a plain English string written directly by the handler. **Do not pin assertions on these strings** — they may change. Possible values today:

| File                 | Possible `error` values                                                                |
| -------------------- | -------------------------------------------------------------------------------------- |
| `ready-<token>.json` | `"settle timeout"` (with `phase: "unknown"`), `"no active reader"` (bug #125 — also with `phase: "unknown"`; probe-shaped fields `fingerprintKey`/`format`/`position` are absent on this path), `"webview not registered"` (bug #250 — EPUB/AZW3 probe settled but format-specific WebView slot is empty or stale-token at the registry; downstream `eval` / `highlight-create` would fail) |
| `eval-<bridge>.json` | `"no active reader"`, `"eval unsupported for format: <fmt>"`, raw JS error description |

For `settle` specifically: the no-active-reader case is reported via the sentinel file (`error: "no active reader"`), NOT via `snapshot.lastError`. `settle` does not throw on this path, so the bridge's `lastError` stays clear. Verification harnesses must poll `ready-<token>.json` regardless of reader state.

For `eval` and the rest of the failure space, assert on the snapshot's `lastError` after running the failing command — it uses the stable prefixes and is the recommended assertion surface.

## Architecture

```
xcrun simctl openurl
        │
        ▼
.onOpenURL (VReaderApp, #if DEBUG only)
        │
        ▼
DebugBridge.handle(url)        ← serializes commands; records lastError
        │
        ▼
DebugCommand.parse(url)         ← path/scheme/param validation
        │
        ▼
RealDebugBridgeContext           ← real handlers
        ├─ persistence (PersistenceActor)        for reset/seed/open/snapshot
        ├─ importer (BookImporting)              for seed
        ├─ ReaderSettingsStore (UserDefaults)    for theme
        └─ DebugReaderRegistry.shared            for settle/eval/snapshot
                │
                ▼
        DebugReaderProbe (weak ref)              ← ReaderContainerView
                                                    registers on .onAppear
```

### Active-reader registry

`DebugReaderRegistry.shared` holds a weak reference to the currently-presented reader. `ReaderContainerView` creates a `DebugReaderProbeAdapter` in `@State`, registers on `.onAppear`, unregisters on `.onDisappear`.

The probe protocol exposes:

- `fingerprintKey: String`
- `format: String`
- `currentPositionString: String?`
- `func awaitSettle(timeout:) async throws`
- `func evaluateJavaScript(_:) async throws -> Data` (raw JSON bytes)

Default adapter:

- `awaitSettle`: sleeps 100ms (placeholder until per-format hooks land — Foliate `relocate` event, TextKit layout completion).
- `evaluateJavaScript`: throws `evalUnsupported(format:)`. EPUB/AZW3 readers will plug a real evaluator into `jsEvaluator` once the active webview is exposed.

## Repro recipes

Each recipe drives the simulator to a known reproduction state for a tracker entry. Use the snapshot/ready files to assert on outcome.

### Bug #107 — Cover images with light edges look like padding (Library)

```bash
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"
xcrun simctl io "$SIM_ID" screenshot /tmp/library-edges.png
# Visual inspection: the war-and-peace card is a TXT with no cover so this
# specific bug needs an EPUB/AZW3 fixture with a white-edged cover. Add the
# fixture to DebugFixtureCatalog when sourced.
```

Status: **partial** — needs an EPUB fixture with a white-edged cover. Recipe blocked on fixture sourcing.

### Bug #108 — AZW3/Foliate reader: center tap doesn't toggle chrome

```bash
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=sample-azw3"   # NOT YET IN CATALOG
ENCODED_KEY="..."
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED_KEY"
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=open"

# Center-tap requires a real touch — DebugBridge can't dispatch UIEvents.
# Use computer-use after settle to click the screen center, then snapshot
# and check theme.fontSize / a chrome-visible flag.
```

Status: **needs ********`sample.azw3`******** fixture and a chrome-visible probe field**. Center-tap itself is computer-use territory.

### Generic verification recipe (template for feature #45)

```bash
# 1. Clean state
xcrun simctl openurl "$SIM_ID" "vreader-debug://reset"

# 2. Seed required fixture
xcrun simctl openurl "$SIM_ID" "vreader-debug://seed?fixture=war-and-peace"

# 3. Set known theme/font
xcrun simctl openurl "$SIM_ID" "vreader-debug://theme?mode=light&fontSize=18"

# 4. Open the book
ENCODED_KEY="txt%3A<sha>%3A<bytes>"
xcrun simctl openurl "$SIM_ID" "vreader-debug://open?bookId=$ENCODED_KEY"

# 5. Wait for render
xcrun simctl openurl "$SIM_ID" "vreader-debug://settle?token=ready"

# 6. (Optional) Drive any user actions via computer-use here.
#    Then snapshot to capture state for assertions.
xcrun simctl openurl "$SIM_ID" "vreader-debug://snapshot?dest=after-action.json"

# 7. Read + assert
DATA=$(xcrun simctl get_app_container "$SIM_ID" com.vreader.app data)
jq '.theme == "light" and .currentBookId != null' \
   "$DATA/Library/Caches/DebugBridge/after-action.json"
```

## Acceptance gate

`scripts/verify-release-no-debugbridge.sh` checks:

1. `Info.plist` does not declare the `vreader-debug` URL scheme.
2. No `DebugFixtures` directory in the bundle.
3. No catalog fixture filenames in the bundle.
4. No DebugBridge-named files in the bundle.
5. No DebugBridge-related strings in bundle resources.
6. No DebugBridge-related strings in the main binary.

Run after a Release build:

```bash
xcodebuild build -configuration Release -derivedDataPath /tmp/vreader-release-build
./scripts/verify-release-no-debugbridge.sh
```

Exits 0 only if all six checks pass.

`scripts/verify-debug-has-debugbridge.sh` is the inverse for Debug builds: confirms the URL scheme is wired into the Info.plist of the freshest Debug build. Catches regressions of bug #121 (DebugBridge.plist orphaned from Info.plist).

## iOS scheme-approval prompt (bug #123)

When `simctl openurl` (running as `CoreSimulatorBridge`) opens `vreader-debug://` on a simulator that has no prior approval entry, iOS LaunchServices presents a one-shot **"Open in 'vreader'?"** alert from `lsd`. The alert is the standard third-party scheme-approval prompt. Until someone taps **Open**, the URL is held by `lsd` and never reaches `.onOpenURL` — `simctl openurl` exits 0 because LaunchServices accepted the request, not because the app received it.

After approval, the grant is persisted in:

```
~/Library/Developer/CoreSimulator/Devices/<UDID>/data/Library/Preferences/com.apple.launchservices.schemeapproval.plist
```

with key:

```
"com.apple.CoreSimulator.CoreSimulatorBridge-->vreader-debug" = com.vreader.app
```

The key tells you the exact scope of the approval: source app `CoreSimulatorBridge` opening the `vreader-debug` scheme on this simulator. Other source apps (e.g. another iOS app calling `UIApplication.open`) would have their own approval entries. The grant survives reinstalls of the app bundle. It does *not* survive `simctl erase`.

For automated verification (no human to tap **Open**), pre-grant the approval before the first `openurl`:

```bash
scripts/grant-debug-scheme-approval.sh         # uses booted device
scripts/grant-debug-scheme-approval.sh <UDID>  # specific device
```

The script writes the plist entry directly. Idempotent — safe to run on every harness setup.

In practice the prompt only appears on a freshly-erased simulator, because `lsd` retains the approval across plist edits, lsd restarts, and app reinstalls. The grant script is defense-in-depth: cheap to run, prevents the rare case where the harness lands on a fresh simulator and would otherwise hang on the first command.

## Adding a new fixture

1. Drop the file in `vreader/Resources/DebugFixtures/<name>.<ext>`.
2. Add a row to `DebugFixtureCatalog.entries`.
3. Confirm `EXCLUDED_SOURCE_FILE_NAMES` on the Release build configuration still globs `*/DebugFixtures/*` (it should — set once in pbxproj).
4. `test_all_entriesResolveInTheTestBundle` should pass without modification.
5. Re-run `scripts/verify-release-no-debugbridge.sh` to confirm the fixture stays out of Release.

## Future work

- Per-format settle hooks: Foliate `relocate` event for EPUB/AZW3, TextKit layout-completed for TXT/MD, PDFKit `viewDidLoad` for PDF.
- Real `evaluateJavaScript` evaluator on the EPUB/AZW3 reader (currently the bridge plumbing is complete but no reader supplies one — eval against EPUB books returns `error: "eval unsupported for format: epub"`).
- `selection` snapshot field: probe field that exposes the active reader's text selection.
- `position` parameter in `open` (currently throws `bridge.notImplemented: open.position`). Resolve string → Locator before pushing the reader.
- Additional fixture books: `alice.epub`, `sample.azw3`, `sample.pdf`. Catalog grows when files are sourced.
- `phase` reporting in `settle` timeout sentinel (currently always `"unknown"`).

## File reference

| File                                                          | Purpose                                     |
| ------------------------------------------------------------- | ------------------------------------------- |
| `vreader/Services/DebugBridge/DebugBridge.swift`              | Orchestrator — parse + dispatch + lastError |
| `vreader/Services/DebugBridge/DebugCommand.swift`             | URL grammar + parameter validation          |
| `vreader/Services/DebugBridge/DebugSnapshot.swift`            | JSON shape for snapshot output              |
| `vreader/Services/DebugBridge/RealDebugBridgeContext.swift`   | Production handlers (reset/seed/open/theme/tts/search/highlight) |
| `vreader/Services/DebugBridge/RealDebugBridgeContext+Provider.swift` | `provider` command handler (Bug #243 — AI provider profile add/remove/clear) |
| `vreader/Services/DebugBridge/RealDebugBridgeContext+Present.swift` | `present` command handler (Bug #253 — posts `.debugBridgePresentSheet`) |
| `vreader/Views/Reader/DebugPresentSheetEffect.swift`         | Pure `(sheet, tab)` → host presentation effect resolver (Bug #253) |
| `vreader/Views/Reader/ReaderContainerView+DebugBridgePresent.swift` | Reader-host `.debugBridgePresentSheet` observer (Bug #253) |
| `vreader/Services/DebugBridge/DebugReaderRegistry.swift`      | Active-reader registry + probe protocol     |
| `vreader/Services/DebugBridge/DebugReaderProbeAdapter.swift`  | Default probe used by ReaderContainerView   |
| `vreader/Services/DebugBridge/DebugBridgeNotifications.swift` | DEBUG-only notification names               |
| `vreader/Services/DebugBridge/DebugFixtureCatalog.swift`      | Fixture name → bundle resource map          |
| `vreader/SupportingFiles/DebugBridge.plist`                   | Partial Info.plist (Debug build only)       |
| `vreader/Resources/DebugFixtures/`                            | Bundled fixture books (Debug build only)    |
| `scripts/verify-release-no-debugbridge.sh`                    | Release-build acceptance gate               |

