// Purpose: Feature #60 WI-6c — the reader More-menu popover. An
// anchored popover from the `⋯` button in `ReaderTopChrome`, replacing
// the WI-6b interim wiring (`⋯` → settings sheet). Six rows split by a
// hairline divider: Read aloud / Auto-turn pages / Bilingual mode |
// Book details / Share book / Export annotations.
//
// Layout pinned to the committed design bundle:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-more.jsx`
// (`MorePopover` + `ToggleSwitch`) and `design-notes/
// reader-search-and-more-menu.md` §2 (width 268, radius 16, notch
// pointing to the trigger, per-theme rendering for all 5 themes).
//
// Row identity, ordering, divider placement, labels, icons, toggle vs
// tap, sub-detail text, and notification routing all live in
// `ReaderMoreMenuRow` so the design contract is unit-testable without
// a SwiftUI render path. This file is purely presentational — taps
// post `ReaderMoreMenuRow.notification`; `ReaderContainerView`
// observes them.
//
// @coordinates-with: ReaderMoreMenuRow.swift, ReaderTopChrome.swift,
//   ReaderThemeV2.swift, ReaderContainerView+Sheets.swift,
//   ReaderNotifications.swift

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

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Dim backdrop — transparent fill, taps anywhere outside
            // the card close the popover. Matches the design's
            // `onClick={onClose}` full-bleed layer.
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

    private var popoverCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(ReaderMoreMenuRow.allCases.enumerated()), id: \.element) { _, row in
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
        // Notch behind the card: it pokes above the top edge as the
        // pointer; the card's own surface covers its base, so no
        // clipping or selective border is needed.
        .background(alignment: .top) { notch }
        .shadow(color: .black.opacity(0.28), radius: 18, x: 0, y: 12)
    }

    /// The small triangular beak that points up toward the `⋯`
    /// trigger. `vreader-more.jsx` draws this as a rotated square
    /// (`top: -6, right: 24`); a triangle is the equivalent SwiftUI
    /// idiom and avoids clipping the base behind the card.
    private var notch: some View {
        ReaderMorePopoverNotch()
            .fill(popoverBackground)
            .frame(width: 16, height: 8)
            // Right-align under the `⋯` button: 24pt from the card's
            // trailing edge per the design, minus half the notch width.
            .frame(width: popoverWidth, alignment: .trailing)
            .padding(.trailing, 16)
            .offset(y: -7)
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
    /// (dark family) / `#fcf8f0` (light family), distinct from the
    /// reader chrome tint so the popover reads as a floating element.
    /// Mapped through `isDark` so all 5 themes pick the right surface
    /// — the same projection `SelectionPopoverView` uses.
    private var popoverBackground: Color {
        theme.isDark
            ? Color(red: 0x2a / 255, green: 0x27 / 255, blue: 0x24 / 255)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
    }
}

// MARK: - Popover notch

/// Upward-pointing triangular beak for the More popover. Apex at top
/// center, base along the bottom edge — drawn behind the card so its
/// base tucks under the card surface.
private struct ReaderMorePopoverNotch: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - Inline toggle switch

/// Small iOS-style toggle rendered in the Auto-turn row, matching
/// `vreader-more.jsx`'s `ToggleSwitch` (34×20 track, green `#3a6a5a`
/// when on). Presentational only — the row's tap posts the toggle
/// notification; the host flips the backing setting and the new
/// `isOn` flows back in.
private struct ReaderMoreToggle: View {
    let isOn: Bool
    let theme: ReaderThemeV2

    var body: some View {
        Capsule()
            .fill(trackColor)
            .frame(width: 34, height: 20)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.15), value: isOn)
            .accessibilityHidden(true)
    }

    private var trackColor: Color {
        isOn
            ? Color(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255)
            : (theme.isDark
                ? Color.white.opacity(0.12)
                : Color.black.opacity(0.12))
    }
}

// MARK: - More-menu action observers

/// Feature #60 WI-6c: bundles the six More-menu notification
/// observers into a single modifier, mirroring `ReaderToolbarActionObservers`
/// (WI-6b). `ReaderContainerView` applies it as one `.modifier(...)`
/// rather than six chained `.onReceive`s — its `body` is already near
/// the Swift type-checker's expression-complexity ceiling.
///
/// Each observer maps its notification back to the `ReaderMoreMenuRow`
/// that posted it via `ReaderMoreMenuRow(notification:)` (the inverse
/// of `.notification`) and hands the row to a single
/// `(ReaderMoreMenuRow) -> Void` callback, so the host has one action
/// funnel instead of six.
struct ReaderMoreMenuActionObservers: ViewModifier {
    let onAction: (ReaderMoreMenuRow) -> Void

    func body(content: Content) -> some View {
        // SwiftUI `.onReceive` needs one publisher per concrete name —
        // a dynamic set can't be observed — but each routes through the
        // inverse initializer so the row resolution is single-sourced
        // and round-trip-tested.
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreReadAloud), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreToggleAutoTurn), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreBilingual), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreBookDetails), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreShareBook), perform: dispatch)
            .onReceive(NotificationCenter.default.publisher(for: .readerMoreExportAnnotations), perform: dispatch)
    }

    /// Resolves the posting row from the notification name and fires
    /// the action funnel. An unrecognised name (no matching row) is
    /// ignored.
    private func dispatch(_ notification: Notification) {
        guard let row = ReaderMoreMenuRow(notification: notification.name) else { return }
        onAction(row)
    }
}

extension View {
    /// Attaches the six More-menu action observers (Feature #60
    /// WI-6c). See `ReaderMoreMenuActionObservers`.
    func readerMoreMenuActionObservers(
        onAction: @escaping (ReaderMoreMenuRow) -> Void
    ) -> some View {
        modifier(ReaderMoreMenuActionObservers(onAction: onAction))
    }
}
#endif
