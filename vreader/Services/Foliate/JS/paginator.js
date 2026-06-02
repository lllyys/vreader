const wait = ms => new Promise(resolve => setTimeout(resolve, ms))

const debounce = (f, wait, immediate) => {
    let timeout
    return (...args) => {
        const later = () => {
            timeout = null
            if (!immediate) f(...args)
        }
        const callNow = immediate && !timeout
        if (timeout) clearTimeout(timeout)
        timeout = setTimeout(later, wait)
        if (callNow) f(...args)
    }
}

const lerp = (min, max, x) => x * (max - min) + min
const easeOutQuad = x => 1 - (1 - x) * (1 - x)
const animate = (a, b, duration, ease, render) => new Promise(resolve => {
    let start
    const step = now => {
        if (document.hidden) {
            render(lerp(a, b, 1))
            return resolve()
        }
        start ??= now
        const fraction = Math.min(1, (now - start) / duration)
        render(lerp(a, b, ease(fraction)))
        if (fraction < 1) requestAnimationFrame(step)
        else resolve()
    }
    if (document.hidden) {
        render(lerp(a, b, 1))
        return resolve()
    }
    requestAnimationFrame(step)
})

// collapsed range doesn't return client rects sometimes (or always?)
// try make get a non-collapsed range or element
const uncollapse = range => {
    if (!range?.collapsed) return range
    const { endOffset, endContainer } = range
    if (endContainer.nodeType === 1) {
        const node = endContainer.childNodes[endOffset]
        if (node?.nodeType === 1) return node
        return endContainer
    }
    if (endOffset + 1 < endContainer.length) range.setEnd(endContainer, endOffset + 1)
    else if (endOffset > 1) range.setStart(endContainer, endOffset - 1)
    else return endContainer.parentNode
    return range
}

const makeRange = (doc, node, start, end = start) => {
    const range = doc.createRange()
    range.setStart(node, start)
    range.setEnd(node, end)
    return range
}

// use binary search to find an offset value in a text node
const bisectNode = (doc, node, cb, start = 0, end = node.nodeValue.length) => {
    if (end - start === 1) {
        const result = cb(makeRange(doc, node, start), makeRange(doc, node, end))
        return result < 0 ? start : end
    }
    const mid = Math.floor(start + (end - start) / 2)
    const result = cb(makeRange(doc, node, start, mid), makeRange(doc, node, mid, end))
    return result < 0 ? bisectNode(doc, node, cb, start, mid)
        : result > 0 ? bisectNode(doc, node, cb, mid, end) : mid
}

const { SHOW_ELEMENT, SHOW_TEXT, SHOW_CDATA_SECTION,
    FILTER_ACCEPT, FILTER_REJECT, FILTER_SKIP } = NodeFilter

const filter = SHOW_ELEMENT | SHOW_TEXT | SHOW_CDATA_SECTION

// needed cause there seems to be a bug in `getBoundingClientRect()` in Firefox
// where it fails to include rects that have zero width and non-zero height
// (CSSOM spec says "rectangles [...] of which the height or width is not zero")
// which makes the visible range include an extra space at column boundaries
const getBoundingClientRect = target => {
    let top = Infinity, right = -Infinity, left = Infinity, bottom = -Infinity
    for (const rect of target.getClientRects()) {
        left = Math.min(left, rect.left)
        top = Math.min(top, rect.top)
        right = Math.max(right, rect.right)
        bottom = Math.max(bottom, rect.bottom)
    }
    return new DOMRect(left, top, right - left, bottom - top)
}

const getVisibleRange = (doc, start, end, mapRect) => {
    // first get all visible nodes
    const acceptNode = node => {
        const name = node.localName?.toLowerCase()
        // ignore all scripts, styles, and their children
        if (name === 'script' || name === 'style') return FILTER_REJECT
        if (node.nodeType === 1) {
            const { left, right } = mapRect(node.getBoundingClientRect())
            // no need to check child nodes if it's completely out of view
            if (right < start || left > end) return FILTER_REJECT
            // elements must be completely in view to be considered visible
            // because you can't specify offsets for elements
            if (left >= start && right <= end) return FILTER_ACCEPT
            // TODO: it should probably allow elements that do not contain text
            // because they can exceed the whole viewport in both directions
            // especially in scrolled mode
        } else {
            // ignore empty text nodes
            if (!node.nodeValue?.trim()) return FILTER_SKIP
            // create range to get rect
            const range = doc.createRange()
            range.selectNodeContents(node)
            const { left, right } = mapRect(range.getBoundingClientRect())
            // it's visible if any part of it is in view
            if (right >= start && left <= end) return FILTER_ACCEPT
        }
        return FILTER_SKIP
    }
    const walker = doc.createTreeWalker(doc.body, filter, { acceptNode })
    const nodes = []
    for (let node = walker.nextNode(); node; node = walker.nextNode())
        nodes.push(node)

    // we're only interested in the first and last visible nodes
    const from = nodes[0] ?? doc.body
    const to = nodes[nodes.length - 1] ?? from

    // find the offset at which visibility changes
    const startOffset = from.nodeType === 1 ? 0
        : bisectNode(doc, from, (a, b) => {
            const p = mapRect(getBoundingClientRect(a))
            const q = mapRect(getBoundingClientRect(b))
            if (p.right < start && q.left > start) return 0
            return q.left > start ? -1 : 1
        })
    const endOffset = to.nodeType === 1 ? 0
        : bisectNode(doc, to, (a, b) => {
            const p = mapRect(getBoundingClientRect(a))
            const q = mapRect(getBoundingClientRect(b))
            if (p.right < end && q.left > end) return 0
            return q.left > end ? -1 : 1
        })

    const range = doc.createRange()
    range.setStart(from, startOffset)
    range.setEnd(to, endOffset)
    return range
}

const selectionIsBackward = sel => {
    const range = document.createRange()
    range.setStart(sel.anchorNode, sel.anchorOffset)
    range.setEnd(sel.focusNode, sel.focusOffset)
    return range.collapsed
}

const setSelectionTo = (target, collapse) => {
    let range
    if (target.startContainer) range = target.cloneRange()
    else if (target.nodeType) {
        range = document.createRange()
        range.selectNode(target)
    }
    if (range) {
        const sel = range.startContainer.ownerDocument.defaultView.getSelection()
        if (sel) {
            sel.removeAllRanges()
            if (collapse === -1) range.collapse(true)
            else if (collapse === 1) range.collapse()
            sel.addRange(range)
        }
    }
}

const getDirection = doc => {
    const { defaultView } = doc
    const { writingMode, direction } = defaultView.getComputedStyle(doc.body)
    const vertical = writingMode === 'vertical-rl'
        || writingMode === 'vertical-lr'
    const rtl = doc.body.dir === 'rtl'
        || direction === 'rtl'
        || doc.documentElement.dir === 'rtl'
    // Feature #76 WI-1b: also surface the raw `writingMode` — `{vertical, rtl}`
    // is lossy (vertical-rl vs -lr collapse; the windowing axis sign can't be
    // recovered). Additive: existing `{vertical, rtl}` consumers are unchanged.
    return { vertical, rtl, writingMode }
}

// Feature #76 WI-1b: the scrolled-mode scroll model derived from a section's
// computed `writing-mode`. MIRRORS the Swift source-of-truth
// `FoliateScrollModel.scrolled(writingMode:)` (pinned by FoliateScrollModelTests)
// so the axis props + RTL/vertical-rl `directionSign` stay in lockstep across the
// Swift seam (FoliateScrolledWindowMath.logicalOffset) and the JS windowing.
// Scrolled mode only; the windowed primitives consume this in WI-3. Horizontal-tb
// keeps sign +1 (Feature #73 path byte-unchanged); unknown modes fall back to it.
const scrollModelFor = writingMode => {
    switch (writingMode) {
        case 'vertical-rl':
            return { axis: 'horizontal', scrollProp: 'scrollLeft', sizeProp: 'width',
                rectStartProp: 'left', directionSign: -1 }
        case 'vertical-lr':
            return { axis: 'horizontal', scrollProp: 'scrollLeft', sizeProp: 'width',
                rectStartProp: 'left', directionSign: 1 }
        default: // horizontal-tb and any non-vertical writing mode
            return { axis: 'vertical', scrollProp: 'scrollTop', sizeProp: 'height',
                rectStartProp: 'top', directionSign: 1 }
    }
}

const getBackground = doc => {
    const bodyStyle = doc.defaultView.getComputedStyle(doc.body)
    return bodyStyle.backgroundColor === 'rgba(0, 0, 0, 0)'
        && bodyStyle.backgroundImage === 'none'
        ? doc.defaultView.getComputedStyle(doc.documentElement).background
        : bodyStyle.background
}

const makeMarginals = (length, part) => Array.from({ length }, () => {
    const div = document.createElement('div')
    const child = document.createElement('div')
    div.append(child)
    child.setAttribute('part', part)
    return div
})

const setStylesImportant = (el, styles) => {
    const { style } = el
    for (const [k, v] of Object.entries(styles)) style.setProperty(k, v, 'important')
}

class View {
    #observer = new ResizeObserver(() => this.expand())
    #element = document.createElement('div')
    #iframe = document.createElement('iframe')
    #contentRange = document.createRange()
    #overlayer
    #vertical = false
    #rtl = false
    // Feature #76 WI-1b: the loaded section's scroll model (axis/props/sign),
    // mirroring Swift `FoliateScrollModel`. Defaults to the horizontal-tb model
    // (Feature #73 vertical-scroll path). Stored additively here; the windowed
    // primitives consume it in WI-3.
    #scrollModel = scrollModelFor('horizontal-tb')
    #column = true
    #size
    #layout = {}
    constructor({ container, onExpand }) {
        this.container = container
        this.onExpand = onExpand
        this.#iframe.setAttribute('part', 'filter')
        this.#element.append(this.#iframe)
        Object.assign(this.#element.style, {
            boxSizing: 'content-box',
            position: 'relative',
            overflow: 'hidden',
            flex: '0 0 auto',
            width: '100%', height: '100%',
            display: 'flex',
            justifyContent: 'center',
            alignItems: 'center',
        })
        Object.assign(this.#iframe.style, {
            overflow: 'hidden',
            border: '0',
            display: 'none',
            width: '100%', height: '100%',
        })
        // `allow-scripts` is needed for events because of WebKit bug
        // https://bugs.webkit.org/show_bug.cgi?id=218086
        this.#iframe.setAttribute('sandbox', 'allow-same-origin allow-scripts')
        this.#iframe.setAttribute('scrolling', 'no')
    }
    get element() {
        return this.#element
    }
    get document() {
        return this.#iframe.contentDocument
    }
    // Feature #76 WI-1b: the loaded section's scroll model (axis/props/sign).
    // Consumed by the windowed primitives in WI-3.
    get scrollModel() {
        return this.#scrollModel
    }
    async load(src, afterLoad, beforeRender) {
        if (typeof src !== 'string') throw new Error(`${src} is not string`)
        return new Promise(resolve => {
            this.#iframe.addEventListener('load', () => {
                const doc = this.document
                afterLoad?.(doc)

                // it needs to be visible for Firefox to get computed style
                this.#iframe.style.display = 'block'
                const { vertical, rtl, writingMode } = getDirection(doc)
                const background = getBackground(doc)
                this.#iframe.style.display = 'none'

                this.#vertical = vertical
                this.#rtl = rtl
                // Feature #76 WI-1b (additive): derive + store the scroll model
                // from the real writing-mode for the windowed primitives (WI-3).
                this.#scrollModel = scrollModelFor(writingMode)

                this.#contentRange.selectNodeContents(doc.body)
                const layout = beforeRender?.({ vertical, rtl, background })
                this.#iframe.style.display = 'block'
                this.render(layout)
                this.#observer.observe(doc.body)

                // the resize observer above doesn't work in Firefox
                // (see https://bugzilla.mozilla.org/show_bug.cgi?id=1832939)
                // until the bug is fixed we can at least account for font load
                doc.fonts.ready.then(() => this.expand())

                resolve()
            }, { once: true })
            this.#iframe.src = src
        })
    }
    render(layout) {
        if (!layout) return
        this.#column = layout.flow !== 'scrolled'
        this.#layout = layout
        if (this.#column) this.columnize(layout)
        else this.scrolled(layout)
    }
    scrolled({ gap, columnWidth }) {
        const vertical = this.#vertical
        const doc = this.document
        setStylesImportant(doc.documentElement, {
            'box-sizing': 'border-box',
            'padding': vertical ? `${gap}px 0` : `0 ${gap}px`,
            'column-width': 'auto',
            'height': 'auto',
            'width': 'auto',
        })
        setStylesImportant(doc.body, {
            [vertical ? 'max-height' : 'max-width']: `${columnWidth}px`,
            'margin': 'auto',
        })
        this.setImageSize()
        this.expand()
    }
    columnize({ width, height, gap, columnWidth }) {
        const vertical = this.#vertical
        this.#size = vertical ? height : width

        const doc = this.document
        setStylesImportant(doc.documentElement, {
            'box-sizing': 'border-box',
            'column-width': `${Math.trunc(columnWidth)}px`,
            'column-gap': `${gap}px`,
            'column-fill': 'auto',
            ...(vertical
                ? { 'width': `${width}px` }
                : { 'height': `${height}px` }),
            'padding': vertical ? `${gap / 2}px 0` : `0 ${gap / 2}px`,
            'overflow': 'hidden',
            // force wrap long words
            'overflow-wrap': 'break-word',
            // reset some potentially problematic props
            'position': 'static', 'border': '0', 'margin': '0',
            'max-height': 'none', 'max-width': 'none',
            'min-height': 'none', 'min-width': 'none',
            // fix glyph clipping in WebKit
            '-webkit-line-box-contain': 'block glyphs replaced',
        })
        setStylesImportant(doc.body, {
            'max-height': 'none',
            'max-width': 'none',
            'margin': '0',
        })
        this.setImageSize()
        this.expand()
    }
    setImageSize() {
        const { width, height, margin } = this.#layout
        const vertical = this.#vertical
        const doc = this.document
        for (const el of doc.body.querySelectorAll('img, svg, video')) {
            // preserve max size if they are already set
            const { maxHeight, maxWidth } = doc.defaultView.getComputedStyle(el)
            setStylesImportant(el, {
                'max-height': vertical
                    ? (maxHeight !== 'none' && maxHeight !== '0px' ? maxHeight : '100%')
                    : `${height - margin * 2}px`,
                'max-width': vertical
                    ? `${width - margin * 2}px`
                    : (maxWidth !== 'none' && maxWidth !== '0px' ? maxWidth : '100%'),
                'object-fit': 'contain',
                'page-break-inside': 'avoid',
                'break-inside': 'avoid',
                'box-sizing': 'border-box',
            })
        }
    }
    expand() {
        const { documentElement } = this.document
        if (this.#column) {
            const side = this.#vertical ? 'height' : 'width'
            const otherSide = this.#vertical ? 'width' : 'height'
            const contentRect = this.#contentRange.getBoundingClientRect()
            const rootRect = documentElement.getBoundingClientRect()
            // offset caused by column break at the start of the page
            // which seem to be supported only by WebKit and only for horizontal writing
            const contentStart = this.#vertical ? 0
                : this.#rtl ? rootRect.right - contentRect.right : contentRect.left - rootRect.left
            const contentSize = contentStart + contentRect[side]
            const pageCount = Math.ceil(contentSize / this.#size)
            const expandedSize = pageCount * this.#size
            this.#element.style.padding = '0'
            this.#iframe.style[side] = `${expandedSize}px`
            this.#element.style[side] = `${expandedSize + this.#size * 2}px`
            this.#iframe.style[otherSide] = '100%'
            this.#element.style[otherSide] = '100%'
            documentElement.style[side] = `${this.#size}px`
            if (this.#overlayer) {
                this.#overlayer.element.style.margin = '0'
                this.#overlayer.element.style.left = this.#vertical ? '0' : `${this.#size}px`
                this.#overlayer.element.style.top = this.#vertical ? `${this.#size}px` : '0'
                this.#overlayer.element.style[side] = `${expandedSize}px`
                this.#overlayer.redraw()
            }
        } else {
            const side = this.#vertical ? 'width' : 'height'
            const otherSide = this.#vertical ? 'height' : 'width'
            const contentSize = documentElement.getBoundingClientRect()[side]
            const expandedSize = contentSize
            const { margin } = this.#layout
            const padding = this.#vertical ? `0 ${margin}px` : `${margin}px 0`
            this.#element.style.padding = padding
            this.#iframe.style[side] = `${expandedSize}px`
            this.#element.style[side] = `${expandedSize}px`
            this.#iframe.style[otherSide] = '100%'
            this.#element.style[otherSide] = '100%'
            if (this.#overlayer) {
                this.#overlayer.element.style.margin = padding
                this.#overlayer.element.style.left = '0'
                this.#overlayer.element.style.top = '0'
                this.#overlayer.element.style[side] = `${expandedSize}px`
                this.#overlayer.redraw()
            }
        }
        this.onExpand()
    }
    set overlayer(overlayer) {
        this.#overlayer = overlayer
        this.#element.append(overlayer.element)
    }
    get overlayer() {
        return this.#overlayer
    }
    destroy() {
        if (this.document) this.#observer.unobserve(this.document.body)
    }
}

// NOTE: everything here assumes the so-called "negative scroll type" for RTL
export class Paginator extends HTMLElement {
    static observedAttributes = [
        'flow', 'gap', 'margin',
        'max-inline-size', 'max-block-size', 'max-column-count',
    ]
    #root = this.attachShadow({ mode: 'closed' })
    #observer = new ResizeObserver(() => this.render())
    #top
    #background
    #container
    #header
    #footer
    #view
    // Feature #73 WI-1a: scrolled-mode windowed-rendering scaffold. The
    // `#scrolledViews` list holds the mounted window of section views (current
    // + neighbours) when `#windowedScroll` is on. The flag defaults OFF, so
    // every consumer that routes through `#mountedViews()` / `#currentView()`
    // is byte-identical to the single-`#view` path until WI-2 lights it up.
    // Paged mode never touches these (it stays the exact single-`#view` code).
    #scrolledViews = []
    #mountingIndices = new Set() // WI-3: in-flight mount dedup (async race guard)
    #windowGeneration = 0 // Gate-4 H1: bumped on navigation/teardown; stale mounts abort
    // Feature #73: windowed multi-section continuous scroll for AZW3/MOBI scroll
    // mode — ON by default. Replaces the per-section view-swap (the Bug #283
    // chapter-boundary jump) with a K-window continuous surface. Horizontal-
    // writing scrolled mode only; vertical writing + paged mode fall back to the
    // single-`#view` path. Shipped after a 2-round Codex audit (ship-as-is) +
    // flag-on device verification.
    #windowedScroll = true
    #K = 3 // Feature #73 WI-2: windowed mount size (current + neighbours)
    #vertical = false
    #rtl = false
    #margin = 0
    #index = -1
    #anchor = 0 // anchor view to a fraction (0-1), Range, or Element
    #justAnchored = false
    #locked = false // while true, prevent any further navigation
    #styles
    #styleMap = new WeakMap()
    #mediaQuery = matchMedia('(prefers-color-scheme: dark)')
    #mediaQueryListener
    #scrollBounds
    #touchState
    #touchScrolled
    #lastVisibleRange
    constructor() {
        super()
        this.#root.innerHTML = `<style>
        :host {
            display: block;
            container-type: size;
        }
        :host, #top {
            box-sizing: border-box;
            position: relative;
            overflow: hidden;
            width: 100%;
            height: 100%;
        }
        #top {
            --_gap: 7%;
            --_margin: 48px;
            --_max-inline-size: 720px;
            --_max-block-size: 1440px;
            --_max-column-count: 2;
            --_max-column-count-portrait: 1;
            --_max-column-count-spread: var(--_max-column-count);
            --_half-gap: calc(var(--_gap) / 2);
            --_max-width: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            --_max-height: var(--_max-block-size);
            display: grid;
            grid-template-columns:
                minmax(var(--_half-gap), 1fr)
                var(--_half-gap)
                minmax(0, calc(var(--_max-width) - var(--_gap)))
                var(--_half-gap)
                minmax(var(--_half-gap), 1fr);
            grid-template-rows:
                minmax(var(--_margin), 1fr)
                minmax(0, var(--_max-height))
                minmax(var(--_margin), 1fr);
            &.vertical {
                --_max-column-count-spread: var(--_max-column-count-portrait);
                --_max-width: var(--_max-block-size);
                --_max-height: calc(var(--_max-inline-size) * var(--_max-column-count-spread));
            }
            @container (orientation: portrait) {
                & {
                    --_max-column-count-spread: var(--_max-column-count-portrait);
                }
                &.vertical {
                    --_max-column-count-spread: var(--_max-column-count);
                }
            }
        }
        #background {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
        }
        #container {
            grid-column: 2 / 5;
            grid-row: 2;
            overflow: hidden;
        }
        :host([flow="scrolled"]) #container {
            grid-column: 1 / -1;
            grid-row: 1 / -1;
            overflow: auto;
        }
        #header {
            grid-column: 3 / 4;
            grid-row: 1;
        }
        #footer {
            grid-column: 3 / 4;
            grid-row: 3;
            align-self: end;
        }
        #header, #footer {
            display: grid;
            height: var(--_margin);
        }
        :is(#header, #footer) > * {
            display: flex;
            align-items: center;
            min-width: 0;
        }
        :is(#header, #footer) > * > * {
            width: 100%;
            overflow: hidden;
            white-space: nowrap;
            text-overflow: ellipsis;
            text-align: center;
            font-size: .75em;
            opacity: .6;
        }
        </style>
        <div id="top">
            <div id="background" part="filter"></div>
            <div id="header"></div>
            <div id="container"></div>
            <div id="footer"></div>
        </div>
        `

        this.#top = this.#root.getElementById('top')
        this.#background = this.#root.getElementById('background')
        this.#container = this.#root.getElementById('container')
        this.#header = this.#root.getElementById('header')
        this.#footer = this.#root.getElementById('footer')

        this.#observer.observe(this.#container)
        this.#container.addEventListener('scroll', () => {
            this.dispatchEvent(new Event('scroll'))
            // Bug #235 (GH #983): in scrolled mode, native scroll alone
            // cannot cross section boundaries because the paginator
            // loads one section at a time. Drive the boundary advance
            // from the IMMEDIATE scroll listener — not the 250ms
            // debounced one below — so the user gets a continuous flow
            // the moment a scroll fling reaches the edge, instead of
            // waiting a quarter-second after the gesture has already
            // stopped. The #turnPage path owns its own re-entrancy
            // lock (#locked), so 60Hz scroll events here collapse to a
            // single section transition.
            if (this.scrolled && !this.#justAnchored) {
                this.#maybeCrossSectionBoundary()
            }
        })
        this.#container.addEventListener('scroll', debounce(() => {
            if (this.scrolled) {
                if (this.#justAnchored) this.#justAnchored = false
                else this.#afterScroll('scroll')
            }
        }, 250))

        const opts = { passive: false }
        this.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
        this.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
        this.addEventListener('touchend', this.#onTouchEnd.bind(this))
        this.addEventListener('load', ({ detail: { doc } }) => {
            doc.addEventListener('touchstart', this.#onTouchStart.bind(this), opts)
            doc.addEventListener('touchmove', this.#onTouchMove.bind(this), opts)
            doc.addEventListener('touchend', this.#onTouchEnd.bind(this))
        })

        this.addEventListener('relocate', ({ detail }) => {
            if (detail.reason === 'selection') setSelectionTo(this.#anchor, 0)
            else if (detail.reason === 'navigation') {
                if (this.#anchor === 1) setSelectionTo(detail.range, 1)
                else if (typeof this.#anchor === 'number')
                    setSelectionTo(detail.range, -1)
                else setSelectionTo(this.#anchor, -1)
            }
        })
        const checkPointerSelection = debounce((range, sel) => {
            if (!sel.rangeCount) return
            const selRange = sel.getRangeAt(0)
            const backward = selectionIsBackward(sel)
            if (backward && selRange.compareBoundaryPoints(Range.START_TO_START, range) < 0)
                this.prev()
            else if (!backward && selRange.compareBoundaryPoints(Range.END_TO_END, range) > 0)
                this.next()
        }, 700)
        this.addEventListener('load', ({ detail: { doc } }) => {
            let isPointerSelecting = false
            doc.addEventListener('pointerdown', () => isPointerSelecting = true)
            doc.addEventListener('pointerup', () => isPointerSelecting = false)
            let isKeyboardSelecting = false
            doc.addEventListener('keydown', () => isKeyboardSelecting = true)
            doc.addEventListener('keyup', () => isKeyboardSelecting = false)
            doc.addEventListener('selectionchange', () => {
                if (this.scrolled) return
                const range = this.#lastVisibleRange
                if (!range) return
                const sel = doc.getSelection()
                if (!sel.rangeCount) return
                if (isPointerSelecting && sel.type === 'Range')
                    checkPointerSelection(range, sel)
                else if (isKeyboardSelecting) {
                    const selRange = sel.getRangeAt(0).cloneRange()
                    const backward = selectionIsBackward(sel)
                    if (!backward) selRange.collapse()
                    this.#scrollToAnchor(selRange)
                }
            })
            doc.addEventListener('focusin', e => this.scrolled ? null :
                // NOTE: `requestAnimationFrame` is needed in WebKit
                requestAnimationFrame(() => this.#scrollToAnchor(e.target)))
        })

        this.#mediaQueryListener = () => {
            if (!this.#view) return
            this.#background.style.background = getBackground(this.#view.document)
        }
        this.#mediaQuery.addEventListener('change', this.#mediaQueryListener)
    }
    attributeChangedCallback(name, _, value) {
        switch (name) {
            case 'flow':
                this.render()
                // Feature #76 WI-2 (Gate-4 Medium): a paged→scrolled flow switch
                // re-renders but the initial #display's container-axis pass may
                // have run while still paginated — re-orient the container BEFORE
                // (re)building the window, so a vertical book entering scrolled
                // mode doesn't stay block-stacked until the next navigation.
                if (this.scrolled && this.#view) this.#applyScrolledContainerAxis()
                // Feature #73 WI-3: the initial #display may have run while flow
                // was still paginated (so its #ensureWindow was gated out). When
                // flow becomes 'scrolled', (re)build the windowed neighbour set.
                if (this.#windowedScroll && this.scrolled && this.#view) this.#ensureWindow()
                break
            case 'gap':
            case 'margin':
            case 'max-block-size':
            case 'max-column-count':
                this.#top.style.setProperty('--_' + name, value)
                break
            case 'max-inline-size':
                // needs explicit `render()` as it doesn't necessarily resize
                this.#top.style.setProperty('--_' + name, value)
                this.render()
                break
        }
    }
    open(book) {
        this.bookDir = book.dir
        this.sections = book.sections
        book.transformTarget?.addEventListener('data', ({ detail }) => {
            if (detail.type !== 'text/css') return
            const w = innerWidth
            const h = innerHeight
            detail.data = Promise.resolve(detail.data).then(data => data
                // unprefix as most of the props are (only) supported unprefixed
                .replace(/(?<=[{\s;])-epub-/gi, '')
                // replace vw and vh as they cause problems with layout
                .replace(/(\d*\.?\d+)vw/gi, (_, d) => parseFloat(d) * w / 100 + 'px')
                .replace(/(\d*\.?\d+)vh/gi, (_, d) => parseFloat(d) * h / 100 + 'px')
                // `page-break-*` unsupported in columns; replace with `column-break-*`
                .replace(/page-break-(after|before|inside)\s*:/gi, (_, x) =>
                    `-webkit-column-break-${x}:`)
                .replace(/break-(after|before|inside)\s*:\s*(avoid-)?page/gi, (_, x, y) =>
                    `break-${x}: ${y ?? ''}column`))
        })
    }
    #createView() {
        // Feature #73 WI-2: a navigation invalidates the windowed neighbour
        // buffer — destroy + remove + UNLOAD every mounted neighbour before the
        // new current view is built; #ensureWindow re-mounts around the new index.
        // Gate-4 M (audit): mirror #evictOutsideWindow — also unload the section
        // data + clear the in-flight mount set so a navigation that interrupts a
        // pending mount can't resurrect a stale neighbour into the new window.
        if (this.#scrolledViews.length) {
            for (const v of this.#scrolledViews) {
                v.destroy()
                if (v.element.parentNode === this.#container) this.#container.removeChild(v.element)
                this.sections[v.wi73Index]?.unload?.()
            }
            this.#scrolledViews = []
        }
        this.#mountingIndices.clear()
        this.#windowGeneration++ // Gate-4 H1: invalidate any in-flight neighbour mounts
        if (this.#view) {
            this.#view.destroy()
            this.#container.removeChild(this.#view.element)
        }
        this.#view = new View({
            container: this,
            onExpand: () => this.#scrollToAnchor(this.#anchor),
        })
        this.#container.append(this.#view.element)
        return this.#view
    }
    // Feature #73 WI-1a: the mounted-view resolvers — the single seam every
    // `#view` consumer will route through. With `#windowedScroll` OFF these
    // return exactly the single `#view`, so behaviour is unchanged; WI-2 fills
    // `#scrolledViews` and WI-5 makes `#currentView()` scroll-position-aware.
    #mountedViews() {
        // WI-3 bugfix: include the anchor `#view` (the current section), not just
        // the neighbour `#scrolledViews` — otherwise multi-doc consumers
        // (getContents/overlays/TTS) miss the section the reader is actually in.
        // Same ordering as `#windowedViews()`.
        if (this.#windowedScroll && this.#scrolledViews.length) return this.#windowedViews()
        return this.#view ? [this.#view] : []
    }
    #currentView() {
        return this.#view
    }
    // Feature #73 WI-2: the windowed-mount primitives (scrolled-gated). These
    // mount NEIGHBOUR sections around the current `#view` into `#scrolledViews`
    // (in section order) so the continuous surface spans more than one section.
    // The current `#view` stays managed by `#createView`/`#display`; eviction
    // (WI-4) and swap replacement (WI-3) build on these.
    #windowRange(current, total, k) {
        if (total <= 0 || k <= 0) return null
        const size = Math.min(k, total)
        const c = Math.min(Math.max(current, 0), total - 1)
        const half = Math.floor((size - 1) / 2)
        let lo = c - half
        let hi = c + (size - 1 - half)
        if (lo < 0) { hi += -lo; lo = 0 }
        if (hi > total - 1) { lo -= (hi - (total - 1)); hi = total - 1 }
        return [Math.max(0, lo), hi]
    }
    #applyCachedStyles(doc) {
        const $$styles = this.#styleMap.get(doc)
        if (!$$styles) return
        const [$beforeStyle, $style] = $$styles
        const s = this.#styles
        if (Array.isArray(s)) { $beforeStyle.textContent = s[0] ?? ''; $style.textContent = s[1] ?? '' }
        else if (s != null) $style.textContent = s
    }
    // Gate-4 round-2 M (audit): unload a section only if the CURRENT generation no
    // longer owns it — i.e. it is neither the anchor (#index) nor a mounted
    // neighbour. An index-only unload from a stale/failed mount could revoke
    // loader resources the fresh window load owns.
    #unloadIfUnowned(index) {
        if (index === this.#index) return
        if (this.#scrolledViews.some(v => v.wi73Index === index)) return
        this.sections[index]?.unload?.()
    }
    async #mountSection(index) {
        if (!this.#canGoToIndex(index)) return null
        if (index === this.#index) return null
        if (this.#scrolledViews.some(v => v.wi73Index === index)) return null
        // WI-3 bugfix: #ensureWindow is called from several paths (#display,
        // #afterScroll, flow change, boundary cross) and #mountSection awaits
        // an async load, so the `scrolledViews.some(...)` dedup above can pass
        // for several concurrent calls before any push completes — double-
        // mounting the same section. Guard with an in-flight index set.
        if (this.#mountingIndices.has(index)) return null
        this.#mountingIndices.add(index)
        // Gate-4 H1: capture the window generation; a navigation/flow change
        // (#createView / destroy) bumps it. After each await we re-check — a
        // stale mount must NOT insert an old section into the rebuilt window.
        const gen = this.#windowGeneration
        try {
        const src = await Promise.resolve(this.sections[index].load())
        if (gen !== this.#windowGeneration || !this.#windowedScroll || !this.scrolled) {
            this.#unloadIfUnowned(index)
            return null
        }
        // WI-6c: a neighbour that grows on a late expand (fonts.ready / reflow)
        // would shift visible content if it sits above the viewport; compensate.
        const view = new View({ container: this, onExpand: () => this.#onNeighbourExpand(view) })
        view.wi73Index = index
        view.wi73Height = 0
        // WI-3 bugfix (device-verified): insert the element into the container
        // BEFORE `view.load`. `View.load` sets `iframe.src` and waits for the
        // iframe's `load` event; a DETACHED iframe has no reliable
        // `contentDocument` / computed style (note View.load's "needs to be
        // visible for computed style"), so loading before insertion silently
        // fails and no neighbour ever mounts. #createView likewise appends the
        // element before #display calls load. The empty view grows 0→content
        // height; #onNeighbourExpand compensates `scrollTop` for above-views as
        // it grows (so no static insert-time height adjustment is needed here).
        // Gate-4 round-2 H (audit): insert in section order against ALL mounted
        // views — the anchor `#view` AND the neighbours. The old code filtered
        // only `#scrolledViews` (excludes `#view`), so once the window had slid
        // and `#view` sat in the middle, a forward neighbour could be inserted
        // before `#view` → DOM order `[1,3,2]` while the sorted indices still
        // READ `[1,2,3]` (masking it from index-only checks). Place the new view
        // after the highest-index mounted view strictly below it; if none is
        // below, before the lowest mounted view.
        const ordered = [this.#view, ...this.#scrolledViews]
            .filter(v => v && v.element?.parentNode === this.#container)
            .map(v => ({ el: v.element, idx: v.wi73Index ?? this.#index }))
            .sort((a, b) => a.idx - b.idx)
        const below = ordered.filter(m => m.idx < index)
        if (below.length) {
            const afterEl = below[below.length - 1].el
            if (afterEl.nextSibling) this.#container.insertBefore(view.element, afterEl.nextSibling)
            else this.#container.append(view.element)
        } else if (ordered.length) {
            this.#container.insertBefore(view.element, ordered[0].el)
        } else {
            this.#container.append(view.element)
        }
        this.#scrolledViews.push(view)
        this.#scrolledViews.sort((a, b) => a.wi73Index - b.wi73Index)
        const afterLoad = doc => {
            if (doc.head) {
                const $styleBefore = doc.createElement('style')
                doc.head.prepend($styleBefore)
                const $style = doc.createElement('style')
                doc.head.append($style)
                this.#styleMap.set(doc, [$styleBefore, $style])
                this.#applyCachedStyles(doc) // Gate-2 H8: style every mounted view
            }
        }
        try {
            await view.load(src, afterLoad, this.#beforeRender.bind(this))
        } catch (e) {
            // unmount the phantom on load failure so the window stays consistent.
            // Gate-4 round-2 M (audit): also unload the section so a repeatedly-
            // failing neighbour doesn't leak loader refs.
            view.destroy()
            if (view.element.parentNode === this.#container) this.#container.removeChild(view.element)
            this.#scrolledViews = this.#scrolledViews.filter(v => v !== view)
            this.#unloadIfUnowned(index)
            throw e
        }
        // Gate-4 H1: if a navigation/flow change landed during the load await,
        // this mount is stale — destroy it instead of leaving a section from the
        // old window stitched into the new one.
        if (gen !== this.#windowGeneration || !this.#windowedScroll || !this.scrolled) {
            view.destroy()
            if (view.element.parentNode === this.#container) this.#container.removeChild(view.element)
            this.#scrolledViews = this.#scrolledViews.filter(v => v !== view)
            this.#unloadIfUnowned(index)
            return null
        }
        // Gate-4 H2: wire the neighbour document the same way the primary path
        // does — dispatch the renderer `load` + `create-overlayer` events so
        // view.js attaches links / cursor / selection / tap handlers and builds
        // the overlayer. Without this, neighbour-section selection + highlights
        // never fire. We deliberately skip #goTo's navigation side effects
        // (old-section unload, setStyles) — this is per-doc wiring only.
        this.dispatchEvent(new CustomEvent('load', { detail: { doc: view.document, index } }))
        this.dispatchEvent(new CustomEvent('create-overlayer', {
            detail: {
                doc: view.document, index,
                attach: overlayer => view.overlayer = overlayer,
            },
        }))
        return view
        } finally {
            this.#mountingIndices.delete(index)
        }
    }
    // Feature #76 WI-3: the active section's scroll model (axis/props/sign),
    // mirroring Swift FoliateScrollModel. The windowed primitives below read the
    // axis through these helpers instead of hardcoding scrollTop/height/top, so
    // the horizontal-writing (#73) path resolves to the IDENTICAL expressions
    // (scrollProp=scrollTop, sizeProp=height, rectStartProp=top, sign=+1) while a
    // vertical-writing section can later drive the horizontal axis. Defaults to
    // the horizontal-tb model when no view is mounted.
    get #activeScrollModel() {
        return this.#view?.scrollModel ?? scrollModelFor('horizontal-tb')
    }
    // Feature #76 WI-2: lay out scrolled-mode sections along the ACTIVE SCROLL
    // AXIS, so the windowed surface (WI-3) accumulates in the right direction.
    // Horizontal-writing (vertical scroll, axis='vertical') keeps the default
    // BLOCK stacking — no inline style is set, so the #73 path is byte-identical.
    // Vertical-writing (horizontal scroll, axis='horizontal') stacks sections in
    // a flex row so they accumulate along the horizontal axis; vertical-rl
    // (directionSign < 0, later content extends leftward) uses `row-reverse`.
    // Idempotent + reversible (a re-display with a different writing-mode resets
    // the inline style), and called from #display BEFORE the windowing gate so it
    // applies even while #ensureWindow still returns early for vertical (WI-3
    // removes that gate).
    #applyScrolledContainerAxis() {
        const m = this.#activeScrollModel
        if (m.axis === 'horizontal') {
            this.#container.style.display = 'flex'
            this.#container.style.flexDirection = 'row'
            // Gate-4 High: the host forces `dir=rtl` for EVERY vertical book
            // (`:1146`, incl. vertical-lr), and `direction` inherits into the
            // shadow tree — so a `row-reverse` here would DOUBLE-reverse
            // vertical-rl and vertical-lr would still mismatch. Instead set the
            // container's logical direction EXPLICITLY from the scroll model and
            // keep a plain `row`: vertical-rl (directionSign < 0) → `rtl` (later
            // sections extend leftward, scroll origin on the right, matching
            // WebKit's negative scrollLeft that `#axisScrollOffset` un-signs);
            // vertical-lr → `ltr`.
            this.#container.style.direction = m.directionSign < 0 ? 'rtl' : 'ltr'
        } else {
            this.#container.style.removeProperty('display')
            this.#container.style.removeProperty('flex-direction')
            this.#container.style.removeProperty('direction')
        }
    }
    // Logical (non-negative, reading-order) scroll offset of the container along
    // the active axis. For vertical-rl, WebKit's `scrollLeft` is negative toward
    // later content, so the sign maps it positive. horizontal-tb: == scrollTop.
    #axisScrollOffset() {
        const m = this.#activeScrollModel
        const raw = this.#container[m.scrollProp]
        return m.directionSign < 0 ? -raw : raw
    }
    #setAxisScrollOffset(logical) {
        const m = this.#activeScrollModel
        this.#container[m.scrollProp] = m.directionSign < 0 ? -logical : logical
    }
    // Element extent along the active axis. horizontal-tb: == rect.height.
    #elementAxisSize(el) {
        return Math.max(0, el.getBoundingClientRect()[this.#activeScrollModel.sizeProp])
    }
    // Element's logical start offset within the container's scroll content along
    // the active axis (axis-aware generalization of the old #elementScrollTop).
    // horizontal-tb: rect.top - container.top + scrollTop — byte-identical.
    #elementAxisStart(el) {
        const m = this.#activeScrollModel
        const rawDelta = el.getBoundingClientRect()[m.rectStartProp]
            - this.#container.getBoundingClientRect()[m.rectStartProp]
        return (m.directionSign < 0 ? -rawDelta : rawDelta) + this.#axisScrollOffset()
    }
    // WI-6c: when a mounted neighbour's size changes after layout (fonts.ready,
    // image load, reflow), shift the axis scroll offset by the delta IF the
    // neighbour sits before the current scroll position — so visible content
    // does not jump. (#76 WI-3: axis-aware; horizontal-tb == the old scrollTop+height path.)
    #onNeighbourExpand(view) {
        if (!this.#windowedScroll || !view?.element) return
        const prev = view.wi73Height ?? 0
        const now = this.#elementAxisSize(view.element)
        view.wi73Height = now
        const delta = now - prev
        if (delta === 0) return
        // a view whose start is before the viewport start contributes its full
        // size to everything after it; growing it pushes later content along.
        if (this.#elementAxisStart(view.element) < this.#axisScrollOffset()) {
            this.#setAxisScrollOffset(Math.max(0, this.#axisScrollOffset() + delta))
        }
    }
    async #ensureWindow() {
        // Gate-4 H (audit): the windowed coordinate math (#elementScrollTop /
        // #windowedResolve / eviction + expand compensation) is vertical-scroll
        // (top/height/scrollTop) only. Vertical-WRITING scrolled mode scrolls on
        // the horizontal axis, so scope windowing to horizontal writing for now —
        // vertical writing falls back to the proven per-section swap (window stays
        // empty → all resolvers return the single `#view`).
        if (!this.#windowedScroll || !this.scrolled || this.#vertical) return
        const range = this.#windowRange(this.#index, this.sections.length, this.#K)
        if (!range) return
        const [lo, hi] = range
        for (let i = lo; i <= hi; i++) {
            if (i === this.#index) continue
            if (!this.#scrolledViews.some(v => v.wi73Index === i)) {
                try { await this.#mountSection(i) } catch (e) { console.warn('WI73 mount', i, e) }
            }
        }
        this.#evictOutsideWindow(lo, hi)
    }
    // Feature #73 WI-4: bound memory to the K-window. Unmount + unload any
    // neighbour outside [lo,hi]; the anchor `#view` (#index) is never in
    // `#scrolledViews` so it can't be evicted. Evicting a section ABOVE the
    // viewport removes content above the scroll position, shifting everything
    // up — so subtract the evicted-above heights from `scrollTop` to keep the
    // visible content stationary (FoliateScrolledWindowMath.offsetAdjustmentOnEvict).
    #evictOutsideWindow(lo, hi) {
        const keep = []
        let scrollAdjust = 0
        for (const v of this.#scrolledViews) {
            const idx = v.wi73Index
            if (idx >= lo && idx <= hi) { keep.push(v); continue }
            if (idx < this.#index) {
                // #76 WI-3: axis-aware extent (horizontal-tb == rect.height).
                scrollAdjust += this.#elementAxisSize(v.element)
            }
            v.destroy()
            if (v.element.parentNode === this.#container) this.#container.removeChild(v.element)
            this.sections[idx]?.unload?.()
        }
        this.#scrolledViews = keep
        if (scrollAdjust > 0) {
            this.#setAxisScrollOffset(Math.max(0, this.#axisScrollOffset() - scrollAdjust))
        }
    }
    // Feature #73 WI-3/WI-5: resolve the CURRENT section + intra-section fraction
    // from the live scroll position over the mounted views (the anchor `#view`
    // plus its neighbours), so windowed crossing is native scroll — no swap.
    #elementScrollTop(el) {
        // #76 WI-3: delegate to the axis-aware helper. horizontal-tb resolves to
        // the identical `rect.top - container.top + scrollTop`.
        return this.#elementAxisStart(el)
    }
    #windowedViews() {
        return [this.#view, ...this.#scrolledViews]
            .filter(Boolean)
            .sort((a, b) => (a.wi73Index ?? this.#index) - (b.wi73Index ?? this.#index))
    }
    #windowedResolve() {
        const views = this.#windowedViews()
        if (!views.length) return { view: this.#view, index: this.#index, intra: 0 }
        if (this.#view && this.#view.wi73Index == null) this.#view.wi73Index = this.#index
        // #76 WI-3: resolve along the active axis (horizontal-tb == scrollTop/height).
        const offset = this.#axisScrollOffset()
        for (const v of views) {
            const start = this.#elementAxisStart(v.element)
            const size = this.#elementAxisSize(v.element)
            if (offset < start + size - 1) {
                const idx = v.wi73Index ?? this.#index
                const intra = size > 0 ? Math.min(Math.max((offset - start) / size, 0), 1) : 0
                return { view: v, index: idx, intra }
            }
        }
        const last = views[views.length - 1]
        return { view: last, index: last.wi73Index ?? this.#index, intra: 1 }
    }
    // Feature #73 WI-6a: keep `#view` pointing at the section the viewport top is
    // in — a POINTER swap, not a DOM move (no flash). After a swap-free crossing
    // the single-`#view` getters (viewSize / pages / #getRectMapper /
    // getVisibleRange / #background / atStart / atEnd) all read the correct
    // section. The old `#view` is demoted into `#scrolledViews` (it stays mounted
    // in the container); the resolved view leaves `#scrolledViews` to become `#view`.
    #promoteCurrentView(resolved) {
        if (!resolved?.view || resolved.view === this.#view) {
            if (resolved) this.#index = resolved.index
            return
        }
        const old = this.#view
        if (old) {
            if (old.wi73Index == null) old.wi73Index = this.#index
            if (!this.#scrolledViews.includes(old)) this.#scrolledViews.push(old)
        }
        this.#scrolledViews = this.#scrolledViews.filter(v => v !== resolved.view)
        this.#view = resolved.view
        this.#index = resolved.index
        // the promoted view becomes the new background source
        if (this.#view?.document) this.#background.style.background = getBackground(this.#view.document)
    }
    // Feature #73 WI-6b: `start` is container-absolute (it spans every view
    // mounted ABOVE the current one). Per-`#view` document operations need the
    // offset RELATIVE to the current view's position in the container. Flag OFF
    // (or no neighbours) → one view at offset 0 → relative == absolute.
    #viewRelativeStart() {
        // Gate-4 H: vertical-writing scroll is horizontal-axis; the windowed
        // helpers are vertical-only, so vertical writing keeps the container-
        // absolute `start` (windowing is disabled for it in #ensureWindow).
        if (!this.#windowedScroll || !this.#view || this.#vertical) return this.start
        return Math.max(0, this.#container.scrollTop - this.#elementScrollTop(this.#view.element))
    }
    #beforeRender({ vertical, rtl, background }) {
        this.#vertical = vertical
        this.#rtl = rtl
        this.#top.classList.toggle('vertical', vertical)

        // set background to `doc` background
        // this is needed because the iframe does not fill the whole element
        this.#background.style.background = background

        const { width, height } = this.#container.getBoundingClientRect()
        const size = vertical ? height : width

        const style = getComputedStyle(this.#top)
        const maxInlineSize = parseFloat(style.getPropertyValue('--_max-inline-size'))
        const maxColumnCount = parseInt(style.getPropertyValue('--_max-column-count-spread'))
        const margin = parseFloat(style.getPropertyValue('--_margin'))
        this.#margin = margin

        const g = parseFloat(style.getPropertyValue('--_gap')) / 100
        // The gap will be a percentage of the #container, not the whole view.
        // This means the outer padding will be bigger than the column gap. Let
        // `a` be the gap percentage. The actual percentage for the column gap
        // will be (1 - a) * a. Let us call this `b`.
        //
        // To make them the same, we start by shrinking the outer padding
        // setting to `b`, but keep the column gap setting the same at `a`. Then
        // the actual size for the column gap will be (1 - b) * a. Repeating the
        // process again and again, we get the sequence
        //     x₁ = (1 - b) * a
        //     x₂ = (1 - x₁) * a
        //     ...
        // which converges to x = (1 - x) * a. Solving for x, x = a / (1 + a).
        // So to make the spacing even, we must shrink the outer padding with
        //     f(x) = x / (1 + x).
        // But we want to keep the outer padding, and make the inner gap bigger.
        // So we apply the inverse, f⁻¹ = -x / (x - 1) to the column gap.
        const gap = -g / (g - 1) * size

        const flow = this.getAttribute('flow')
        if (flow === 'scrolled') {
            // FIXME: vertical-rl only, not -lr
            this.setAttribute('dir', vertical ? 'rtl' : 'ltr')
            this.#top.style.padding = '0'
            const columnWidth = maxInlineSize

            this.heads = null
            this.feet = null
            this.#header.replaceChildren()
            this.#footer.replaceChildren()

            return { flow, margin, gap, columnWidth }
        }

        const divisor = Math.min(maxColumnCount, Math.ceil(size / maxInlineSize))
        const columnWidth = (size / divisor) - gap
        this.setAttribute('dir', rtl ? 'rtl' : 'ltr')

        const marginalDivisor = vertical
            ? Math.min(2, Math.ceil(width / maxInlineSize))
            : divisor
        const marginalStyle = {
            gridTemplateColumns: `repeat(${marginalDivisor}, 1fr)`,
            gap: `${gap}px`,
            direction: this.bookDir === 'rtl' ? 'rtl' : 'ltr',
        }
        Object.assign(this.#header.style, marginalStyle)
        Object.assign(this.#footer.style, marginalStyle)
        const heads = makeMarginals(marginalDivisor, 'head')
        const feet = makeMarginals(marginalDivisor, 'foot')
        this.heads = heads.map(el => el.children[0])
        this.feet = feet.map(el => el.children[0])
        this.#header.replaceChildren(...heads)
        this.#footer.replaceChildren(...feet)

        return { height, width, margin, gap, columnWidth }
    }
    render() {
        if (!this.#view) return
        const layout = this.#beforeRender({
            vertical: this.#vertical,
            rtl: this.#rtl,
        })
        // Gate-4 M7: re-render mounted neighbours with the same layout so a resize
        // / margin / flow change keeps their dimensions in sync — stale neighbour
        // heights would corrupt the windowed offset math + eviction compensation.
        // Flag OFF → #scrolledViews empty → only #view renders (unchanged).
        for (const v of this.#scrolledViews) v.render(layout)
        this.#view.render(layout)
        this.#scrollToAnchor(this.#anchor)
    }
    get scrolled() {
        return this.getAttribute('flow') === 'scrolled'
    }
    get scrollProp() {
        const { scrolled } = this
        return this.#vertical ? (scrolled ? 'scrollLeft' : 'scrollTop')
            : scrolled ? 'scrollTop' : 'scrollLeft'
    }
    get sideProp() {
        const { scrolled } = this
        return this.#vertical ? (scrolled ? 'width' : 'height')
            : scrolled ? 'height' : 'width'
    }
    get size() {
        return this.#container.getBoundingClientRect()[this.sideProp]
    }
    get viewSize() {
        return this.#view.element.getBoundingClientRect()[this.sideProp]
    }
    get start() {
        return Math.abs(this.#container[this.scrollProp])
    }
    get end() {
        return this.start + this.size
    }
    get page() {
        return Math.floor(((this.start + this.end) / 2) / this.size)
    }
    get pages() {
        return Math.round(this.viewSize / this.size)
    }
    scrollBy(dx, dy) {
        const delta = this.#vertical ? dy : dx
        const element = this.#container
        const { scrollProp } = this
        const [offset, a, b] = this.#scrollBounds
        const rtl = this.#rtl
        const min = rtl ? offset - b : offset - a
        const max = rtl ? offset + a : offset + b
        element[scrollProp] = Math.max(min, Math.min(max,
            element[scrollProp] + delta))
    }
    snap(vx, vy) {
        const velocity = this.#vertical ? vy : vx
        const [offset, a, b] = this.#scrollBounds
        const { start, end, pages, size } = this
        const min = Math.abs(offset) - a
        const max = Math.abs(offset) + b
        const d = velocity * (this.#rtl ? -size : size)
        const page = Math.floor(
            Math.max(min, Math.min(max, (start + end) / 2
                + (isNaN(d) ? 0 : d))) / size)

        this.#scrollToPage(page, 'snap').then(() => {
            const dir = page <= 0 ? -1 : page >= pages - 1 ? 1 : null
            if (dir) return this.#goTo({
                index: this.#adjacentIndex(dir),
                anchor: dir < 0 ? () => 1 : () => 0,
            })
        })
    }
    #onTouchStart(e) {
        const touch = e.changedTouches[0]
        this.#touchState = {
            x: touch?.screenX, y: touch?.screenY,
            t: e.timeStamp,
            vx: 0, xy: 0,
        }
    }
    #onTouchMove(e) {
        const state = this.#touchState
        if (state.pinched) return
        state.pinched = globalThis.visualViewport.scale > 1
        if (this.scrolled || state.pinched) return
        if (e.touches.length > 1) {
            if (this.#touchScrolled) e.preventDefault()
            return
        }
        e.preventDefault()
        const touch = e.changedTouches[0]
        const x = touch.screenX, y = touch.screenY
        const dx = state.x - x, dy = state.y - y
        const dt = e.timeStamp - state.t
        state.x = x
        state.y = y
        state.t = e.timeStamp
        state.vx = dx / dt
        state.vy = dy / dt
        this.#touchScrolled = true
        this.scrollBy(dx, dy)
    }
    #onTouchEnd() {
        this.#touchScrolled = false
        if (this.scrolled) return

        // XXX: Firefox seems to report scale as 1... sometimes...?
        // at this point I'm basically throwing `requestAnimationFrame` at
        // anything that doesn't work
        requestAnimationFrame(() => {
            if (globalThis.visualViewport.scale === 1)
                this.snap(this.#touchState.vx, this.#touchState.vy)
        })
    }
    // allows one to process rects as if they were LTR and horizontal
    #getRectMapper() {
        if (this.scrolled) {
            const size = this.viewSize
            const margin = this.#margin
            return this.#vertical
                ? ({ left, right }) =>
                    ({ left: size - right - margin, right: size - left - margin })
                : ({ top, bottom }) => ({ left: top + margin, right: bottom + margin })
        }
        const pxSize = this.pages * this.size
        return this.#rtl
            ? ({ left, right }) =>
                ({ left: pxSize - right, right: pxSize - left })
            : this.#vertical
                ? ({ top, bottom }) => ({ left: top, right: bottom })
                : f => f
    }
    async #scrollToRect(rect, reason) {
        if (this.scrolled) {
            let offset = this.#getRectMapper()(rect).left - this.#margin
            // Feature #73 WI-6c: the rect is in `#view`'s own document
            // coordinates; in windowed mode `#view` may sit at a nonzero
            // container offset, so add its position to land at the right
            // container scroll. Flag OFF → offset 0 → unchanged.
            if (this.#windowedScroll && this.#view && !this.#vertical) offset += this.#elementScrollTop(this.#view.element)
            return this.#scrollTo(offset, reason)
        }
        const offset = this.#getRectMapper()(rect).left
        return this.#scrollToPage(Math.floor(offset / this.size) + (this.#rtl ? -1 : 1), reason)
    }
    async #scrollTo(offset, reason, smooth) {
        const element = this.#container
        const { scrollProp, size } = this
        if (element[scrollProp] === offset) {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
            return
        }
        // FIXME: vertical-rl only, not -lr
        if (this.scrolled && this.#vertical) offset = -offset
        if ((reason === 'snap' || smooth) && this.hasAttribute('animated')) return animate(
            element[scrollProp], offset, 300, easeOutQuad,
            x => element[scrollProp] = x,
        ).then(() => {
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
        })
        else {
            element[scrollProp] = offset
            this.#scrollBounds = [offset, this.atStart ? 0 : size, this.atEnd ? 0 : size]
            this.#afterScroll(reason)
        }
    }
    async #scrollToPage(page, reason, smooth) {
        const offset = this.size * (this.#rtl ? -page : page)
        return this.#scrollTo(offset, reason, smooth)
    }
    async scrollToAnchor(anchor, select) {
        return this.#scrollToAnchor(anchor, select ? 'selection' : 'navigation')
    }
    async #scrollToAnchor(anchor, reason = 'anchor') {
        this.#anchor = anchor
        const rects = uncollapse(anchor)?.getClientRects?.()
        // if anchor is an element or a range
        if (rects) {
            // when the start of the range is immediately after a hyphen in the
            // previous column, there is an extra zero width rect in that column
            const rect = Array.from(rects)
                .find(r => r.width > 0 && r.height > 0) || rects[0]
            if (!rect) return
            await this.#scrollToRect(rect, reason)
            return
        }
        // if anchor is a fraction
        if (this.scrolled) {
            // Feature #73 WI-7 (Gate-5 restore fix): `anchor * viewSize` is the
            // intra-section offset; in windowed mode `#view` may sit at a nonzero
            // container offset (neighbours mounted above), so add its position —
            // otherwise a fraction seek (Bug #265 position restore + the
            // re-assert window) lands too high by the above-sections' height.
            // Same offset gap WI-6c fixed for `#scrollToRect`. Flag OFF → 0.
            let offset = anchor * this.viewSize
            if (this.#windowedScroll && this.#view && !this.#vertical) offset += this.#elementScrollTop(this.#view.element)
            await this.#scrollTo(offset, reason)
            return
        }
        const { pages } = this
        if (!pages) return
        const textPages = pages - 2
        const newPage = Math.round(anchor * (textPages - 1))
        await this.#scrollToPage(newPage + 1, reason)
    }
    #getVisibleRange() {
        if (this.scrolled) {
            // Feature #73 WI-6b: window-relative offsets so the per-`#view`
            // document mapper gets coordinates relative to the current view's
            // position in the container (not the container-absolute `start`,
            // which spans every view mounted above). Flag OFF → start/end.
            const vStart = this.#viewRelativeStart()
            const vEnd = vStart + this.size
            return getVisibleRange(this.#view.document,
                vStart + this.#margin, vEnd - this.#margin, this.#getRectMapper())
        }
        const size = this.#rtl ? -this.size : this.size
        return getVisibleRange(this.#view.document,
            this.start - size, this.end - size, this.#getRectMapper())
    }
    #afterScroll(reason) {
        // Feature #73 WI-5/WI-6a: in windowed scrolled mode, resolve the current
        // section from the live scroll position and PROMOTE `#view` to it BEFORE
        // computing the visible range — so the range + emitted fraction read the
        // section the viewport is actually in, not the stale anchor. The emitted
        // fraction is the Gate-2 C1 INTRA-section value (view.js→SectionProgress
        // still owns whole-book conversion + Bug #265 restore). Non-windowed path
        // unchanged.
        let scrolledFraction = null
        if (this.scrolled && this.#windowedScroll && !this.#vertical) {
            const r = this.#windowedResolve()
            this.#promoteCurrentView(r)
            scrolledFraction = r.intra
            this.#ensureWindow() // WI-3: keep the K-window built around the current section (idempotent)
        }
        const range = this.#getVisibleRange()
        this.#lastVisibleRange = range
        // don't set new anchor if relocation was to scroll to anchor
        if (reason !== 'selection' && reason !== 'navigation' && reason !== 'anchor')
            this.#anchor = range
        else this.#justAnchored = true

        const index = this.#index
        const detail = { reason, range, index }
        if (this.scrolled) detail.fraction = scrolledFraction != null ? scrolledFraction : this.start / this.viewSize
        else if (this.pages > 0) {
            const { page, pages } = this
            this.#header.style.visibility = page > 1 ? 'visible' : 'hidden'
            detail.fraction = (page - 1) / (pages - 2)
            detail.size = 1 / (pages - 2)
        }
        this.dispatchEvent(new CustomEvent('relocate', { detail }))
    }
    async #display(promise) {
        const { index, src, anchor, onLoad, select } = await promise
        this.#index = index
        const hasFocus = this.#view?.document?.hasFocus()
        if (src) {
            const view = this.#createView()
            const afterLoad = doc => {
                if (doc.head) {
                    const $styleBefore = doc.createElement('style')
                    doc.head.prepend($styleBefore)
                    const $style = doc.createElement('style')
                    doc.head.append($style)
                    this.#styleMap.set(doc, [$styleBefore, $style])
                }
                onLoad?.({ doc, index })
            }
            const beforeRender = this.#beforeRender.bind(this)
            await view.load(src, afterLoad, beforeRender)
            this.dispatchEvent(new CustomEvent('create-overlayer', {
                detail: {
                    doc: view.document, index,
                    attach: overlayer => view.overlayer = overlayer,
                },
            }))
            this.#view = view
        }
        await this.scrollToAnchor((typeof anchor === 'function'
            ? anchor(this.#view.document) : anchor) ?? 0, select)
        if (hasFocus) this.focusView()
        // Feature #76 WI-2: orient the scrolled container along the active scroll
        // axis BEFORE the windowing math — runs for vertical-writing even though
        // #ensureWindow still gates it out (WI-3). Horizontal-writing is a no-op
        // (block stacking, byte-identical to #73).
        if (this.scrolled) this.#applyScrolledContainerAxis()
        // Feature #73 WI-2: after the anchor section renders, mount the
        // neighbour window so the scrolled surface spans multiple sections.
        // Gated on #windowedScroll (OFF by default → paged + non-windowed
        // scrolled paths are byte-identical).
        if (this.scrolled && this.#windowedScroll) this.#ensureWindow()
    }
    #canGoToIndex(index) {
        return index >= 0 && index <= this.sections.length - 1
    }
    async #goTo({ index, anchor, select}) {
        if (index === this.#index) await this.#display({ index, anchor, select })
        else {
            const oldIndex = this.#index
            const onLoad = detail => {
                this.sections[oldIndex]?.unload?.()
                this.setStyles(this.#styles)
                this.dispatchEvent(new CustomEvent('load', { detail }))
            }
            await this.#display(Promise.resolve(this.sections[index].load())
                .then(src => ({ index, src, anchor, onLoad, select }))
                .catch(e => {
                    console.warn(e)
                    console.warn(new Error(`Failed to load section ${index}`))
                    return {}
                }))
        }
    }
    async goTo(target) {
        if (this.#locked) return
        const resolved = await target
        if (this.#canGoToIndex(resolved.index)) return this.#goTo(resolved)
    }
    #scrollPrev(distance) {
        if (!this.#view) return true
        if (this.scrolled) {
            // Feature #73 H4: in windowed mode the scrollable surface is the whole
            // container (all mounted sections), not just `#view`. Scroll within it
            // and let the scroll-driven promote/#ensureWindow slide the window; only
            // fall through to #goTo at the true top of the book.
            if (this.#windowedScroll && !this.#vertical) {
                const top = this.#container.scrollTop
                if (top > 0) return this.#scrollTo(Math.max(0, top - (distance ?? this.size)), null, true)
                return this.#adjacentIndex(-1) != null
            }
            if (this.start > 0) return this.#scrollTo(
                Math.max(0, this.start - (distance ?? this.size)), null, true)
            return true
        }
        if (this.atStart) return
        const page = this.page - 1
        return this.#scrollToPage(page, 'page', true).then(() => page <= 0)
    }
    #scrollNext(distance) {
        if (!this.#view) return true
        if (this.scrolled) {
            if (this.#windowedScroll && !this.#vertical) {
                const c = this.#container
                const remaining = c.scrollHeight - (c.scrollTop + c.clientHeight)
                if (remaining > 2) return this.#scrollTo(c.scrollTop + (distance ?? this.size), null, true)
                return this.#adjacentIndex(1) != null
            }
            if (this.viewSize - this.end > 2) return this.#scrollTo(
                Math.min(this.viewSize, distance ? this.start + distance : this.end), null, true)
            return true
        }
        if (this.atEnd) return
        const page = this.page + 1
        const pages = this.pages
        return this.#scrollToPage(page, 'page', true).then(() => page >= pages - 1)
    }
    get atStart() {
        return this.#adjacentIndex(-1) == null && this.page <= 1
    }
    get atEnd() {
        return this.#adjacentIndex(1) == null && this.page >= this.pages - 2
    }
    #adjacentIndex(dir) {
        for (let index = this.#index + dir; this.#canGoToIndex(index); index += dir)
            if (this.sections[index]?.linear !== 'no') return index
    }
    async #turnPage(dir, distance) {
        if (this.#locked) return
        this.#locked = true
        const prev = dir === -1
        const shouldGo = await (prev ? this.#scrollPrev(distance) : this.#scrollNext(distance))
        if (shouldGo) await this.#goTo({
            index: this.#adjacentIndex(dir),
            anchor: prev ? () => 1 : () => 0,
        })
        if (shouldGo || !this.hasAttribute('animated')) await wait(100)
        this.#locked = false
    }
    // Bug #235 (GH #983): cross-section continuity for scrolled mode.
    // Native scrolling alone cannot leave the current section because
    // each section is rendered into a single iframe-backed #view; the
    // user hits the section edge and stops. Detect that edge DURING
    // the live scroll (called from the immediate scroll listener that
    // fires every native scroll event, ~60Hz under a fling) and feed
    // the result through the same #turnPage() pipeline that programmatic
    // next()/prev() uses — so the user gets a continuous reading flow
    // without any new chrome and without the quarter-second lag a
    // post-settle debounce would impose. The separate 250ms-debounced
    // listener still owns relocate / anchor maintenance (it calls
    // #afterScroll('scroll') so other observers see the new offset).
    //
    // Gates:
    //   * scrolled mode only — paged mode already advances sections via
    //     #scrollNext / #scrollPrev's page-bound exhaustion path.
    //   * not locked — #turnPage owns the transition lock; firing here
    //     while another transition is in flight would double-advance
    //     and drop the user's position.
    //   * #view exists — guards against firing during teardown.
    //   * adjacent section exists in the same direction — guards
    //     against scrolling past the first/last chapter.
    //
    // Re-entrancy under fling: the immediate listener fires per scroll
    // event. The first time atEnd/atStart resolves true, we call
    // #turnPage(±1), which sets #locked=true synchronously (before its
    // first await). Subsequent same-fling scroll events then short-
    // circuit on `#locked`. The new section's programmatic
    // scrollToAnchor sets #justAnchored=true, which the immediate
    // listener checks before invoking this helper, so the post-load
    // landing scroll events do not re-trigger a cross-section advance.
    //
    // Boundary epsilons mirror upstream Foliate's own asymmetric
    // thresholds so this helper does not fire one frame earlier than
    // #scrollPrev / #scrollNext would on the same input:
    //   atEnd matches #scrollNext's "viewSize - end > 2" (2px slack
    //     for sub-pixel residual after animated scrollTo).
    //   atStart matches #scrollPrev's "start > 0" (no slack — start
    //     is clamped at 0 by native scroll).
    #maybeCrossSectionBoundary() {
        if (!this.scrolled) return
        if (this.#locked) return
        if (!this.#view) return
        // Feature #73 WI-3: in windowed mode the neighbour sections are already
        // mounted contiguously, so a boundary crossing is just native scroll —
        // do NOT swap. Track the current section live from the scroll position
        // and keep the K-window mounted ahead/behind. (D1 offset-reset gone:
        // there is no scrollToAnchor(0) reset, the scroll simply continues.)
        if (this.#windowedScroll && !this.#vertical) {
            const r = this.#windowedResolve()
            this.#promoteCurrentView(r) // WI-6a: track `#view` to the viewport's section
            this.#ensureWindow()
            return
        }
        const atEnd = this.viewSize - this.end <= 2
        const atStart = this.start <= 0
        if (atEnd && this.#adjacentIndex(1) != null) {
            this.#turnPage(1)
        } else if (atStart && this.#adjacentIndex(-1) != null) {
            this.#turnPage(-1)
        }
    }
    prev(distance) {
        return this.#turnPage(-1, distance)
    }
    next(distance) {
        return this.#turnPage(1, distance)
    }
    prevSection() {
        return this.goTo({ index: this.#adjacentIndex(-1) })
    }
    nextSection() {
        return this.goTo({ index: this.#adjacentIndex(1) })
    }
    firstSection() {
        const index = this.sections.findIndex(section => section.linear !== 'no')
        return this.goTo({ index })
    }
    lastSection() {
        const index = this.sections.findLastIndex(section => section.linear !== 'no')
        return this.goTo({ index })
    }
    getContents() {
        // Feature #73 WI-1a: route the multi-doc consumer (Gate-2 M11 / round-2
        // H1) through `#mountedViews()`. Flag OFF → `[this.#view]` → byte-identical
        // to the old single-view return; WI-7 makes each mounted view carry its
        // own section index for cross-section selection/overlay/TTS.
        return this.#mountedViews().map(v => ({
            index: v.wi73Index ?? this.#index, // WI-7: each mounted view carries its own section index
            overlayer: v.overlayer,
            doc: v.document,
        }))
    }
    setStyles(styles) {
        this.#styles = styles
        // Gate-4 M (audit): apply the theme/typography style pair to EVERY mounted
        // view, not just `#view` — otherwise windowed neighbours keep the old CSS
        // (stale theme/font, and a height change that desyncs the offset math)
        // until they're evicted + remounted. Flag OFF → only `#view` is mounted.
        for (const view of this.#mountedViews()) {
            const $$styles = this.#styleMap.get(view?.document)
            if (!$$styles) continue
            const [$beforeStyle, $style] = $$styles
            if (Array.isArray(styles)) {
                const [beforeStyle, style] = styles
                $beforeStyle.textContent = beforeStyle
                $style.textContent = style
            } else $style.textContent = styles
            // needed because the resize observer doesn't work in Firefox
            view?.document?.fonts?.ready?.then(() => view.expand())
        }

        // NOTE: needs `requestAnimationFrame` in Chromium
        requestAnimationFrame(() => {
            if (this.#view?.document) this.#background.style.background = getBackground(this.#view.document)
        })
    }
    focusView() {
        this.#view.document.defaultView.focus()
    }
    destroy() {
        this.#observer.unobserve(this)
        // Gate-4 M (audit): tear down the windowed neighbour buffer too — destroy
        // their Views (releasing each View's ResizeObserver) + unload sections —
        // else closing the reader while windowed leaks live observers.
        for (const v of this.#scrolledViews) {
            v.destroy()
            if (v.element.parentNode === this.#container) this.#container.removeChild(v.element)
            this.sections[v.wi73Index]?.unload?.()
        }
        this.#scrolledViews = []
        this.#mountingIndices.clear()
        this.#windowGeneration++ // Gate-4 H1: invalidate any in-flight neighbour mounts
        this.#view.destroy()
        this.#view = null
        this.sections[this.#index]?.unload?.()
        this.#mediaQuery.removeEventListener('change', this.#mediaQueryListener)
    }
}

customElements.define('foliate-paginator', Paginator)
