// Purpose: Bridge adapter between Foliate-js <foliate-view> and VReader Swift host.
// Exposes window.readerAPI for Swift→JS calls.
// Forwards Foliate-js events to webkit.messageHandlers for JS→Swift communication.

import './view.js'

const view = document.getElementById('view')

// --- Helpers ---

function post(name, detail) {
    try {
        window.webkit?.messageHandlers?.[name]?.postMessage(detail ?? {})
    } catch (e) {
        console.error(`[foliate-host] postMessage "${name}" failed:`, e)
    }
}

function serializeRect(rect) {
    if (!rect) return null
    return { x: rect.x, y: rect.y, width: rect.width, height: rect.height }
}

// --- Event Forwarding ---

view.addEventListener('relocate', e => {
    const d = e.detail
    post('relocate', {
        cfi: d.cfi,
        fraction: d.fraction,
        sectionIndex: d.section?.current ?? 0,
        sectionTotal: d.section?.total ?? 1,
        locationCurrent: d.location?.current ?? 0,
        locationTotal: d.location?.total ?? 1,
        tocLabel: d.tocItem?.label ?? null,
        tocHref: d.tocItem?.href ?? null,
        timeSection: d.time?.section ?? null,
        timeTotal: d.time?.total ?? null,
    })
})

view.addEventListener('load', e => {
    post('section-load', {
        index: e.detail.index,
    })
})

view.addEventListener('create-overlay', e => {
    post('create-overlay', {
        index: e.detail.index,
    })
})

view.addEventListener('draw-annotation', e => {
    // Ask Swift for the annotation style
    const { draw, annotation, doc, range } = e.detail
    const value = annotation.value
    // Default to yellow highlight; Swift can override via addAnnotation options
    const color = annotation.color || 'yellow'
    draw(Overlayer.highlight, { color })
})

view.addEventListener('show-annotation', e => {
    post('annotation-show', {
        value: e.detail.value,
        index: e.detail.index,
    })
})

view.addEventListener('external-link', e => {
    e.preventDefault()
    post('external-link', { href: e.detail.href })
})

// Selection tracking
{
    let selectionTimeout = null
    const handleSelection = () => {
        clearTimeout(selectionTimeout)
        selectionTimeout = setTimeout(() => {
            const contents = view.renderer?.getContents?.()
            if (!contents?.length) return
            const { doc, index } = contents[0]
            const sel = doc.getSelection()
            if (!sel || sel.isCollapsed || !sel.rangeCount) {
                post('selection', { collapsed: true })
                return
            }
            const range = sel.getRangeAt(0)
            const text = sel.toString().trim()
            if (!text) return
            const cfi = view.getCFI(index, range)
            const rect = range.getBoundingClientRect()
            post('selection', {
                collapsed: false,
                text,
                cfi,
                index,
                rect: serializeRect(rect),
            })
        }, 300)
    }

    // Listen for selection on each loaded section
    view.addEventListener('load', e => {
        const doc = e.detail.doc
        doc.addEventListener('selectionchange', handleSelection)
    })
}

// Content tap (for toolbar toggle)
view.addEventListener('load', e => {
    const doc = e.detail.doc
    doc.addEventListener('click', event => {
        // Ignore link clicks
        if (event.target.closest('a[href]')) return
        // Ignore if text is selected
        const sel = doc.getSelection()
        if (sel && !sel.isCollapsed) return
        post('tap', {})
    })
})

// Import Overlayer for draw-annotation handler
import { Overlayer } from './overlayer.js'

// --- Public API (Swift → JS) ---

let bookReady = false
let currentBook = null

window.readerAPI = {
    // Open a book from URL (fetched by Foliate-js)
    async open(url) {
        try {
            await view.open(url)
            bookReady = true
            currentBook = view.book

            // Send book metadata and TOC to Swift
            const meta = currentBook.metadata ?? {}
            const toc = currentBook.toc ?? []
            post('book-ready', {
                title: meta.title ?? '',
                author: typeof meta.author === 'string'
                    ? meta.author
                    : meta.author?.join?.(', ') ?? '',
                language: meta.language ?? '',
                toc: serializeTOC(toc),
                sections: currentBook.sections?.length ?? 0,
                layout: currentBook.rendition?.layout ?? 'reflowable',
            })
        } catch (e) {
            post('error', {
                message: e.message ?? String(e),
                type: e.constructor?.name ?? 'Error',
            })
        }
    },

    // Initialize with saved position
    init(opts) {
        if (!opts) return view.init({})
        if (opts.cfi) return view.init({ lastLocation: opts.cfi })
        if (opts.fraction != null) return view.goToFraction(opts.fraction)
        return view.init({})
    },

    // Navigation
    next() { view.next() },
    prev() { view.prev() },
    goLeft() { view.goLeft() },
    goRight() { view.goRight() },
    goTo(target) { view.goTo(target) },
    goToFraction(f) { view.goToFraction(f) },

    // Annotations
    addAnnotation(annotation) { view.addAnnotation(annotation) },
    deleteAnnotation(annotation) { view.deleteAnnotation(annotation) },
    showAnnotation(annotation) { view.showAnnotation(annotation) },

    // Selection
    deselect() { view.deselect() },

    // Search (async generator → posts results)
    async search(opts) {
        try {
            for await (const result of view.search(opts)) {
                if (result === 'done') {
                    post('search-done', {})
                    break
                }
                if (result.progress != null) {
                    post('search-progress', { progress: result.progress })
                } else {
                    post('search-result', result)
                }
            }
        } catch (e) {
            post('error', { message: `Search failed: ${e.message}` })
        }
    },
    clearSearch() { view.clearSearch() },

    // TTS
    async initTTS(granularity) {
        view.initTTS(granularity ?? 'word', range => {
            view.renderer.scrollToAnchor(range)
        })
    },
    tts: {
        start() {
            const ssml = view.tts?.start?.()
            if (ssml) post('tts-ssml', { ssml })
            return ssml
        },
        next() {
            const ssml = view.tts?.next?.()
            if (ssml) post('tts-ssml', { ssml })
            return ssml
        },
        prev() {
            const ssml = view.tts?.prev?.()
            if (ssml) post('tts-ssml', { ssml })
            return ssml
        },
        setMark(mark) { view.tts?.setMark?.(mark) },
    },

    // Theme / Layout
    setStyles(css) {
        view.renderer?.setStyles?.(css)
    },
    setLayout(opts) {
        const r = view.renderer
        if (!r) return
        if (opts.flow) r.setAttribute('flow', opts.flow)
        if (opts.margin != null) r.setAttribute('margin', String(opts.margin))
        if (opts.gap != null) r.setAttribute('gap', String(opts.gap))
        if (opts.maxInlineSize != null) r.setAttribute('max-inline-size', String(opts.maxInlineSize))
        if (opts.maxBlockSize != null) r.setAttribute('max-block-size', String(opts.maxBlockSize))
        if (opts.maxColumnCount != null) r.setAttribute('max-column-count', String(opts.maxColumnCount))
    },

    // Feature #57: whole-book plain-text extraction for TTS.
    // Walks `currentBook.sections` (the same pattern view.search()'s
    // `#searchBook` uses), builds an off-screen Document per section
    // via `createDocument()`, and concatenates the body text. Runs on
    // the host page where `currentBook` is in scope — no shadow-root
    // or iframe traversal. Returns a Promise<string> that
    // evaluateJavaScript is expected to resolve to a Swift String.
    // A section that fails to parse is skipped (partial text is
    // better than no TTS); a book with no sections returns ''.
    async extractPlainText() {
        if (!bookReady || !currentBook?.sections) return ''
        const parts = []
        for (const section of currentBook.sections) {
            if (typeof section.createDocument !== 'function') continue
            try {
                const doc = await section.createDocument()
                const text = (doc?.body?.textContent ?? '').trim()
                if (text) parts.push(text)
            } catch (e) {
                console.warn('[foliate-host] extractPlainText section failed:', e)
            }
        }
        return parts.join('\n\n')
    },

    // Cleanup
    close() {
        view.close()
        bookReady = false
        currentBook = null
    },

    // Debug
    getState() {
        return {
            bookReady,
            lastLocation: view.lastLocation,
            sections: currentBook?.sections?.length ?? 0,
        }
    },
}

// --- Utilities ---

function serializeTOC(toc) {
    if (!toc) return []
    return toc.map(item => ({
        label: item.label ?? '',
        href: item.href ?? '',
        subitems: item.subitems ? serializeTOC(item.subitems) : [],
    }))
}

// Signal to Swift that the bridge is loaded
post('bridge-ready', {})
