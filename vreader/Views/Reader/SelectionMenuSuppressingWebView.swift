// Purpose: Bug #339 (legacy-engine sibling) — a WKWebView subclass that
// suppresses the system text-selection edit menu (Copy / Look Up / Translate /
// Share …) so the designed `SelectionPopoverView` card is the SOLE selection
// surface. Readium gets the same result via `editingActions: []`
// (`ReadiumNavigatorRepresentable`); TXT/MD suppress via
// `editMenuForTextIn → UIMenu(children: [])` on their UITextViews. The two
// WKWebView readers (legacy EPUB stitch + Foliate AZW3/MOBI) had no
// suppression at all, so the stock callout appeared ALONGSIDE the card.
//
// Mechanism: since iOS 16 the selection callout is built through the
// responder-chain `buildMenu(with:)` (UIEditMenuInteraction). Removing the
// standard text menus here kills the callout without touching selection
// itself — handles, drag-to-expand, and the bridges' selection events all
// keep working.
//
// @coordinates-with: EPUBWebViewBridge.swift, FoliateSpikeView.swift,
//   SelectionPopoverPresenter.swift, ReadiumNavigatorRepresentable.swift

#if canImport(UIKit)
import WebKit
import UIKit

/// WKWebView whose text-selection edit menu is fully suppressed — the
/// designed selection card (posted by the owning bridge) is the only
/// selection-action surface, matching every other reader format.
final class SelectionMenuSuppressingWebView: WKWebView {
    override func buildMenu(with builder: UIMenuBuilder) {
        for identifier: UIMenu.Identifier in [
            .standardEdit,      // cut / copy / paste
            .lookup,            // Look Up / Translate / Search Web
            .share,
            .replace,
            .find,
            .textStyle,
            .spelling,
            .substitutions,
            .transformations,
            .learn,
            .speech,
        ] {
            builder.remove(menu: identifier)
        }
        super.buildMenu(with: builder)
    }
}

#endif
