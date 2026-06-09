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

// Bug #334: the SINGLE source of the bilingual leaf-block selection. The
// translate path's paragraph count (`bilingualSectionText` → Swift
// `ChapterSegmenter.paragraphs`) MUST equal the enumerate path's block count
// (`bilingualEnumerate`), or the 1:1 inject pairing fails and the translation
// never replaces the loading shimmer (it stays stuck). Both paths walk THIS
// helper so they can never diverge again. Returns the ordered leaf-block
// elements of a section document (document order). A leaf block is a
// `BILINGUAL_BLOCK_TAGS` element that is NOT already a decoration sibling and
// does NOT contain another block (Bug #268 leaf rule), and whose
// whitespace-normalized text is non-empty.
const BILINGUAL_BLOCK_TAGS = { p: 1, li: 1, blockquote: 1, pre: 1, dd: 1, dt: 1 }
const BILINGUAL_BLOCK_SELECTOR = Object.keys(BILINGUAL_BLOCK_TAGS).join(',')

function bilingualNormalizeBlockText(el) {
    return ((el && el.textContent) || '').replace(/\s+/g, ' ').trim()
}

function bilingualLeafBlockElements(doc) {
    if (!doc) return []
    const root = doc.body || doc
    if (!root || !root.getElementsByTagName) return []
    const all = root.getElementsByTagName('*')
    const out = []
    for (let i = 0; i < all.length; i++) {
        const el = all[i]
        const tag = (el.localName || '').toLowerCase()
        if (!BILINGUAL_BLOCK_TAGS[tag]) continue
        if (el.hasAttribute && el.hasAttribute('data-vreader-decoration')) continue
        // Bug #268: leaf blocks only — a block that contains another block
        // (e.g. <blockquote><p>…</p></blockquote>) is skipped; its inner block
        // is enumerated instead, so the container isn't double-counted.
        if (el.querySelector && el.querySelector(BILINGUAL_BLOCK_SELECTOR)) continue
        if (!bilingualNormalizeBlockText(el)) continue
        out.push(el)
    }
    return out
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
    const handleSelection = (sourceDoc) => {
        clearTimeout(selectionTimeout)
        selectionTimeout = setTimeout(() => {
            const contents = view.renderer?.getContents?.()
            if (!contents?.length) return
            // Feature #73 WI-7: in windowed scrolled mode `getContents()` returns
            // EVERY mounted section, so `contents[0]` is just the lowest-index one
            // — not necessarily the section the user selected in. Prefer the doc
            // that actually FIRED `selectionchange` (Gate-4 M: a stale selection
            // in another mounted iframe could otherwise win); fall back to scanning
            // for any live selection. Single-view mode → the one entry, unchanged.
            const hasLiveSel = c => {
                const s = c?.doc?.getSelection?.()
                return s && !s.isCollapsed && s.rangeCount
            }
            let owner = sourceDoc ? contents.find(c => c.doc === sourceDoc) : null
            if (!owner || !hasLiveSel(owner)) owner = contents.find(hasLiveSel)
            if (!owner) {
                post('selection', { collapsed: true })
                return
            }
            const { doc, index } = owner
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
        doc.addEventListener('selectionchange', () => handleSelection(doc))
    })
}

// Content tap (chrome toggle + bug #239 side-tap page-turn). The body now
// carries the tap's x-coordinate and the width in *host-viewport* pixels so
// the Swift FoliateSpikeView coordinator can route through
// `ReaderTapZoneRouter` for paged-mode side-tap → next/prev page. Synthetic
// clicks that lack `clientX` post the empty body (`{}`) and fall through to the
// chrome-toggle path.
//
// Bug #108 REOPEN (GH #224): the click `event` fires inside the section's
// iframe document. In paginated mode foliate-js renders the section as a
// multi-column page in an iframe WIDER than the screen and shifts that iframe
// horizontally (`left: -<columnWidth>`) to reveal one column at a time. So
// `event.clientX` is in the iframe's internal coordinate space (0..iframeWidth)
// while `documentElement.clientWidth` is a single column's width. Posting that
// raw pair made `ReaderTapZoneRouter` see `x/w > 2/3` on every right-column
// page and misclassify a center tap as a right-zone next-page — the toolbar
// never toggled. We map the click back to the host viewport via the section's
// `frameElement`: `hostX = clientX + frameRect.left`, `hostW = host window
// innerWidth`. That matches the coordinate space the EPUB content-tap handler
// already uses (EPUB renders in the top-level document, so its clientX/width
// are host-relative to begin with). When there is no host frame (defensive —
// a non-iframe renderer or a cross-origin section we cannot read), we post the
// bare `'tap'` so the tap still toggles chrome (the safe default) rather than
// turning the page on a wrong coordinate.
view.addEventListener('load', e => {
    const doc = e.detail.doc
    doc.addEventListener('click', event => {
        // Bug #287 / GH #1268: a highlight tap (exact OR within the 44pt
        // tolerance) was marked by view.js's capture-phase annotation handler,
        // which already emitted `show-annotation`. Absorb the tap here so it
        // does NOT turn the page or toggle chrome — the popover is the action.
        if (event.__vreaderAnnotationHit) return
        // Ignore link clicks
        if (event.target.closest('a[href]')) return
        // Ignore if text is selected
        const sel = doc.getSelection()
        if (sel && !sel.isCollapsed) return
        const x = (typeof event.clientX === 'number') ? event.clientX : null
        if (x === null || !isFinite(x)) {
            post('tap', {})
            return
        }
        const mapped = mapTapToHostViewport(doc, x)
        if (!mapped) {
            // No reliable host-viewport mapping — toggle chrome rather than
            // risk a wrong side-tap classification.
            post('tap', {})
            return
        }
        post('tap', { x: mapped.x, w: mapped.w })
    })
})

// Bug #108 REOPEN: convert a click's iframe-internal `clientX` into the host
// viewport's coordinate space + return the host viewport width, so
// `ReaderTapZoneRouter`'s 30/40/30 zone split lands on the screen the user
// actually sees. Returns `null` when no usable mapping exists (caller then
// posts the bare chrome-toggle tap).
//
// - `frameEl` is the iframe element hosting this section, read from the
//   section document's own window. Its `getBoundingClientRect().left` is the
//   horizontal shift foliate-js applies to page through columns (0 on the
//   first column, negative on later columns).
// - `hostWin` is the window that OWNS that iframe (the foliate host page).
//   Its `innerWidth` is the on-screen reader width — the correct `w`.
// - When `frameEl` is absent (top-level / non-iframe renderer), `clientX`
//   and `documentElement.clientWidth` are already host-relative, so we use
//   them directly.
//
// We do NOT fall back to the iframe element's own width when the host
// viewport width is unavailable: that width is the WIDE multi-column iframe
// (the very thing that broke `clientX`/`clientWidth` parity), so using it
// would re-introduce the mixed-coordinate bug. When `hostWin.innerWidth`
// isn't a usable number we return `null` so the caller posts the bare
// chrome-toggle `tap` (the safe default) rather than risk a wrong side-tap.
function mapTapToHostViewport(doc, clientX) {
    try {
        // `docWin` is the section document's own window — NOT the module-level
        // `view` (<foliate-view>). Named distinctly to avoid shadowing it.
        const docWin = doc.defaultView
        const frameEl = docWin && docWin.frameElement
        if (!frameEl) {
            // No nested iframe → clientX / clientWidth are already in the
            // host viewport space (matches the EPUB top-level-document case).
            const w = doc.documentElement?.clientWidth
                || (docWin && docWin.innerWidth) || 0
            if (!isFinite(w) || w <= 0) return null
            return { x: clientX, w: w }
        }
        const frameLeft = frameEl.getBoundingClientRect().left
        const hostWin = frameEl.ownerDocument
            && frameEl.ownerDocument.defaultView
        const hostW = hostWin && hostWin.innerWidth
        // Only the HOST viewport width is a valid `w`. No iframe-width
        // fallback — that would re-mix coordinate spaces (Bug #108).
        if (!isFinite(frameLeft) || !isFinite(hostW) || hostW <= 0) return null
        return { x: clientX + frameLeft, w: hostW }
    } catch (e) {
        // Cross-origin frame access (should not happen for blob: sections,
        // but defensive) — no reliable mapping.
        return null
    }
}

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
            // Bug #334: extract ONE paragraph per leaf block, joined by a blank
            // line, instead of the whole-body `textContent` (which mushes every
            // paragraph into a single string with no boundaries). Swift's
            // `ChapterSegmenter.paragraphs` splits on blank lines, so this makes
            // the translate's segment count EQUAL the `bilingualEnumerate` block
            // count — without that equality the 1:1 inject pairing returns an
            // empty map and the loading shimmer never gets replaced. Uses the
            // SAME shared selector as the enumerate so the two can't drift.
            const texts = bilingualLeafBlockElements(doc)
                .map(bilingualNormalizeBlockText)
                .filter(Boolean)
            if (texts.length > 0) return texts.join('\n\n')
            // Fallback: a section with no recognized leaf blocks (rare — e.g. a
            // cover page that's pure text) keeps the legacy whole-body behavior
            // so it still translates as a single segment.
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
                let seq = (doc.__vreaderBilingualSeq ?? 0)
                // Bug #334: source the leaf blocks from the shared selector so the
                // enumerate's block set is byte-identical to what
                // `bilingualSectionText` feeds the translate — see
                // `bilingualLeafBlockElements`.
                const els = bilingualLeafBlockElements(doc)
                for (const el of els) {
                    const txt = bilingualNormalizeBlockText(el)
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
                        // Feature #77: if this decoration is currently a
                        // LOADING shimmer, drop the loading modifier so the
                        // same node becomes the final translation block in
                        // place (no flicker / re-insert) — the shimmer bars
                        // are wiped by the textContent assignment below.
                        next.classList.remove('vreader-bilingual-loading')
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

    // Feature #77: insert an inline LOADING shimmer decoration after each
    // of `opts.loadingBids`' blocks while that unit's translation is being
    // fetched. Skips any block that already carries a decoration (a landed
    // translation OR an existing shimmer) so it never downgrades a translated
    // row or stacks duplicates. The shimmer node is `<div class="vreader-
    // bilingual vreader-bilingual-loading" data-vreader-decoration>` with two
    // `<div class="vreader-shimmer-bar">` children; the inject path above
    // replaces it in place (dropping the loading class) when the translation
    // lands. Mirrors `EPUBBilingualJS.bilingualInjectLoadingJS`.
    bilingualInjectLoading(opts) {
        try {
            const loadingBids = Array.isArray(opts?.loadingBids)
                ? opts.loadingBids : []
            if (loadingBids.length === 0) return
            const DECO = opts?.decorationAttribute || 'data-vreader-decoration'
            const BID = opts?.blockIDAttribute || 'data-vreader-bid'
            const CLS = opts?.blockClassName || 'vreader-bilingual'
            const LOADING_CLS = opts?.loadingClassName || 'vreader-bilingual-loading'
            const BAR_CLS = opts?.shimmerBarClassName || 'vreader-shimmer-bar'
            const STYLE = opts?.styleCssText ||
                'user-select: none; -webkit-user-select: none;'
            const targetSectionIndex = opts?.targetSectionIndex
            const WIDTHS = ['92%', '54%']

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
                for (let b = 0; b < loadingBids.length; b++) {
                    const block = doc.querySelector(
                        '[' + BID + '="' + esc(loadingBids[b]) + '"]'
                    )
                    if (!block) continue
                    const next = block.nextElementSibling
                    if (next
                        && next.hasAttribute
                        && next.hasAttribute(DECO)
                        && next.classList
                        && next.classList.contains(CLS)) {
                        continue // already decorated — don't downgrade / duplicate
                    }
                    const div = doc.createElement('div')
                    div.className = CLS + ' ' + LOADING_CLS
                    div.setAttribute(DECO, '')
                    div.style.cssText = STYLE
                    for (let w = 0; w < WIDTHS.length; w++) {
                        const bar = doc.createElement('div')
                        bar.className = BAR_CLS
                        bar.style.width = WIDTHS[w]
                        div.appendChild(bar)
                    }
                    if (block.parentNode) {
                        block.parentNode.insertBefore(div, block.nextSibling)
                    }
                }
            }
        } catch (e) {
            console.warn('[foliate-host] bilingualInjectLoading failed:', e)
        }
    },

    // Feature #77: remove ONLY the loading-shimmer decoration nodes (a failed
    // / cancelled prefetch), leaving landed translations intact. With
    // `targetSectionIndex` omitted, walks every loaded section. Idempotent.
    bilingualClearLoading(targetSectionIndex) {
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
                    '.vreader-bilingual-loading[data-vreader-decoration]'
                )
                for (let i = 0; i < nodes.length; i++) {
                    const n = nodes[i]
                    if (n.parentNode) {
                        n.parentNode.removeChild(n)
                    }
                }
            }
        } catch (e) {
            console.warn('[foliate-host] bilingualClearLoading failed:', e)
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
