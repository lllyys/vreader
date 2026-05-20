// Bilingual offline / translation-unavailable inline state — issue #1024.
//
// PARENT FEATURE: #56 bilingual reading mode. Paragraph-interlinear renderer
// (vreader-bilingual.jsx → BilingualPageContent) needs a visible state for:
//   (c) chapter not cached + device offline.
//
// Current shipped behavior (per the issue): silent source-only fallback. This
// design adds the visible affordance.
//
// CRITICAL CONSTRAINTS FROM THE ISSUE
// - Inline within the interlinear flow, NOT a modal or sheet.
// - Must preserve the source-paragraph + translation-paragraph rhythm.
// - Distinct from "translation in progress" loading state.
// - Retry affordance once back online (optional / could be automatic).
//
// SYSTEM
// The existing translation block uses a left accent border + indent + sub
// color + 0.88× font. Every state below INHERITS that shell so the eye sees
// "translation slot is here" even when content is unavailable. The shell IS
// the rhythm — we don't break it for any state.
//
// THREE APPROACHES
//   A (canonical) — Ghost placeholder + page banner.
//     Per-paragraph: shell stays; content is a dim dashed bar (~1 line tall).
//     Page-top banner explains once; offers Retry when back online.
//     Why canonical: copy isn't repeated across 8-12 paragraphs of a page.
//
//   B — Inline italic copy.
//     Per-paragraph: shell stays; content is one italic muted line
//     ("Translation will appear when online"). No banner needed.
//     Why considered: more explicit; better for screen readers.
//
//   C — Source-only collapse + banner.
//     Translation slot is omitted entirely. Banner is the only signal.
//     Why considered: cleanest visually. Why not canonical: the user just
//     toggled bilingual ON; a page that looks identical to non-bilingual
//     reads as "feature failed".
//
// LOADING (distinct)
//   - Shell stays; content is 2 shimmer bars. Header pill / banner indicates
//     "translating…" so the user can tell it's transient.
//
// PARTIAL
//   - Per-paragraph state. Cached paragraphs render normally; uncached use
//     the ghost. Banner counts ("3 of 9 paragraphs translated").


// ────────────────────────────────────────────────────
// Shared shell — exact replica of BilingualPageContent's translation block.
// Every state below wraps its content in this so the layout rhythm is
// preserved across cached / uncached / loading / empty.
// ────────────────────────────────────────────────────
function BilingualSlot({ t, fontSize, isRTL = false, dim = false, children, style = {} }) {
  const accentAlpha = dim ? `${t.accent}33` : `${t.accent}55`;
  return (
    <div style={{
      margin: '6px 0 0',
      borderLeft: isRTL ? 'none' : `2px solid ${accentAlpha}`,
      borderRight: isRTL ? `2px solid ${accentAlpha}` : 'none',
      paddingLeft:  isRTL ? 0 : fontSize * 0.7,
      paddingRight: isRTL ? fontSize * 0.7 : 0,
      direction: isRTL ? 'rtl' : 'ltr',
      textAlign: isRTL ? 'right' : 'left',
      ...style,
    }}>{children}</div>
  );
}


// ────────────────────────────────────────────────────
// State 1 — Cached translation (the baseline; included so the canvas can
//   show it side-by-side with the offline states for rhythm comparison).
// ────────────────────────────────────────────────────
function BilingualCachedSlot({ theme, fontSize, lang = 'Chinese', text, isRTL = false }) {
  const t = theme;
  const ff = (lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean')
    ? '"Songti SC", "Source Han Serif", serif'
    : '"Source Serif 4", Georgia, serif';
  return (
    <BilingualSlot t={t} fontSize={fontSize} isRTL={isRTL}>
      <p style={{
        margin: 0, fontFamily: ff,
        fontSize: fontSize * 0.88, lineHeight: 1.55, color: t.sub,
      }}>{text}</p>
    </BilingualSlot>
  );
}


// ────────────────────────────────────────────────────
// State 2 — Loading ("translating now"). Distinct shimmer bars so users
//   learn the difference. Two bars on most paragraphs; the variability
//   keeps it from reading like a UI element rather than "in-flight content".
// ────────────────────────────────────────────────────
function BilingualLoadingSlot({ theme, fontSize, isRTL = false, barWidths = ['92%', '54%'] }) {
  const t = theme;
  const shimmer = t.isDark
    ? 'linear-gradient(90deg, rgba(255,255,255,0.04), rgba(255,255,255,0.12), rgba(255,255,255,0.04))'
    : 'linear-gradient(90deg, rgba(20,14,4,0.04), rgba(20,14,4,0.10), rgba(20,14,4,0.04))';
  return (
    <BilingualSlot t={t} fontSize={fontSize} isRTL={isRTL}>
      <style>{`@keyframes bShim { 0% { background-position: 100% 0; } 100% { background-position: -100% 0; } }`}</style>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 5, padding: '3px 0' }}>
        {barWidths.map((w, i) => (
          <div key={i} style={{
            height: fontSize * 0.7, width: w, borderRadius: 3,
            background: shimmer, backgroundSize: '200% 100%',
            animation: 'bShim 1.4s ease-in-out infinite',
          }}/>
        ))}
      </div>
    </BilingualSlot>
  );
}


// ────────────────────────────────────────────────────
// State 3a — APPROACH A: Ghost placeholder.
//   Same shell, dim accent border (33 instead of 55), single dashed line.
//   NO copy. The page banner carries the explanation once.
//   Optional cloud-off glyph on the FIRST instance of the page only — set
//   `withGlyph` on that one and leave others bare.
// ────────────────────────────────────────────────────
function BilingualGhostSlot({ theme, fontSize, isRTL = false, withGlyph = false }) {
  const t = theme;
  const dashColor = t.isDark
    ? 'rgba(255,255,255,0.16)'
    : 'rgba(20,14,4,0.18)';
  return (
    <BilingualSlot t={t} fontSize={fontSize} isRTL={isRTL} dim>
      <div style={{
        height: fontSize * 0.88 * 1.55,  // matches one line of translation
        display: 'flex', alignItems: 'center', gap: 8,
        opacity: 0.85,
      }}>
        {withGlyph && (
          <svg width={fontSize * 0.9} height={fontSize * 0.9} viewBox="0 0 24 24"
            fill="none" stroke={t.sub} strokeWidth="1.6"
            strokeLinecap="round" strokeLinejoin="round"
            style={{ flexShrink: 0, opacity: 0.75 }}>
            <path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18"/>
            <path d="M3 3l18 18"/>
          </svg>
        )}
        <div style={{
          flex: 1, height: 0, minHeight: 1,
          borderTop: `1px dashed ${dashColor}`,
        }}/>
      </div>
    </BilingualSlot>
  );
}


// ────────────────────────────────────────────────────
// State 3b — APPROACH B: Inline italic copy.
//   Same shell, italic muted line per paragraph. More explicit. Noisier
//   when many paragraphs are offline — but better for screen readers and
//   for users who only see one paragraph on screen.
// ────────────────────────────────────────────────────
function BilingualInlineCopySlot({ theme, fontSize, isRTL = false }) {
  const t = theme;
  return (
    <BilingualSlot t={t} fontSize={fontSize} isRTL={isRTL} dim>
      <p style={{
        margin: 0,
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: fontSize * 0.78, lineHeight: 1.5,
        fontStyle: 'italic', color: t.sub, opacity: 0.7,
      }}>Translation will appear when back online</p>
    </BilingualSlot>
  );
}


// ────────────────────────────────────────────────────
// State 4 — Page-level offline banner.
//   Sits between the chapter heading and the first paragraph (or where the
//   chapter heading would be on non-chapter-start pages). Two variants:
//     status = 'offline' — generic "you're offline, translations cached"
//     status = 'online'  — back online + Retry button (uncached chapters)
//     status = 'partial' — some paragraphs translated, some not (mixed)
// ────────────────────────────────────────────────────
function BilingualPageBanner({ theme, status = 'offline', cached = 0, total = 0, onRetry }) {
  const t = theme;
  const isOffline = status === 'offline';
  const isPartial = status === 'partial';
  const isReady   = status === 'online';

  const bg = t.isDark
    ? (isReady ? `${t.accent}22` : 'rgba(255,255,255,0.045)')
    : (isReady ? `${t.accent}14` : 'rgba(20,14,4,0.045)');

  const Glyph = () => {
    if (isReady) {
      // cloud-on-line "ready" glyph
      return (
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
          stroke={t.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
          <path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18"/>
          <path d="M9 13l2 2 4-4"/>
        </svg>
      );
    }
    return (
      <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
        stroke={t.sub} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18"/>
        <path d="M3 3l18 18"/>
      </svg>
    );
  };

  const label =
    isReady   ? 'Back online — fetch translations'
  : isPartial ? `Partial translation — ${cached} of ${total} cached`
  :             'Bilingual mode · offline';
  const detail =
    isReady   ? 'Tap Retry to translate this chapter.'
  : isPartial ? 'Missing paragraphs will fill in when you reconnect.'
  :             'Translations will appear when you reconnect.';

  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10,
      padding: '8px 12px', margin: '0 0 14px',
      borderRadius: 10, background: bg,
      border: isReady ? `0.5px solid ${t.accent}55` : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 22, height: 22, borderRadius: 11, flexShrink: 0,
        background: isReady
          ? `${t.accent}22`
          : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(20,14,4,0.05)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Glyph/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 11.5, color: t.ink, fontWeight: 600,
          letterSpacing: 0.2, lineHeight: 1.2,
        }}>{label}</div>
        <div style={{
          fontSize: 10.5, color: t.sub, marginTop: 2, lineHeight: 1.3,
        }}>{detail}</div>
      </div>
      {isReady && (
        <button onClick={onRetry} style={{
          padding: '4px 10px', borderRadius: 100, border: 'none',
          background: t.accent, color: '#fff', cursor: 'pointer',
          fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600,
          flexShrink: 0,
        }}>Retry</button>
      )}
    </div>
  );
}


// ────────────────────────────────────────────────────
// Renderer — drop-in replacement for BilingualPageContent that takes a
// per-paragraph cache map. Used by every artboard so the variations stay
// faithful to the production layout.
//
// paragraphs:    [{ text, state }]
//   state ∈ 'cached' | 'offline' | 'loading'   (default 'cached')
// approach:      'A' (ghost), 'B' (inline copy), 'C' (collapse → no slot)
// pageStatus:    'offline' | 'partial' | 'online' | 'none'  — banner control
// ────────────────────────────────────────────────────
function BilingualPageContent_OfflineDemo({
  theme, fontFamily = 'serif', fontSize = 17, lineHeight = 1.55, margin = 22,
  lang = 'Chinese',
  paragraphs, translations,
  approach = 'A', pageStatus = 'offline',
  cachedCount = 0, totalCount = 0,
  chapter,
}) {
  const t = theme;
  const ff = fontFamily === 'serif'
    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
    : '"Inter", -apple-system, system-ui, sans-serif';
  const isRTL = lang === 'Arabic';

  // First ghost paragraph on the page carries the cloud-off glyph as a
  // visual anchor; the rest are bare.
  let ghostShown = false;

  return (
    <div style={{
      position: 'absolute', top: 76, bottom: 56,
      left: margin, right: margin, overflow: 'hidden',
    }}>
      {chapter && (
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13, color: t.sub, letterSpacing: 2,
          textTransform: 'uppercase', textAlign: 'center',
          marginBottom: 18, marginTop: 8, fontWeight: 500,
        }}>{chapter}</div>
      )}

      {pageStatus !== 'none' && (
        <BilingualPageBanner theme={t} status={pageStatus}
          cached={cachedCount} total={totalCount} onRetry={() => {}}/>
      )}

      {paragraphs.map((para, i) => {
        const state = para.state || 'cached';
        const tr = translations && translations[i];
        const firstGhost = state === 'offline' && !ghostShown;
        if (state === 'offline') ghostShown = true;
        return (
          <div key={i} style={{ marginBottom: lineHeight * fontSize * 0.55 }}>
            <p style={{
              fontFamily: ff, fontSize, lineHeight, color: t.ink, margin: 0,
              textIndent: i === 0 ? 0 : `${fontSize * 1.4}px`,
              textAlign: 'justify', hyphens: 'auto',
            }}>
              {i === 0 && (
                <span style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: fontSize * 2.6, lineHeight: 0.85,
                  float: 'left', marginRight: 6, marginTop: 4,
                  color: t.accent, fontWeight: 600,
                }}>{para.text[0]}</span>
              )}
              {i === 0 ? para.text.slice(1) : para.text}
            </p>

            {/* translation slot — varies by state and approach */}
            {state === 'cached' && tr && (
              <BilingualCachedSlot theme={t} fontSize={fontSize} lang={lang} text={tr} isRTL={isRTL}/>
            )}
            {state === 'loading' && (
              <BilingualLoadingSlot theme={t} fontSize={fontSize} isRTL={isRTL}
                barWidths={i % 2 ? ['88%', '64%'] : ['92%', '46%']}/>
            )}
            {state === 'offline' && approach === 'A' && (
              <BilingualGhostSlot theme={t} fontSize={fontSize} isRTL={isRTL} withGlyph={firstGhost}/>
            )}
            {state === 'offline' && approach === 'B' && (
              <BilingualInlineCopySlot theme={t} fontSize={fontSize} isRTL={isRTL}/>
            )}
            {/* approach C: nothing — source-only collapse */}
          </div>
        );
      })}
    </div>
  );
}


Object.assign(window, {
  BilingualSlot, BilingualCachedSlot, BilingualLoadingSlot,
  BilingualGhostSlot, BilingualInlineCopySlot, BilingualPageBanner,
  BilingualPageContent_OfflineDemo,
});
