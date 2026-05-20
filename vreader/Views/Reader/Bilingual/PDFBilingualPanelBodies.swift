// Purpose: Feature #56 WI-13 — body subviews for
// `PDFBilingualPanel`. Split out so the parent stays under the ~300
// LOC budget (rule 50 §9). Pure SwiftUI views; theme-driven; no VM
// coupling.
//
// @coordinates-with: PDFBilingualPanel.swift,
//   PDFBilingualPanelState.swift, ReaderThemeV2.swift

#if canImport(UIKit)
import SwiftUI

// MARK: - .translated

/// Renders translation paragraphs. Echoes the interlinear typography
/// hierarchy (size, color opacity, line-height) so a user toggling
/// between EPUB and PDF in bilingual mode sees the same rhythm.
struct PDFBilingualTranslatedBody: View {

    let theme: ReaderThemeV2
    let segments: [String]

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph)
                        .font(.system(size: 13))
                        .lineSpacing(13 * 0.65) // line-height ~1.65
                        .foregroundStyle(Color(theme.inkColor).opacity(0.85))
                        .padding(.leading, index == 0 ? 0 : 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

// MARK: - .loading

/// Three shimmer bars with a 1.4s sweep — intentionally less elaborate
/// than the default state because this is a 1-3s view, not a
/// destination.
struct PDFBilingualLoadingBody: View {

    let theme: ReaderThemeV2

    @State private var phase: CGFloat = -1

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            shimmerBar(widthFraction: 0.92)
            shimmerBar(widthFraction: 0.88)
            shimmerBar(widthFraction: 0.64)
                .padding(.bottom, 8)
            shimmerBar(widthFraction: 0.90)
            shimmerBar(widthFraction: 0.46)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            withAnimation(
                .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
            ) {
                phase = 1
            }
        }
    }

    @ViewBuilder
    private func shimmerBar(widthFraction: CGFloat) -> some View {
        GeometryReader { geometry in
            let width = geometry.size.width * widthFraction
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: shimmerColors,
                        startPoint: .init(x: phase, y: 0.5),
                        endPoint: .init(x: phase + 1, y: 0.5)
                    )
                )
                .frame(width: width, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 10)
    }

    private var shimmerColors: [Color] {
        if theme.isDark {
            return [
                Color.white.opacity(0.04),
                Color.white.opacity(0.12),
                Color.white.opacity(0.04),
            ]
        } else {
            let c = Color(red: 20/255, green: 14/255, blue: 4/255)
            return [
                c.opacity(0.04),
                c.opacity(0.10),
                c.opacity(0.04),
            ]
        }
    }
}

// MARK: - .offline

/// Cloud-off icon + explanatory copy + two CTAs (Retry primary,
/// Open-AI-tab secondary). Doesn't pretend to translate from a stale
/// cache; says exactly what's missing and what unlocks it.
struct PDFBilingualOfflineBody: View {

    let theme: ReaderThemeV2
    let onRetry: () -> Void
    let onOpenAITab: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "icloud.slash")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                Text("Translation unavailable offline")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
            }
            Text(
                "This page hasn’t been translated yet. Connect to the internet and tap retry, or translate a single paragraph on demand with the AI tab."
            )
            .font(.system(size: 12))
            .lineSpacing(2)
            .foregroundStyle(Color(theme.subColor))
            HStack(spacing: 8) {
                retryButton
                openAITabButton
                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var retryButton: some View {
        Button(action: onRetry) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 10, weight: .semibold))
                Text("Retry")
                    .font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundStyle(.white)
            .background(
                Capsule().fill(Color(theme.accentColor))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PDFBilingualPanel.retryButtonIdentifier)
    }

    @ViewBuilder
    private var openAITabButton: some View {
        Button(action: onOpenAITab) {
            Text("Open AI tab")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .foregroundStyle(Color(theme.inkColor))
                .background(
                    Capsule()
                        .stroke(Color(theme.ruleColor), lineWidth: 0.5)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(PDFBilingualPanel.openAITabButtonIdentifier)
    }
}

// MARK: - .empty

/// Image-only / scan-without-OCR page. Distinct copy from offline so
/// the user doesn't keep hitting retry on a page that will never
/// translate.
struct PDFBilingualEmptyBody: View {

    let theme: ReaderThemeV2

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "photo")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(Color(theme.subColor))
            Text(
                "No translatable text on this page — the page contains only an image or scan. Continue to the next page for the translation."
            )
            .font(.system(size: 12.5))
            .lineSpacing(1.5)
            .foregroundStyle(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 6)
    }
}
#endif
