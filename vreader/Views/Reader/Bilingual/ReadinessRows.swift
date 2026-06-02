// Purpose: Feature #82 — the consent disclosure card + the "ready" payoff
// banner for the in-reader AI readiness sheet. The AI master toggle reuses the
// shipped `SettingsToggleRow` directly in `ReaderAIReadinessView`; these two
// surfaces are the bespoke ones.
//
// `ConsentDisclosureCard` — a shield tile + an EXPLICIT consent toggle + a
// two-column "Sent to provider / Stays on device" ledger (the #1068 Variant C
// disclosure, tuned to translation). Consent is granted ONLY by this toggle —
// turning the assistant on does not imply it. The card is rendered by the
// container only when AI is on.
//
// `ReadyBanner` — shown when all four gates clear; prompts the user to go back
// and turn on bilingual mode (the payoff).
//
// Layout pinned to `dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-readiness.jsx`
// (`ConsentDisclosureCard`, `ReadyBanner`) + `vreader-ai-toggles.jsx` (the ledger).
//
// @coordinates-with: ReaderAIReadinessView.swift, PillSwitch.swift,
//   ReaderThemeV2.swift, AIConsentManager.swift

import SwiftUI

/// Shield tile + explicit consent toggle + the two-column disclosure ledger.
/// Consent is bound to `AISettingsViewModel.hasConsent` via `$consentOn`; this
/// card's toggle is the ONLY consent writer in the readiness flow.
struct ConsentDisclosureCard: View {

    let theme: ReaderThemeV2
    @Binding var consentOn: Bool

    /// `RDY_SHIELD` from the design — consent/privacy tile.
    private var shieldColor: Color { Color(red: 0.290, green: 0.416, blue: 0.541) }
    private var greenColor: Color { Color(red: 0.227, green: 0.416, blue: 0.353) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(shieldColor).frame(width: 30, height: 30)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.white)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Allow data sharing")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color(theme.inkColor))
                    Text("Required to translate — paragraphs are sent to your provider as you read.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(Color(theme.subColor))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                PillSwitch(isOn: $consentOn, theme: theme)
                    .accessibilityIdentifier("readinessConsentToggle")
            }

            HStack(alignment: .top, spacing: 10) {
                ledgerColumn(
                    icon: "paperplane.fill", tint: Color(theme.accentColor), title: "Sent to provider",
                    items: ["The paragraph being read", "Your target language"])
                ledgerColumn(
                    icon: "lock.shield.fill", tint: greenColor, title: "Stays on device",
                    items: ["Your API key (keychain)", "Reading history & notes"])
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color(theme.ruleColor).opacity(0.10)))
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(Color(theme.sheetCardSurfaceColor))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color(theme.ruleColor), lineWidth: 0.5))
        )
        .accessibilityIdentifier("consentDisclosureCard")
    }

    private func ledgerColumn(icon: String, tint: Color, title: String, items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
                Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(theme.inkColor))
            }
            ForEach(items, id: \.self) { item in
                Text("• \(item)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(Color(theme.subColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The all-gates-cleared payoff banner.
struct ReadyBanner: View {

    let theme: ReaderThemeV2
    let providerName: String

    private var greenColor: Color { Color(red: 0.227, green: 0.416, blue: 0.353) }

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(greenColor).frame(width: 30, height: 30)
                Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(Color.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to translate")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(theme.inkColor))
                Text("\(providerName) is connected. Go back to turn on bilingual mode.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Color(theme.subColor))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14).fill(greenColor.opacity(0.10))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(greenColor.opacity(0.4), lineWidth: 0.5))
        )
        .accessibilityIdentifier("readinessReadyBanner")
    }
}
