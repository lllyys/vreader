// Purpose: Row rendering for `ReaderMorePopover` — the bilingual
// cluster group (feature #99), the per-row button (icon chip + label +
// sub-detail + trailing accessory), and the muted-state rule. Split
// from ReaderMorePopover.swift for the ~300-line file budget after the
// feature-99 cluster pushed it over.
//
// @coordinates-with: ReaderMorePopover.swift, ReaderMoreMenuRow.swift,
//   ReaderMoreMenuBilingualContext.swift, ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI

extension ReaderMorePopover {

    // MARK: - Bilingual cluster (feature #99)

    /// The accent-tinted group holding the bilingual toggle row + the
    /// Translation settings row (design `BSMorePopover`: radius 12,
    /// accent at ~8%/5% dark/light, inset hairline from x≈54 — the
    /// icon-chip gutter).
    var bilingualClusterGroup: some View {
        VStack(spacing: 0) {
            rowButton(.bilingual)
            Color(theme.ruleColor)
                .frame(height: 0.5)
                .padding(.leading, 54)
                .padding(.trailing, 14)
            rowButton(.translationSettings)
        }
        .background(
            RoundedRectangle(cornerRadius: 12).fill(
                Color(theme.accentColor).opacity(theme.isDark ? 0.08 : 0.05)
            )
        )
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .accessibilityIdentifier("readerMoreBilingualCluster")
    }

    // MARK: - Rows

    func rowButton(_ row: ReaderMoreMenuRow) -> some View {
        let active = row.isActive(
            ttsPlaying: ttsPlaying,
            autoTurnOn: autoTurnOn,
            bilingualState: bilingualState
        )
        let sub = row.subDetail(
            ttsPlaying: ttsPlaying,
            autoTurnOn: autoTurnOn,
            autoTurnInterval: autoTurnInterval,
            bilingualState: bilingualState,
            bilingualContext: bilingualContext
        )
        let muted = isMutedRow(row)
        return Button {
            // Post first, then dismiss — the host's notification
            // observer and the popover teardown are independent.
            // Feature #99: the book key rides every row post so keyed
            // observers (`.readerMoreTranslationSettings`) can filter.
            let userInfo: [String: Any]? = bookFingerprintKey.map { key in
                var info: [String: Any] = ["fingerprintKey": key]
                if let bookTitle { info["bookTitle"] = bookTitle }
                return info
            }
            NotificationCenter.default.post(
                name: row.notification, object: nil, userInfo: userInfo)
            onClose()
        } label: {
            HStack(spacing: 12) {
                iconChip(for: row, active: active, muted: muted)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.label)
                        .font(.system(size: 14.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor).opacity(muted ? 0.4 : 1.0))
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

    /// Whether the row renders with reduced opacity — design §2.3:
    /// the bilingual row's `.unavailable` state uses 40% icon opacity
    /// to signal "disabled but visible (one-tap fix)". No other row
    /// uses this muted state.
    func isMutedRow(_ row: ReaderMoreMenuRow) -> Bool {
        row == .bilingual && bilingualState == .unavailable
    }

    /// 28×28 rounded icon chip. Per the design, an active row lifts
    /// the chip to a faint accent tint; a muted row (bilingual
    /// unavailable) renders at 40% opacity; otherwise it's a neutral
    /// low-contrast fill.
    func iconChip(
        for row: ReaderMoreMenuRow,
        active: Bool,
        muted: Bool
    ) -> some View {
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
            .opacity(muted ? 0.4 : 1.0)
    }

    /// Trailing accessory — driven by `ReaderMoreMenuRow.trailingControl`:
    /// an inline toggle switch for the toggle rows (Auto-turn,
    /// Bilingual off/on), a chevron for tap rows (including the
    /// bilingual `.unavailable` state per design §2.3 — `trailingControl`
    /// returns `.chevron` for that state, not `.none`). `.none`
    /// renders no trailing accessory; no row currently uses it, but
    /// the variant is preserved so the design's "no trailing control"
    /// possibility remains expressible.
    @ViewBuilder
    func trailingAccessory(for row: ReaderMoreMenuRow) -> some View {
        switch row.trailingControl(
            bilingualState: bilingualState,
            autoTurnOn: autoTurnOn
        ) {
        case .toggle(let on):
            ReaderMoreToggle(isOn: on, theme: theme)
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color(theme.subColor))
        case .none:
            EmptyView()
        }
    }
}
#endif
