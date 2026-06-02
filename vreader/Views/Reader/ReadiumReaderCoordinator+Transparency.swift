// Purpose: Feature #42 WI-7 photo/custom-background compositing — the transparent
// navigator machinery for the Readium EPUB coordinator. Extracted from
// `ReadiumReaderCoordinator.swift` for the 300-line budget. ReadiumCSS paints
// `:root { background-color: var(--RS__backgroundColor) !important }` (white in
// light / black in night) which occludes the composited `ThemeBackgroundView`
// even when `body` + the spine WebView are already clear. This file injects a
// SELF-GATING `<style>` that forces `:root`/html/body transparent.
//
// State model (Gate-4 audit rounds 2+3): the WebView's per-origin `localStorage`
// is the single source of truth. Swift writes it AUTHORITATIVELY — on every
// `locationDidChange` (a spread just rendered) via `syncTransparentState`, and on
// a live toggle via `setTransparentBackground`. The persistent documentEnd
// applier only READS it (defaulting to opaque when unset). No persistent script
// WRITES state, so a stale `WKUserScript` cannot resurrect transparency after a
// disable (round-2), and a fresh navigator open is not stuck on a prior session's
// stale storage because Swift re-asserts the live flag as each spread loads
// (round-3).
//
// @coordinates-with ReadiumReaderCoordinator.swift, ReadiumNavigatorRepresentable.swift

#if canImport(UIKit)
import UIKit
import WebKit
import ReadiumNavigator

extension ReadiumReaderCoordinator {

    /// Element id for the injected transparent-background `<style>`. Fixed.
    static var transparentStyleID: String { "vreader-transparent-bg" }
    /// localStorage key the applier reads + Swift writes authoritatively. Fixed.
    static var transparentStateKey: String { "vreaderTransparentBG" }
    /// CSS the applier installs when transparency is wanted. Fixed.
    ///
    /// `html:root` (specificity 0,1,1) beats ReadiumCSS's `:root` (0,1,0) rule
    /// REGARDLESS of source order — Readium re-appends its `:root{background-color:
    /// var(--RS__backgroundColor)!important}` after our style on a live theme
    /// switch (no spread reload), so equal-specificity + source order would let it
    /// win. Higher specificity makes ours authoritative without depending on DOM
    /// position. `body`/`html` carry the same override for completeness.
    static var transparentCSS: String {
        "html:root,html:root body,html,body"
            + "{background-color:transparent !important;background-image:none !important;}"
    }

    /// Self-gating applier: READS the desired state from `localStorage` (default
    /// opaque when unset) and installs (idempotent) or removes the id'd `<style>`.
    /// On install it re-appends the style LAST so it also wins on source order;
    /// re-runnable safely on every document load and never WRITES state. No
    /// app-controlled interpolation — only fixed compile-time constants.
    static var transparentStyleApplyJS: String {
        """
        (function(){var id='\(transparentStyleID)';var want='0';try{var v=localStorage.getItem('\(transparentStateKey)');if(v!==null)want=v;}catch(e){}\
        var el=document.getElementById(id);\
        if(want==='1'){if(!el){el=document.createElement('style');el.id=id;}\
        el.textContent='\(transparentCSS)';document.documentElement.appendChild(el);}else if(el){el.remove();}})();
        """
    }

    /// JS that writes the given state to `localStorage` then runs the applier.
    private static func writeAndApplyJS(_ value: String) -> String {
        "try{localStorage.setItem('\(transparentStateKey)','\(value)');}catch(e){}"
            + transparentStyleApplyJS
    }

    /// Readium calls this per spine WebView content controller as it loads. Only
    /// the READ-ONLY self-gating applier is installed persistently — it honors
    /// whatever `localStorage` currently holds. State WRITES come exclusively from
    /// Swift (`syncTransparentState` / `setTransparentBackground`), so a persistent
    /// script can never resurrect a stale state.
    func navigator(
        _ navigator: EPUBNavigatorViewController,
        setupUserScripts userContentController: WKUserContentController
    ) {
        userContentController.addUserScript(WKUserScript(
            source: Self.transparentStyleApplyJS,
            injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))
        // Feature #83: cross-chapter continuous scroll — install the boundary-
        // intent observer + weak message-handler proxy so scroll mode auto-
        // advances across spine boundaries (resolves Bug #309). Self-gating to
        // scroll layout (the proxy + model re-check `currentLayout`).
        installContinuousScroll(on: userContentController)
    }

    /// Authoritatively asserts the current `transparentBackground` flag into the
    /// visible spread's `localStorage` + style. Called on every `locationDidChange`
    /// (a spread just rendered) so a fresh navigator open reflects the live flag
    /// even if a prior same-origin session left stale storage. Idempotent.
    func syncTransparentState() {
        applyState(transparentBackground)
    }

    /// Live toggle: updates the flag + asserts it immediately to the visible
    /// spread. A spread that loads later runs the persistent applier, which by
    /// then reads the value this method wrote.
    func setTransparentBackground(_ transparent: Bool) {
        guard transparentBackground != transparent else { return }
        transparentBackground = transparent
        applyState(transparent)
    }

    private func applyState(_ transparent: Bool) {
        guard let navigator = boundNavigator else { return }
        let js = Self.writeAndApplyJS(transparent ? "1" : "0")
        // Best-effort: an error here (no document yet) is benign + not user-visible;
        // the persistent applier covers any spread that loads later, and the next
        // `locationDidChange` re-asserts the state.
        Task { @MainActor in _ = await navigator.evaluateJavaScript(js) }
    }
}

#endif
