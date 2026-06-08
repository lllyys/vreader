// Purpose: Feature #54 Phase D-1 — applies content-replacement rules to the
// Readium EPUB navigator's rendered spines, CFI-safely.
//
// The native MD path applies `ReplacementTransform` to the source text before
// parse (`MDFileLoader`). EPUB renders via Readium, so the equivalent injects
// `EPUBReplacementJS` into each spine's WebView, rewriting text-node values
// only — the original resource HTML (which Readium's locators/CFI are computed
// against) is untouched, so saved positions still resolve.
//
// Applied on every `locationDidChange` (a spread just rendered) via
// `applyReplacement`, and on a live rules change via `setReplacementRules`.
// The injected JS is idempotent per document (a `window` guard flag), so the
// re-assert on the visible spine is a cheap no-op once applied. Mirrors the
// `+Transparency` extension's lifecycle.
//
// @coordinates-with: ReadiumReaderCoordinator.swift (owns `replacementRules` +
//   the `locationDidChange` call site), EPUBReplacementJS.swift (the JS builder),
//   ReadiumNavigatorRepresentable.swift (sets the rules from the host).

#if canImport(UIKit)

import Foundation

extension ReadiumReaderCoordinator {

    /// Update the rules + re-apply to the currently visible spine. Called by the
    /// representable's `updateUIViewController` when the host's rules change.
    func setReplacementRules(_ rules: [ReplacementRuleDescriptor]) {
        replacementRules = rules
        applyReplacement()
    }

    /// Inject the replacement JS into the visible spine's WebView. Best-effort:
    /// an error (no document yet) is benign — the next `locationDidChange`
    /// re-asserts. A no-op when no enabled rule applies (`injectionJS` returns
    /// "") or when the navigator isn't bound.
    func applyReplacement() {
        guard let navigator = boundNavigator else { return }
        let js = EPUBReplacementJS.injectionJS(rules: replacementRules)
        guard !js.isEmpty else { return }
        Task { @MainActor in _ = await navigator.evaluateJavaScript(js) }
    }
}

#endif
