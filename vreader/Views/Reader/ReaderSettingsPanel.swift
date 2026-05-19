// Purpose: Slide-up settings panel for reader theme and typography controls.
// Provides theme picker, font size slider, line spacing slider,
// font family picker, CJK spacing toggle, Chinese-conversion picker, and
// live-preview text.
// When paged layout is selected, shows page turn animation picker and auto page turn toggle.
//
// Re-skinned for feature #60 visual-identity v2 (WI-10): wrapped in the
// shared `ReaderSheetChrome` ("Display" title bar + theme-tinted
// surface) instead of a `NavigationStack`. The panel has no push
// destinations — every control is inline — so the design's `Sheet`
// title bar cleanly replaces the nav bar. Every existing section,
// control, binding, gate, `.onChange`, and the background-picker alert
// are preserved unchanged.
//
// Key decisions:
// - Presented as a sheet from the reader bottom chrome's Display button.
// - All changes apply immediately (no "save" button needed).
// - Preview text updates live as settings change.
// - Theme picker (feature #60 WI-11) shows all 5 `ReaderThemeV2`
//   themes (Paper / Sepia / Dark / OLED / Photo) as rounded-square
//   swatches per `vreader-panels.jsx`'s `ReaderSettingsSheet`.
// - Compact layout suitable for half-sheet presentation.
//
// @coordinates-with: ReaderSettingsStore.swift, ReaderContainerView.swift,
//   ReaderSheetChrome.swift, SheetSectionContract.swift, ReaderThemeV2.swift

import PhotosUI
import SwiftUI

/// Settings panel for reader appearance.
struct ReaderSettingsPanel: View {
    /// Sheet dismissal — drives the `ReaderSheetChrome` close button
    /// (feature #60 WI-10). The system swipe-down dismiss still works
    /// too; this is the design `Sheet`'s explicit close affordance.
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: ReaderSettingsStore
    /// Fingerprint key for the currently open book (nil if no per-book support).
    var bookFingerprintKey: String?
    /// Base URL for per-book settings storage.
    var perBookBaseURL: URL?
    /// Capabilities of the current book's format. Used to gate settings whose
    /// effect depends on the active rendering path. When nil, the panel falls
    /// back to "available everywhere" — preserves backward compat for callers
    /// (and tests/previews) that don't supply the value.
    var formatCapabilities: FormatCapabilities? = nil
    /// The book's format identity. The Chinese-conversion gate is purely
    /// format-driven (feature #54 — TXT/MD have a native conversion path;
    /// EPUB/AZW3 do not yet; PDF never). When nil, that gate falls back to
    /// the conservative "disabled" default.
    var bookFormat: BookFormat? = nil
    /// Whether per-book settings are currently enabled for this book.
    @State private var isPerBookEnabled = false
    /// Photo picker state for theme background (feature #32).
    @State private var backgroundPickerItem: PhotosPickerItem?
    /// Bug #134: surface theme-background load/save/remove failures.
    @State private var backgroundErrorMessage: String?

    /// The design theme for the sheet chrome — the reader's current
    /// `ReaderThemeV2` so the Display sheet's surface tint follows the
    /// book's theme. (Feature #60 WI-11: `store.theme` is now
    /// `ReaderThemeV2`, so no `asV2` projection is needed.)
    private var sheetTheme: ReaderThemeV2 { store.theme }

    /// The re-skinned panel's `ReaderSheetChrome` title — exposed for
    /// the WI-10 composition test.
    var sheetChromeTitleForTesting: String? {
        ReaderSheetKind.display.designTitle
    }

    var body: some View {
        ReaderSheetChrome(
            theme: sheetTheme,
            title: ReaderSheetKind.display.designTitle,
            onClose: { dismiss() }
        ) {
            List {
                themeSection
                themeBackgroundSection
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
                if bookFingerprintKey != nil { perBookSection }
                previewSection
            }
            // Hide the grouped-List backdrop so the design's sheet
            // surface tint (`ReaderSheetChrome`) shows through.
            .scrollContentBackground(.hidden)
        }
        .onAppear { loadPerBookState() }
        .onChange(of: store.typography.fontSize) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.lineSpacing) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.fontFamily) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.typography.cjkSpacing) { _, _ in syncPerBookIfEnabled() }
        .onChange(of: store.theme) { _, _ in syncPerBookIfEnabled() }
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
                    // Feature #60 WI-12 (#795): signal cached readers
                    // (EPUB `data:` URL, ThemeBackgroundView) to re-read
                    // the file — `theme` / `useCustomBackground` are
                    // unchanged on a re-pick, so they need this nudge.
                    store.customBackgroundRevision += 1
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
        // Bug #209 / GH #804: `.accessibilityElement(children: .contain)`
        // makes the panel one container element so the identifier names
        // that single element (resolvable as `app.otherElements`) instead
        // of propagating onto — and duplicating across — the panel's
        // title, Close button, and settings list.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("readerSettingsPanel")
    }

    // MARK: - Theme

    /// The themes the picker offers — Feature #60 WI-11: all 5
    /// `ReaderThemeV2` cases (Paper / Sepia / Dark / OLED / Photo), in
    /// the design bundle's `THEMES` declaration order. Exposed
    /// `static` for the WI-11 composition-contract test.
    static var themePickerThemes: [ReaderThemeV2] { ReaderThemeV2.allCases }

    /// Human label for a theme swatch caption — matches the design
    /// bundle's `name` field (`vreader-themes.jsx`).
    static func themeDisplayName(_ theme: ReaderThemeV2) -> String {
        switch theme {
        case .paper: return "Paper"
        case .sepia: return "Sepia"
        case .dark:  return "Dark"
        case .oled:  return "OLED"
        case .photo: return "Photo"
        }
    }

    @ViewBuilder
    private var themeSection: some View {
        Section("Theme") {
            HStack(spacing: 10) {
                ForEach(Self.themePickerThemes, id: \.self) { theme in
                    themeSwatch(theme)
                }
            }
            .padding(.vertical, 8)
        }
    }

    /// The Photo swatch's preview fill — the design renders the Photo
    /// theme's chip as a 135° diagonal gradient (`vreader-panels.jsx`:
    /// `linear-gradient(135deg, #3a2818, #1a1410)`) rather than a flat
    /// color, since the real Photo theme shows a user image.
    private static let photoSwatchGradient = LinearGradient(
        colors: [
            Color(red: 0x3a / 255, green: 0x28 / 255, blue: 0x18 / 255),
            Color(red: 0x1a / 255, green: 0x14 / 255, blue: 0x10 / 255),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// One theme swatch — the design's rounded-square chip
    /// (`vreader-panels.jsx` `ReaderSettingsSheet` theme selector):
    /// a 12pt-radius tile filled with the theme background (a diagonal
    /// gradient for the Photo theme), an `Aa` glyph (or a photo glyph
    /// for the Photo theme), the theme name below, and — on the
    /// selected tile — the design's two-ring treatment: a 2.5pt accent
    /// ring hugging the tile plus a 1.5pt outer band in the sheet's
    /// surface color (the design's `0 0 0 2.5px accent, 0 0 0 4px
    /// surface` box-shadow). Per the design the selected ring uses the
    /// *sheet's* accent (`t.accent`) and the caption colour uses the
    /// sheet's `sub` token — consistent across all swatches regardless
    /// of which theme each depicts.
    @ViewBuilder
    private func themeSwatch(_ theme: ReaderThemeV2) -> some View {
        let isSelected = store.theme == theme
        Button {
            store.theme = theme
        } label: {
            VStack(spacing: 6) {
                themeSwatchTile(theme)
                    .aspectRatio(1, contentMode: .fit)
                    // Outer band — the design's second box-shadow ring
                    // in the sheet surface color (`0 0 0 4px surface`).
                    // Only drawn when selected; the 1.5pt padding makes
                    // room for it so the tile size stays constant.
                    .padding(1.5)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: 13.5)
                                .strokeBorder(
                                    Color(sheetTheme.sheetSurfaceColor),
                                    lineWidth: 1.5
                                )
                        }
                    }

                Text(Self.themeDisplayName(theme))
                    .font(.caption2)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(Color(sheetTheme.subColor))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(Self.themeDisplayName(theme)) theme")
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The inner tile of a theme swatch — the 12pt-radius filled chip
    /// with the `Aa`/photo glyph and the selected/unselected hairline
    /// ring (the design's first box-shadow: `0 0 0 2.5px accent` when
    /// selected, `inset 0 0 0 0.5px rule` otherwise).
    @ViewBuilder
    private func themeSwatchTile(_ theme: ReaderThemeV2) -> some View {
        let isSelected = store.theme == theme
        RoundedRectangle(cornerRadius: 12)
            .fill(swatchTileShading(theme))
            .overlay {
                if theme.usesBackgroundImage {
                    Image(systemName: "photo")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color(theme.accentColor))
                } else {
                    Text("Aa")
                        .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 20)))
                        .fontWeight(.semibold)
                        .foregroundStyle(Color(theme.inkColor))
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected
                            ? Color(sheetTheme.accentColor)
                            : Color(sheetTheme.ruleColor),
                        lineWidth: isSelected ? 2.5 : 0.5
                    )
            }
    }

    /// Fill for a swatch tile — the theme background for the four flat
    /// themes; the design's 135° diagonal gradient for the Photo theme.
    private func swatchTileShading(_ theme: ReaderThemeV2) -> AnyShapeStyle {
        if theme.usesBackgroundImage {
            return AnyShapeStyle(Self.photoSwatchGradient)
        }
        return AnyShapeStyle(Color(theme.backgroundColor))
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
                .accessibilityIdentifier("autoPageTurnToggle")

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
                    .accessibilityIdentifier("autoPageTurnIntervalSlider")
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

    /// Feature #66 WI-1: the design's custom accent-track `SettingsSliderRow`
    /// (`vreader-panels.jsx` `SliderRow`) replaces the native `Slider`.
    @ViewBuilder
    private var fontSizeSection: some View {
        Section("Font Size") {
            SettingsSliderRow(
                value: Binding(
                    get: { store.typography.fontSize },
                    set: { store.typography.fontSize = $0 }
                ),
                range: TypographySettings.fontSizeRange,
                step: 1,
                leading: .text("Aa", size: 12),
                trailing: .text("Aa", size: 22),
                accessibilityLabel: "Font size",
                theme: sheetTheme
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Line Spacing

    /// Feature #66 WI-1: `SettingsSliderRow` replaces the native `Slider`.
    /// The design's `lines-tight` / `lines-loose` SVG pictograms map to
    /// the closest stable SF Symbols (dense block vs three spaced lines).
    @ViewBuilder
    private var lineSpacingSection: some View {
        Section("Line Spacing") {
            SettingsSliderRow(
                value: Binding(
                    get: { store.typography.lineSpacing },
                    set: { store.typography.lineSpacing = $0 }
                ),
                range: TypographySettings.lineSpacingRange,
                step: 0.1,
                leading: .symbol("text.justify"),
                trailing: .symbol("line.3.horizontal"),
                accessibilityLabel: "Line spacing",
                theme: sheetTheme
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: - Font Family

    /// Feature #66 WI-2: the design's `TypefacePillToggle`
    /// (`vreader-panels.jsx` "Font" pill) replaces the native segmented
    /// `Picker`. Behavior-preserving re-skin — it presents the same three
    /// `ReaderFontFamily` options this picker offered (System / Serif /
    /// Monospace), not the design's 2-option reduction (plan §2).
    @ViewBuilder
    private var fontFamilySection: some View {
        Section("Font") {
            TypefacePillToggle(
                selection: $store.typography.fontFamily,
                accessibilityLabel: "Font family",
                theme: sheetTheme
            )
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
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

    /// Why the picker is disabled, used to pick the right footer/hint copy.
    /// Returns nil when the picker is enabled.
    /// Internal (not private) so `ReaderSettingsPanelChineseConversionGateTests` can test directly.
    enum ChineseConversionDisableReason: Equatable {
        case nativeMode        // EPUB/AZW3 — no native conversion path yet (#54 Phase D)
        case formatUnsupported // format never supports conversion (PDF)
    }
    private var chineseConversionDisableReason: ChineseConversionDisableReason? {
        Self.chineseConversionDisableReason(for: bookFormat)
    }

    /// Testable static helper — the Chinese-conversion picker gate.
    ///
    /// Purely format-driven (feature #54 retired the Native/Unified toggle, so
    /// the gate no longer depends on a reading mode):
    /// - **TXT / MD** → `nil` (enabled). Both apply `SimpTradTransform` natively
    ///   before `TXTAttributedStringBuilder` / `MDFileLoader` parse.
    /// - **EPUB / AZW3** → `.nativeMode`. These are JS-rendered and have no
    ///   native conversion path yet — feature #54 Phase D wires one.
    /// - **PDF** → `.formatUnsupported`. No text-transform path at all.
    /// - **nil / unknown format** → `.nativeMode` (conservative — no proven
    ///   native conversion path).
    ///
    /// - Important: `SimpTradTransform` (Hans-Hant ICU) produces 1:1 UTF-16
    ///   mappings for BMP CJK characters, so reading-position and highlight
    ///   offsets saved in source-text coordinates remain valid in the
    ///   transformed display text.
    static func chineseConversionDisableReason(
        for format: BookFormat?
    ) -> ChineseConversionDisableReason? {
        switch format {
        case .txt, .md:
            return nil
        case .pdf:
            return .formatUnsupported
        case .epub, .azw3, nil:
            return .nativeMode
        }
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
            .accessibilityIdentifier("chineseTextPicker")
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
            return "Disabled — Chinese conversion is not yet available for this book's format"
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
            Text("Chinese text conversion is not yet available for this book's format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .formatUnsupported:
            Text("Not supported for this book's format.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
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
        // `readingMode` is intentionally omitted (feature #54 removed the
        // picker); the `PerBookSettingsOverride.readingMode` field is
        // removed entirely in WI-5.
        let override = PerBookSettingsOverride(
            fontSize: store.typography.fontSize,
            fontName: store.typography.fontFamily.rawValue,
            lineSpacing: store.typography.lineSpacing,
            letterSpacing: store.typography.cjkSpacing ? store.typography.fontSize * 0.05 : 0,
            themeName: store.theme.rawValue
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

    /// SwiftUI Font preview for the settings panel's typography preview.
    /// Per Feature #60 WI-1, resolves via `ReaderTypography.body(...)` for
    /// non-system cases so the dormant `.sourceSerif4` and `.inter`
    /// families show the correct fallback face (Georgia / system sans)
    /// until WI-1b bundles the binaries.
    private var previewFont: Font {
        let size = store.typography.fontSize
        switch store.typography.fontFamily {
        case .system:
            return .system(size: size)
        case .monospace:
            return .system(size: size, design: .monospaced)
        case .serif, .sourceSerif4, .inter:
            return Font(ReaderTypography.body(
                for: store.typography.fontFamily, size: size
            ))
        }
    }
}
