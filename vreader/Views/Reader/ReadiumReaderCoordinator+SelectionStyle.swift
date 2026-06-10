// Purpose: Bug #340 — themed `::selection` paint for the Readium (default)
// EPUB engine. The themed rule has always existed for the LEGACY engine
// (`ReaderThemeV2+EPUBCSS.swift`), but the Readium path never injected it,
// so selection washed stock iOS blue. Mirrors the `+Transparency` state
// model exactly: the spread's per-origin `localStorage` is the single source
// of truth — Swift writes it AUTHORITATIVELY (on every `locationDidChange`
// via `syncSelectionStyle`, and on a live theme change via
// `setSelectionStyle`), and a persistent READ-only documentEnd applier
// installs the id'd `<style>` for spreads that load later.
//
// Injection safety: the two stored values are CSS color strings derived
// from compile-time theme constants, but they still cross into JS — they
// are sanitized to a strict color-literal character set before
// interpolation (bridge-safety rule; no quotes/backslashes can survive).
//
// @coordinates-with: ReadiumReaderCoordinator.swift,
//   ReadiumReaderCoordinator+Transparency.swift,
//   ReadiumNavigatorRepresentable.swift, ReaderThemeV2+EPUBCSS.swift

#if canImport(UIKit)
import UIKit
import WebKit
import ReadiumNavigator

extension ReadiumReaderCoordinator {

    /// Element id for the injected selection `<style>`. Fixed.
    static var selectionStyleID: String { "vreader-selection-style" }
    /// localStorage key the applier reads + Swift writes authoritatively.
    static var selectionStateKey: String { "vreaderSelectionStyle" }

    /// Keeps only characters that can appear in a CSS color literal
    /// (`#RRGGBB`, `rgba(…)`) — anything else (quotes, backslashes, braces)
    /// is dropped so the value can never escape the JS string or the CSS
    /// declaration it is interpolated into.
    static func sanitizedCSSColor(_ value: String) -> String {
        String(value.unicodeScalars.filter {
            CharacterSet.alphanumerics.contains($0)
                || $0 == "#" || $0 == "(" || $0 == ")" || $0 == ","
                || $0 == "." || $0 == "%" || $0 == " "
        })
    }

    /// Self-gating applier: READS `localStorage` (value `"accent|text"`;
    /// absent = no themed selection) and installs/refreshes or removes the
    /// id'd `<style>`. Re-runnable on every document load; never WRITES
    /// state. The stored value was sanitized by Swift before writing.
    static var selectionStyleApplyJS: String {
        """
        (function(){var id='\(selectionStyleID)';var v=null;try{v=localStorage.getItem('\(selectionStateKey)');}catch(e){}\
        var el=document.getElementById(id);\
        if(v){var p=v.split('|');if(p.length===2){if(!el){el=document.createElement('style');el.id=id;}\
        el.textContent='::selection{background-color:'+p[0]+' !important;color:'+p[1]+' !important;}';\
        document.documentElement.appendChild(el);return;}}\
        if(el){el.remove();}})();
        """
    }

    /// JS that writes the sanitized state then runs the applier.
    private static func writeAndApplySelectionJS(accent: String, text: String) -> String {
        let value = "\(sanitizedCSSColor(accent))|\(sanitizedCSSColor(text))"
        return "try{localStorage.setItem('\(selectionStateKey)','\(value)');}catch(e){}"
            + selectionStyleApplyJS
    }

    /// Asserts the current theme's selection colors into the visible spread.
    /// Called on every `locationDidChange` (a spread just rendered) and on a
    /// live theme change, mirroring `syncTransparentState`.
    func syncSelectionStyle() {
        guard let navigator = boundNavigator,
              !selectionAccentCSS.isEmpty, !selectionTextCSS.isEmpty else { return }
        let js = Self.writeAndApplySelectionJS(
            accent: selectionAccentCSS, text: selectionTextCSS)
        // Best-effort: a spread that loads later runs the persistent applier
        // against the state this (or an earlier) call wrote.
        Task { @MainActor in _ = await navigator.evaluateJavaScript(js) }
    }
}

#endif
