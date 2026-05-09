// Purpose: Slide-up settings panel for reader theme, reading mode, and typography controls.
// Provides theme picker, reading mode picker, font size slider, line spacing slider,
// font family picker, CJK spacing toggle, and live-preview text.
// When paged layout is selected, shows page turn animation picker and auto page turn toggle.
//
// Key decisions:
// - Presented as a sheet from reader toolbar.
// - All changes apply immediately (no "save" button needed).
// - Preview text updates live as settings change.
// - Theme picker uses colored circles (light/sepia/dark).
// - Compact layout suitable for half-sheet presentation.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderContainerView.swift

import PhotosUI
import SwiftUI

/// Settings panel for reader appearance.
struct ReaderSettingsPanel: View {
    @Bindable var store: ReaderSettingsStore
    /// Tap zone configuration store (feature #25).
    var tapZoneStore: TapZoneStore?
    /// Fingerprint key for the currently open book (nil if no per-book support).
    var bookFingerprintKey: String?
    /// Base URL for per-book settings storage.
    var perBookBaseURL: URL?
    /// Capabilities of the current book's format. Used to gate settings whose
    /// effect depends on the active rendering path (bug #120). When nil, the
    /// panel falls back to "available everywhere" — preserves backward compat
    /// for callers (and tests/previews) that don't supply the value.
    var formatCapabilities: FormatCapabilities? = nil
    /// Whether per-book settings are currently enabled for this book.
    @State private var isPerBookEnabled = false
    /// Photo picker state for theme background (feature #32).
    @State private var backgroundPickerItem: PhotosPickerItem?
    /// Bug #134: surface theme-background load/save/remove failures.
    @State private var backgroundErrorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                themeSection
                themeBackgroundSection
                readingModeSection
                epubLayoutSection
                if store.epubLayout == .paged {
                    pageTurnAnimationSection
                    // Bug #156 / GH #456: only render the Auto Page Turn
                    // toggle for formats whose reader host actually wires
                    // `AutoPageTurner`. Today that's TXT and MD only —
                    // EPUB / PDF / AZW3 / MOBI / Unified hosts don't
                    // observe `store.autoPageTurn`, so the toggle would
                    // silently no-op for those formats. Defaulting to
                    // "show" when capabilities aren't supplied keeps
                    // tests/previews/legacy callers working.
                    if formatCapabilities?.contains(.autoPageTurn) ?? true {
                        autoPageTurnSection
                    }
                }
                fontSizeSection
                lineSpacingSection
                fontFamilySection
                cjkSection
                chineseConversionSection
                if tapZoneStore != nil { tapZoneSection }
                if bookFingerprintKey != nil { perBookSection }
                previewSection
            }
            .navigationTitle("Reading Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onAppear { loadPerBookState() }
        .onChange(of: store.typography.fontSize) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.lineSpacing) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.fontFamily) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.cjkSpacing) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.theme) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.readingMode) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.chineseConversion) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: backgroundPickerItem) { _, newItem in
            // Bug #134: surface failures instead of silently swallowing.
            guard let item = newItem else { return }
            Task {
                let data: Data
                do {
                    guard let loaded = try await item.loadTransferable(type: Data.self) else {
                        backgroundErrorMessage = "Selected image returned no data."
                        backgroundPickerItem = nil
                        return
                    }
                    data = loaded
                } catch {
                    backgroundErrorMessage = "Could not load image: \(error.localizedDescription)"
                    backgroundPickerItem = nil
                    return
                }
                guard let image = UIImage(data: data) else {
                    backgroundErrorMessage = "Could not decode image — unsupported format?"
                    backgroundPickerItem = nil
                    return
                }
                do {
                    try ThemeBackgroundStore.saveBackground(image, for: store.theme.rawValue)
                    store.useCustomBackground = true
                } catch {
                    backgroundErrorMessage = "Could not save background: \(error.localizedDescription)"
                }
                backgroundPickerItem = nil
            }
        }
        .alert(
            "Background",
            isPresented: .init(
                get: { backgroundErrorMessage != nil },
                set: { if !$0 { backgroundErrorMessage = nil } }
            )
        ) {
            Button("OK") { backgroundErrorMessage = nil }
        } message: {
            Text(backgroundErrorMessage ?? "")
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

    // MARK: - Theme Background (A04, feature #32)

    @ViewBuilder
    private var themeBackgroundSection: some View {
        Section {
            Toggle("Custom Background", isOn: $store.useCustomBackground)
                .accessibilityLabel("Custom background")

            if store.useCustomBackground {
                HStack {
                    Text("Opacity")
                    Slider(value: $store.backgroundOpacity, in: 0.05...1, step: 0.05)
                        .accessibilityLabel("Background opacity")
                    Text("\(Int(store.backgroundOpacity * 100))%")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36)
                }

                PhotosPicker(selection: $backgroundPickerItem, matching: .images) {
                    Label("Choose Image", systemImage: "photo.on.rectangle")
                }
                .accessibilityLabel("Choose background image")

                Button(role: .destructive) {
                    // Bug #134: surface removeBackground failures.
                    do {
                        try ThemeBackgroundStore.removeBackground(for: store.theme.rawValue)
                        store.useCustomBackground = false
                    } catch {
                        backgroundErrorMessage = "Could not remove background: \(error.localizedDescription)"
                    }
                } label: {
                    Label("Remove Background", systemImage: "trash")
                }
                .accessibilityLabel("Remove background image")
            }
        }
    }

    // MARK: - Reading Mode

    @ViewBuilder
    private var readingModeSection: some View {
        Section {
            Picker("Reading Mode", selection: $store.readingMode) {
                Text("Native").tag(ReadingMode.native)
                Text("Unified").tag(ReadingMode.unified)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Reading mode")
        } footer: {
            Text("Native uses format-specific readers. Unified reflow engine is coming in V2.")
                .font(.caption)
        }
    }

    // MARK: - EPUB Layout

    @ViewBuilder
    private var epubLayoutSection: some View {
        Section {
            Picker("EPUB Layout", selection: $store.epubLayout) {
                Text("Scroll").tag(EPUBLayoutPreference.scroll)
                Text("Paged").tag(EPUBLayoutPreference.paged)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("EPUB layout")
        } footer: {
            Text("Scroll uses continuous vertical scrolling. Paged uses horizontal page turns.")
                .font(.caption)
        }
    }

    // MARK: - Page Turn Animation (B11)

    @ViewBuilder
    private var pageTurnAnimationSection: some View {
        Section {
            Picker("Page Turn Animation", selection: $store.pageTurnAnimation) {
                Text("None").tag(PageTurnAnimation.none)
                Text("Slide").tag(PageTurnAnimation.slide)
                Text("Cover").tag(PageTurnAnimation.cover)
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Page turn animation")
        }
    }

    // MARK: - Auto Page Turn (B10)

    @ViewBuilder
    private var autoPageTurnSection: some View {
        Section {
            Toggle("Auto Page Turn", isOn: $store.autoPageTurn)
                .accessibilityLabel("Auto page turn")

            if store.autoPageTurn {
                HStack {
                    Text("Interval")
                    Spacer()
                    Slider(
                        value: $store.autoPageTurnInterval,
                        in: 1...60,
                        step: 1
                    )
                    .frame(maxWidth: 160)
                    .accessibilityLabel("Auto page turn interval")
                    Text("\(Int(store.autoPageTurnInterval))s")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 32)
                }
            }
        } footer: {
            Text("Automatically turn pages at the set interval. Pauses on user interaction.")
                .font(.caption)
        }
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

    // MARK: - Chinese Conversion (E04)

    /// Whether the Simp/Trad transform actually applies in the current state.
    /// Bug #120: the transform is wired only into Unified mode's
    /// `activeTransforms`; Native mode (the default) is a no-op for this
    /// setting, AND formats without `.unifiedReflow` (PDF, complex EPUB) never
    /// run through the unified pipeline regardless of mode. Disabling the
    /// picker in those cases prevents a silent UX dead-end.
    ///
    /// Residual gap (separate sub-bug): EPUB books are reported as
    /// `.unifiedReflow`-capable here based on format alone, but a complex EPUB
    /// can fall back to native WKWebView at render time (`ReaderUnifiedDispatch.swift:73`).
    /// In that case the picker shows enabled even though the transform is a
    /// runtime no-op. The render-time `isComplexEPUB` signal isn't available
    /// at panel-open time, so this guard intentionally errs on "show enabled"
    /// for EPUBs to avoid a false-disable for the simple-EPUB-in-unified path
    /// where the conversion does work.
    private var chineseConversionSupported: Bool {
        guard store.readingMode == .unified else { return false }
        // If the caller didn't supply capabilities (e.g. older tests, previews),
        // fall back to "trust user preference" so the picker stays enabled —
        // matches the pre-fix behavior for unsupplied callers.
        guard let caps = formatCapabilities else { return true }
        return caps.contains(.unifiedReflow)
    }

    /// Why the picker is disabled, used to pick the right footer/hint copy.
    /// Returns nil when the picker is enabled.
    private enum ChineseConversionDisableReason {
        case nativeMode       // user is in Native; Unified mode would enable it
        case formatUnsupported // format never supports unified reflow (PDF)
    }
    private var chineseConversionDisableReason: ChineseConversionDisableReason? {
        if let caps = formatCapabilities, !caps.contains(.unifiedReflow) {
            // Format-level disqualifier wins regardless of readingMode —
            // PDF can't convert even if user picks Unified.
            return .formatUnsupported
        }
        if store.readingMode != .unified {
            return .nativeMode
        }
        return nil
    }

    @ViewBuilder
    private var chineseConversionSection: some View {
        Section {
            Picker("Chinese Text", selection: $store.chineseConversion) {
                Text("None").tag(ChineseConversionDirection.none)
                Text("Simp \u{2192} Trad").tag(ChineseConversionDirection.simpToTrad)
                Text("Trad \u{2192} Simp").tag(ChineseConversionDirection.tradToSimp)
            }
            .pickerStyle(.segmented)
            .disabled(chineseConversionDisableReason != nil)
            .accessibilityLabel("Chinese text conversion")
            .accessibilityHint(chineseConversionAccessibilityHint)
        } footer: {
            chineseConversionFooter
        }
    }

    private var chineseConversionAccessibilityHint: String {
        switch chineseConversionDisableReason {
        case nil:
            return "Choose conversion direction between Simplified and Traditional Chinese"
        case .nativeMode:
            return "Disabled — switch Reading Mode to Unified to convert Chinese text"
        case .formatUnsupported:
            return "Disabled — this book's format does not support text conversion"
        }
    }

    @ViewBuilder
    private var chineseConversionFooter: some View {
        switch chineseConversionDisableReason {
        case nil:
            Text("Convert Chinese text between Simplified and Traditional scripts.")
                .font(.caption)
        case .nativeMode:
            Text("Available in Unified reading mode only. Native mode does not yet convert Chinese text.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .formatUnsupported:
            Text("Not supported for this book's format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Tap Zones (A03, feature #25)

    @ViewBuilder
    private var tapZoneSection: some View {
        if let zoneStore = tapZoneStore {
            Section {
                tapZonePicker("Left Zone", action: Binding(
                    get: { zoneStore.config.leftAction },
                    set: { zoneStore.config.leftAction = $0 }
                ))
                tapZonePicker("Center Zone", action: Binding(
                    get: { zoneStore.config.centerAction },
                    set: { zoneStore.config.centerAction = $0 }
                ))
                tapZonePicker("Right Zone", action: Binding(
                    get: { zoneStore.config.rightAction },
                    set: { zoneStore.config.rightAction = $0 }
                ))
            } header: {
                Text("Tap Zones")
            } footer: {
                Text("Choose what happens when you tap each area of the screen.")
                    .font(.caption)
            }
        }
    }

    private func tapZonePicker(_ label: String, action: Binding<TapAction>) -> some View {
        Picker(label, selection: action) {
            Text("Previous Page").tag(TapAction.previousPage)
            Text("Next Page").tag(TapAction.nextPage)
            Text("Toggle Toolbar").tag(TapAction.toggleChrome)
            Text("None").tag(TapAction.none)
        }
        .accessibilityLabel(label)
    }

    // MARK: - Per-Book Settings (A05)

    @ViewBuilder
    private var perBookSection: some View {
        Section {
            Toggle("Custom settings for this book", isOn: $isPerBookEnabled)
                .accessibilityLabel("Custom settings for this book")
                .onChange(of: isPerBookEnabled) { _, newValue in
                    if newValue { savePerBookSnapshot() } else { deletePerBookOverride() }
                }
        } footer: {
            Text(isPerBookEnabled
                ? "Font, spacing, and theme changes apply only to this book."
                : "All books share the same settings.")
                .font(.caption)
        }
    }

    private func loadPerBookState() {
        guard let key = bookFingerprintKey, let baseURL = perBookBaseURL else { return }
        isPerBookEnabled = PerBookSettingsStore.settings(for: key, baseURL: baseURL) != nil
    }

    private func savePerBookSnapshot() {
        guard let key = bookFingerprintKey, let baseURL = perBookBaseURL else { return }
        let override = PerBookSettingsOverride(
            fontSize: store.typography.fontSize,
            fontName: store.typography.fontFamily.rawValue,
            lineSpacing: store.typography.lineSpacing,
            letterSpacing: store.typography.cjkSpacing ? store.typography.fontSize * 0.05 : 0,
            themeName: store.theme.rawValue,
            readingMode: store.readingMode.rawValue
        )
        try? PerBookSettingsStore.save(override, for: key, baseURL: baseURL)
    }

    private func deletePerBookOverride() {
        guard let key = bookFingerprintKey, let baseURL = perBookBaseURL else { return }
        PerBookSettingsStore.delete(for: key, baseURL: baseURL)
        // Bug #147: re-resolve from globals so the live reader reflects
        // the new state immediately. Without this, the live store keeps
        // whatever values were applied while the override was active
        // until the user closes and reopens the reader.
        store.reconcileFromDefaults()
    }

    private func syncPerBookIfEnabled() {
        guard isPerBookEnabled else { return }
        savePerBookSnapshot()
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
