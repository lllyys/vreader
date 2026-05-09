/**
 * foliate-bridge.js — Vendored foliate-js modules adapted for VReader's WKWebView.
 *
 * Source: https://github.com/johnfactotum/foliate-js (MIT License)
 * Modules included: epubcfi, overlayer, text-walker, tts, footnotes (detection only)
 *
 * Adaptations:
 * - Removed ES module exports (WKWebView injection doesn't support import/export)
 * - All classes exposed on window.__foliate namespace
 * - TTS generates SSML and posts marks to Swift via webkit.messageHandlers
 * - Footnote detection exposes isFootnoteReference() for Swift bridge
 */
(function() {
'use strict';

// ============================================================
// EPUB CFI (epubcfi.js) — Canonical Fragment Identifier
// ============================================================
const CFI = {
    parse(cfi) {
        const tokens = [];
        let i = 0;
        const s = cfi.replace(/^epubcfi\(|\)$/g, '');
        while (i < s.length) {
            if (s[i] === '/') {
                i++;
                let num = '';
                while (i < s.length && /\d/.test(s[i])) num += s[i++];
                const step = { index: parseInt(num) };
                if (s[i] === '[') {
                    i++;
                    let id = '';
                    while (i < s.length && s[i] !== ']') id += s[i++];
                    step.id = id;
                    i++; // skip ]
                }
                tokens.push(step);
            } else if (s[i] === ':') {
                i++;
                let num = '';
                while (i < s.length && /\d/.test(s[i])) num += s[i++];
                tokens.push({ offset: parseInt(num) });
            } else {
                i++;
            }
        }
        return tokens;
    },
    fromRange(range, doc) {
        if (!range || range.collapsed) return null;
        const start = this._pathTo(range.startContainer, range.startOffset, doc);
        const end = this._pathTo(range.endContainer, range.endOffset, doc);
        if (!start || !end) return null;
        return 'epubcfi(' + start + ',' + end + ')';
    },
    _pathTo(node, offset, doc) {
        const steps = [];
        let current = node;
        if (current.nodeType === Node.TEXT_NODE) {
            steps.unshift(':' + offset);
            const parent = current.parentNode;
            let idx = 0;
            for (const child of parent.childNodes) {
                idx++;
                if (child === current) break;
            }
            steps.unshift('/' + (idx * 2));
            current = parent;
        }
        while (current && current !== doc.documentElement) {
            const parent = current.parentNode;
            if (!parent) break;
            let idx = 0;
            for (const child of parent.childNodes) {
                if (child.nodeType === Node.ELEMENT_NODE) idx++;
                if (child === current) break;
            }
            steps.unshift('/' + (idx * 2));
            current = parent;
        }
        return steps.join('');
    },
    toRange(doc, cfi) {
        const parsed = typeof cfi === 'string' ? this.parse(cfi) : cfi;
        let node = doc.documentElement;
        let offset = 0;
        for (const step of parsed) {
            if (step.index !== undefined) {
                const children = Array.from(node.childNodes);
                const target = Math.floor(step.index / 2) - 1;
                let elementIdx = -1;
                for (const child of children) {
                    if (child.nodeType === Node.ELEMENT_NODE) elementIdx++;
                    if (elementIdx === target) { node = child; break; }
                }
            }
            if (step.offset !== undefined) offset = step.offset;
        }
        try {
            const range = doc.createRange();
            if (node.nodeType === Node.TEXT_NODE) {
                range.setStart(node, Math.min(offset, node.length));
                range.setEnd(node, Math.min(offset, node.length));
            } else {
                const textNode = node.childNodes[0];
                if (textNode && textNode.nodeType === Node.TEXT_NODE) {
                    range.setStart(textNode, Math.min(offset, textNode.length));
                    range.setEnd(textNode, Math.min(offset, textNode.length));
                } else {
                    range.selectNodeContents(node);
                }
            }
            return range;
        } catch { return null; }
    }
};

// ============================================================
// Overlayer (overlayer.js) — SVG annotation overlay
// ============================================================
const createSVGElement = tag =>
    document.createElementNS('http://www.w3.org/2000/svg', tag);

class Overlayer {
    #svg = createSVGElement('svg');
    #map = new Map();
    constructor() {
        Object.assign(this.#svg.style, {
            position: 'absolute', top: '0', left: '0',
            width: '100%', height: '100%',
            pointerEvents: 'none',
        });
    }
    get element() { return this.#svg; }
    add(key, range, draw, options) {
        if (this.#map.has(key)) this.remove(key);
        if (typeof range === 'function') range = range(this.#svg.getRootNode());
        const rects = range.getClientRects();
        const element = draw(rects, options);
        this.#svg.append(element);
        this.#map.set(key, { range, draw, options, element, rects });
    }
    remove(key) {
        if (!this.#map.has(key)) return;
        this.#svg.removeChild(this.#map.get(key).element);
        this.#map.delete(key);
    }
    redraw() {
        for (const obj of this.#map.values()) {
            const { range, draw, options, element } = obj;
            this.#svg.removeChild(element);
            const rects = range.getClientRects();
            const el = draw(rects, options);
            this.#svg.append(el);
            obj.element = el;
            obj.rects = rects;
        }
    }
    hitTest({ x, y }) {
        const arr = Array.from(this.#map.entries());
        for (let i = arr.length - 1; i >= 0; i--) {
            const [key, obj] = arr[i];
            for (const { left, top, right, bottom } of obj.rects)
                if (top <= y && left <= x && bottom > y && right > x)
                    return [key, obj.range];
        }
        return [];
    }
    static highlight(rects, options = {}) {
        const { color = 'yellow' } = options;
        const g = createSVGElement('g');
        g.setAttribute('fill', color);
        g.style.opacity = '0.3';
        g.style.mixBlendMode = 'multiply';
        for (const { left, top, height, width } of rects) {
            const el = createSVGElement('rect');
            el.setAttribute('x', left);
            el.setAttribute('y', top);
            el.setAttribute('height', height);
            el.setAttribute('width', width);
            g.append(el);
        }
        return g;
    }
    static underline(rects, options = {}) {
        const { color = 'red', width: sw = 2 } = options;
        const g = createSVGElement('g');
        g.setAttribute('fill', color);
        for (const { left, bottom, width } of rects) {
            const el = createSVGElement('rect');
            el.setAttribute('x', left);
            el.setAttribute('y', bottom - sw);
            el.setAttribute('height', sw);
            el.setAttribute('width', width);
            g.append(el);
        }
        return g;
    }
    static squiggly(rects, options = {}) {
        const { color = 'red', width: sw = 2 } = options;
        const g = createSVGElement('g');
        g.setAttribute('fill', 'none');
        g.setAttribute('stroke', color);
        g.setAttribute('stroke-width', sw);
        const block = sw * 1.5;
        for (const { left, bottom, width } of rects) {
            const el = createSVGElement('path');
            const n = Math.max(Math.round(width / block / 1.5), 1);
            const inline = width / n;
            const ls = Array.from({ length: n },
                (_, i) => `l${inline} ${i % 2 ? block : -block}`).join('');
            el.setAttribute('d', `M${left} ${bottom}${ls}`);
            g.append(el);
        }
        return g;
    }
}

// ============================================================
// Text Walker (text-walker.js) — collect text nodes for search/TTS
// ============================================================
function* textWalker(doc, filter) {
    const walker = doc.createTreeWalker(doc.body, NodeFilter.SHOW_TEXT, filter);
    let node;
    while ((node = walker.nextNode())) {
        yield { node, text: node.nodeValue };
    }
}

function getTextNodes(range) {
    const doc = range.startContainer.ownerDocument || range.startContainer;
    const nodes = [];
    for (const { node, text } of textWalker(doc)) {
        if (range.intersectsNode(node)) {
            nodes.push({ node, text });
        }
    }
    return nodes;
}

// ============================================================
// TTS (tts.js) — SSML generation with word marks
// ============================================================
class TTSBridge {
    #marks = new Map();
    #currentBlock = null;
    #blockIndex = 0;

    getBlocks(doc) {
        const blocks = [];
        const walker = doc.createTreeWalker(
            doc.body, NodeFilter.SHOW_ELEMENT,
            { acceptNode: el => {
                const display = getComputedStyle(el).display;
                return display === 'block' || display === 'list-item' || display === 'table-cell'
                    ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
            }}
        );
        let node;
        while ((node = walker.nextNode())) {
            const range = doc.createRange();
            range.selectNodeContents(node);
            const text = range.toString().trim();
            if (text) blocks.push({ element: node, range, text });
        }
        return blocks;
    }

    generateSSML(block) {
        this.#marks.clear();
        this.#currentBlock = block;
        const text = block.text;
        // Segment by words using Intl.Segmenter if available, else whitespace
        const words = [];
        if (typeof Intl !== 'undefined' && Intl.Segmenter) {
            const segmenter = new Intl.Segmenter(document.documentElement.lang || 'en', { granularity: 'word' });
            for (const { segment, index, isWordLike } of segmenter.segment(text)) {
                if (isWordLike) words.push({ text: segment, offset: index });
            }
        } else {
            let match;
            const re = /\S+/g;
            while ((match = re.exec(text))) {
                words.push({ text: match[0], offset: match.index });
            }
        }

        let ssml = '<speak>';
        for (let i = 0; i < words.length; i++) {
            const markName = 'w' + i;
            this.#marks.set(markName, { offset: words[i].offset, length: words[i].text.length });
            ssml += `<mark name="${markName}"/>${this._escapeXML(words[i].text)} `;
        }
        ssml += '</speak>';
        return { ssml, plainText: text, wordCount: words.length };
    }

    setMark(name) {
        const mark = this.#marks.get(name);
        if (!mark || !this.#currentBlock) return null;
        return { offset: mark.offset, length: mark.length };
    }

    _escapeXML(s) {
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    }
}

// ============================================================
// Footnote Detection (footnotes.js) — detect footnote links
// ============================================================
const FootnoteDetector = {
    isFootnoteReference(a) {
        const getTypes = el => new Set(el?.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type')?.split(' '));
        const getRoles = el => new Set(el?.getAttribute?.('role')?.split(' '));
        const refTypes = ['biblioref', 'glossref', 'noteref'];
        const refRoles = ['doc-biblioref', 'doc-glossref', 'doc-noteref'];
        const types = getTypes(a);
        const roles = getRoles(a);
        const definite = refRoles.some(r => roles.has(r)) || refTypes.some(t => types.has(t));
        if (definite) return true;
        // Heuristic: superscript link
        const isSuper = el => {
            if (el.matches('sup')) return true;
            const vs = getComputedStyle(el).verticalAlign;
            return vs === 'super' || vs === 'top' || vs === 'text-top';
        };
        return !types.has('backlink') && !roles.has('doc-backlink')
            && (isSuper(a) || (a.children.length === 1 && isSuper(a.children[0]))
            || isSuper(a.parentElement));
    },
    getReferencedType(el) {
        const types = new Set(el?.getAttributeNS?.('http://www.idpf.org/2007/ops', 'type')?.split(' '));
        const roles = new Set(el?.getAttribute?.('role')?.split(' '));
        if (roles.has('doc-footnote') || types.has('footnote')) return 'footnote';
        if (roles.has('doc-endnote') || types.has('endnote') || types.has('rearnote')) return 'endnote';
        if (roles.has('note') || types.has('note')) return 'note';
        return null;
    }
};

// ============================================================
// Expose on window for WKWebView bridge
// ============================================================
window.__foliate = {
    CFI: CFI,
    Overlayer: Overlayer,
    TTSBridge: TTSBridge,
    FootnoteDetector: FootnoteDetector,
    textWalker: textWalker,
    getTextNodes: getTextNodes,
};

// Auto-setup: create overlayer instance and attach to body.
// Bug #159 / GH #472: this script is injected at .atDocumentEnd (just after
// document parsing), which means `DOMContentLoaded` has already fired by
// the time the listener gets registered — the callback never ran, and
// `window.__foliate.overlayer` stayed undefined. Without the overlayer,
// the user-flow highlight path silently failed (it falls back to CSS
// Highlight API, which has its own latent issue tracked in #159). Use
// the readyState check to invoke setup synchronously when the document
// is already past the loading phase.
function __vreader_setupFoliate() {
    const overlayer = new Overlayer();
    const container = document.body.parentElement || document.body;
    if (getComputedStyle(container).position === 'static') {
        container.style.position = 'relative';
    }
    container.appendChild(overlayer.element);
    window.__foliate.overlayer = overlayer;
    window.__foliate.tts = new TTSBridge();
}
if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', __vreader_setupFoliate);
} else {
    __vreader_setupFoliate();
}

})();
