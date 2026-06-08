// Purpose: Feature #54 Phase D-1 — builds the CFI-safe JS that applies content
// replacement rules to a Readium EPUB spine's rendered text nodes.
//
// EPUB now renders via the Readium navigator (feature #42). The native MD path
// applies `ReplacementTransform` to the source text before parse
// (`MDFileLoader`); the EPUB equivalent injects JS that walks the loaded spine's
// text nodes and rewrites their values, so the *original resource HTML is
// untouched*. This is the CFI-safe property the original #54 plan called for:
// Readium computes locators/CFI against the loaded resource, then this JS runs
// — so saved positions still resolve against the real document; only the
// visible text is substituted.
//
// Key decisions:
// - JSON-built rule array (clean escaping of user-configured pattern/replacement
//   strings — no manual JS-string escaping needed).
// - String rules = replace-all, non-recursive (`split(p).join(r)`); regex rules =
//   global `RegExp` with the same `$1` template grammar as `ReplacementTransform`.
//   Per-text-node application (a pattern spanning multiple text nodes is a known
//   v1 limitation — most rules are single-word/phrase within one node).
// - Section-scoped idempotency: each chapter section is processed once and
//   marked (`data-vreader-repl`). The legacy #71 stitch is ONE document with
//   chapters appended as you scroll (`[data-vreader-spine-index]`), so a
//   document-global flag would skip later-appended chapters; marking each
//   section lets a re-assert process only the new ones. Readium renders each
//   spine as its own document with no spine-index wrapper, so it falls back to
//   `[document.body]` (one root per spine; the mark guards the re-assert).
// - Skips SCRIPT/STYLE/NOSCRIPT/TEXTAREA text. Returns "applied:N" (N = nodes
//   changed) so `eval`-based verification can confirm it ran.
//
// @coordinates-with: ReplacementTransform.swift (the Swift semantics this
//   mirrors), MDReplacementRuleFetcher.swift (the rule source),
//   ReadiumReaderCoordinator+Replacement.swift (the injector).

import Foundation

enum EPUBReplacementJS {

    /// Builds the replacement-injection JS for `rules`. Returns "" when no
    /// enabled rule applies (the caller then skips injection entirely).
    ///
    /// The emitted JS is a self-invoking function returning a short status
    /// string (`"already"` / `"norules"` / `"noroot"` / `"applied:<N>"`).
    static func injectionJS(rules: [ReplacementRuleDescriptor]) -> String {
        let enabled = rules.filter(\.enabled).sorted { $0.order < $1.order }
        guard !enabled.isEmpty else { return "" }

        let array: [[String: Any]] = enabled.map {
            ["p": $0.pattern, "r": $0.replacement, "x": $0.isRegex]
        }
        let json = (try? JSONSerialization.data(withJSONObject: array, options: []))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

        return """
        (function(){
          var rules = \(json);
          if (!rules.length) return "norules";
          var compiled = rules.map(function(rule){
            if (rule.x) { try { return { re: new RegExp(rule.p, "g"), r: rule.r }; } catch (e) { return null; } }
            return { p: rule.p, r: rule.r };
          });
          var MARK = "data-vreader-repl";
          // Apply rules to ONE root's text nodes, once (idempotent via MARK).
          function applyToRoot(root){
            if (!root || (root.getAttribute && root.getAttribute(MARK) === "1")) return 0;
            var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
              acceptNode: function(n){
                var p = n.parentNode; if (!p) return NodeFilter.FILTER_REJECT;
                var tag = p.nodeName;
                if (tag === "SCRIPT" || tag === "STYLE" || tag === "NOSCRIPT" || tag === "TEXTAREA") return NodeFilter.FILTER_REJECT;
                return NodeFilter.FILTER_ACCEPT;
              }
            });
            var nodes = []; while (walker.nextNode()) nodes.push(walker.currentNode);
            var changed = 0;
            nodes.forEach(function(n){
              var s = n.nodeValue, orig = s;
              for (var i = 0; i < compiled.length; i++){
                var c = compiled[i]; if (!c) continue;
                if (c.re) { s = s.replace(c.re, c.r); }
                else if (c.p) { s = s.split(c.p).join(c.r); }
              }
              if (s !== orig) { n.nodeValue = s; changed++; }
            });
            if (root.setAttribute) root.setAttribute(MARK, "1");
            return changed;
          }
          // Roots: the legacy #71 stitch is ONE document with chapters as
          // `[data-vreader-spine-index]` sections; Readium renders each spine as
          // its own document with no such wrapper → fall back to the body.
          var sections = document.querySelectorAll("[data-vreader-spine-index]");
          var roots = sections.length
            ? Array.prototype.slice.call(sections)
            : (document.body ? [document.body] : []);
          if (!roots.length) return "noroot";
          var changed = 0;
          roots.forEach(function(r){ changed += applyToRoot(r); });
          // Legacy stitch: sections are APPENDED as you scroll and never re-run
          // this script, so observe the scroll-root and apply rules to each new
          // chapter section. Readium has no scroll-root (each spine re-injects on
          // locationDidChange), so the observer is skipped there.
          var scrollRoot = document.getElementById("vreader-scroll-root");
          if (scrollRoot && !window.__vreaderReplObserver) {
            window.__vreaderReplObserver = new MutationObserver(function(muts){
              muts.forEach(function(m){
                for (var i = 0; i < m.addedNodes.length; i++){
                  var node = m.addedNodes[i];
                  if (!node || node.nodeType !== 1) continue;
                  if (node.matches && node.matches("[data-vreader-spine-index]")) { applyToRoot(node); }
                  else if (node.querySelectorAll) {
                    var subs = node.querySelectorAll("[data-vreader-spine-index]");
                    for (var j = 0; j < subs.length; j++) applyToRoot(subs[j]);
                  }
                }
              });
            });
            window.__vreaderReplObserver.observe(scrollRoot, { childList: true, subtree: true });
          }
          return "applied:" + changed + " sections:" + roots.length;
        })();
        """
    }
}
