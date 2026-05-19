// Purpose: Feature #62 WI-2 — the shared annotations empty-state view.
//
// Reproduces the committed design's `EmptyState` component
// (`dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`):
// a centred 96×96 art illustration, a serif title, a body paragraph,
// and an OPTIONAL accent-pill CTA button. The four annotations list
// surfaces — `TOCSheet`'s Contents/Bookmarks tabs and `HighlightsSheet`'s
// filters — reuse it for their empty states, replacing the plain
// `ContentUnavailableView` the legacy list views used (rule 51 — the
// designed surface).
//
// `accessibilityIdentifier` is a configurable input so WI-5 can re-home
// the legacy `tocEmptyState` / `bookmarkEmptyState` XCUITest identifiers
// onto this view when the legacy views are deleted.
//
// @coordinates-with: AnnotationsEmptyStateArt.swift, TOCSheet.swift,
//   HighlightsSheet.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-annotations.jsx`

import SwiftUI

/// The design's `EmptyState` — centred art + serif title + body + an
/// optional accent CTA. Pure presentation; the CTA action is injected.
struct AnnotationsEmptyStateView: View {
    /// Visual-identity-v2 theme tokens.
    let theme: ReaderThemeV2
    /// Stable accessibility identifier for XCUITest lookup.
    let accessibilityIdentifier: String
    /// The empty-state illustration (one of the three `Empty*Art` views).
    let art: AnyView
    /// Serif heading.
    let title: String
    /// Supporting paragraph.
    let body_: String
    /// CTA button label — when nil, no CTA is shown.
    let ctaLabel: String?
    /// SF Symbol drawn before the CTA label.
    let ctaSystemImage: String?
    /// CTA tap action.
    let onCTA: (() -> Void)?

    init(
        theme: ReaderThemeV2,
        accessibilityIdentifier: String,
        art: AnyView,
        title: String,
        body: String,
        ctaLabel: String? = nil,
        ctaSystemImage: String? = nil,
        onCTA: (() -> Void)? = nil
    ) {
        self.theme = theme
        self.accessibilityIdentifier = accessibilityIdentifier
        self.art = art
        self.title = title
        self.body_ = body
        self.ctaLabel = ctaLabel
        self.ctaSystemImage = ctaSystemImage
        self.onCTA = onCTA
    }

    /// True when a CTA button is part of the composition — the design's
    /// `cta && ...` guard. Both a label and an action must be supplied.
    var hasCTA: Bool {
        ctaLabel != nil && onCTA != nil
    }

    /// Test-only hook: invokes the CTA action so a unit test can pin the
    /// closure wiring without a tap-gesture render path. Gated on
    /// `hasCTA` so it is a faithful proxy for "tap the visible CTA" — it
    /// no-ops when no button is rendered (label or action absent).
    func invokeCTAForTesting() {
        guard hasCTA else { return }
        onCTA?()
    }

    var body: some View {
        VStack(spacing: 16) {
            art
                .frame(width: 96, height: 96)
                .opacity(0.85)
                // The art is a decorative SVG-path illustration — its
                // shape "lines" can read as text to the accessibility
                // audit's element-detection pass. Hide it: the empty
                // state's meaning is the title + body copy below, which
                // VoiceOver announces.
                .accessibilityHidden(true)

            Text(title)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 18)))
                .fontWeight(.semibold)
                .foregroundStyle(Color(theme.inkColor))
                .multilineTextAlignment(.center)

            Text(body_)
                .font(.system(size: 13))
                .foregroundStyle(Color(theme.subColor))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: 280)

            if hasCTA, let ctaLabel, let onCTA {
                Button(action: onCTA) {
                    HStack(spacing: 6) {
                        if let ctaSystemImage {
                            Image(systemName: ctaSystemImage)
                                .font(.system(size: 13, weight: .bold))
                        }
                        Text(ctaLabel)
                            .font(.system(size: 12.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule().fill(Color(theme.accentColor))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 36)
        .padding(.top, 24)
        .padding(.bottom, 56)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
