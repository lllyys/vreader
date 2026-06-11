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
                .buttonStyle(MetricsReadoutButtonStyle(theme: theme))
                .layoutPriority(1)
                .accessibilityIdentifier("readerMetricsReadout")
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(Color(theme.subColor))
            .onAppear {
                guard let bookFingerprintKey, let perBookBaseURL else { return }
                metricsReadout = ReaderMetricsReadout.resolve(
                    persisted: PerBookSettingsStore.settings(
                        for: bookFingerprintKey, baseURL: perBookBaseURL
                    )?.metricsReadout)
            }
        }
        .padding(.horizontal, 22)
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

// MARK: - Scrubber

/// Custom progress scrubber — a 3 pt track with an accent fill and a
/// 14 pt draggable thumb, matching the design. Clamp + discrete-step
/// snapping reuse `ReadingProgressBar`'s tested statics so WI-6b does
/// not re-derive that logic.
private struct ReaderScrubber: View {
    let theme: ReaderThemeV2
    @Binding var progress: Double
    let onSeek: (Double) -> Void
    let discreteSteps: Int?

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let clamped = ReadingProgressBar.clampedProgress(progress)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 3)
                Capsule()
                    .fill(Color(theme.accentColor))
                    .frame(width: max(0, width * clamped), height: 3)
                Circle()
                    .fill(Color(theme.accentColor))
                    .frame(width: 14, height: 14)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .offset(x: width * clamped - 7)
            }
            .frame(height: 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        guard width > 0 else { return }
                        let fraction = max(0, min(1, value.location.x / width))
                        let resolved = ReadingProgressBar.resolveSeekValue(
                            fraction, discreteSteps: discreteSteps
                        )
                        progress = resolved
                        onSeek(resolved)
                    }
            )
        }
        .frame(height: 24)
        .accessibilityElement()
        .accessibilityLabel("Reading progress scrubber")
        .accessibilityValue(ReadingProgressBar.formatLabel(
            progress: ReadingProgressBar.clampedProgress(progress), label: nil
        ))
        .accessibilityIdentifier("readingProgressScrubber")
    }
}

// MARK: - Toolbar action observers

/// Feature #60 WI-6b: bundles the four bottom-chrome toolbar
/// notification observers into a single modifier. `ReaderContainerView`
/// applies it as one `.modifier(...)` rather than four chained
/// `.onReceive`s — its `body` is already near the Swift type-checker's
/// expression-complexity ceiling, and four more chain links tipped it
/// over ("unable to type-check in reasonable time").
struct ReaderToolbarActionObservers: ViewModifier {
    let onContents: () -> Void
    let onNotes: () -> Void
    let onDisplay: () -> Void
    let onAI: () -> Void

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenContents)) { _ in
                onContents()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenNotes)) { _ in
                onNotes()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenDisplay)) { _ in
                onDisplay()
            }
            .onReceive(NotificationCenter.default.publisher(for: .readerOpenAI)) { _ in
                onAI()
            }
    }
}

extension View {
    /// Attaches the four bottom-chrome toolbar observers (Feature #60
    /// WI-6b). See `ReaderToolbarActionObservers`.
    func readerToolbarActionObservers(
        onContents: @escaping () -> Void,
        onNotes: @escaping () -> Void,
        onDisplay: @escaping () -> Void,
        onAI: @escaping () -> Void
    ) -> some View {
        modifier(ReaderToolbarActionObservers(
            onContents: onContents,
            onNotes: onNotes,
            onDisplay: onDisplay,
            onAI: onAI
        ))
    }
}

/// Feature #101: the design's pressed state — a subtle rounded fill behind
/// the trailing label while the finger is down (RTMetricsLine `pressed`).
private struct MetricsReadoutButtonStyle: ButtonStyle {
    let theme: ReaderThemeV2

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 7).fill(
                    configuration.isPressed
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
