// Purpose: Feature #56 WI-14 — the iOS-style confirmation alert shown
// when the user taps "Translate entire book…". Body shows the chapter
// count + a (currently coarse) cost / token / time estimate, plus a
// "Change provider" mini-row.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`TranslateBookConfirmAlert`).
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationProgress.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// The confirm alert for global book translation — chapter count +
/// estimate + change-provider + Cancel/Translate buttons.
struct TranslateBookConfirmAlert: View {

    /// The book whose chapters will be translated. Used for the
    /// italicized title in the body copy.
    let bookTitle: String
    /// The unit count from `BookTranslationCoordinator.estimate(...)`.
    let unitCount: Int
    /// Rough input-token estimate from `BookTranslationEstimate`; `nil`
    /// when the coordinator could not sample enough text to produce one.
    let approximateInputTokens: Int?
    /// The current provider label (e.g. "Claude \u{00b7} Sonnet 4.5").
    let providerLabel: String
    /// Localized target language (e.g. "Chinese").
    let targetLanguageLabel: String
    let theme: ReaderThemeV2

    /// User tapped "Change…" — host pushes the provider picker.
    let onChangeProvider: () -> Void
    /// User tapped "Not now" — VM dismisses the alert.
    let onCancel: () -> Void
    /// User confirmed "Translate" — VM starts the coordinator job.
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onCancel)
            VStack(spacing: 0) {
                heading
                Divider().overlay(Color(theme.ruleColor))
                providerRow
                Divider().overlay(Color(theme.ruleColor))
                buttons
            }
            .frame(width: 290)
            .background(alertBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.40), radius: 25, y: 16)
            .padding(18)
        }
        .accessibilityIdentifier("translateBookConfirmAlert")
    }

    /// "Translate the whole book?" + body copy with chapter count.
    private var heading: some View {
        VStack(spacing: 8) {
            Text("Translate the whole book?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)
            VStack(spacing: 0) {
                Text(bodyAttributed)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Color(theme.subColor))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 12)
    }

    /// AttributedString with the italicized title + bolded chapter
    /// count + the optional token estimate.
    private var bodyAttributed: AttributedString {
        var attr = AttributedString("")
        var italic = AttributedString(bookTitle)
        italic.font = .system(size: 12.5).italic()
        italic.foregroundColor = Color(theme.inkColor)
        attr.append(italic)
        attr.append(AttributedString(" has "))
        var bold = AttributedString("\(unitCount) chapters")
        bold.font = .system(size: 12.5, weight: .bold)
        bold.foregroundColor = Color(theme.inkColor)
        attr.append(bold)
        attr.append(AttributedString(". This will send every chapter to your AI provider."))
        if let tokens = approximateInputTokens, tokens > 0 {
            attr.append(AttributedString(" Approximately "))
            var tokensBold = AttributedString(Self.formatTokens(tokens))
            tokensBold.font = .system(size: 12.5, weight: .bold)
            tokensBold.foregroundColor = Color(theme.inkColor)
            attr.append(tokensBold)
            attr.append(AttributedString(" input tokens — actual cost depends on your provider's pricing."))
        } else {
            attr.append(AttributedString(" Cost depends on your provider's pricing."))
        }
        return attr
    }

    /// Localized number formatting with thousands separators —
    /// "1,234,567" reads more honestly than "1234567" at a glance.
    private static func formatTokens(_ tokens: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: tokens))
            ?? String(tokens)
    }

    /// "Provider · {label}" mini-row with a "Change…" CTA.
    private var providerRow: some View {
        Button(action: onChangeProvider) {
            HStack(spacing: 10) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 14))
                    .foregroundStyle(Color(theme.accentColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Provider")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color(theme.subColor))
                    Text(providerLabel)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                }
                Spacer(minLength: 0)
                Text("Change\u{2026}")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
            }
            .padding(.horizontal, 22)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("translateBookConfirmAlertChangeProvider")
    }

    /// "Not now" / "Translate" twin-button row — design pairing.
    private var buttons: some View {
        HStack(spacing: 0) {
            Button("Not now", action: onCancel)
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.accentColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .accessibilityIdentifier("translateBookConfirmAlertCancel")
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(width: 0.5)
            Button("Translate", action: onConfirm)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(theme.accentColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .accessibilityIdentifier("translateBookConfirmAlertConfirm")
        }
    }

    /// Alert surface fill — design `t.isDark ? '#2a2724' : '#fcf8f0'`.
    private var alertBackground: Color {
        theme.isDark
            ? Color(red: 0x2a / 255, green: 0x27 / 255, blue: 0x24 / 255)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
    }
}
#endif
