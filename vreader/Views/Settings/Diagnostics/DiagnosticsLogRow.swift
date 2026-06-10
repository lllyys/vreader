// Purpose: Feature #96 WI-2 — one diagnostics log row (design `DiagLogRow`):
// a meta line (mono timestamp · colored uppercase level · category pill) over a
// monospace message clamped to 3 lines; tapping expands it in place and reveals
// a "Copy entry" pill. Chrome stays Inter; only log content is monospace.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-diagnostics.jsx`.
//
// @coordinates-with: DiagnosticsLogView.swift, DiagnosticsLevelStyle.swift,
//   DiagnosticsLogEntry.swift

import SwiftUI

extension Color {
    /// Build a `Color` from a 24-bit `0xRRGGBB` literal — the diagnostics
    /// viewer's functional level tints are specified as design hex.
    init(diagnosticsHex rgb: Int) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255
        )
    }
}

/// The concrete colors for a level tint over a theme — shared by the row and
/// the filter chips so the "Errors" chip and an error row read the same red.
extension DiagnosticsLevelTint {
    func color(isDark: Bool, neutral: Color) -> Color {
        switch self {
        case .error:   return isDark ? Color(diagnosticsHex: 0xe0826f) : Color(diagnosticsHex: 0xb13e36)
        case .info:    return isDark ? Color(diagnosticsHex: 0x7fb2d9) : Color(diagnosticsHex: 0x3a6f9c)
        case .neutral: return neutral
        }
    }
}

struct DiagnosticsLogRow: View {
    let theme: ReaderThemeV2
    let entry: DiagnosticsLogEntry
    let isExpanded: Bool
    let onTap: () -> Void
    let onCopy: () -> Void

    /// `HH:mm:ss.SSS` mono timestamp (design meta line).
    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private var levelColor: Color {
        entry.level.viewerTint.color(isDark: theme.isDark, neutral: Color(theme.subColor))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            metaLine
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color(theme.inkColor))
                .lineLimit(isExpanded ? nil : 3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isExpanded {
                Button(action: onCopy) {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Copy entry")
                            .font(.system(size: 11.5, weight: .semibold))
                    }
                    .foregroundStyle(Color(theme.accentColor))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .overlay(
                        Capsule().stroke(Color(theme.ruleColor), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 5)
                .accessibilityIdentifier("diagnosticsCopyEntry")
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isExpanded
                ? Color(theme.inkColor).opacity(theme.isDark ? 0.03 : 0.025)
                : Color.clear
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }

    private var metaLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Self.timeFormatter.string(from: entry.date))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(Color(theme.subColor))
            Text(entry.level.exportTag)
                .font(.system(size: 10, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(levelColor)
            if !entry.category.isEmpty {
                Text(entry.category)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(Color(theme.subColor))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(theme.inkColor).opacity(theme.isDark ? 0.07 : 0.05))
                    )
            }
            Spacer(minLength: 0)
        }
    }
}
