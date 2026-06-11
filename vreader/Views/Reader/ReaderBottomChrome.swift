// Purpose: Feature #60 WI-6b — re-skinned bottom reader chrome. A
// shared overlay carrying the progress scrubber, the two end-aligned
// position labels, and the 4-button toolbar (Contents / Notes /
// Display / AI). Replaces the legacy `ReadingProgressBar` +
// `ReaderBottomOverlay` pair inside each paginated format container
// (TXT / MD / EPUB / PDF). Foliate (AZW3/MOBI) keeps its own bottom
// overlay — plan #60 Risk (f).
//
// Layout mirrors `dev-docs/designs/vreader-fidelity-v1/project/vreader-reader.jsx`
// `ReaderBottomChrome`. The toolbar buttons post the WI-6b reader
// notifications (`.readerOpenContents` / `.readerOpenNotes` /
// `.readerOpenDisplay` / `.readerOpenAI`) rather than taking handler
// closures, so the chrome composes inside any container with no
// closure plumbing through the per-format host views.
//
// @coordinates-with: ReaderTopChrome.swift, ReaderChromeButton.swift,
//   ReaderThemeV2.swift, ReadingProgressBar.swift (reused clamp/snap
//   statics), ReaderNotifications.swift, ReaderContainerView.swift
//   (observes the toolbar notifications)

import SwiftUI

/// Re-skinned bottom reader chrome (Feature #60 WI-6b). Composed inside
/// each paginated format container with that format's own `progress`
/// binding + `onSeek` closure.
struct ReaderBottomChrome: View {
    /// Visual-identity-v2 theme tokens for the active book.
    let theme: ReaderThemeV2
    /// Reading progress, 0...1. Two-way so the scrubber thumb tracks
    /// programmatic position changes (page turns) as well as drags.
    @Binding var progress: Double
    /// Called with the resolved (clamped + step-snapped) fraction when
    /// the user scrubs.
    let onSeek: (Double) -> Void
    /// Discrete seek granularity — e.g. PDF page count so the scrubber
    /// snaps to page boundaries. `nil` for continuous (TXT / MD / EPUB).
    var discreteSteps: Int? = nil
    /// Leading position label under the scrubber (e.g. "Page 3" or
    /// "45%"). Format-supplied — the design's "Page N" is one instance.
    let leadingLabel: String
    /// Trailing PAGES readout (e.g. "414 pages left in book",
    /// "Chapter 8 of 54", a percent) — the default readout. Feature #101:
    /// session time no longer lives here; it moved inside the time readout.
    let trailingLabel: String

    /// Feature #101: the combined time readout
    /// ("12m read · 6h 40m total"). nil until session time accrues and the
    /// book totals attach — the trailing label pins the pages readout and
    /// the tap is inert.
    var timeTrailingLabel: String? = nil

    /// Feature #101: the book key + per-book settings base URL for the
    /// persisted readout choice. nil (previews / non-book surfaces)
    /// disables persistence — the choice is session-local.
    var bookFingerprintKey: String? = nil
    var perBookBaseURL: URL? = nil

    /// Feature #101: the current readout. Seeded from the persisted
    /// per-book choice on appear; toggled by tapping the trailing label.
    @State private var metricsReadout: ReaderMetricsReadout = .pages

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(spacing: 14) {
                scrubberSection
                toolbar
            }
            .padding(.top, 14)
            // Design baseline is 28pt (`vreader-reader.jsx` paddingBottom).
            // On home-indicator devices the real inset (~34) is larger and
            // wins; on zero-inset layouts we keep the 28pt design baseline
            // rather than collapsing to a too-low value.
            .padding(.bottom, max(ReaderSafeAreaResolver.windowSafeAreaBottom, 28))
            .background(chromeBackground)
            .overlay(alignment: .top) {
                Color(theme.ruleColor).frame(height: 0.5)
            }
        }
    }

    // MARK: - Background

    /// Chrome surface: the theme `chrome` token, or a dark scrim over a
    /// Photo-theme background image so the chrome stays legible.
    private var chromeBackground: Color {
        theme.usesBackgroundImage
            ? Color.black.opacity(0.55)
            : Color(theme.chromeColor)
    }

    // MARK: - Scrubber + labels

    private var scrubberSection: some View {
        VStack(spacing: 4) {
            ReaderScrubber(
                theme: theme,
                progress: $progress,
                onSeek: onSeek,
                discreteSteps: discreteSteps
            )
            HStack {
                Text(leadingLabel)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                // Feature #101: the trailing label is a tap target cycling
                // page ↔ time readouts (design RTMetricsLine). It never
                // wraps; the leading label truncates instead.
                Button {
                    let next = metricsReadout.toggled(
                        hasTimeReadout: timeTrailingLabel != nil)
                    guard next != metricsReadout else { return }
                    metricsReadout = next
                    persistReadoutChoice(next)
                } label: {
                    Text(metricsReadout.displayLabel(
                        pages: trailingLabel, time: timeTrailingLabel))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                // Gate-4 r1 Medium: with no time readout the tap is inert —
                // suppress the pressed flash too, not just the cycle.
                .buttonStyle(MetricsReadoutButtonStyle(
                    theme: theme, showsPressedFill: timeTrailingLabel != nil))
                .layoutPriority(1)
                .accessibilityIdentifier("readerMetricsReadout")
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(Color(theme.subColor))
            .onAppear { resolvePersistedReadout() }
            // Gate-4 r1 Medium: the chrome instance can be reused for a
            // different book (host swap under the same container) — re-resolve
            // the persisted choice when the book identity changes.
            .onChange(of: bookFingerprintKey) { resolvePersistedReadout() }
        }
        .padding(.horizontal, 22)
    }

    /// Feature #101: seeds `metricsReadout` from the book's persisted choice
    /// (pages when absent / unknown / non-book surface).
    private func resolvePersistedReadout() {
        guard let bookFingerprintKey, let perBookBaseURL else {
            metricsReadout = .pages
            return
        }
        metricsReadout = ReaderMetricsReadout.resolve(
            persisted: PerBookSettingsStore.settings(
                for: bookFingerprintKey, baseURL: perBookBaseURL
            )?.metricsReadout)
    }

    /// Feature #101: persists the readout choice per book through the shared
    /// read-modify-write helper (Gate-2 M2 — never hand-merge the JSON).
    private func persistReadoutChoice(_ readout: ReaderMetricsReadout) {
        guard let bookFingerprintKey, let perBookBaseURL else { return }
        try? PerBookSettingsStore.update(
            for: bookFingerprintKey, baseURL: perBookBaseURL
        ) { $0.metricsReadout = readout.rawValue }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 0) {
            ForEach(ReaderBottomChromeButton.allCases, id: \.self) { button in
                toolbarButton(button)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 12)
    }

    private func toolbarButton(_ button: ReaderBottomChromeButton) -> some View {
        // Per the design, a non-accent button draws its icon in `ink`
        // but its label in the dimmer `sub` token; the accent button
        // (AI) draws both in `accent`.
        let iconColor = button.isAccent ? Color(theme.accentColor) : Color(theme.inkColor)
        let labelColor = button.isAccent ? Color(theme.accentColor) : Color(theme.subColor)
        return Button {
            NotificationCenter.default.post(name: Self.notification(for: button), object: nil)
        } label: {
            VStack(spacing: 3) {
                Image(systemName: Self.symbol(for: button))
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(iconColor)
                Text(Self.label(for: button))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(labelColor)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(button.accessibilityIdentifier)
    }

    // MARK: - Per-button mapping

    /// Toolbar notification posted on tap. `ReaderContainerView`
    /// observes all four and presents the matching sheet/panel.
    static func notification(for button: ReaderBottomChromeButton) -> Notification.Name {
        switch button {
        case .contents: return .readerOpenContents
        case .notes:    return .readerOpenNotes
        case .display:  return .readerOpenDisplay
        case .ai:       return .readerOpenAI
        }
    }

    private static func symbol(for button: ReaderBottomChromeButton) -> String {
        switch button {
        case .contents: return "list.bullet"
        case .notes:    return "highlighter"
        case .display:  return "textformat.size"
        case .ai:       return "sparkles"
        }
    }

    private static func label(for button: ReaderBottomChromeButton) -> String {
        switch button {
        case .contents: return "Contents"
        case .notes:    return "Notes"
        case .display:  return "Display"
        case .ai:       return "AI"
        }
    }
}

// (Feature #60 WI-6b `ReaderScrubber` and `ReaderToolbarActionObservers`
// moved to their own files for the ~300-line budget — see
// ReaderScrubber.swift / ReaderToolbarActionObservers.swift.)

/// Feature #101: the design's pressed state — a subtle rounded fill behind
/// the trailing label while the finger is down (RTMetricsLine `pressed`).
/// `showsPressedFill` is false while the tap is inert (no time readout) so
/// the pinned-pages state gives no pressed flash (Gate-4 r1 Medium).
private struct MetricsReadoutButtonStyle: ButtonStyle {
    let theme: ReaderThemeV2
    let showsPressedFill: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(
                    configuration.isPressed && showsPressedFill
                        ? (theme.isDark
                            ? Color.white.opacity(0.08)
                            : Color.black.opacity(0.06))
                        : Color.clear
                )
            )
            .padding(.horizontal, -6)
            .padding(.vertical, -1)
    }
}
