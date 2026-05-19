// Purpose: Feature #60 WI-6c — the reader More-menu popover. An
// anchored popover from the `⋯` button in `ReaderTopChrome`, replacing
// the WI-6b interim wiring (`⋯` → settings sheet). Five rows split by a
// hairline divider: Read aloud / Auto-turn pages | Book details /
// Share book / Export annotations. (The design's sixth row, Bilingual
// mode, is deferred — GH #790 — see `ReaderMoreMenuRow`'s header.)
//
// Layout pinned to the committed design bundle:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// (`MorePopover`) and `design-notes/reader-search-and-more-menu.md`
// §2 (width 268, radius 16, notch pointing to the trigger, per-theme
// rendering for all 5 themes).
//
// Row identity, ordering, divider placement, labels, icons, toggle vs
// tap, sub-detail text, and notification routing all live in
// `ReaderMoreMenuRow` so the design contract is unit-testable without
// a SwiftUI render path. The notch / toggle / observer-modifier
// helpers live in `ReaderMorePopoverParts.swift`. This file is purely
// presentational — taps post `ReaderMoreMenuRow.notification`;
// `ReaderContainerView` observes them.
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderMorePopoverParts.swift,
//   ReaderTopChrome.swift, ReaderThemeV2.swift,
//   ReaderContainerView+Sheets.swift, ReaderNotifications.swift

#if canImport(UIKit)
import SwiftUI

/// Anchored More-menu popover (Feature #60 WI-6c). Composed in
/// `ReaderContainerView`'s chrome overlay above `ReaderTopChrome`.
/// The view owns no state — TTS / auto-turn state is passed in, and
/// every tap is funnelled through a posted notification + the
/// `onClose` callback.
struct ReaderMorePopover: View {
    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2
    /// Whether read-aloud is currently speaking — drives the Read
    /// aloud row's active tint + sub-detail.
    let ttsPlaying: Bool
    /// Whether auto-page-turn is enabled — drives the Auto-turn row's
    /// toggle position, active tint, and sub-detail.
    let autoTurnOn: Bool
    /// Auto-turn interval in seconds — rendered in the Auto-turn
    /// sub-detail ("Every Ns") when the toggle is on.
    let autoTurnInterval: Double
    /// The active book format's capability set, used to gate rows
    /// whose backing action would be a no-op for this format.
    /// Bug #176 / GH #602: the `Read aloud` row is dropped when the
    /// format excludes `.tts` (AZW3 / MOBI) — otherwise the menu
    /// surfaces a silent dead-end control. `nil` keeps every row, for
    /// previews / tests / legacy call sites (see
    /// `ReaderMoreMenuRow.visibleRows(for:)`).
    let formatCapabilities: FormatCapabilities?
    /// Top inset (points) at which the popover floats — passed from
    /// the host so the popover clears the top chrome. The design's
    /// `top: 92` baseline is for the prototype's fixed-height chrome;
    /// the production chrome height varies with the Dynamic Island
    /// inset, so the host computes it.
    let topInset: CGFloat
    /// Called when the user dismisses the popover — backdrop tap or
    /// after any row tap. The host clears its presentation flag.
    let onClose: () -> Void

    /// Design popover width (`vreader-more.jsx`: `width: 268`).
    private let popoverWidth: CGFloat = 268
    /// Edge length of the design's rotated-square notch
    /// (`vreader-more.jsx`: `width: 12, height: 12`).
    private let notchSize: CGFloat = 12

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dim backdrop — near-transparent fill, taps anywhere
            // outside the card close the popover. Matches the design's
            // full-bleed `onClick={onClose}` layer.
            Color.black.opacity(0.001)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onClose)
                .accessibilityIdentifier("readerMorePopoverBackdrop")

            popoverCard
                .padding(.top, topInset)
                .padding(.trailing, 14)
        }
        .accessibilityIdentifier("readerMorePopover")
    }

    // MARK: - Popover card

    /// The rows this popover renders — capability-gated for the active
    /// format: the `Read aloud` row is dropped when the format lacks
    /// `.tts` (PDF). AZW3/MOBI regained `.tts` in feature #57, so they
    /// keep the row. Exposed (not `private`) so a wiring test can prove
    /// the popover actually consults `formatCapabilities` rather than
    /// rendering `ReaderMoreMenuRow.allCases` unconditionally.
    var resolvedRows: [ReaderMoreMenuRow] {
        ReaderMoreMenuRow.visibleRows(for: formatCapabilities)
    }

    private var popoverCard: some View {
        // Filter capability-gated rows (e.g. drop `Read aloud` for a
        // format without a wired TTS path — PDF) before rendering. The
        // divider still trails `dividerAfter` — that row is never
        // gated, so the anchor always survives the filter.
        VStack(spacing: 0) {
            ForEach(resolvedRows, id: \.self) { row in
                rowButton(row)
                if row == ReaderMoreMenuRow.dividerAfter {
                    divider
                }
            }
        }
        .padding(.vertical, 6)
        .frame(width: popoverWidth)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(popoverBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(theme.ruleColor), lineWidth: 0.5)
        )
        // Notch behind the card: a rotated square whose top half pokes
        // above the card edge as the pointer; the card's own surface +
        // border cover its bottom half, so the only visible notch
        // edges are the two pointing up — matching the design's
        // two-sided hairline (`box-shadow: -1px -1px`).
        .background(alignment: .topTrailing) { notch }
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
    }

    /// The rotated-square notch that points up toward the `⋯` trigger.
    /// `vreader-more.jsx`: a 12×12 square, `transform: rotate(45deg)`,
    /// `top: -6, right: 24`.
    private var notch: some View {
        Rectangle()
            .fill(popoverBackground)
            .overlay(
                Rectangle().stroke(Color(theme.ruleColor), lineWidth: 0.5)
            )
            .frame(width: notchSize, height: notchSize)
            .rotationEffect(.degrees(45))
            // `right: 24` from the card's trailing edge to the notch
            // center; the rotated square is `notchSize` wide, so its
            // leading offset is 24 − notchSize/2 from the trailing
            // inset. `top: -6` lifts it half-out of the card.
            .offset(x: -(24 - notchSize / 2), y: -6)
            .allowsHitTesting(false)
    }

    private var divider: some View {
        Color(theme.ruleColor)
            .frame(height: 0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 4)
    }

    // MARK: - Rows

    private func rowButton(_ row: ReaderMoreMenuRow) -> some View {
        let active = row.isActive(ttsPlaying: ttsPlaying, autoTurnOn: autoTurnOn)
        let sub = row.subDetail(
            ttsPlaying: ttsPlaying,
            autoTurnOn: autoTurnOn,
            autoTurnInterval: autoTurnInterval
        )
        return Button {
            // Post first, then dismiss — the host's notification
            // observer and the popover teardown are independent.
            NotificationCenter.default.post(name: row.notification, object: nil)
            onClose()
        } label: {
            HStack(spacing: 12) {
                iconChip(for: row, active: active)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                        .lineLimit(1)
                    if let sub {
                        Text(sub)
                            .font(.system(size: 11))
                            .foregroundStyle(Color(theme.subColor))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                trailingAccessory(for: row)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(row.accessibilityIdentifier)
    }

    /// 28×28 rounded icon chip. Per the design, an active row lifts
    /// the chip to a faint accent tint; otherwise it's a neutral
    /// low-contrast fill.
    private func iconChip(for row: ReaderMoreMenuRow, active: Bool) -> some View {
        let accent = Color(theme.accentColor)
        let chipFill: Color = active
            ? accent.opacity(theme.isDark ? 0.20 : 0.10)
            : (theme.isDark
                ? Color.white.opacity(0.05)
                : Color.black.opacity(0.04))
        return RoundedRectangle(cornerRadius: 8)
            .fill(chipFill)
            .frame(width: 28, height: 28)
            .overlay(
                Image(systemName: row.systemImage)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(active ? accent : Color(theme.inkColor))
            )
    }

    /// Trailing accessory: an inline toggle switch for the toggle row
    /// (Auto-turn), a chevron for tap rows.
    @ViewBuilder
    private func trailingAccessory(for row: ReaderMoreMenuRow) -> some View {
        if row.isToggle {
            ReaderMoreToggle(isOn: autoTurnOn, theme: theme)
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    // MARK: - Theme-aware surface

    /// Popover surface fill. The design ships hardcoded `#2a2724`
    /// (dark / OLED family) / `#fcf8f0` (Paper / Sepia family) for the
    /// popover surface, distinct from the reader chrome tint so the
    /// popover reads as a floating element. The Photo theme uses a
    /// translucent dark fill (`rgba(20,16,12,0.92)`, design note §2)
    /// so the popover stays legible over an arbitrary background
    /// image without depending on a backdrop blur.
    private var popoverBackground: Color {
        if theme.usesBackgroundImage {
            // Photo theme — design-specified translucent surface.
            return Color(red: 20 / 255, green: 16 / 255, blue: 12 / 255)
                .opacity(0.92)
        }
        return theme.isDark
            ? Color(red: 0x2a / 255, green: 0x27 / 255, blue: 0x24 / 255)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
    }
}
#endif
