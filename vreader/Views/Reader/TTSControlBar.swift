// Purpose: SwiftUI control bar for TTS playback controls.
// Shows play/pause/stop buttons and a speed slider. Appears at the bottom
// of the reader when TTS is active.
//
// Key decisions:
// - Accepts TTSService as Bindable for two-way rate binding.
// - Only visible when TTS state is not idle.
// - Speed slider range 0.0–1.0 matching AVSpeechUtterance rate range.
// - Displays human-readable speed labels (0.5x, 1x, 2x mapped from rate).
// - Compact horizontal layout matching ReaderBottomOverlay style.
//
// @coordinates-with: TTSService.swift, ReaderContainerView.swift

import SwiftUI

/// Bottom bar with TTS playback controls (play/pause, stop, speed).
struct TTSControlBar: View {

    @Bindable var ttsService: TTSService
    let settingsStore: ReaderSettingsStore?

    var body: some View {
        HStack(spacing: 16) {
            // Play/Pause button
            Button {
                switch ttsService.state {
                case .speaking:
                    ttsService.pause()
                case .paused:
                    ttsService.resume()
                case .idle:
                    break  // Should not be visible when idle
                }
            } label: {
                Image(systemName: ttsService.state == .speaking ? "pause.fill" : "play.fill")
                    .font(.title3)
            }
            .accessibilityLabel(ttsService.state == .speaking ? "Pause" : "Resume")
            .accessibilityIdentifier("ttsPlayPauseButton")

            // Stop button
            Button {
                ttsService.stop()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.title3)
            }
            .accessibilityLabel("Stop reading")
            .accessibilityIdentifier("ttsStopButton")

            Spacer()

            // Speed label
            Text(Self.speedLabel(for: ttsService.rate))
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(secondaryColor)
                .accessibilityIdentifier("ttsSpeedLabel")

            // Speed slider
            Slider(value: $ttsService.rate, in: 0.0...1.0, step: 0.05)
                .frame(width: 100)
                .accessibilityLabel("Speech speed")
                .accessibilityIdentifier("ttsSpeedSlider")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .accessibilityIdentifier("ttsControlBar")
    }

    // MARK: - Theme Colors

    // Feature #60 WI-11: `theme` is `ReaderThemeV2`; `subColor` is the
    // V2 token for secondary text. Fallback uses `ReaderThemeV2.default`.
    private var secondaryColor: Color {
        Color(settingsStore?.theme.subColor ?? ReaderThemeV2.default.subColor)
    }

    private var backgroundColor: Color {
        Color(settingsStore?.theme.backgroundColor ?? ReaderThemeV2.default.backgroundColor)
            .opacity(0.95)
    }

    // MARK: - Speed Label

    /// Converts AVSpeechUtterance rate (0.0–1.0) to a human-readable speed label.
    /// AVSpeechUtteranceDefaultSpeechRate is 0.5, which we label "1x".
    /// 0.0 = "0.5x" (slowest), 0.25 = "0.75x", 0.5 = "1x" (normal), 0.75 = "1.5x", 1.0 = "2x".
    static func speedLabel(for rate: Float) -> String {
        // Linear mapping: rate 0.0 → 0.5x, rate 0.5 → 1.0x, rate 1.0 → 2.0x
        let displaySpeed = 0.5 + Double(rate) * 1.5
        if displaySpeed == Double(Int(displaySpeed)) {
            return "\(Int(displaySpeed))x"
        }
        return String(format: "%.1fx", displaySpeed)
    }
}
