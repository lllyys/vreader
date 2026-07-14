---
branch: feat/137-wi6b-tapzones
threadId: 019f61b3-5163-70a2-b373-582cc0f537a2
rounds: 1
final_verdict: follow-up-recommended
---

# Gate-4 audit — feature #137 WI-6b (paged 30/40/30 tap-zones + first-open TapZoneHint)

Auditor: Codex `gpt-5.5` / high, via `scripts/run-codex.sh` (rule 53). Read-only sandbox.
Full transcript: `.reports/wi6b-audit.txt`. `RUN-CODEX RESULT: SUCCEEDED`.

## Scope

- `android/app/src/main/kotlin/com/vreader/app/reader/paged/PagedTapZones.kt` (NEW — the
  `Modifier.pagedTapZones` 30/40/30 gesture + the `TapZoneHint` overlay).
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderBody.kt` (`TxtPagedBody` wiring:
  store-backed theme + persisted hint-seen flag, hint arm/dismiss, `pagedTapZones` on the pager,
  `TapZoneHint` render).
- `android/app/src/main/kotlin/com/vreader/app/reader/settings/ReaderSettingsStore.kt`
  (`tapHintSeen`/`markTapHintSeen`/`resetTapHintSeenForTest` on a SEPARATE `paged_tap_hint_seen`
  boolean pref key).
- `android/app/src/main/kotlin/com/vreader/app/reader/TxtReaderActivity.kt` (host wires
  `onToggleChrome` reusing the existing `chromeState` visibility flip).

## Verdict: follow-up-recommended (0 Critical, 0 High, 2 Medium, 3 Low)

### Confirmed good (auditor)
30/40/30 geometry (`x < 0.3` prev / `x > 0.7` next / center toggle); the center zone reuses the
existing `chromeState` toggle in `TxtReaderActivity` (no NEW chrome); side taps drive
`animateScrollToPage`; the hint uses a SEPARATE `paged_tap_hint_seen` pref key, so it does NOT
mutate the display-settings JSON / re-render the reader body.

### Medium — FIXED
1. **Stale callback capture on `pointerInput(isRtl)`** — after a font/margin/rotation reflow the tap
   detector could keep the first pagination's `pageCount` clamp. FIXED: the turn / toggle /
   first-interaction callbacks are wrapped in `rememberUpdatedState` in `TxtPagedBody` and
   `pagedTapZones` is handed STABLE trampolines to the live closures.
2. **Long-press did not dismiss the hint** — FIXED: `onLongPress` now also calls
   `onFirstInteraction()` (a long-press is a first interaction), so the hint dismisses + persists on
   any touch, while the WI-7a selection seam still fires.

### Low
- **Hint disc bg inverted vs the design** (`vreader-tap-zones.jsx:53`) — FIXED: dark disc on a dark
  theme, white disc on a light theme.
- **Persistence launched in the composition scope** — FIXED: `markTapHintSeen()` now runs on the app
  scope (`container.appScope`, the position-save pattern), so a dismiss-then-leave cannot cancel the
  "seen" write.
- **Test refinement** — the reopen wait used an immediately-true predicate. FIXED: the reopen test
  now polls `hintShowing()` across the hint's would-be enter+hold window (~3.5s) and fails if it ever
  reappears. Remaining coverage of native-swipe / RTL-inversion / long-press-coexistence as separate
  connected cases is accepted as a follow-up (the mechanism is unit-visible; the connected class
  already proves left/right/center + hint show-dismiss-persist). Non-blocking.
  - Also non-blocking cosmetic: the hint's designed dashed separators / disc shadow / blur are not
    reproduced (the accent/base tints + flex 3/4/3 + labels + chevrons + dot are). Follow-up.

## Post-fix re-test
`RUN-ANDROID-TESTS RESULT: SUCCEEDED` — `TxtPagedTapZonesConnectedTest` 4/0 (right/left/center
zones + hint show→dismiss→persist), and the WI-6a `TxtPagedBodyConnectedTest` 6/0 (no regression to
the paged/scroll bodies) on emulator-5554.
