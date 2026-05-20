// Purpose: Feature #56 WI-15 — picker sub-views for the
// `ReTranslatePickerSheet`: provider list, model chips, style segmented
// control, "keep glossary" toggle row. Pure SwiftUI value views — theme
// driven, no async dependencies.
//
// @coordinates-with: ReTranslatePickerSheet.swift,
//   ChapterReTranslateViewModel.swift, ReaderThemeV2.swift,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-retranslate.jsx,
//   dev-docs/plans/20260519-feature-56-bilingual-reading.md (WI-15)

import SwiftUI

// MARK: - Section label

/// A small uppercased section header — matches the design's `SectionLabel`
/// component from `vreader-retranslate.jsx`. Kept private to this file
/// because the picker is its only consumer.
struct ReTranslateSectionLabel: View {
    let theme: ReaderThemeV2
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Color(theme.subColor))
            .padding(.bottom, 6)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Provider list

/// The "Provider" section — one button per configured `ProviderProfile`.
/// Tapping a row updates the VM's selection.
struct ReTranslateProviderList: View {
    let theme: ReaderThemeV2
    let profiles: [ProviderProfile]
    let selectedProfileID: UUID
    let onSelect: (ProviderProfile) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReTranslateSectionLabel(theme: theme, text: "Provider")
            if profiles.isEmpty {
                emptyState
            } else {
                providerRows
            }
        }
    }

    private var emptyState: some View {
        Text("Configure an AI provider in Settings to enable re-translation.")
            .font(.system(size: 12))
            .foregroundStyle(Color(theme.subColor))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(theme.paperColor))
            )
            .accessibilityIdentifier("reTranslateProvidersEmpty")
    }

    private var providerRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(profiles.enumerated()), id: \.element.id) { index, profile in
                Button {
                    onSelect(profile)
                } label: {
                    providerRow(profile: profile, isFirst: index == 0)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reTranslateProviderRow-\(profile.id.uuidString)")
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(theme.paperColor))
        )
    }

    private func providerRow(profile: ProviderProfile, isFirst: Bool) -> some View {
        let active = profile.id == selectedProfileID
        return HStack(spacing: 12) {
            ProviderGlyph(theme: theme, profile: profile, active: active)
            VStack(alignment: .leading, spacing: 1) {
                Text(profile.name)
                    .font(.system(size: 14, weight: active ? .semibold : .medium))
                    .foregroundStyle(Color(theme.inkColor))
                Text(profile.kind.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(Color(theme.subColor))
            }
            Spacer()
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(theme.accentColor))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .overlay(alignment: .top) {
            if !isFirst {
                Rectangle()
                    .fill(Color(theme.ruleColor))
                    .frame(height: 0.5)
            }
        }
    }
}

// MARK: - Provider glyph

/// The square letter glyph next to a provider name. Pulls a fixed-palette
/// color keyed by the provider's `kind` so the glyph is consistent across
/// the picker without needing a registered icon per provider.
struct ProviderGlyph: View {
    let theme: ReaderThemeV2
    let profile: ProviderProfile
    let active: Bool

    var body: some View {
        let swatch = swatchColor
        let letter = String(profile.name.prefix(1)).uppercased()
        ZStack {
            RoundedRectangle(cornerRadius: 7)
                .fill(active ? swatch : swatch.opacity(0.15))
                .frame(width: 28, height: 28)
            Text(letter.isEmpty ? "?" : letter)
                .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 14)))
                .fontWeight(.bold)
                .foregroundStyle(active ? Color.white : swatch)
        }
    }

    private var swatchColor: Color {
        switch profile.kind {
        case .openAICompatible: return Color(red: 0.06, green: 0.64, blue: 0.50)
        case .anthropicNative:  return Color(red: 0.85, green: 0.47, blue: 0.34)
        }
    }
}

// MARK: - Model chips

/// Pill chips for the "Model" picker. Only rendered when there's more than
/// one model to choose from for the active provider.
struct ReTranslateModelChips: View {
    let theme: ReaderThemeV2
    let models: [String]
    let selectedModel: String
    let onSelect: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReTranslateSectionLabel(theme: theme, text: "Model")
            ReTranslateFlowLayout(spacing: 6) {
                ForEach(models, id: \.self) { model in
                    chip(model)
                }
            }
        }
    }

    private func chip(_ model: String) -> some View {
        let active = model == selectedModel
        return Button {
            onSelect(model)
        } label: {
            Text(model)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(active
                    ? (theme.isDark ? Color(red: 0.10, green: 0.10, blue: 0.10) : Color(red: 0.99, green: 0.97, blue: 0.94))
                    : Color(theme.inkColor))
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(active
                            ? Color(theme.inkColor)
                            : Color(theme.paperColor))
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reTranslateModelChip-\(model)")
    }
}

// `ReTranslateFlowLayout` (used above by `ReTranslateModelChips`) lives in
// `ReTranslateFlowLayout.swift` so this file stays under the ~300-LoC
// budget (rule 50 §9).

// MARK: - Style segmented

/// Three-way segmented control for translation style. Matches the design's
/// `STYLES` triad: Literal / Natural / Literary.
struct ReTranslateStyleSegmented: View {
    let theme: ReaderThemeV2
    let selectedStyle: TranslationStyle
    let onSelect: (TranslationStyle) -> Void

    private static let styles: [(style: TranslationStyle, title: String, sub: String)] = [
        (.literal,  "Literal",  "Closer to source"),
        (.natural,  "Natural",  "Reads like target"),
        (.literary, "Literary", "Preserves register")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ReTranslateSectionLabel(theme: theme, text: "Style")
            HStack(spacing: 0) {
                ForEach(Self.styles, id: \.style) { entry in
                    button(for: entry)
                }
            }
            .padding(3)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(theme.paperColor))
            )
        }
    }

    private func button(for entry: (style: TranslationStyle, title: String, sub: String)) -> some View {
        let active = entry.style == selectedStyle
        return Button {
            onSelect(entry.style)
        } label: {
            VStack(spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Text(entry.sub)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(theme.subColor))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(active
                        ? Color(theme.backgroundColor)
                        : Color.clear)
                    .shadow(color: Color.black.opacity(active ? 0.08 : 0), radius: 2, y: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reTranslateStyleButton-\(entry.style.rawValue)")
    }
}

// MARK: - Glossary toggle row

/// "Keep term overrides" row — the design's `keep-glossary` toggle.
/// vreader has no glossary feature yet; the toggle is wired UI state with
/// no current effect, so the user choice persists across re-translation
/// invocations when glossary support lands.
struct ReTranslateGlossaryToggleRow: View {
    let theme: ReaderThemeV2
    let keepGlossary: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: "note.text")
                    .font(.system(size: 15))
                    .foregroundStyle(Color(theme.subColor))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Keep term overrides")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(Color(theme.inkColor))
                    Text("Reuse glossary entries from the previous translation")
                        .font(.system(size: 11))
                        .foregroundStyle(Color(theme.subColor))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                glossaryPill
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(theme.paperColor))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reTranslateGlossaryToggle")
    }

    private var glossaryPill: some View {
        Capsule()
            .fill(keepGlossary
                ? Color(red: 0.23, green: 0.42, blue: 0.35)
                : Color(theme.ruleColor))
            .frame(width: 34, height: 20)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .offset(x: keepGlossary ? 7 : -7),
                alignment: .center
            )
    }
}
