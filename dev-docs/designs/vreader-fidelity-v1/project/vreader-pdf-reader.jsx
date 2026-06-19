// Android PDF reader — base page-view surface (issue #1766, feature #110).
//
// iOS gets the PDF reading surface free from PDFKit's PDFView. Android's
// PdfRenderer only hands back per-page *bitmaps*, so the page-display +
// navigation UI must be built — and therefore designed.
//
// This file is the base reader, NOT the bilingual translation panel
// (that's vreader-pdf-translation.jsx). It composes:
//   1. PdfPaper            — one rendered page bitmap mock (text / figure /
//                            scanned-image / blank kinds).
//   2. PdfContinuousReader — vertical scroll of pages (CANONICAL). Mirrors
//                            how PdfRenderer bitmaps naturally stack; matches
//                            every mainstream Android PDF surface.
//   3. PdfPagedReader      — one page at a time, reusing the EPUB reader's
//                            left/right/centre tap-zones for cross-format
//                            muscle-memory (alternative B).
//   4. PdfReaderTopChrome / PdfReaderBottomChrome — the reader chrome from
//                            vreader-reader.jsx's vocabulary (back + italic
//                            title + icon row / bottom toolbar), self-contained.
//   5. State surfaces      — PdfRendering, PdfEncrypted, PdfCorrupt, PdfEmpty.
//   6. PdfPageJump         — thumbnail-strip + scrubber overlay for jumping.
//
// Source-of-truth book: "Designing Data-Intensive Applications.pdf" (the
// PDF in BOOKS — 614 pages, currentPage 111). Page content is a typeset
// mock; the point is that the eye reads it as a real PDF page bitmap.

const PDF_BOOK = { title: 'Designing Data-Intensive Applications', file: 'ddia.pdf', total: 614 };

// Neutral "viewer backdrop" the page bitmaps sit on. Distinct from the
// reader paper tone so a white page reads as an object floating on the
// viewer, exactly like every native PDF surface.
function pdfBackdrop(t) {
  // Photo theme gets a warm photographic backdrop so the page bitmap reads
  // as floating on the cover image, like the reader's photo mode.
  if (t.image) return 'linear-gradient(150deg, #3a2818 0%, #1a1410 55%, #2a1818 100%)';
  return t.isDark ? '#101010' : '#cdc7ba';
}
function pdfPaperTone(t) {
  // The page bitmap itself. Real PDFs are white/cream regardless of the
  // app theme; in dark mode we offer the dimmed-paper rendering (the
  // bitmap is drawn onto a muted sheet, not pure white, to avoid glare).
  return t.isDark ? '#standin' : '#ffffff';
}

// ════════════════════════════════════════════════════
// 1. PdfPaper — a single page bitmap mock.
//    kind: 'text' | 'figure' | 'scan' | 'blank'
//    dim:  in dark theme, render the page muted instead of glaring white.
// ════════════════════════════════════════════════════
function PdfPaper({ theme, w, h, pageNumber, kind = 'text', dim = false, heading }) {
  const t = theme;
  const paperBg = t.isDark
    ? (dim ? '#2a2724' : '#e8e3d8')
    : '#ffffff';
  const inkFull = t.isDark ? (dim ? '#cfc9bd' : '#23201b') : '#23201b';
  const inkSub = t.isDark ? (dim ? 'rgba(207,201,189,0.55)' : 'rgba(35,32,27,0.55)') : 'rgba(35,32,27,0.5)';
  const rule = t.isDark ? (dim ? 'rgba(207,201,189,0.16)' : 'rgba(35,32,27,0.14)') : 'rgba(35,32,27,0.12)';
  const pad = Math.round(w * 0.11);
  const fs = Math.max(7, Math.round(w * 0.032));

  return (
    <div style={{
      width: w, height: h, flexShrink: 0, position: 'relative',
      background: paperBg, overflow: 'hidden',
      boxShadow: t.isDark
        ? '0 2px 10px rgba(0,0,0,0.5)'
        : '0 2px 10px rgba(40,30,15,0.22)',
    }}>
      {/* running header */}
      <div style={{
        position: 'absolute', top: pad * 0.55, left: pad, right: pad,
        display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: fs * 0.78, color: inkSub,
        letterSpacing: 1, textTransform: 'uppercase',
        paddingBottom: pad * 0.28, borderBottom: `0.5px solid ${rule}`,
      }}>
        <span style={{ textTransform: 'none', letterSpacing: 0 }}>Chapter 5 · Replication</span>
        <span style={{ fontVariantNumeric: 'tabular-nums' }}>{pageNumber}</span>
      </div>

      {kind === 'blank' && null}

      {kind === 'text' && (
        <div style={{
          position: 'absolute', top: pad * 1.5, left: pad, right: pad, bottom: pad,
          fontFamily: '"Source Serif 4", Georgia, "Times New Roman", serif',
          fontSize: fs, lineHeight: 1.5, color: inkFull, textAlign: 'justify',
        }}>
          {heading && (
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: fs * 1.5, fontWeight: 700, color: inkFull,
              marginBottom: fs * 0.9, lineHeight: 1.15, textAlign: 'left',
            }}>{heading}</div>
          )}
          {PDF_TEXT.map((p, i) => (
            <p key={i} style={{ margin: 0, marginBottom: fs * 0.7, textIndent: i === 0 || heading && i === 0 ? 0 : fs * 1.5 }}>{p}</p>
          ))}
        </div>
      )}

      {kind === 'figure' && (
        <div style={{
          position: 'absolute', top: pad * 1.5, left: pad, right: pad, bottom: pad,
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: fs, lineHeight: 1.5, color: inkFull,
        }}>
          <p style={{ margin: 0, marginBottom: fs * 0.8, textAlign: 'justify' }}>{PDF_TEXT[0]}</p>
          {/* a diagram block */}
          <div style={{
            border: `1px solid ${rule}`, borderRadius: 2, padding: fs,
            display: 'flex', flexDirection: 'column', gap: fs * 0.7, marginBottom: fs * 0.5,
          }}>
            <div style={{ display: 'flex', gap: fs * 0.7, justifyContent: 'space-between' }}>
              {['Leader', 'Follower', 'Follower'].map((n, i) => (
                <div key={i} style={{
                  flex: 1, border: `1px solid ${inkSub}`, borderRadius: 2,
                  padding: `${fs * 0.5}px 0`, textAlign: 'center',
                  fontFamily: '"Inter", sans-serif', fontSize: fs * 0.74,
                  color: inkFull, background: i === 0 ? (t.isDark ? 'rgba(214,136,90,0.18)' : 'rgba(140,47,47,0.08)') : 'transparent',
                }}>{n}</div>
              ))}
            </div>
            <svg viewBox="0 0 200 24" style={{ width: '100%', height: fs * 1.4 }} fill="none" stroke={inkSub} strokeWidth="1">
              <path d="M40 4 L100 20 M160 4 L100 20" />
              <path d="M96 16 l4 4 l4 -4" fill={inkSub} stroke="none"/>
            </svg>
          </div>
          <div style={{
            textAlign: 'center', fontSize: fs * 0.82, color: inkSub, fontStyle: 'italic',
            marginBottom: fs * 0.8,
          }}>Figure 5-1. Leader-based replication.</div>
          <p style={{ margin: 0, textAlign: 'justify', textIndent: fs * 1.5 }}>{PDF_TEXT[1]}</p>
        </div>
      )}

      {kind === 'scan' && (
        <div style={{
          position: 'absolute', top: pad * 1.5, left: pad, right: pad, bottom: pad,
          display: 'flex', flexDirection: 'column', gap: fs * 0.7,
        }}>
          {/* a slightly skewed, lower-contrast "photographed page" look */}
          <div style={{
            flex: 1, borderRadius: 1,
            background: t.isDark ? '#dad3c4' : '#f0ead9',
            transform: 'rotate(-0.4deg)',
            boxShadow: 'inset 0 0 40px rgba(120,100,70,0.18)',
            padding: fs, display: 'flex', flexDirection: 'column', gap: fs * 0.6,
            overflow: 'hidden', filter: 'contrast(0.92) sepia(0.12)',
          }}>
            {Array.from({ length: 14 }).map((_, i) => (
              <div key={i} style={{
                height: fs * 0.5,
                width: `${[96, 92, 94, 60, 95, 90, 88, 70, 93, 91, 50, 94, 89, 64][i]}%`,
                background: 'rgba(60,45,25,0.34)', borderRadius: 1,
              }}/>
            ))}
          </div>
        </div>
      )}

      {/* page number footer */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: pad * 0.5,
        textAlign: 'center', fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: fs * 0.86, color: inkSub, fontVariantNumeric: 'oldstyle-nums tabular-nums',
      }}>{pageNumber}</div>
    </div>
  );
}

const PDF_TEXT = [
  'Replication means keeping a copy of the same data on multiple machines that are connected via a network. There are several reasons why you might want to replicate data: to keep it geographically close to your users, to allow the system to continue working even if some of its parts have failed, and to scale out the number of machines that can serve read queries.',
  'The leader-based approach requires all writes to go through a single node, but reads can be served by any replica. This is a popular choice because it is relatively easy to reason about and is implemented by many relational and nonrelational databases. The main downside appears when the leader fails and a follower must be promoted in its place.',
  'In this chapter we will assume that your dataset is small enough that each machine can hold a copy of the entire dataset. In Chapter 6 we will relax that assumption and discuss partitioning of datasets that are too big for a single machine.',
];

// ════════════════════════════════════════════════════
// Reader chrome (back + italic title + icons / bottom toolbar)
// Slim, self-contained, matches vreader-reader.jsx vocabulary.
// ════════════════════════════════════════════════════
function PdfReaderTopChrome({ theme, title = PDF_BOOK.title, onlyBack = false }) {
  const t = theme;
  const ico = (path, key) => (
    <button key={key} style={{
      width: 34, height: 34, borderRadius: 17, background: 'none', border: 'none',
      cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
    }}>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">{path}</svg>
    </button>
  );
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      paddingTop: 38, paddingBottom: 9, zIndex: 30,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 12px' }}>
        <button style={{
          display: 'flex', alignItems: 'center', gap: 2, padding: '6px 6px',
          background: 'none', border: 'none', cursor: 'pointer',
          color: t.accent, fontFamily: '"Inter", system-ui', fontSize: 14, fontWeight: 500,
        }}>
          <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
          <span>Library</span>
        </button>
        <div style={{
          flex: 1, textAlign: 'center', padding: '0 8px', overflow: 'hidden',
          whiteSpace: 'nowrap', textOverflow: 'ellipsis',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>{title}<span style={{ fontStyle: 'normal', fontFamily: '"Inter", system-ui', fontWeight: 600, fontSize: 9, color: t.sub, letterSpacing: 0.5, marginLeft: 6, verticalAlign: 'middle' }}>PDF</span></div>
        {onlyBack ? <div style={{ width: 68 }}/> : (
          <div style={{ display: 'flex', gap: 0 }}>
            {ico(<><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></>, 's')}
            {ico(<><rect x="4" y="4" width="6" height="6" rx="1"/><rect x="14" y="4" width="6" height="6" rx="1"/><rect x="4" y="14" width="6" height="6" rx="1"/><rect x="14" y="14" width="6" height="6" rx="1"/></>, 'g')}
          </div>
        )}
      </div>
    </div>
  );
}

function PdfReaderBottomChrome({ theme }) {
  const t = theme;
  const items = [
    { glyph: <><path d="M4 6h2M4 12h2M4 18h2M9 6h11M9 12h11M9 18h11"/></>, label: 'Contents' },
    { glyph: <><rect x="4" y="3" width="7" height="8" rx="1"/><rect x="13" y="3" width="7" height="8" rx="1"/><rect x="4" y="13" width="7" height="8" rx="1"/><rect x="13" y="13" width="7" height="8" rx="1"/></>, label: 'Pages' },
    { glyph: <><text x="2" y="18" fontSize="17" fontFamily="serif" fontWeight="700" fill={t.ink} stroke="none">Aa</text></>, label: 'Display' },
    { glyph: <><path d="M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7z"/></>, label: 'AI', accent: true },
  ];
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0,
      paddingBottom: 22, paddingTop: 9, zIndex: 30,
      background: t.chrome, borderTop: `0.5px solid ${t.rule}`,
      display: 'flex', justifyContent: 'space-around', alignItems: 'center',
    }}>
      {items.map((b, i) => (
        <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, color: b.accent ? t.accent : t.sub }}>
          <svg width="21" height="21" viewBox="0 0 24 24" fill="none" stroke={b.accent ? t.accent : t.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">{b.glyph}</svg>
          <span style={{ fontFamily: '"Inter", system-ui', fontSize: 9.5, fontWeight: 500 }}>{b.label}</span>
        </div>
      ))}
    </div>
  );
}

// Floating "Page N of M" pill — the page-progress indicator. Appears while
// scrolling / on chrome-hidden; bottom-centre, glassy.
function PdfProgressPill({ theme, page, total, floating = true }) {
  const t = theme;
  return (
    <div style={{
      position: floating ? 'absolute' : 'static',
      bottom: 16, left: '50%', transform: floating ? 'translateX(-50%)' : 'none',
      zIndex: 25,
      display: 'inline-flex', alignItems: 'center', gap: 6,
      padding: '6px 13px', borderRadius: 100,
      background: t.isDark ? 'rgba(20,20,20,0.82)' : 'rgba(40,32,20,0.78)',
      color: '#f3ede0', fontFamily: '"Inter", system-ui',
      fontSize: 12, fontWeight: 600, letterSpacing: 0.2,
      backdropFilter: 'blur(8px)', boxShadow: '0 4px 16px rgba(0,0,0,0.3)',
      fontVariantNumeric: 'tabular-nums',
    }}>
      <span>Page {page}</span>
      <span style={{ opacity: 0.5 }}>of {total}</span>
    </div>
  );
}

// ════════════════════════════════════════════════════
// 2. PdfContinuousReader — vertical scroll of pages (CANONICAL)
// ════════════════════════════════════════════════════
function PdfContinuousReader({ theme, scroll = 0, chromeVisible = true, dim = false,
                               firstKind = 'text', secondKind = 'figure' }) {
  const t = theme;
  const W = 402, topH = 80, botH = 53;
  const pageW = W - 36;
  const pageH = Math.round(pageW * 1.34);
  const gap = 14;
  // scroll offset (0..1) shifts the stack; 0 shows top of page 111.
  const offset = -scroll * (pageH + gap);

  return (
    <div style={{ position: 'absolute', inset: 0, background: pdfBackdrop(t), overflow: 'hidden' }}>
      {/* stacked pages */}
      <div style={{
        position: 'absolute', top: topH, left: 18, right: 18, bottom: 0,
        overflow: 'hidden',
      }}>
        <div style={{
          display: 'flex', flexDirection: 'column', gap, alignItems: 'center',
          transform: `translateY(${offset}px)`,
          paddingTop: 10,
          transition: 'transform 0.3s cubic-bezier(0.32,0.72,0,1)',
        }}>
          <PdfPaper theme={t} w={pageW} h={pageH} pageNumber={110} kind={firstKind} dim={dim} heading={firstKind === 'text' ? 'Leaders and Followers' : null}/>
          <PdfPaper theme={t} w={pageW} h={pageH} pageNumber={111} kind={secondKind} dim={dim}/>
          <PdfPaper theme={t} w={pageW} h={pageH} pageNumber={112} kind="text" dim={dim}/>
        </div>
      </div>

      {chromeVisible && <PdfReaderTopChrome theme={t}/>}
      {chromeVisible && <PdfReaderBottomChrome theme={t}/>}
      <PdfProgressPill theme={t} page={111} total={PDF_BOOK.total}
        floating />
    </div>
  );
}

// ════════════════════════════════════════════════════
// 3. PdfPagedReader — one page at a time, reusing tap-zones
// ════════════════════════════════════════════════════
function PdfPagedReader({ theme, chromeVisible = true, showZones = false, turning = false, dim = false, kind = 'text' }) {
  const t = theme;
  const W = 402;
  const pageW = Math.round(W * 0.9);
  const pageH = Math.round(pageW * 1.4);

  return (
    <div style={{ position: 'absolute', inset: 0, background: pdfBackdrop(t), overflow: 'hidden' }}>
      {/* centred single page */}
      <div style={{
        position: 'absolute', inset: 0, display: 'flex',
        alignItems: 'center', justifyContent: 'center',
        transform: turning ? 'translateX(-9%)' : 'none',
        opacity: turning ? 0 : 1,
        transition: 'transform 0.3s cubic-bezier(0.32,0.72,0,1), opacity 0.24s ease-out',
      }}>
        <PdfPaper theme={t} w={pageW} h={pageH} pageNumber={111} kind={kind} dim={dim} heading={kind === 'text' ? 'Leaders and Followers' : null}/>
      </div>

      {/* tap-zone debug overlay */}
      {showZones && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', zIndex: 20, pointerEvents: 'none' }}>
          {[['Prev', 'rgba(140,47,47,0.10)'], ['Menu', 'rgba(40,40,40,0.06)'], ['Next', 'rgba(58,106,90,0.12)']].map(([lab, bg], i) => (
            <div key={i} style={{
              flex: i === 1 ? 1.33 : 1, background: bg,
              borderLeft: i ? `1px dashed ${t.rule}` : 'none',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexDirection: 'column', gap: 6,
            }}>
              <span style={{
                fontFamily: '"Inter", system-ui', fontSize: 11, fontWeight: 700,
                letterSpacing: 1, textTransform: 'uppercase',
                color: t.isDark ? 'rgba(255,255,255,0.6)' : 'rgba(40,30,15,0.55)',
              }}>{lab}</span>
              <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
                stroke={t.isDark ? 'rgba(255,255,255,0.5)' : 'rgba(40,30,15,0.45)'} strokeWidth="1.8" strokeLinecap="round">
                {i === 0 && <path d="M15 6l-6 6 6 6"/>}
                {i === 1 && <><circle cx="12" cy="12" r="2.4"/><path d="M12 4v3M12 17v3M4 12h3M17 12h3"/></>}
                {i === 2 && <path d="M9 6l6 6-6 6"/>}
              </svg>
            </div>
          ))}
        </div>
      )}

      {chromeVisible && <PdfReaderTopChrome theme={t}/>}
      {chromeVisible && <PdfReaderBottomChrome theme={t}/>}
      {!chromeVisible && <PdfProgressPill theme={t} page={111} total={PDF_BOOK.total} floating/>}
    </div>
  );
}

// ════════════════════════════════════════════════════
// 5. State surfaces
// ════════════════════════════════════════════════════
function PdfStateScaffold({ theme, children }) {
  const t = theme;
  return (
    <div style={{ position: 'absolute', inset: 0, background: pdfBackdrop(t), overflow: 'hidden' }}>
      <PdfReaderTopChrome theme={t} onlyBack/>
      <div style={{
        position: 'absolute', top: 80, left: 0, right: 0, bottom: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '0 40px',
      }}>{children}</div>
    </div>
  );
}

// Rendering — the page bitmap is being rasterized by PdfRenderer. Skeleton
// page frame + a thin determinate-ish bar. This is the loading state.
function PdfRendering({ theme }) {
  const t = theme;
  const pageW = 280, pageH = Math.round(280 * 1.4);
  const shimmer = t.isDark
    ? 'linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,255,255,0.11), rgba(255,255,255,0.04))'
    : 'linear-gradient(90deg, rgba(255,255,255,0.5), rgba(255,255,255,0.95), rgba(255,255,255,0.5))';
  return (
    <PdfStateScaffold theme={t}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
        <div style={{
          width: pageW, height: pageH, background: t.isDark ? '#2a2724' : '#e7e1d4',
          boxShadow: t.isDark ? '0 2px 10px rgba(0,0,0,0.5)' : '0 2px 10px rgba(40,30,15,0.22)',
          padding: 28, display: 'flex', flexDirection: 'column', gap: 11,
          position: 'relative', overflow: 'hidden',
        }}>
          {[92, 88, 94, 60, 90, 86, 70, 93, 50].map((w, i) => (
            <div key={i} style={{
              height: 9, width: `${w}%`, borderRadius: 3,
              background: shimmer, backgroundSize: '200% 100%',
              animation: `pdfShimmer 1.4s ease-in-out ${i * 0.05}s infinite`,
            }}/>
          ))}
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          fontFamily: '"Inter", system-ui', fontSize: 12.5, color: t.isDark ? 'rgba(230,225,215,0.7)' : 'rgba(40,32,20,0.6)', fontWeight: 500,
        }}>
          <svg className="apf-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={t.accent} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
          Rendering page 111…
        </div>
      </div>
    </PdfStateScaffold>
  );
}

// Encrypted — password-protected PDF. Lock + password field + Unlock.
function PdfEncrypted({ theme, wrong = false }) {
  const t = theme;
  const onDark = t.isDark;
  const fg = onDark ? '#e6e1d5' : '#2a241b';
  const sub = onDark ? 'rgba(230,225,213,0.55)' : 'rgba(42,36,27,0.55)';
  const fieldBg = onDark ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.7)';
  return (
    <PdfStateScaffold theme={t}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0, maxWidth: 300, textAlign: 'center' }}>
        <div style={{
          width: 56, height: 56, borderRadius: 28,
          background: onDark ? 'rgba(214,136,90,0.16)' : 'rgba(140,47,47,0.1)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 18,
        }}>
          <svg width="26" height="26" viewBox="0 0 24 24" fill="none" stroke={t.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
            <rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 018 0v3"/><circle cx="12" cy="15.5" r="1.3" fill={t.accent} stroke="none"/>
          </svg>
        </div>
        <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 19, fontWeight: 600, color: fg, marginBottom: 7, lineHeight: 1.25 }}>
          This PDF is protected
        </div>
        <div style={{ fontFamily: '"Inter", system-ui', fontSize: 13, color: sub, lineHeight: 1.5, marginBottom: 20 }}>
          Enter the document password to open <span style={{ fontStyle: 'italic', fontFamily: '"Source Serif 4", serif' }}>{PDF_BOOK.title}</span>.
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', width: '100%',
          background: fieldBg, borderRadius: 12, padding: '0 14px', height: 46,
          boxShadow: wrong ? 'inset 0 0 0 1.5px #c0492f' : `inset 0 0 0 1px ${t.rule}`,
        }}>
          <span style={{ fontFamily: '"Inter"', fontSize: 17, letterSpacing: 3, color: fg }}>••••••••</span>
          <span style={{ flex: 1 }}/>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={sub} strokeWidth="1.7"><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg>
        </div>
        {wrong && (
          <div style={{ fontFamily: '"Inter", system-ui', fontSize: 12, color: '#c0492f', marginTop: 8, alignSelf: 'flex-start' }}>
            Incorrect password — try again.
          </div>
        )}
        <button style={{
          marginTop: 16, width: '100%', height: 46, borderRadius: 12, border: 'none',
          background: t.accent, color: '#fff', fontFamily: '"Inter", system-ui',
          fontSize: 15, fontWeight: 600, cursor: 'pointer',
        }}>Unlock</button>
      </div>
    </PdfStateScaffold>
  );
}

// Corrupt — the file can't be decoded by PdfRenderer at all.
function PdfCorrupt({ theme }) {
  const t = theme;
  const onDark = t.isDark;
  const fg = onDark ? '#e6e1d5' : '#2a241b';
  const sub = onDark ? 'rgba(230,225,213,0.55)' : 'rgba(42,36,27,0.55)';
  return (
    <PdfStateScaffold theme={t}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 0, maxWidth: 300, textAlign: 'center' }}>
        <svg width="46" height="46" viewBox="0 0 24 24" fill="none" stroke={onDark ? 'rgba(230,225,213,0.5)' : 'rgba(42,36,27,0.4)'} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" style={{ marginBottom: 16 }}>
          <path d="M6 2h8l4 4v14a2 2 0 01-2 2H6a2 2 0 01-2-2V4a2 2 0 012-2z"/><path d="M14 2v4h4"/><path d="M9.5 11l5 5M14.5 11l-5 5"/>
        </svg>
        <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 19, fontWeight: 600, color: fg, marginBottom: 7, lineHeight: 1.25 }}>
          Couldn’t open this PDF
        </div>
        <div style={{ fontFamily: '"Inter", system-ui', fontSize: 13, color: sub, lineHeight: 1.5, marginBottom: 20 }}>
          The file appears to be damaged or uses a format the reader can’t decode. Try re-importing it from the original source.
        </div>
        <div style={{ display: 'flex', gap: 10 }}>
          <button style={{
            height: 42, padding: '0 18px', borderRadius: 100, border: 'none',
            background: t.accent, color: '#fff', fontFamily: '"Inter", system-ui', fontSize: 14, fontWeight: 600, cursor: 'pointer',
          }}>Re-import</button>
          <button style={{
            height: 42, padding: '0 18px', borderRadius: 100,
            background: 'transparent', border: `1px solid ${t.rule}`,
            color: fg, fontFamily: '"Inter", system-ui', fontSize: 14, fontWeight: 500, cursor: 'pointer',
          }}>Back to Library</button>
        </div>
      </div>
    </PdfStateScaffold>
  );
}

// ════════════════════════════════════════════════════
// 6. PdfPageJump — thumbnail strip + scrubber overlay (the "Pages" affordance)
// ════════════════════════════════════════════════════
function PdfPageJump({ theme, current = 111 }) {
  const t = theme;
  const onDark = t.isDark;
  const panelBg = onDark ? 'rgba(24,24,24,0.96)' : 'rgba(250,247,240,0.97)';
  const fg = onDark ? '#e6e1d5' : '#2a241b';
  const sub = onDark ? 'rgba(230,225,213,0.55)' : 'rgba(42,36,27,0.55)';
  const thumbs = [108, 109, 110, 111, 112, 113, 114];
  return (
    <div style={{ position: 'absolute', inset: 0, background: pdfBackdrop(t), overflow: 'hidden' }}>
      <PdfReaderTopChrome theme={t}/>
      {/* dimmed current page behind */}
      <div style={{ position: 'absolute', top: 80, left: 0, right: 0, bottom: 200, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: 0.5 }}>
        <PdfPaper theme={t} w={230} h={Math.round(230 * 1.4)} pageNumber={111} kind="text" heading="Leaders and Followers"/>
      </div>
      {/* bottom jump panel */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0,
        background: panelBg, backdropFilter: 'blur(12px)',
        borderTop: `0.5px solid ${t.rule}`,
        borderTopLeftRadius: 18, borderTopRightRadius: 18,
        paddingTop: 14, paddingBottom: 24,
        boxShadow: '0 -10px 30px rgba(0,0,0,0.2)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', padding: '0 18px', marginBottom: 12 }}>
          <span style={{ fontFamily: '"Inter", system-ui', fontSize: 14, fontWeight: 600, color: fg }}>Jump to page</span>
          <span style={{ fontFamily: '"Inter", system-ui', fontSize: 12, color: sub, fontVariantNumeric: 'tabular-nums' }}>{current} / {PDF_BOOK.total}</span>
        </div>
        {/* thumbnail strip */}
        <div className="hide-scroll" style={{ display: 'flex', gap: 10, padding: '0 18px 14px', overflowX: 'auto' }}>
          {thumbs.map(n => {
            const active = n === current;
            return (
              <div key={n} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 5, flexShrink: 0 }}>
                <div style={{
                  width: 58, height: 80, background: onDark ? '#2a2724' : '#fff',
                  boxShadow: active ? `0 0 0 2px ${t.accent}` : `0 0 0 0.5px ${t.rule}, 0 1px 4px rgba(0,0,0,0.12)`,
                  padding: 7, display: 'flex', flexDirection: 'column', gap: 3.5,
                }}>
                  {[90, 80, 86, 50, 84, 78, 60].map((w, i) => (
                    <div key={i} style={{ height: 2.5, width: `${w}%`, background: onDark ? 'rgba(207,201,189,0.3)' : 'rgba(35,32,27,0.22)', borderRadius: 1 }}/>
                  ))}
                </div>
                <span style={{ fontFamily: '"Inter", system-ui', fontSize: 10, color: active ? t.accent : sub, fontWeight: active ? 700 : 500, fontVariantNumeric: 'tabular-nums' }}>{n}</span>
              </div>
            );
          })}
        </div>
        {/* scrubber */}
        <div style={{ padding: '0 22px' }}>
          <div style={{ height: 4, borderRadius: 2, background: t.rule, position: 'relative' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '18%', background: t.accent, borderRadius: 2 }}/>
            <div style={{ position: 'absolute', left: '18%', top: '50%', width: 16, height: 16, borderRadius: 8, background: t.accent, transform: 'translate(-50%,-50%)', boxShadow: '0 1px 4px rgba(0,0,0,0.3)' }}/>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontFamily: '"Inter", system-ui', fontSize: 10.5, color: sub, marginTop: 7 }}>
            <span>1</span><span>{PDF_BOOK.total}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  PDF_BOOK, PdfPaper, PdfReaderTopChrome, PdfReaderBottomChrome, PdfProgressPill,
  PdfContinuousReader, PdfPagedReader,
  PdfStateScaffold, PdfRendering, PdfEncrypted, PdfCorrupt, PdfPageJump,
});
