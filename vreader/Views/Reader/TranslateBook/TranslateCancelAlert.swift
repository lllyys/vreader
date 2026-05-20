// Purpose: Feature #56 WI-14 — the cancel-confirmation alert shown when
// the user taps "Cancel translation" in the status sheet. The text
// disabuses the user — already-translated chapters stay cached.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`TranslateCancelAlert`).
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationProgress.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// Confirmation alert presented when the user taps "Cancel translation"
/// in the status sheet. Reassures the user that finished chapters remain
/// cached and resumable.
struct TranslateCancelAlert: View {

    /// Progress snapshot at cancel time — used for "{done} of {total}".
    let progress: BookTranslationProgress
    let theme: ReaderThemeV2

    /// "Keep translating" — VM dismisses the alert, job keeps running.
    let onKeep: () -> Void
    /// "Cancel translation" — VM tells the coordinator to stop.
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture(perform: onKeep)
            VStack(spacing: 0) {
                heading
                Divider().overlay(Color(theme.ruleColor))
                buttons
            }
            .frame(width: 290)
            .background(alertBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .shadow(color: .black.opacity(0.40), radius: 25, y: 16)
            .padding(18)
        }
        .accessibilityIdentifier("translateCancelAlert")
    }

    private var heading: some View {
        VStack(spacing: 8) {
            Text("Cancel translation?")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)
            Text(bodyAttributed)
                .font(.system(size: 12.5))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .lineSpacing(2)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 14)
    }

    private var bodyAttributed: AttributedString {
        var attr = AttributedString("")
        var bold1 = AttributedString("\(progress.completed) of \(progress.total)")
        bold1.font = .system(size: 12.5, weight: .bold)
        bold1.foregroundColor = Color(theme.inkColor)
        attr.append(bold1)
        attr.append(AttributedString(" chapters are already translated and will "))
        var bold2 = AttributedString("stay cached")
        bold2.font = .system(size: 12.5, weight: .bold)
        bold2.foregroundColor = Color(theme.inkColor)
        attr.append(bold2)
        attr.append(AttributedString(" \u{2014} you can resume from where you stopped any time."))
        return attr
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            Button("Keep translating", action: onKeep)
                .font(.system(size: 15))
                .foregroundStyle(Color(theme.accentColor))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .accessibilityIdentifier("translateCancelAlertKeep")
            Rectangle()
                .fill(Color(theme.ruleColor))
                .frame(width: 0.5)
            Button("Cancel translation", action: onConfirm)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .accessibilityIdentifier("translateCancelAlertConfirm")
        }
    }

    private var alertBackground: Color {
        theme.isDark
            ? Color(red: 0x2a / 255, green: 0x27 / 255, blue: 0x24 / 255)
            : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255)
    }
}
#endif
