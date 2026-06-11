// Purpose: Feature #99 WI-4 — the confirmed-state floating banner
// (design §#1640 `BSRetranslateBanner`): shown under the top chrome for
// ~4s after applying a NEW target language — "Re-translating in
// {lang}…" with "Cached {previous} stays — switch back anytime".
//
// Adaptation (plan Known limitations): the mock's trailing "p. 3 →"
// current-page chip is omitted (host-specific indicator on a transient
// surface).
//
// @coordinates-with: ReaderContainerView.swift, ReaderNotifications.swift,
//   BilingualSettingsEditRouter.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-bilingual-suite.jsx`

import SwiftUI

/// The feature-#99 re-translate confirmation banner.
struct BilingualRetranslateBanner: View {

    let theme: ReaderThemeV2
    /// The NEW target language's display name.
    let language: String
    /// The previous language (its cache survives — the sub line says so).
    let previousLanguage: String

    /// The banner's sub line — pinned by tests.
    static func detail(previousLanguage: String) -> String {
        "Cached \(previousLanguage) stays \u{2014} switch back anytime"
    }

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(Color(theme.accentColor))
            VStack(alignment: .leading, spacing: 1) {
                Text("Re-translating in \(language)\u{2026}")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                Text(Self.detail(previousLanguage: previousLanguage))
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(theme.subColor))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.isDark
                    ? Color(red: 0.165, green: 0.153, blue: 0.141).opacity(0.96)
                    : Color(red: 0.988, green: 0.973, blue: 0.941).opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(theme.accentColor).opacity(0.27), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.16), radius: 10, y: 6)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("bilingualRetranslateBanner")
    }
}

/// Feature #99 WI-4: the self-contained banner host —
/// `ReaderContainerView` attaches it as ONE chain link (its body is
/// near the type-checker ceiling). Observes the keyed
/// `.readerBilingualRetranslateStarted`, floats the banner under the
/// top chrome, and auto-dismisses after ~4s (a newer apply restarts
/// the clock).
struct BilingualRetranslateBannerHost: ViewModifier {
    let theme: ReaderThemeV2
    let bookFingerprintKey: String

    /// The active banner's languages (new, previous); nil = hidden.
    @State private var banner: (language: String, previous: String)?
    /// Identity of the current showing — a newer apply supersedes the
    /// running auto-dismiss.
    @State private var showingGeneration = 0

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let banner {
                    BilingualRetranslateBanner(
                        theme: theme,
                        language: banner.language,
                        previousLanguage: banner.previous
                    )
                    .padding(.top, ReaderSafeAreaResolver.windowSafeAreaTop + 56)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .onReceive(NotificationCenter.default.publisher(
                for: .readerBilingualRetranslateStarted)
            ) { notification in
                guard let info = notification.userInfo,
                      info["fingerprintKey"] as? String == bookFingerprintKey,
                      let language = info["language"] as? String
                else { return }
                let previous = info["previousLanguage"] as? String ?? ""
                showingGeneration += 1
                let generation = showingGeneration
                withAnimation(.easeInOut(duration: 0.2)) {
                    banner = (language, previous)
                }
                Task {
                    try? await Task.sleep(for: .seconds(4))
                    guard generation == showingGeneration else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { banner = nil }
                }
            }
    }
}
