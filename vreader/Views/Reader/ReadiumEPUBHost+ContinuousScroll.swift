// Purpose: Feature #83 WI-3 — Readium cross-chapter continuous scroll (resolves
// Bug #309). Makes scroll mode flow across chapter boundaries: when the user
// drags PAST the end (or start) of the current resource, auto-`goForward`
// (`goBackward`) to the next (previous) spine item. WI-1 proved on device that a
// `setupUserScripts`-injected observer can read `window.scrollY`/`scrollHeight`/
// `innerHeight` (Readium scrolls the window/scrollingElement in scroll mode);
// this wires that boundary-intent signal → `ReadiumContinuousScrollModel` →
// `navigator.goForward(animated:false)`.
//
// Honest scope (Gate-2): AUTO-ADVANCE at the boundary (no manual swipe), NOT
// pixel-continuous #71 stitching — Readium swaps resources via its own
// transition, so a seam remains. Tracked + accepted on #1403.
//
// Lifecycle (Gate-2 audit): the message handler is a WEAK proxy (so the
// Readium-owned, per-spread `WKUserContentController` that strongly retains it
// cannot create a retain cycle to the coordinator); a per-spread debounce
// prevents a double-advance during the resource transition; the observer is
// self-gating to scroll layout (the proxy + the model both re-check
// `currentLayout == .scroll`).
//
// @coordinates-with: ReadiumReaderCoordinator.swift,
//   ReadiumReaderCoordinator+Transparency.swift (setupUserScripts),
//   ReadiumContinuousScrollModel.swift, ReadiumEPUBHost+Navigation.swift

#if canImport(UIKit)
import UIKit
import WebKit
import ReadiumNavigator

extension ReadiumReaderCoordinator {

    /// Message-handler name for the boundary-intent observer.
    static var continuousScrollHandlerName: String { "vreaderBoundary" }

    /// Boundary-intent observer (atDocumentEnd). Posts ONLY when the user drags
    /// past the resource edge while already scrolled there — `{scrollY,
    /// scrollHeight, innerHeight, dragDelta}` (dragDelta>0 = finger up =
    /// scroll-down intent). Fixed compile-time string (no app interpolation).
    static var continuousScrollObserverJS: String {
        """
        (function(){
          var H=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(continuousScrollHandlerName);
          if(!H)return; if(window.__vreaderBoundary)return; window.__vreaderBoundary=true;
          var sy=null;
          function se(){return document.scrollingElement||document.documentElement;}
          document.addEventListener('touchstart',function(e){if(e.touches.length)sy=e.touches[0].clientY;},{passive:true,capture:true});
          document.addEventListener('touchmove',function(e){
            if(sy===null||!e.touches.length)return;
            var dy=sy-e.touches[0].clientY; var el=se();
            var y=(window.scrollY||el.scrollTop||0); var h=(el.scrollHeight||0); var ih=window.innerHeight||0;
            var atBot=(y+ih)>=(h-4); var atTop=y<=4;
            if((dy>10&&atBot)||(dy<-10&&atTop)){
              try{H.postMessage({scrollY:Math.round(y),scrollHeight:Math.round(h),innerHeight:Math.round(ih),dragDelta:Math.round(dy)});}catch(err){}
            }
          },{passive:true,capture:true});
        })();
        """
    }

    /// Install the observer + a WEAK message-handler proxy on a freshly set-up
    /// spread content controller. Called from `setupUserScripts`.
    func installContinuousScroll(on userContentController: WKUserContentController) {
        userContentController.removeScriptMessageHandler(forName: Self.continuousScrollHandlerName)
        userContentController.add(
            ReadiumBoundaryScrollProxy(coordinator: self),
            name: Self.continuousScrollHandlerName
        )
        userContentController.addUserScript(WKUserScript(
            source: Self.continuousScrollObserverJS,
            injectionTime: .atDocumentEnd, forMainFrameOnly: false
        ))
    }

    /// Act on a decoded boundary-intent signal: in scroll layout, decide via the
    /// pure model and auto-advance/retreat with NO animation (minimise the
    /// transition feel). Debounced by the proxy.
    @MainActor
    func handleContinuousScrollBoundary(geometry: ReadiumScrollGeometry, dragDelta: Double) {
        // In-flight guard (Gate-4 High): once an advance/retreat starts, ignore
        // every further boundary message — including a stale message from the
        // outgoing spread during a slow transition or a long-held drag — until
        // the navigation settles. Without this a second post could skip a
        // chapter. Cleared in the Task below + on locationDidChange/detach/layout.
        guard !continuousScrollAdvancing else { return }
        let decision = ReadiumContinuousScrollModel.decide(
            geometry: geometry, dragDelta: dragDelta, layout: currentLayout)
        guard decision != .none else { return }
        continuousScrollAdvancing = true
        // Re-read the WEAK navigator INSIDE the task (Gate-4 Medium): a detach
        // between now and execution must not drive a torn-down navigator —
        // mirrors `ReadiumEPUBHost+Navigation`.
        Task { @MainActor [weak self] in
            guard let self, let navigator = self.boundNavigator else {
                self?.continuousScrollAdvancing = false
                return
            }
            switch decision {
            case .advance: _ = await navigator.goForward(options: NavigatorGoOptions(animated: false))
            case .retreat: _ = await navigator.goBackward(options: NavigatorGoOptions(animated: false))
            case .none: break
            }
            // The navigation has settled (or no-op'd at the book edge). Clear so
            // the next resource's boundary can advance. `locationDidChange` also
            // clears as belt-and-suspenders.
            self.continuousScrollAdvancing = false
        }
    }
}

/// Weak proxy between Readium's per-spread `WKUserContentController` (which
/// strongly retains its message handlers) and the coordinator — avoids a retain
/// cycle. Holds the per-spread debounce so a single boundary drag advances once.
final class ReadiumBoundaryScrollProxy: NSObject, WKScriptMessageHandler {

    private weak var coordinator: ReadiumReaderCoordinator?
    private var lastAdvance: TimeInterval = 0
    /// Min seconds between auto-advances (covers the resource transition).
    private static let debounce: TimeInterval = 0.7

    init(coordinator: ReadiumReaderCoordinator) {
        self.coordinator = coordinator
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == ReadiumReaderCoordinator.continuousScrollHandlerName,
              let coordinator else { return }
        let b = (message.body as? [String: Any]) ?? [:]
        func num(_ k: String) -> Double {
            if let d = b[k] as? Double { return d }
            if let i = b[k] as? Int { return Double(i) }
            return 0
        }
        let now = Date().timeIntervalSinceReferenceDate
        guard now - lastAdvance >= Self.debounce else { return }

        let geometry = ReadiumScrollGeometry(
            scrollY: num("scrollY"), scrollHeight: num("scrollHeight"), innerHeight: num("innerHeight"))
        let dragDelta = num("dragDelta")
        let decision = ReadiumContinuousScrollModel.decide(
            geometry: geometry, dragDelta: dragDelta, layout: coordinator.currentLayout)
        guard decision != .none else { return }
        lastAdvance = now

        // WKScriptMessageHandler callbacks arrive on the main thread; hop to the
        // MainActor explicitly for Swift 6 isolation.
        Task { @MainActor in
            coordinator.handleContinuousScrollBoundary(geometry: geometry, dragDelta: dragDelta)
        }
    }
}

#endif
