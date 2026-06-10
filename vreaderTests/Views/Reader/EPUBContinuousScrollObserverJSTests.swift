// Purpose: Bug #329 round 4 — EXECUTABLE coverage for the observer JS's
// gesture/settle state machine (Codex round-1 Medium: string-shape checks are
// exactly how rounds 1–3 missed the real gesture bug). The production
// `continuousScrollObserverJS` runs unmodified inside JavaScriptCore over a
// stubbed DOM (fake scroll root + listeners), fake timers (manual advance),
// captured rAF queue, and a captured `postMessage` sink — so the tests drive
// real touchstart/touchend/scroll sequences and assert the `touchActive`
// wire value + the deferred ResizeObserver compensation.
//
// @coordinates-with: EPUBContinuousScrollJS.swift,
//   EPUBContinuousScrollCoordinator.swift, EPUBContinuousScrollBridge.swift

import Testing
import Foundation
import JavaScriptCore
@testable import vreader

@Suite("Bug #329 round 4 — observer gesture/settle state machine (JSC)")
struct EPUBContinuousScrollObserverJSTests {

    /// Builds a JSContext with the DOM/timer/rAF/postMessage stubs and the
    /// PRODUCTION observer script evaluated (the IIFE installs its listeners
    /// on the fake root immediately).
    private func makeContext() -> JSContext {
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, exc in
            Issue.record("JS exception: \(exc?.toString() ?? "?")")
        }
        ctx.evaluateScript("""
        var window = this;
        var __posts = [];
        var __timers = [];
        var __now = 0;
        var __rafs = [];
        var __resizeCB = null;
        function setTimeout(fn, ms) {
            // Browser timer ids are never 0 — the production code uses
            // `if (settleTimer)` truthiness, so the fake must match.
            var id = __timers.length + 1;
            __timers.push({ fn: fn, at: __now + ms, cleared: false, fired: false });
            return id;
        }
        function clearTimeout(id) { if (__timers[id-1]) { __timers[id-1].cleared = true; } }
        function __advance(ms) {
            __now += ms;
            __timers.filter(function(t){ return !t.cleared && !t.fired && t.at <= __now; })
                .sort(function(a,b){ return a.at - b.at; })
                .forEach(function(t){ t.fired = true; t.fn(); });
        }
        function requestAnimationFrame(fn) { __rafs.push(fn); return __rafs.length; }
        function __drainRaf() { var f = __rafs.splice(0); f.forEach(function(x){ x(); }); }
        function MutationObserver(cb) { this.observe = function(){}; }
        function ResizeObserver(cb) { __resizeCB = cb; this.observe = function(){}; }
        window.webkit = { messageHandlers: { continuousScrollHandler: {
            postMessage: function(m) { __posts.push(m); }
        } } };
        var __sections = [
            { isConnected: true, offsetTop: 0, offsetHeight: 10000,
              getAttribute: function(){ return "0"; } }
        ];
        var __handlers = {};
        var __root = {
            scrollTop: 500, scrollHeight: 10000, clientHeight: 800,
            __vreaderScrollObserver: false,
            querySelectorAll: function(){ return __sections; },
            addEventListener: function(type, fn) {
                (__handlers[type] = __handlers[type] || []).push(fn);
            }
        };
        // The observer reads `__vreaderScrollObserver` truthily; start unset.
        delete __root.__vreaderScrollObserver;
        var document = { getElementById: function(){ return __root; } };
        function __fire(type, evt) {
            (__handlers[type] || []).forEach(function(fn){ fn(evt || {}); });
        }
        """)
        ctx.evaluateScript(EPUBContinuousScrollJS.continuousScrollObserverJS)
        return ctx
    }

    private func lastPostTouchActive(_ ctx: JSContext) -> Bool? {
        ctx.evaluateScript("__drainRaf();")
        let v = ctx.evaluateScript("__posts.length ? __posts[__posts.length-1].touchActive : null")
        return v?.isBoolean == true ? v!.toBool() : nil
    }

    @Test func touchstartOpensWindow_settleClosesAfterQuiescence() {
        let ctx = makeContext()
        ctx.evaluateScript("__fire('touchstart', { touches: { length: 1 } });")
        ctx.evaluateScript("__fire('scroll');")
        #expect(lastPostTouchActive(ctx) == true, "reports during the touch carry touchActive=true")

        ctx.evaluateScript("__fire('touchend', { touches: { length: 0 } });")
        // Momentum: scroll events after finger-up re-arm the settle window.
        ctx.evaluateScript("__fire('scroll'); __drainRaf();")
        #expect(lastPostTouchActive(ctx) == true, "momentum still inside the gesture window")
        ctx.evaluateScript("__advance(100); __fire('scroll'); __drainRaf();")
        ctx.evaluateScript("__advance(100);")  // 100 < 160 since the re-arm → not settled
        #expect(lastPostTouchActive(ctx) == true)
        ctx.evaluateScript("__advance(200);")  // quiescent past 160ms → settled
        ctx.evaluateScript("__fire('scroll');")
        #expect(lastPostTouchActive(ctx) == false, "post-settle reports carry touchActive=false")
    }

    @Test func retouchDuringSettle_keepsWindowOpen() {
        let ctx = makeContext()
        ctx.evaluateScript("__fire('touchstart', { touches: { length: 1 } });")
        ctx.evaluateScript("__fire('touchend', { touches: { length: 0 } });")
        ctx.evaluateScript("__advance(100);")
        ctx.evaluateScript("__fire('touchstart', { touches: { length: 1 } });")  // re-touch cancels settle
        ctx.evaluateScript("__advance(500);")  // the old timer must not fire settled()
        ctx.evaluateScript("__fire('scroll');")
        #expect(lastPostTouchActive(ctx) == true, "a re-touch during the settle window keeps the gesture open")
    }

    @Test func multiTouch_secondFingerKeepsWindowOpen() {
        let ctx = makeContext()
        ctx.evaluateScript("__fire('touchstart', { touches: { length: 2 } });")
        // Finger A lifts; finger B remains (touches reflects the remainder).
        ctx.evaluateScript("__fire('touchend', { touches: { length: 1 } });")
        ctx.evaluateScript("__advance(500);")
        ctx.evaluateScript("__fire('scroll');")
        #expect(lastPostTouchActive(ctx) == true, "Codex round-1 High: one remaining finger keeps the window open")

        ctx.evaluateScript("__fire('touchend', { touches: { length: 0 } });")
        ctx.evaluateScript("__advance(200);")
        ctx.evaluateScript("__fire('scroll');")
        #expect(lastPostTouchActive(ctx) == false, "settles only after the LAST finger lifts")
    }

    @Test func resizeCompensation_queuesDuringGesture_appliesOnSettle() {
        let ctx = makeContext()
        // Baseline observation (records oldH; never compensates).
        ctx.evaluateScript("var el = { isConnected: true, offsetTop: 0, offsetHeight: 100 }; __resizeCB([{ target: el }]);")
        // Grow the section ENTIRELY above the viewport during a touch.
        ctx.evaluateScript("__fire('touchstart', { touches: { length: 1 } });")
        ctx.evaluateScript("el.offsetHeight = 150; __resizeCB([{ target: el }]);")
        let during = ctx.evaluateScript("__root.scrollTop")!.toInt32()
        #expect(during == 500, "no scrollTop write while the gesture owns the scroller")

        ctx.evaluateScript("__fire('touchend', { touches: { length: 0 } });")
        ctx.evaluateScript("__advance(200);")  // settle fires → queued delta applies
        let after = ctx.evaluateScript("__root.scrollTop")!.toInt32()
        #expect(after == 550, "the queued +50 compensation lands exactly once at settle")
    }

    @Test func resizeCompensation_appliesImmediately_whenNoGesture() {
        let ctx = makeContext()
        ctx.evaluateScript("var el = { isConnected: true, offsetTop: 0, offsetHeight: 100 }; __resizeCB([{ target: el }]);")
        ctx.evaluateScript("el.offsetHeight = 160; __resizeCB([{ target: el }]);")
        let after = ctx.evaluateScript("__root.scrollTop")!.toInt32()
        #expect(after == 560, "outside a gesture the compensation is immediate (rounds 1–3 behavior)")
    }

    // MARK: - Bridge parse

    @Test func bridgeParsesTouchActive() {
        let base: [String: Any] = [
            "visibleSpineIndex": 2, "intraFraction": 0.5,
            "nearTopBoundary": false, "nearBottomBoundary": true,
        ]
        var with = base; with["touchActive"] = true
        #expect(EPUBScrollBoundarySignal.parse(with)?.touchActive == true)
        #expect(EPUBScrollBoundarySignal.parse(base)?.touchActive == false,
                "absent → false (synthetic/legacy signals never defer)")
    }
}
