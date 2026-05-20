// Purpose: Feature #56 WI-14 — the per-book translate-status sheet.
// Hero progress (large fraction + bar), per-unit list ("Unit N — queued/
// translating/done"), and a destructive "Cancel translation" CTA at the
// bottom.
//
// Pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`
// (`TranslateStatusSheet` + `ChapterStatusRow`).
//
// Design fidelity note: the design shows per-chapter titles (e.g.
// "Bingley arrives at Netherfield"). The runtime translation unit is the
// format's spine doc / TXT chapter / PDF page-range — there is no
// authoritative human title for each unit available to the coordinator.
// We render `Ch. N — {storage key short suffix}` so the list still maps
// 1:1 to the design's row structure. A later iteration can join in TOC
// titles once a `TranslationUnitID -> title` resolver lands.
//
// @coordinates-with: BookTranslationViewModel.swift,
//   BookTranslationProgress.swift, ReaderThemeV2.swift,
//   `dev-docs/designs/vreader-fidelity-v1/project/vreader-translate-book.jsx`

#if canImport(UIKit)
import SwiftUI

/// Per-book translation-status sheet — hero progress + per-unit list +
/// cancel CTA.
struct TranslateStatusSheet: View {

    /// Latest progress snapshot.
    let progress: BookTranslationProgress
    /// Localized target language label (sheet title + hero subtitle).
    let targetLanguageLabel: String
    /// Provider label rendered under the hero progress.
    let providerLabel: String
    let theme: ReaderThemeV2

    /// User tapped "Cancel translation" — VM shows the cancel alert.
    let onCancelAll: () -> Void

    var body: some View {
        ReaderSheetChrome(theme: theme, title: "Translating to \(targetLanguageLabel)") {
            VStack(spacing: 0) {
                hero
                Divider().overlay(Color(theme.ruleColor)).padding(.top, 18)
                chaptersList
                Spacer(minLength: 0)
                bottomBar
            }
        }
        .accessibilityIdentifier("translateStatusSheet")
    }

    /// "{done} / {total}" big fraction + progress bar + provider line.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(progress.completed)")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Text("/ \(progress.total)")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                Spacer(minLength: 0)
                Text(phaseLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(theme.subColor))
                    .kerning(0.3)
            }
            progressBar
            HStack {
                Spacer(minLength: 0)
                Text(providerLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(theme.isDark ? Color.white.opacity(0.04) : Color.black.opacity(0.03))
        )
        .padding(.horizontal, 18)
        .padding(.top, 12)
    }

    private var progressBar: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.isDark ? Color.white.opacity(0.08) : Color.black.opacity(0.06))
                Capsule()
                    .fill(Color(theme.accentColor))
                    .frame(width: proxy.size.width * CGFloat(progress.fraction))
            }
        }
        .frame(height: 5)
    }

    private var phaseLabel: String {
        switch progress.phase {
        case .running: return "TRANSLATING"
        case .completed: return "DONE"
        case .cancelled: return "CANCELLED"
        case .failed: return "PAUSED"
        case .idle: return ""
        }
    }

    /// The list of units — uses `progress.completed`/`progress.total` to
    /// derive a queued/done split. Per the file's "design fidelity note"
    /// we render anonymous "Ch. N" rows.
    private var chaptersList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<max(progress.total, 0), id: \.self) { index in
                    ChapterStatusRow(
                        chapterNumber: index + 1,
                        state: state(for: index),
                        last: index == progress.total - 1,
                        theme: theme)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 12)
        }
    }

    private func state(for index: Int) -> ChapterStatusRow.State {
        if index < progress.completed { return .done }
        if index == progress.completed && progress.isRunning { return .running }
        if progress.phase == .failed && index == progress.completed { return .failed }
        return .queued
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider().overlay(Color(theme.ruleColor))
            Button(action: onCancelAll) {
                Text("Cancel translation")
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(theme.isDark
                                  ? Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255).opacity(0.12)
                                  : Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255).opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .accessibilityIdentifier("translateStatusSheetCancel")
        }
        .background(theme.isDark
                    ? Color(red: 0x22 / 255, green: 0x20 / 255, blue: 0x20 / 255)
                    : Color(red: 0xfc / 255, green: 0xf8 / 255, blue: 0xf0 / 255))
    }
}

/// One row in `TranslateStatusSheet`'s per-unit list — pinned to the
/// design's `ChapterStatusRow` (queued / running / done / failed).
struct ChapterStatusRow: View {
    enum State { case queued, running, done, failed }

    let chapterNumber: Int
    let state: State
    let last: Bool
    let theme: ReaderThemeV2

    var body: some View {
        HStack(spacing: 12) {
            iconChip
            Text("Ch. \(chapterNumber)")
                .font(.system(size: 13.5, weight: state == .running ? .semibold : .medium))
                .foregroundStyle(state == .queued ? Color(theme.subColor) : Color(theme.inkColor))
                .lineLimit(1)
            Spacer(minLength: 0)
            stateLabel
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) {
            if !last {
                Rectangle()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 0.5)
            }
        }
    }

    private var iconChip: some View {
        Circle()
            .fill(chipFill)
            .frame(width: 22, height: 22)
            .overlay { chipContent }
    }

    @ViewBuilder
    private var chipContent: some View {
        switch state {
        case .done:
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
        case .running:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.mini)
                .tint(Color(theme.accentColor))
        case .failed:
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255))
        case .queued:
            Text("\(chapterNumber)")
                .font(.system(size: 10, weight: .medium).monospaced())
                .foregroundStyle(Color(theme.subColor))
        }
    }

    private var chipFill: Color {
        switch state {
        case .done: return Color(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255)
        case .running: return Color(theme.accentColor).opacity(0.15)
        case .failed: return Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255).opacity(0.14)
        case .queued: return theme.isDark
            ? Color.white.opacity(0.06)
            : Color.black.opacity(0.05)
        }
    }

    private var stateLabel: some View {
        Text(label)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(labelColor)
            .kerning(0.4)
    }

    private var label: String {
        switch state {
        case .done: return ""
        case .running: return "NOW"
        case .failed: return "FAILED"
        case .queued: return "QUEUED"
        }
    }

    private var labelColor: Color {
        switch state {
        case .done: return Color(red: 0x3a / 255, green: 0x6a / 255, blue: 0x5a / 255)
        case .running: return Color(theme.accentColor)
        case .failed: return Color(red: 0xc4 / 255, green: 0x44 / 255, blue: 0x44 / 255)
        case .queued: return Color(theme.subColor)
        }
    }
}
#endif
