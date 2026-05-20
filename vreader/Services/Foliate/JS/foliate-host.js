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

    // Feature #56 WI-11: per-section ordered identifiers for the
    // bilingual translation cache. The unit identifier is the
    // section's index (stringified). A stable index per render is
    // sufficient — Foliate's `view.book.sections` ordering matches
    // the rendered section order; the cache row is keyed by the
    // book's fingerprintKey + this index + the prompt version, so a
    // book reopen looks up the same cached chapter translations.
    async bilingualSectionIDs() {
        if (!bookReady || !currentBook?.sections) return []
        const ids = []
        for (let i = 0; i < currentBook.sections.length; i++) {
            const s = currentBook.sections[i]
            if (typeof s?.createDocument !== 'function') continue
            ids.push(String(i))
        }
        return ids
    },

    // Feature #56 WI-11: per-section source text for the bilingual
    // translation pipeline. Mirrors `extractPlainText`'s
    // `createDocument()` walk but for a single section, so the
    // `FoliateChapterTextProvider` actor can fetch one unit at a
    // time without re-walking the whole book.
    //
    // `unitID` is the stringified section index (matches what
    // `bilingualSectionIDs` returns). Returns '' on any failure
    // (missing section, parse error, empty body) — translation is
    // a decoration, partial text is the right failure mode.
    async bilingualSectionText(unitID) {
        if (!bookReady || !currentBook?.sections) return ''
        const idx = parseInt(unitID, 10)
        if (isNaN(idx) || idx < 0 || idx >= currentBook.sections.length) {
            return ''
        }
        const s = currentBook.sections[idx]
        if (typeof s?.createDocument !== 'function') return ''
        try {
            const doc = await s.createDocument()
            return (doc?.body?.textContent ?? '').trim()
        } catch (e) {
            console.warn('[foliate-host] bilingualSectionText section failed:', e)
            return ''
        }
    },

    // Feature #56 WI-11: walk a specific section's rendered DOM,
    // stamp a stable `data-vreader-bid` attribute on each
    // translatable block (`p` / `li` / `blockquote` / `pre` / `dd`
    // / `dt` — same set the EPUB renderer enumerates), and post
    // an ordered `[{bid, text, sectionIndex}]` payload back to
    // Swift via the `bilingualEnumerate` channel.
    //
    // Gate-4 audit finding H2: in paginated mode foliate-js can
    // keep multiple section docs loaded simultaneously
    // (`view.renderer.getContents()` returns `[{doc, index}]`
    // for every retained section). Walking them all and posting
    // one flat block list would let one unit's translation map
    // spill into adjacent sections. We therefore (a) tag every
    // emitted block with its section's `index`, and (b) accept
    // an optional `targetSectionIndex` so the caller can scope
    // the enumerate to one section. When omitted, every loaded
    // section is enumerated and the Swift pipeline partitions
    // by the per-block `sectionIndex`.
    //
    // The rendered DOM lives inside the section's iframe / shadow
    // root, reachable only via `view.renderer.getContents()`. A
    // re-enumerate after inject keeps existing `data-vreader-bid`
    // values (idempotent stamp) so a section re-render does not
    // shift the cache-key mapping. Decoration siblings carrying
    // `data-vreader-decoration` are skipped so a re-enumerate
    // never stamps a translation block.
    //
    // Gate-4 audit finding M2: an existing
    // `data-vreader-bid` from third-party book HTML cannot be
    // trusted — a hostile attribute value would break the
    // attribute-selector lookup in `bilingualInject` and abort
    // the whole pass. We re-stamp any pre-existing bid whose
    // value does not match the trusted `^fb\d+$` shape so the
    // selector is always over content we wrote.
    bilingualEnumerate(targetSectionIndex) {
        // Gate-4 round-3 audit fix: wrap the payload in
        // `{requestedSectionIndex, blocks}` so the Swift container
        // can call `clearBlocks(forSection:)` when an enumerate
        // returns empty — a previously-populated section that
        // re-enumerates to `[]` (re-render, failure) would otherwise
        // leave a stale per-section cache. `null` means "no scope
        // requested" — used by the legacy bulk-walk path.
        const reqIdx = (targetSectionIndex == null) ? null : targetSectionIndex
        try {
            const contents = view.renderer?.getContents?.()
            if (!Array.isArray(contents) || contents.length === 0) {
                post('bilingualEnumerate', {
                    requestedSectionIndex: reqIdx,
                    blocks: [],
                })
                return
            }
            const BLOCK_TAGS = {
                p: 1, li: 1, blockquote: 1, pre: 1, dd: 1, dt: 1,
            }
            const TRUSTED_BID = /^fb\d+$/
            const out = []
            for (const entry of contents) {
                const doc = entry?.doc
                if (!doc) continue
                const sectionIndex = (typeof entry.index === 'number')
                    ? entry.index : -1
                if (targetSectionIndex != null
                    && sectionIndex !== targetSectionIndex) {
                    continue
                }
                const all = doc.body
                    ? doc.body.getElementsByTagName('*')
                    : doc.getElementsByTagName('*')
                let seq = (doc.__vreaderBilingualSeq ?? 0)
                for (let i = 0; i < all.length; i++) {
                    const el = all[i]
                    const tag = (el.localName || '').toLowerCase()
                    if (!BLOCK_TAGS[tag]) continue
                    if (el.hasAttribute && el.hasAttribute('data-vreader-decoration')) {
                        continue
                    }
                    let txt = el.textContent || ''
                    txt = txt.replace(/\s+/g, ' ').trim()
                    if (!txt) continue
                    let bid = el.getAttribute('data-vreader-bid')
                    if (!bid || !TRUSTED_BID.test(bid)) {
                        seq += 1
                        bid = 'fb' + seq
                        el.setAttribute('data-vreader-bid', bid)
                    }
                    out.push({
                        bid: bid,
                        text: txt,
                        sectionIndex: sectionIndex,
                    })
                }
                doc.__vreaderBilingualSeq = seq
            }
            post('bilingualEnumerate', {
                requestedSectionIndex: reqIdx,
                blocks: out,
            })
        } catch (e) {
            console.warn('[foliate-host] bilingualEnumerate failed:', e)
            post('bilingualEnumerate', {
                requestedSectionIndex: reqIdx,
                blocks: [],
            })
        }
    },

    // Feature #56 WI-11: inject a translation `<div>` after each
    // stamped block in a specific section's DOM. `opts` is the
    // payload `FoliateBilingualJS.bilingualInjectJS` emits:
    //
    //   { translations: {bid: text, ...},
    //     decorationAttribute, blockIDAttribute, blockClassName,
    //     styleCssText,
    //     targetSectionIndex: Int | null }
    //
    // Gate-4 audit finding H2: scope the inject walk to the
    // requested section. With multiple sections loaded
    // simultaneously (paginated mode), an unscoped walk would
    // let one unit's translations leak into adjacent sections.
    // `targetSectionIndex == null` falls back to "every loaded
    // section" (the original behaviour) so a future bulk-inject
    // path stays open.
    //
    // Gate-4 audit finding M2: bid keys come from the (trusted)
    // Swift Pipeline and were stamped by `bilingualEnumerate`'s
    // re-stamping logic (any third-party value not matching
    // `^fb\d+$` is overwritten before its bid enters the
    // pipeline). Even so, we use `CSS.escape` defensively so the
    // selector is always well-formed regardless of upstream
    // contract changes.
    //
    // Idempotent: if a decoration sibling already exists for a
    // block, its `textContent` is replaced in place rather than a
    // second sibling appended.
    bilingualInject(opts) {
        try {
            const translations = opts?.translations || {}
            const DECO = opts?.decorationAttribute || 'data-vreader-decoration'
            const BID = opts?.blockIDAttribute || 'data-vreader-bid'
            const CLS = opts?.blockClassName || 'vreader-bilingual'
            const STYLE = opts?.styleCssText ||
                'user-select: none; -webkit-user-select: none;'
            const targetSectionIndex = opts?.targetSectionIndex

            const contents = view.renderer?.getContents?.()
            if (!Array.isArray(contents) || contents.length === 0) return
            const esc = (typeof CSS !== 'undefined' && CSS.escape)
                ? CSS.escape
                : (s) => String(s).replace(/[^a-zA-Z0-9_-]/g, '\\$&')
            for (const entry of contents) {
                const doc = entry?.doc
                if (!doc) continue
                const sectionIndex = (typeof entry.index === 'number')
                    ? entry.index : -1
                if (targetSectionIndex != null
                    && sectionIndex !== targetSectionIndex) {
                    continue
                }
                for (const bid in translations) {
                    if (!Object.prototype.hasOwnProperty.call(translations, bid)) {
                        continue
                    }
                    const block = doc.querySelector(
                        '[' + BID + '="' + esc(bid) + '"]'
                    )
                    if (!block) continue
                    const next = block.nextElementSibling
                    if (next
                        && next.hasAttribute
                        && next.hasAttribute(DECO)
                        && next.classList
                        && next.classList.contains(CLS)) {
                        next.textContent = translations[bid]
                        continue
                    }
                    const div = doc.createElement('div')
                    div.className = CLS
                    div.setAttribute(DECO, '')
                    div.style.cssText = STYLE
                    div.textContent = translations[bid]
                    if (block.parentNode) {
                        block.parentNode.insertBefore(div, block.nextSibling)
                    }
                }
            }
        } catch (e) {
            console.warn('[foliate-host] bilingualInject failed:', e)
        }
    },

    // Feature #56 WI-11: remove every `vreader-bilingual` node from
    // loaded section DOMs. With `targetSectionIndex` omitted, walks
    // every section (the safe default on disable / book close).
    // Safe to run multiple times — an empty NodeList is a no-op.
    bilingualClear(targetSectionIndex) {
        try {
            const contents = view.renderer?.getContents?.()
            if (!Array.isArray(contents) || contents.length === 0) return
            for (const entry of contents) {
                const doc = entry?.doc
                if (!doc) continue
                const sectionIndex = (typeof entry.index === 'number')
                    ? entry.index : -1
                if (targetSectionIndex != null
                    && sectionIndex !== targetSectionIndex) {
                    continue
                }
                const nodes = doc.querySelectorAll(
                    '.vreader-bilingual[data-vreader-decoration]'
                )
                for (let i = 0; i < nodes.length; i++) {
                    const n = nodes[i]
                    if (n.parentNode) {
                        n.parentNode.removeChild(n)
                    }
                }
            }
        } catch (e) {
            console.warn('[foliate-host] bilingualClear failed:', e)
        }
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
