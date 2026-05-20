// PDF below-page translation panel — issue #1023 (feature #56, Decision 1 Tier C).
//
// PDF is fixed-layout. The paragraph-interlinear renderer that EPUB / text
// content gets (vreader-bilingual.jsx → BilingualPageContent) cannot reflow
// PDF glyphs, so when bilingual mode is on and the open book is a PDF, the
// translation is shown in a panel rendered BELOW the current page instead
// of between paragraphs.
//
// The panel is rooted in the reader frame so it shares the same paper /
// dark / sepia tones as the page. Source-of-truth for the translation is
// PDFChapterTextProvider's per-page extracted text (WI-2.5); this surface
// just visualises it.
//
// One panel, four states:
//   default   — translation present, scrolls within the panel.
//   loading   — translation in flight; skeleton bars + "Translating page N".
//   offline   — extracted text exists, translation not cached, device offline.
//                Retry CTA + the AI-Translate single-paragraph escape hatch.
//   empty     — page has no extractable text (image-only, scan without OCR).
//
// Plus a fifth presentational state: collapsed (header only, body hidden).
// That's the persistent affordance for users who want the PDF page to fill
// the reader; tap the chevron to expand again.
//
// Below, in order:
//   1. PDFPageMock        — fixed-layout page mock (the thing above the panel)
//   2. PDFTranslationPanel — the panel itself, all five states
//   3. PDFPeekSheet       — alternative B (peek/expand drawer)
//   4. PDFReaderShell     — full-screen composition (page + panel + chrome)
//   5. PDFTopChrome / PDFBottomChrome — slimmer chrome variants


// Sample fixed-layout text + matching Chinese translation.
const PDF_SAMPLE = {
  pageNumber: 42,
  chapter: 'Chapter VII',
  paragraphs: [
    'Mr. Bingley’s large fortune, the brother and sisters insisted on giving the ball at Netherfield, and the day was fixed. Mrs. Bennet looked forward to it as the realisation of all her happiest visions. She accepted Mr. Bingley’s compliments to her family with an air of triumph; her two youngest girls were never quiet for a single moment.',
    'Catherine and Lydia were unconcerned that the carriage might be lost in the rain, and listened with a sort of glee to the description of every dance, every partner; Elizabeth bore it patiently, but her thoughts were elsewhere, lingering on the man who had refused her at Meryton.',
    'It was not until the following Tuesday that Mr. Bingley’s sisters condescended to call at Longbourn. Their visit was short — a quarter of an hour at most — and the chill of their civility was sufficient to convince Mrs. Bennet that the friendship was no friendship at all.',
  ],
};

const PDF_SAMPLE_TR = {
  Chinese: [
    '彬格莱先生家境富裕，他的兄弟姐妹坚持要在尼日斐花园举行那场舞会，日期也已经定下来了。班纳特太太把这件事看作是她一切美好幻想的实现。她以胜利者的姿态接受着彬格莱先生对她家人的恭维；她那两个最小的女儿一刻也安静不下来。',
    '凯瑟琳和丽迪雅毫不担心马车会迷失在雨中，反而带着一种得意之情，听着关于每一支舞、每一位舞伴的描述；伊丽莎白耐着性子听下去，可她的思绪却在别处，停留在那个在麦里屯拒绝过她的男人身上。',
    '一直到下星期二，彬格莱先生的两位姐妹才屈尊回访浪博恩。她们这次造访极短——顶多不过一刻钟——而她们那种冷淡的礼数已足以使班纳特太太相信，所谓的友情根本就不是什么友情。',
  ],
};

const PDF_TR_FONT = '"Songti SC", "Source Han Serif", serif';


// ════════════════════════════════════════════════════
// 1. PDF page mock — fixed-layout, paragraphs + page number footer.
//     The point isn't to be a real PDF; it's to look unmistakably *like*
//     a typeset PDF page (margins inside the page paper, header rule,
//     page number bottom-centre) so the reader's eye reads top half as
//     source and bottom half as panel.
// ════════════════════════════════════════════════════
function PDFPageMock({ theme, height, scale = 1 }) {
  const t = theme;
  const pad = 22 * scale;
  const fs = 11 * scale;
  // The page "paper" — slightly different from reader bg so it reads as
  // an embedded object, not the chrome itself.
  const paper = t.isDark ? '#28251f' : '#fdfaf1';
  return (
    <div style={{
      position: 'absolute', inset: 0, padding: '12px 18px',
      display: 'flex', alignItems: 'stretch', justifyContent: 'center',
    }}>
      <div style={{
        position: 'relative', width: '100%', height: '100%',
        background: paper,
        boxShadow: t.isDark
          ? '0 6px 18px rgba(0,0,0,0.5), inset 0 0 0 0.5px rgba(255,255,255,0.05)'
          : '0 6px 18px rgba(60,40,20,0.16), inset 0 0 0 0.5px rgba(0,0,0,0.06)',
        borderRadius: 2,
        overflow: 'hidden',
      }}>
        {/* running header */}
        <div style={{
          padding: `${pad * 0.7}px ${pad}px ${pad * 0.3}px`,
          display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 9.5 * scale, color: t.sub,
          letterSpacing: 1.2, textTransform: 'uppercase',
          borderBottom: `0.5px solid ${t.rule}`,
        }}>
          <span style={{ fontStyle: 'italic', textTransform: 'none', letterSpacing: 0 }}>
            Pride and Prejudice
          </span>
          <span>{PDF_SAMPLE.chapter}</span>
        </div>

        {/* body */}
        <div style={{
          padding: `${pad * 0.9}px ${pad}px`,
          fontFamily: '"Source Serif 4", Georgia, "Times New Roman", serif',
          fontSize: fs, lineHeight: 1.5, color: t.ink,
          textAlign: 'justify', hyphens: 'auto',
        }}>
          {PDF_SAMPLE.paragraphs.map((p, i) => (
            <p key={i} style={{
              margin: 0, marginBottom: fs * 0.7,
              textIndent: i === 0 ? 0 : fs * 1.6,
            }}>{p}</p>
          ))}
        </div>

        {/* page number */}
        <div style={{
          position: 'absolute', left: 0, right: 0, bottom: pad * 0.7,
          textAlign: 'center',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 10 * scale, color: t.sub,
          fontVariantNumeric: 'oldstyle-nums tabular-nums',
        }}>· {PDF_SAMPLE.pageNumber} ·</div>
      </div>
    </div>
  );
}


// ════════════════════════════════════════════════════
// 2. PDFTranslationPanel
//    Below-page panel. Header is always visible; body depends on state.
//    `collapsed=true` shrinks to header-only.
// ════════════════════════════════════════════════════
function PDFTranslationPanel({
  theme, state = 'default', lang = 'Chinese',
  collapsed = false, onToggle, page = PDF_SAMPLE.pageNumber,
}) {
  const t = theme;
  const isDark = t.isDark;
  const glyph = (lang === 'Chinese') ? '中' : (lang === 'Japanese' ? '日' : 'Es');
  // Subtly different from the reader bg so the panel reads as a separate
  // surface but still belongs to the page's tonal family.
  const panelBg = isDark
    ? 'rgba(255,255,255,0.025)'
    : 'rgba(20,14,4,0.025)';

  const headerH = 38;
  const showBody = !collapsed;

  return (
    <div style={{
      position: 'relative', height: '100%',
      background: panelBg,
      borderTop: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column',
      overflow: 'hidden',
      transition: 'height 0.22s cubic-bezier(0.32, 0.72, 0, 1)',
    }}>
      {/* Header */}
      <div style={{
        flexShrink: 0, height: headerH,
        padding: '0 16px',
        display: 'flex', alignItems: 'center', gap: 8,
        borderBottom: showBody ? `0.5px solid ${t.rule}` : 'none',
      }}>
        {/* lang glyph chip — same family as the BilingualPill */}
        <div style={{
          display: 'inline-flex', alignItems: 'center', gap: 4,
          padding: '2px 6px 2px 3px', borderRadius: 100,
          background: `${t.accent}1a`,
        }}>
          <span style={{
            width: 15, height: 15, borderRadius: 8, background: t.accent,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontSize: 8.5, fontWeight: 700,
            letterSpacing: 0.2,
          }}>EN</span>
          <span style={{ color: t.accent, opacity: 0.7, fontSize: 9 }}>↔</span>
          <span style={{
            fontFamily: PDF_TR_FONT, color: t.accent,
            fontWeight: 700, fontSize: 12, lineHeight: 1,
          }}>{glyph}</span>
        </div>
        <div style={{
          fontSize: 11.5, color: t.sub, fontWeight: 500,
          letterSpacing: 0.3,
        }}>
          Page {page}
          {state === 'loading' && <span style={{ marginLeft: 6, color: t.accent }}>· translating…</span>}
          {state === 'offline' && <span style={{ marginLeft: 6 }}>· offline</span>}
          {state === 'empty'   && <span style={{ marginLeft: 6 }}>· no text on page</span>}
        </div>
        <div style={{ flex: 1 }}/>
        {/* collapse / expand */}
        <button onClick={onToggle} aria-label={collapsed ? 'Expand translation' : 'Collapse translation'}
          style={{
            width: 24, height: 24, borderRadius: 12, border: 'none',
            background: 'transparent', cursor: 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: t.sub,
          }}>
          <svg width="11" height="11" viewBox="0 0 11 11" fill="none"
            stroke="currentColor" strokeWidth="1.8" strokeLinecap="round"
            style={{ transform: collapsed ? 'rotate(180deg)' : 'none', transition: 'transform 0.18s' }}>
            <path d="M2 7l3.5-3.5L9 7"/>
          </svg>
        </button>
      </div>

      {/* Body */}
      {showBody && (
        <div className="hide-scroll" style={{
          flex: 1, overflow: 'auto', padding: '12px 16px 16px',
          animation: 'fadeIn 0.22s ease-out',
        }}>
          {state === 'default' && <PDFTrDefault t={t} lang={lang}/>}
          {state === 'loading' && <PDFTrLoading t={t}/>}
          {state === 'offline' && <PDFTrOffline t={t} lang={lang}/>}
          {state === 'empty'   && <PDFTrEmpty t={t}/>}
        </div>
      )}
    </div>
  );
}

// Default — paragraphs of translation. Type echoes the interlinear style
// (smaller than source, line-height 1.55, sub color) so a user toggling
// between EPUB and PDF in bilingual mode sees the same hierarchy.
function PDFTrDefault({ t, lang }) {
  const paras = PDF_SAMPLE_TR[lang] || PDF_SAMPLE_TR.Chinese;
  return (
    <div style={{
      fontFamily: PDF_TR_FONT, fontSize: 13, lineHeight: 1.65,
      color: t.ink, opacity: 0.85,
    }}>
      {paras.map((p, i) => (
        <p key={i} style={{
          margin: 0, marginBottom: i === paras.length - 1 ? 0 : 8,
          textIndent: i === 0 ? 0 : '1.8em',
        }}>{p}</p>
      ))}
    </div>
  );
}

// Loading — three shimmer lines per paragraph plus a "translating" label.
// Keep it intentionally less elaborate than the default state — this is
// the state a user sees for ~1-3s, not a destination.
function PDFTrLoading({ t }) {
  const shimmer = t.isDark
    ? 'linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,255,255,0.12), rgba(255,255,255,0.04))'
    : 'linear-gradient(90deg, rgba(20,14,4,0.04), rgba(20,14,4,0.10), rgba(20,14,4,0.04))';
  const Bar = ({ w, mb = 8 }) => (
    <div style={{
      height: 10, width: w, borderRadius: 3, marginBottom: mb,
      background: shimmer, backgroundSize: '200% 100%',
      animation: 'pdfShimmer 1.4s ease-in-out infinite',
    }}/>
  );
  return (
    <>
      <style>{`@keyframes pdfShimmer { 0% { background-position: 100% 0; } 100% { background-position: -100% 0; } }`}</style>
      <Bar w="92%"/>
      <Bar w="88%"/>
      <Bar w="64%" mb={16}/>
      <Bar w="90%"/>
      <Bar w="46%"/>
    </>
  );
}

// Offline — explicit affordance + retry CTA. Doesn't pretend to translate
// from a stale cache; says exactly what's missing and what unlocks it.
function PDFTrOffline({ t, lang }) {
  return (
    <div style={{
      display: 'flex', flexDirection: 'column', alignItems: 'flex-start',
      gap: 10, paddingTop: 4,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        {/* cloud-off glyph drawn inline (no Icons.CloudOff in the kit) */}
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none"
          stroke={t.sub} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
          <path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18"/>
          <path d="M3 3l18 18"/>
        </svg>
        <div style={{ fontSize: 12.5, color: t.ink, fontWeight: 600 }}>
          Translation unavailable offline
        </div>
      </div>
      <div style={{ fontSize: 12, color: t.sub, lineHeight: 1.5 }}>
        This page hasn’t been translated yet. Connect to the
        internet and tap retry, or translate a single paragraph
        on demand with the AI tab.
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
        <button style={{
          padding: '6px 12px', borderRadius: 100, border: 'none',
          background: t.accent, color: '#fff', cursor: 'pointer',
          fontFamily: 'inherit', fontSize: 12, fontWeight: 600,
          display: 'inline-flex', alignItems: 'center', gap: 5,
        }}>
          <svg width="11" height="11" viewBox="0 0 12 12" fill="none"
            stroke="currentColor" strokeWidth="1.8" strokeLinecap="round">
            <path d="M2 6a4 4 0 017-2.6l1.5 1.5M10 2v3H7"/>
            <path d="M10 6a4 4 0 01-7 2.6L1.5 7M2 10V7h3"/>
          </svg>
          <span>Retry</span>
        </button>
        <button style={{
          padding: '6px 12px', borderRadius: 100,
          background: 'transparent',
          border: `0.5px solid ${t.rule}`,
          color: t.ink, cursor: 'pointer',
          fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
        }}>Open AI tab</button>
      </div>
    </div>
  );
}

// Empty — page has no extractable text (image-only, scanned w/o OCR,
// title page, etc). Distinct copy from "offline" so the user doesn't keep
// hitting retry on a page that will never translate.
function PDFTrEmpty({ t }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '6px 0',
    }}>
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none"
        stroke={t.sub} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round"
        style={{ flexShrink: 0 }}>
        <rect x="3.5" y="4.5" width="17" height="15" rx="1.5"/>
        <path d="M3.5 16.5l5-4 3 3 4-5 5 6"/>
        <circle cx="9" cy="9" r="1.4"/>
      </svg>
      <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.45 }}>
        No translatable text on this page — the page contains only an
        image or scan. Continue to the next page for the translation.
      </div>
    </div>
  );
}


// ════════════════════════════════════════════════════
// 3. PDFPeekSheet — alternative B (peek/expand). Drawer pinned to bottom;
//    peek = 36pt grabber + 1-line summary; expanded = ~52% height with
//    full body. Used in §B of the canvas.
// ════════════════════════════════════════════════════
function PDFPeekSheet({ theme, expanded, state, lang, onToggle, page = PDF_SAMPLE.pageNumber }) {
  const t = theme;
  const peekH = 56;
  const expH = 360;
  const h = expanded ? expH : peekH;
  const paras = PDF_SAMPLE_TR[lang] || PDF_SAMPLE_TR.Chinese;
  const firstLine = paras[0];

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 56, height: h,
      background: t.isDark ? '#221f1c' : '#fcf8ef',
      borderTopLeftRadius: 16, borderTopRightRadius: 16,
      boxShadow: '0 -10px 28px rgba(0,0,0,0.18)',
      transition: 'height 0.26s cubic-bezier(0.32,0.72,0,1)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
      zIndex: 10,
    }}>
      {/* grabber + header */}
      <div onClick={onToggle} style={{
        flexShrink: 0, padding: '7px 14px 8px',
        cursor: 'pointer',
        borderBottom: expanded ? `0.5px solid ${t.rule}` : 'none',
      }}>
        <div style={{
          width: 36, height: 4, borderRadius: 2, margin: '0 auto 6px',
          background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.14)',
        }}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '2px 6px 2px 3px', borderRadius: 100,
            background: `${t.accent}1a`,
          }}>
            <span style={{
              width: 15, height: 15, borderRadius: 8, background: t.accent,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              color: '#fff', fontSize: 8.5, fontWeight: 700,
            }}>EN</span>
            <span style={{ color: t.accent, opacity: 0.7, fontSize: 9 }}>↔</span>
            <span style={{
              fontFamily: PDF_TR_FONT, color: t.accent,
              fontWeight: 700, fontSize: 12, lineHeight: 1,
            }}>中</span>
          </div>
          <div style={{ fontSize: 11.5, color: t.sub, fontWeight: 500 }}>
            Page {page}
          </div>
          <div style={{ flex: 1 }}/>
          {!expanded && state === 'default' && (
            <div style={{
              flex: '0 1 auto', minWidth: 0,
              fontFamily: PDF_TR_FONT, fontSize: 12, color: t.sub,
              whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
              maxWidth: 200,
            }}>{firstLine}</div>
          )}
        </div>
      </div>
      {/* body when expanded */}
      {expanded && (
        <div className="hide-scroll" style={{
          flex: 1, overflow: 'auto', padding: '12px 16px 16px',
        }}>
          {state === 'default' && <PDFTrDefault t={t} lang={lang}/>}
          {state === 'loading' && <PDFTrLoading t={t}/>}
          {state === 'offline' && <PDFTrOffline t={t} lang={lang}/>}
          {state === 'empty'   && <PDFTrEmpty t={t}/>}
        </div>
      )}
    </div>
  );
}


// ════════════════════════════════════════════════════
// 4. PDFReaderShell — page + panel + chrome. variant: 'split' | 'sheet'
// ════════════════════════════════════════════════════
function PDFReaderShell({
  theme, panelState = 'default', panelCollapsed = false,
  variant = 'split', sheetExpanded = false, lang = 'Chinese',
}) {
  const t = theme;
  const topH = 92;
  const botH = 56;

  // Split layout — panel height proportional to body. When collapsed the
  // panel shrinks to header-only (38pt) so the page reclaims the space.
  const splitPanelH = panelCollapsed ? 38 : 260;

  return (
    <div style={{
      position: 'absolute', inset: 0, background: t.bg, overflow: 'hidden',
    }}>
      {/* top chrome */}
      <PDFTopChrome theme={t} lang={lang}/>

      {/* page region */}
      <div style={{
        position: 'absolute', top: topH, left: 0, right: 0,
        bottom: (variant === 'split') ? (botH + splitPanelH) : botH,
        transition: 'bottom 0.22s cubic-bezier(0.32,0.72,0,1)',
      }}>
        <PDFPageMock theme={t}/>
      </div>

      {/* split: persistent below-page panel */}
      {variant === 'split' && (
        <div style={{
          position: 'absolute', left: 0, right: 0,
          bottom: botH, height: splitPanelH,
          transition: 'height 0.22s cubic-bezier(0.32,0.72,0,1)',
        }}>
          <PDFTranslationPanel
            theme={t} state={panelState} lang={lang}
            collapsed={panelCollapsed}/>
        </div>
      )}

      {/* sheet variant */}
      {variant === 'sheet' && (
        <PDFPeekSheet
          theme={t} state={panelState} lang={lang}
          expanded={sheetExpanded}/>
      )}

      {/* bottom chrome */}
      <PDFBottomChrome theme={t}/>
    </div>
  );
}


// ════════════════════════════════════════════════════
// 5. Slimmed-down chrome — matches the production reader's vocabulary
//    (back chevron / italic title / icon row + bottom toolbar) but
//    self-contained so this canvas doesn't have to pull in the whole
//    ReaderScreen tree.
// ════════════════════════════════════════════════════
function PDFTopChrome({ theme, lang }) {
  const t = theme;
  const glyph = (lang === 'Chinese') ? '中' : (lang === 'Japanese' ? '日' : 'Es');
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      paddingTop: 36, paddingBottom: 8, zIndex: 30,
      background: t.chrome,
      borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 14px',
      }}>
        <button style={{
          display: 'flex', alignItems: 'center', gap: 2,
          padding: '6px 6px', background: 'none', border: 'none', cursor: 'pointer',
          color: t.accent, fontFamily: 'inherit', fontSize: 14, fontWeight: 500,
        }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none"
            stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round">
            <path d="M15 6l-6 6 6 6"/>
          </svg>
          <span>Library</span>
        </button>
        <div style={{
          flex: 1, textAlign: 'center', padding: '0 8px',
          overflow: 'hidden', whiteSpace: 'nowrap',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>
          <span>Pride and Prejudice.pdf</span>
          {/* bilingual pill */}
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 3,
            padding: '2px 7px 2px 3px', borderRadius: 100, marginLeft: 6,
            background: `${t.accent}1a`, color: t.accent,
            fontStyle: 'normal', fontFamily: '"Inter", system-ui',
            fontSize: 9.5, fontWeight: 600, verticalAlign: 'middle',
          }}>
            <span style={{
              width: 14, height: 14, borderRadius: 7, background: t.accent,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              color: '#fff', fontSize: 8, fontWeight: 700,
            }}>EN</span>
            <span style={{ opacity: 0.7, fontSize: 8 }}>↔</span>
            <span style={{ fontFamily: PDF_TR_FONT, fontWeight: 700, fontSize: 11 }}>{glyph}</span>
          </span>
        </div>
        <div style={{ display: 'flex', gap: 0 }}>
          {/* search · more */}
          {[
            <svg key="s" width="17" height="17" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.7" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>,
            <svg key="m" width="17" height="17" viewBox="0 0 24 24" fill={t.ink} strokeLinecap="round"><circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/></svg>,
          ].map((ico, i) => (
            <button key={i} style={{
              width: 32, height: 32, borderRadius: 16, background: 'none', border: 'none',
              cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{ico}</button>
          ))}
        </div>
      </div>
    </div>
  );
}

function PDFBottomChrome({ theme }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0,
      height: 56, paddingBottom: 14, paddingTop: 8, zIndex: 30,
      background: t.chrome,
      borderTop: `0.5px solid ${t.rule}`,
      display: 'flex', justifyContent: 'space-around', alignItems: 'center',
    }}>
      {[
        { glyph: 'TOC', label: 'Contents' },
        { glyph: '✺',  label: 'Notes' },
        { glyph: 'Aa', label: 'Display' },
        { glyph: '✦',  label: 'AI', accent: true },
      ].map((b, i) => (
        <div key={i} style={{
          display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 1,
          color: b.accent ? t.accent : t.sub,
        }}>
          <div style={{
            fontFamily: b.glyph === 'Aa' ? 'Georgia, serif' : 'inherit',
            fontSize: b.glyph === 'TOC' ? 9 : 16, fontWeight: 700,
            lineHeight: 1, letterSpacing: b.glyph === 'TOC' ? 0.5 : 0,
          }}>{b.glyph}</div>
          <div style={{ fontSize: 9, fontWeight: 500 }}>{b.label}</div>
        </div>
      ))}
    </div>
  );
}


Object.assign(window, {
  PDF_SAMPLE, PDF_SAMPLE_TR,
  PDFPageMock, PDFTranslationPanel, PDFPeekSheet,
  PDFReaderShell, PDFTopChrome, PDFBottomChrome,
});
