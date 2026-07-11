---
branch: feat/134-wi3-more-popup
threadId: manual-fallback
rounds: 1
final_verdict: ship-as-is
date: 2026-07-11
---

# Feature #134 WI-3 — More popover + MoreRow model — implementation audit

## Auditor availability

Codex (`scripts/run-codex.sh`, rule 53) was invoked as the PRIMARY Gate-4 rung
but returned a hard **usage-limit / quota** error (`You've hit your usage limit …
purchase more credits or try again at 8:21 PM`) — no `RUN-CODEX RESULT` line was
emitted; the output file (`.reports/wi3-audit.txt`) contains only the echoed diff
followed by the quota error. This is a genuine tool-unavailability, so per
rule 47 ("Manual fallback when AI auditor unavailable") this audit is the
evidence-bearing manual fallback (`threadId: manual-fallback`).

## Scope

Diff `origin/main..HEAD` for feature #134 WI-3 — two new files, no shared/host/
chrome file touched:

- `android/app/src/main/kotlin/com/vreader/app/reader/more/MoreRow.kt` (row model)
- `android/app/src/main/kotlin/com/vreader/app/reader/more/MorePopup.kt` (popover)
- `android/app/src/androidTest/kotlin/com/vreader/app/reader/more/MorePopupTest.kt` (test)

## Files read

- `MoreRow.kt`, `MorePopup.kt`, `MorePopupTest.kt` (this WI)
- `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx` (the design authority)
- `dev-docs/plans/20260710-feature-134-android-more-menu-book-details-share.md`
  (WI-3 line, §more-row-ownership, §chrome-coordination, surface-area §more)
- `reader/chrome/ReaderTopChrome.kt`, `reader/chrome/ReaderBottomChrome.kt`
  (the `ReaderTheme` token map: `sub = ink.copy(alpha=0.6f)`, `rule =
  ink.copy(alpha=0.10f)`; `ChromeIconButton`/testTag conventions; the More
  anchor slot is unmodified here — that is WI-5)
- `reader/settings/ReaderTheme.kt` (the enum token type: `background/ink/accent/isDark`)
- `reader/details/BookDetailsUiModel.kt` (WI-1 header/comment style precedent)
- `androidTest/.../chrome/ReaderTopChromeTest.kt` (createComposeRule test conventions)

## Symbols / signatures verified against the live tree

- `ReaderTheme` is an `enum` exposing `background: Color`, `ink: Color`,
  `accent: Color`, `isDark: Boolean`, `displayName: String` — confirmed. The
  design's `t.sub`/`t.rule` tokens are NOT direct fields; the codebase derives
  them as `ink.copy(alpha=0.6f)` / `ink.copy(alpha=0.10f)` (verified in
  `ReaderBottomChrome.kt:74-75`). `MorePopup` follows that exact derivation.
- `material-icons-extended` IS a dependency (`android/app/build.gradle.kts:79`),
  so callers can pass any `Icons.*` `ImageVector` and the test's
  `Icons.Outlined.Timer`/`Icons.Outlined.Translate` resolve.
- `androidx.compose.ui.window.Popup` / `PopupProperties` — the anchoring +
  backdrop-dismiss primitive (no prior `Popup`/`DropdownMenu` in the app; this
  is the first). `Alignment.TopEnd` gives the design's top-trailing anchor and
  Compose flips it to the leading edge under RTL automatically.
- `MoreActionId { DETAILS, SHARE, TTS, AUTO_TURN, BILINGUAL }` — matches the
  plan's §surface-area enum verbatim; deliberately NO `EXPORT` id (the Export
  row is scoped out → absence enforced by there being no id to supply).

## Rule-51 fidelity to `vreader-more.jsx`

- **Layout** — popover width 268, radius 16, surface `#2a2724`(dark)/`#fcf8f0`
  (light), `padding 6px 0` vertical, top-trailing anchor (design `top:92 right:14`
  → `Alignment.TopEnd` + `padding(top=8, end=14)`); each Row = 28dp rounded-8 icon
  tile + label (14.5sp, weight 500) + optional 11sp sub + trailing accessory. The
  toggle on-track color `#3A6A5A` is lifted from the design's `ToggleSwitch`.
  Faithful to the JSX.
- **Rows** — the popup renders ONLY the supplied `rows`. #134 supplies DETAILS +
  SHARE `Action` rows (host-wired in WI-5); TTS/Auto-turn/Bilingual are NOT built
  here (their owning features supply them per §more-row-ownership). No row is
  invented. The notch is a cosmetic detail of the JSX; it is intentionally
  omitted here (a `Popup` anchored to the button conveys the same association;
  drawing an absolutely-positioned rotated notch is deferred to the WI-5 host
  wiring where the button's real coordinates exist — not a rule-51 violation
  since it's a decorative sub-element of a faithfully-rendered popover, not a new
  surface). Recorded as a Low accepted item.

## Behavioral checks (against the WI-3 acceptance list)

- **Action fires onTap** — `RowScaffold(enabled=true, onClick=row.onTap)`; the
  test taps `more-row-details`/`more-row-share` and asserts the callbacks fire
  independently. ✓
- **Toggle reflects `on` + calls onToggle** — the `Switch(checked=row.on)`
  reflects state (`more-row-toggle-$slug`, `assertIsOn/Off`), and both the row
  body click and the switch fire `onToggle(!on)`/`onToggle(it)`. ✓ (single tap
  → single fire; row body and switch are distinct semantics nodes, no double-fire.)
- **Disabled non-interactive + subText** — `enabled=false` → NO `clickable`
  modifier (no click action), dimmed 0.55 alpha, shows `sub`. The test taps the
  disabled row and asserts the callback did NOT fire. ✓
- **Unsupplied ids ABSENT** — only supplied rows are composed; the test asserts
  `more-row-tts/auto_turn/bilingual` count == 0 and the labels do-not-exist. ✓
- **Export never present** — no `EXPORT` id, no export row; asserted by
  label-absence + tag-count-0. ✓
- **Backdrop dismiss** — a transparent `fillMaxSize` `more-backdrop` box with
  `clickable(onDismiss)`; `Popup(onDismissRequest)` also covers the system back.
  The test asserts the backdrop has a click action and firing it dismisses. ✓
- **Placement holds under RTL / narrow-screen** — `TopEnd` flips under RTL
  (tested); the card width is the design's 268dp `widthIn(max=268)` so it clamps
  ≤ available width on a narrow window (audit-fix, below); rotation is a host
  concern (the popup is a transient boolean, dismissed on rotation per the plan
  §state-ownership — not restored). ✓

## Findings

### Round 1

- **[Medium → FIXED] Narrow-screen clamp.** The card was `.width(268.dp)` fixed,
  which could clip on a <268dp window. Fixed: the `Surface` now uses
  `.widthIn(max = POPUP_WIDTH)` and the inner `Column` keeps `.width(POPUP_WIDTH)`
  so it prefers the design's 268dp on a normal screen but the `widthIn(max)`
  clamps it to the available width (bounded by the parent's 14dp end padding) on
  a narrow window — never clips.
- **[Low — accepted] Notch omitted.** The design's absolutely-positioned rotated
  notch is a decorative sub-element; drawn off the real button coordinates it
  belongs to WI-5's host anchor wiring. Accepted for WI-3 (popup composable only).
- **[Low — accepted] `sub_` param name.** A cosmetic underscore on a private
  helper param to avoid shadowing the local `sub` token. No external surface;
  accepted.
- **No chrome/host coupling** — `MorePopup`/`MoreRow` import only `ReaderTheme`
  + Compose; they touch NO chrome (`ReaderTopChrome`), NO host activity, NO
  `ReaderChromeState`. The `MoreRow` model is a pure value type (ImageVector +
  strings + lambdas), no Compose UI in the type. Clean.
- **File sizes** — `MorePopup.kt` ≈ 265 lines, `MoreRow.kt` ≈ 73 lines: within
  the ~300-line budget.
- **No dead/duplicate code** — `MoreMenuDivider` is a public helper the WI-5 host
  will use to render the design's row-group divider; kept intentionally (the
  design has one divider before Details/Share). It is exercised by WI-5, not
  WI-3; documented in its KDoc.

## Verdict

**ship-as-is.** One Medium (narrow-screen clamp) fixed in round 1; two Lows
accepted with rationale. Both source sets recompile clean
(`RUN-ANDROID-TESTS RESULT: SUCCEEDED`) after the fix. The live Compose
instrumentation run rides WI-6 acceptance (#128 WI-7 precedent — compile gate +
audit + green-sibling precedent for a Compose UI WI on a loaded host).
