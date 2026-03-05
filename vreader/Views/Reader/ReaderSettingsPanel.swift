// Purpose: Slide-up settings panel for reader theme and typography controls.
// Provides theme picker, font size slider, line spacing slider, font family picker,
// CJK spacing toggle, and live-preview text.
//
// Key decisions:
// - Presented as a sheet from reader toolbar.
// - All changes apply immediately (no "save" button needed).
// - Preview text updates live as settings change.
// - Theme picker uses colored circles (light/sepia/dark).
// - Compact layout suitable for half-sheet presentation.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderContainerView.swift

import SwiftUI

/// Settings panel for reader appearance.
struct ReaderSettingsPanel: View {
    @Bindable var store: ReaderSettingsStore

    var body: some View {
        NavigationStack {
            List {
                themeSection
                fontSizeSection
                lineSpacingSection
                fontFamilySection
                cjkSection
                previewSection
            }
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .accessibilityIdentifier("readerSettingsPanel")
    }

    // MARK: - Theme

    @ViewBuilder
    private var themeSection: some View {
        Section("Theme") {
            HStack(spacing: 20) {
                Spacer()
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    themeCircle(theme)
                }
                Spacer()
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private func themeCircle(_ theme: ReaderTheme) -> some View {
        Button {
            store.theme = theme
        } label: {
            VStack(spacing: 6) {
                Circle()
                    .fill(Color(theme.backgroundColor))
                    .overlay(
                        Circle().stroke(
                            store.theme == theme ? Color.accentColor : Color.gray.opacity(0.3),
                            lineWidth: store.theme == theme ? 3 : 1
                        )
                    )
                    .frame(width: 44, height: 44)

                Text(theme.rawValue.capitalized)
                    .font(.caption2)
                    .foregroundStyle(store.theme == theme ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.rawValue) theme")
        .accessibilityAddTraits(store.theme == theme ? [.isSelected] : [])
    }

    // MARK: - Font Size

    @ViewBuilder
    private var fontSizeSection: some View {
        Section("Font Size") {
            HStack {
                Text("A")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { store.typography.fontSize },
                        set: { store.typography.fontSize = $0 }
                    ),
                    in: TypographySettings.fontSizeRange,
                    step: 1
                )
                .accessibilityLabel("Font size")
                Text("A")
                    .font(.system(size: 24))
                    .foregroundStyle(.secondary)
                Text("\(Int(store.typography.fontSize))pt")
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36)
            }
        }
    }

    // MARK: - Line Spacing

    @ViewBuilder
    private var lineSpacingSection: some View {
        Section("Line Spacing") {
            HStack {
                Image(systemName: "text.alignleft")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(
                    value: Binding(
                        get: { store.typography.lineSpacing },
                        set: { store.typography.lineSpacing = $0 }
                    ),
                    in: TypographySettings.lineSpacingRange,
                    step: 0.1
                )
                .accessibilityLabel("Line spacing")
                Text(String(format: "%.1fx", store.typography.lineSpacing))
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width: 36)
            }
        }
    }

    // MARK: - Font Family

    @ViewBuilder
    private var fontFamilySection: some View {
        Section("Font") {
            Picker("Font Family", selection: $store.typography.fontFamily) {
                Text("System").tag(ReaderFontFamily.system)
                Text("Serif").tag(ReaderFontFamily.serif)
                Text("Monospace").tag(ReaderFontFamily.monospace)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Font family")
        }
    }

    // MARK: - CJK Spacing

    @ViewBuilder
    private var cjkSection: some View {
        Section {
            Toggle("CJK Character Spacing", isOn: $store.typography.cjkSpacing)
                .accessibilityLabel("CJK character spacing")
        } footer: {
            Text("Adds extra spacing between CJK characters for improved readability.")
                .font(.caption)
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Section("Preview") {
            Text(previewText)
                .font(previewFont)
                .tracking(store.cjkLetterSpacing)
                .lineSpacing(store.lineSpacingPoints)
                .foregroundStyle(Color(store.uiTextColor))
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(store.uiBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var previewText: String {
        if store.typography.cjkSpacing {
            return "The quick brown fox jumps over the lazy dog.\n\u{6587}\u{5B57}\u{306E}\u{8868}\u{793A}\u{30B5}\u{30F3}\u{30D7}\u{30EB}\u{3067}\u{3059}\u{3002}"
        }
        return "The quick brown fox jumps over the lazy dog. Typography matters for comfortable reading."
    }

    private var previewFont: Font {
        switch store.typography.fontFamily {
        case .system:
            return .system(size: store.typography.fontSize)
        case .serif:
            return .custom("Georgia", size: store.typography.fontSize)
        case .monospace:
            return .system(size: store.typography.fontSize, design: .monospaced)
        }
    }
}
