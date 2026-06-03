// Purpose: The whole-book retrieval cluster — the context bar morphs in place
// while the AI reads the whole book on demand (Feature #86 WI-5b, design #1455).
// Replaces the normal scope/sources bar when the scope is `.wholeBook`:
//   - Armed:   accent "Whole book" chip + "Reads on your next question"
//   - Reading: spinner + "Reading the whole book… 38%" + "23 / 61" + Cancel ×
//              + a thin accent progress bar; the composer disables.
//   - Ready:   green "Whole book" chip + "Indexed · ready"
//   - Partial: a cancel/overflow left a partial index — rendered with the Ready
//              treatment (a partial digest IS usable scope text), captioned
//              "Partial · ready" so it never claims full coverage.
//
// @coordinates-with: WholeBookRetrievalViewModel.swift, AIChatView.swift,
//   ChatContextBar.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/chat-context-artboards.jsx`

#if canImport(UIKit)
import SwiftUI

struct ChatRetrievalCluster: View {
    let phase: WholeBookRetrievalViewModel.Phase
    let theme: ReaderThemeV2
    let progressFraction: Double
    let unitProgressLabel: String
    /// Tap the "Whole book" chip (armed / ready / partial) → reopen the scope menu.
    let onScopeTap: () -> Void
    /// Cancel the in-flight read.
    let onCancel: () -> Void

    static let identifier = "chatRetrievalCluster"

    var body: some View {
        Group {
            switch phase {
            case .idle, .armed: armedBar
            case .reading:      readingBar
            case .ready:        readyBar(caption: "Indexed · ready")
            case .partial:      readyBar(caption: "Partial · ready")
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 9)
        .padding(.bottom, 2)
        .overlay(alignment: .top) {
            Rectangle().fill(Color(theme.ruleColor)).frame(height: 0.5)
        }
        .accessibilityIdentifier(Self.identifier)
    }

    // MARK: - Armed

    private var armedBar: some View {
        HStack {
            wholeBookChip(accentBorder: true, fill: scopeOpenWash, leading: sparkle)
            Spacer(minLength: 8)
            Text("Reads on your next question")
                .font(.system(size: 11.5))
                .foregroundStyle(Color(theme.subColor))
        }
    }

    // MARK: - Reading

    private var readingBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 9) {
                ProgressView()
                    .controlSize(.small)
                    .tint(Color(theme.accentColor))
                Text("Reading the whole book…")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Text("\(Int((progressFraction * 100).rounded()))%")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(Color(theme.subColor))
                Spacer(minLength: 4)
                if !unitProgressLabel.isEmpty {
                    Text(unitProgressLabel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(theme.subColor))
                }
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color(theme.subColor))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color(neutralWash)))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("chatRetrievalCancel")
                .accessibilityLabel("Cancel reading the whole book")
            }
            // Thin accent progress bar.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(neutralWash))
                    Capsule().fill(Color(theme.accentColor))
                        .frame(width: max(0, min(1, progressFraction)) * geo.size.width)
                }
            }
            .frame(height: 3)
        }
    }

    // MARK: - Ready / Partial

    private func readyBar(caption: String) -> some View {
        HStack {
            wholeBookChip(accentBorder: false, fill: greenWash, leading: greenCheck)
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                Text(caption)
                    .font(.system(size: 11.5, weight: .semibold))
            }
            .foregroundStyle(Color(ChatContextBar.accentGreen))
        }
    }

    // MARK: - Shared chip

    @ViewBuilder
    private func wholeBookChip<L: View>(accentBorder: Bool, fill: UIColor, leading: L) -> some View {
        Button(action: onScopeTap) {
            HStack(spacing: 6) {
                leading
                Text("Context")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                Text("Whole book")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(theme.subColor))
            }
            .padding(.leading, 11)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(Color(fill)))
            .overlay(Capsule().stroke(Color(accentBorder ? theme.accentColor : .clear), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(ChatContextBar.scopeChipIdentifier)
        .accessibilityLabel("Chat context scope: Whole book")
    }

    private var sparkle: some View {
        Image(systemName: "sparkle").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color(theme.accentColor))
    }
    private var greenCheck: some View {
        Image(systemName: "checkmark").font(.system(size: 11, weight: .bold))
            .foregroundStyle(Color(ChatContextBar.accentGreen))
    }

    private var scopeOpenWash: UIColor {
        theme.isDark
            ? UIColor(red: 214/255, green: 136/255, blue: 90/255, alpha: 0.14)
            : UIColor(red: 140/255, green: 47/255, blue: 47/255, alpha: 0.07)
    }
    private var greenWash: UIColor {
        ChatContextBar.accentGreen.withAlphaComponent(theme.isDark ? 0.22 : 0.12)
    }
    private var neutralWash: UIColor {
        theme.isDark ? UIColor(white: 1, alpha: 0.08) : UIColor(white: 0, alpha: 0.06)
    }
}
#endif
