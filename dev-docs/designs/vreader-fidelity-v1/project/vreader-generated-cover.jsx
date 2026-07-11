// Non-interactive generated-cover fallback for the Book Details sheet · #1905
// (blocks feature #134 — Android reader More menu + book details + share).
//
// The committed missing-cover state (vreader-book-details.jsx CoverWithSwap) is
// INTERACTIVE — a "Tap to add cover" placeholder + a pencil "Replace cover"
// overlay + an Actions "Add cover…" row. But Android has NO cover store (the
// Book model has no coverPath — verified), so EVERY Android book hits the
// missing-cover branch and none of those controls can be honored. Shipping them
// would be dead "Tap to add cover" controls (rule 51 + #129's no-dead-control
// rule). So feature #134 ships NO cover art at all in the details sheet.
//
// This file designs the missing piece: a NON-INTERACTIVE generated-cover tile
// — a deterministic title-initial monogram — that stands in for the absent
// cover, plus the details-sheet composition that drops the pencil overlay and
// the "Add cover…" Actions row entirely.
//
// ────────────────────────────────────────────────────
// DECISION SUMMARY
// ────────────────────────────────────────────────────
//
// The tile · a generated monogram in the app's existing generative-cover
//   vocabulary (vreader-cover.jsx BookCover: cloth-tone ground, spine shadow,
//   page edge, serif type). Ground colour is DETERMINISTIC from the title, so
//   the same book always gets the same cover and a shelf of them reads as
//   varied, not a wall of identical placeholders. A large serif initial is the
//   hero; the title (2-line clamp) + author sit at the base like a real
//   spine-less paperback. No dashed "empty" border, no glyph that says
//   "missing" — it's a cover, not a hole.
//
// Non-interactive · the tile has no pencil overlay, no tap target, no focus
//   ring. The details sheet drops the "Add cover…" Actions row. Nothing on
//   this surface promises an action Android can't perform. If a cover store
//   ever lands, the tile becomes the fallback and the swap controls return —
//   the composition doesn't have to change.
//
// Composition · the tile leads the stacked layout exactly where the real
//   cover would; the title / author / year block reads the same below it. In
//   the compact (split) layout it sits left. Because the ground is tonal and
//   the type on it is small, it never competes with the sheet's own title.
//
// Light + dark · the tile is theme-independent (a cover looks the same in
//   both) — only the surrounding sheet chrome changes. This is deliberate:
//   inverting a "cover" per theme would read as a UI surface, not artwork.

const GC_SERIF = '"Source Serif 4", Georgia, serif';
const GC_SANS = '"Inter", -apple-system, system-ui, sans-serif';

// Deterministic cloth tones — muted, harmonious (matched lightness/chroma,
// varied hue). A book cover, not a saturated placeholder.
const GC_TONES = [
  { bg: '#7c3b34', ink: '#f3e7d4', accent: '#e6c69a' }, // red-brown
  { bg: '#3f5a4a', ink: '#eef0e2', accent: '#ccd8a8' }, // forest
  { bg: '#3f4d63', ink: '#e8ecf3', accent: '#b9c8e0' }, // slate blue
  { bg: '#8a6a30', ink: '#f6ecd6', accent: '#e8cf92' }, // ochre
  { bg: '#5f3f57', ink: '#f1e6ee', accent: '#d9b8ce' }, // plum
  { bg: '#35595c', ink: '#e6f0ef', accent: '#a9d2cf' }, // teal
];

function gcToneFor(title) {
  let h = 0;
  for (let i = 0; i < title.length; i++) h = (h * 31 + title.charCodeAt(i)) >>> 0;
  return GC_TONES[h % GC_TONES.length];
}
function gcInitial(title) {
  const m = (title || '').match(/[A-Za-z0-9]/);
  return (m ? m[0] : '?').toUpperCase();
}

// ── the generated-cover tile — non-interactive ──────────────
function CoverMonogram({ book, width = 120, height = 180 }) {
  const tone = gcToneFor(book.title);
  const initial = gcInitial(book.title);
  const pad = Math.round(width * 0.11);
  return (
    <div aria-hidden="false" role="img"
      aria-label={`Generated cover for ${book.title} by ${book.author}`}
      style={{
        width, height, borderRadius: 4, position: 'relative', overflow: 'hidden',
        background: tone.bg, color: tone.ink, flexShrink: 0,
        boxShadow: '0 1px 2px rgba(0,0,0,0.18), 0 8px 24px rgba(0,0,0,0.18), inset 0 0 0 1px rgba(0,0,0,0.08)',
      }}>
      {/* spine shadow + page edge — same as BookCover */}
      <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: 6, background: 'linear-gradient(to right, rgba(0,0,0,0.28), rgba(0,0,0,0) 60%)' }} />
      <div style={{ position: 'absolute', right: 0, top: 0, bottom: 0, width: 2, background: 'linear-gradient(to left, rgba(255,255,255,0.16), rgba(0,0,0,0.14))' }} />
      {/* hairline frame */}
      <div style={{ position: 'absolute', inset: pad * 0.7, border: `1px solid ${tone.accent}`, opacity: 0.4, borderRadius: 1 }} />

      {/* big serif initial */}
      <div style={{
        position: 'absolute', top: pad * 1.1, left: 0, right: 0, textAlign: 'center',
        fontFamily: GC_SERIF, fontWeight: 600, fontStyle: 'italic',
        fontSize: width * 0.5, lineHeight: 1, color: tone.ink,
      }}>{initial}</div>

      {/* title + author at the base, like a spine-less paperback */}
      <div style={{ position: 'absolute', left: pad, right: pad, bottom: pad }}>
        <div style={{ width: width * 0.34, height: 1, background: tone.accent, opacity: 0.7, marginBottom: width * 0.05 }} />
        <div style={{
          fontFamily: GC_SERIF, fontWeight: 600, fontSize: Math.max(9.5, width * 0.105), lineHeight: 1.12,
          color: tone.ink, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden',
        }}>{book.title}</div>
        <div style={{
          fontFamily: GC_SANS, fontSize: Math.max(7.5, width * 0.062), letterSpacing: 0.3,
          textTransform: 'uppercase', color: tone.ink, opacity: 0.72, marginTop: width * 0.03,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        }}>{book.author}</div>
      </div>
    </div>
  );
}

// ── the details sheet with the generated cover, no swap controls ──
function gcMiniBtn(t) {
  return {
    width: 26, height: 26, borderRadius: 8, padding: 0,
    background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
    border: 'none', cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
  };
}

function GCSectionLabel({ t, children }) {
  return <div style={{ fontFamily: GC_SANS, fontSize: 12, fontWeight: 600, color: t.sub, letterSpacing: 0.8, textTransform: 'uppercase' }}>{children}</div>;
}

function GCMetaList({ t, book }) {
  const fingerprint = `${(book.format || 'epub').toLowerCase()}:8a4f2e91b7c3…2c1b`;
  const rows = [
    { label: 'Format', value: book.format, mono: true },
    { label: 'Size', value: book.size, mono: true },
    { label: 'Pages', value: `${book.pages}`, mono: true },
    { label: 'Fingerprint', value: fingerprint, mono: true, copy: true },
  ];
  return (
    <div style={{ marginTop: 22 }}>
      <GCSectionLabel t={t}>Metadata</GCSectionLabel>
      <div style={{ marginTop: 8, borderRadius: 14, overflow: 'hidden', background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff', boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)' }}>
        {rows.map((r, i) => (
          <div key={r.label} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '11px 14px', borderBottom: i === rows.length - 1 ? 'none' : `0.5px solid ${t.rule}` }}>
            <div style={{ width: 96, fontFamily: GC_SANS, fontSize: 12, fontWeight: 500, color: t.sub, flexShrink: 0 }}>{r.label}</div>
            <div style={{ flex: 1, minWidth: 0, fontSize: 13.5, color: t.ink, fontFamily: r.mono ? '"SF Mono", Menlo, monospace' : 'inherit', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>{r.value}</div>
            {r.copy && (
              <button style={gcMiniBtn(t)} aria-label="Copy fingerprint">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none"><rect x="8" y="4" width="12" height="14" rx="2" stroke={t.sub} strokeWidth="1.6"/><path d="M4 8v10a2 2 0 002 2h10" stroke={t.sub} strokeWidth="1.6"/></svg>
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

// Actions WITHOUT the cover-swap row — the whole point of the issue.
function GCActionList({ t }) {
  const actions = [
    { label: 'Share book…', glyph: (p) => <window.Icons.Share {...p}/> },
    { label: 'Export annotations…', sub: 'Markdown · JSON · VReader JSON', glyph: (p) => <window.Icons.Download {...p}/> },
  ];
  return (
    <div style={{ marginTop: 22 }}>
      <GCSectionLabel t={t}>Actions</GCSectionLabel>
      <div style={{ marginTop: 8, borderRadius: 14, overflow: 'hidden', background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff', boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)' }}>
        {actions.map((a, i) => {
          const G = a.glyph;
          return (
            <div key={a.label} style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', borderBottom: i === actions.length - 1 ? 'none' : `0.5px solid ${t.rule}` }}>
              <div style={{ width: 28, height: 28, borderRadius: 8, background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
                <G size={14} color={t.ink} stroke={1.7}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontFamily: GC_SANS, fontSize: 14.5, color: t.ink, fontWeight: 500, lineHeight: 1.2 }}>{a.label}</div>
                {a.sub && <div style={{ fontFamily: GC_SANS, fontSize: 11, color: t.sub, marginTop: 2 }}>{a.sub}</div>}
              </div>
              <window.Icons.Chevron size={13} color={t.sub} stroke={2}/>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function GCTag({ t, children }) {
  return <span style={{ padding: '3px 10px', borderRadius: 100, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', color: t.ink, fontSize: 11, fontWeight: 500, fontFamily: GC_SANS }}>{children}</span>;
}

function BookDetailsGeneratedSheet({ themeKey = 'paper', book, layout = 'stacked', height = 720 }) {
  const t = window.THEMES[themeKey];
  const b = book || GC_BOOK;
  const stacked = layout === 'stacked';
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0 }} />
      <window.Sheet theme={t} onClose={() => {}} height={height - (stacked ? 90 : 170)} title="Book details"
        trailing={
          <button style={{ background: 'rgba(0,0,0,0.06)', border: 'none', width: 28, height: 28, borderRadius: 14, padding: 0, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center' }} aria-label="Share">
            <window.Icons.Share size={16} color={t.ink} stroke={1.7}/>
          </button>
        }>
        <div style={{ padding: stacked ? '20px 22px 32px' : '18px 20px 30px' }}>
          {stacked ? (
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
              <CoverMonogram book={b} width={120} height={180}/>
              <div style={{ textAlign: 'center', width: '100%' }}>
                <div style={{ fontFamily: GC_SERIF, fontSize: 22, fontStyle: 'italic', fontWeight: 600, color: t.ink, lineHeight: 1.12, textWrap: 'pretty', margin: '2px 0 6px' }}>{b.title}</div>
                <div style={{ fontFamily: GC_SANS, fontSize: 13, color: t.sub, lineHeight: 1.35 }}>{b.author} · {b.year}</div>
              </div>
              {b.tags && <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', justifyContent: 'center' }}>{b.tags.map((tg) => <GCTag key={tg} t={t}>{tg}</GCTag>)}</div>}
            </div>
          ) : (
            <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
              <CoverMonogram book={b} width={92} height={138}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontFamily: GC_SERIF, fontSize: 18, fontStyle: 'italic', fontWeight: 600, color: t.ink, lineHeight: 1.15, textWrap: 'pretty', marginBottom: 4 }}>{b.title}</div>
                <div style={{ fontFamily: GC_SANS, fontSize: 12.5, color: t.sub, lineHeight: 1.35, marginBottom: 10, display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical', overflow: 'hidden' }}>{b.author} · {b.year}</div>
                {b.tags && <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>{b.tags.slice(0, 3).map((tg) => <GCTag key={tg} t={t}>{tg}</GCTag>)}</div>}
              </div>
            </div>
          )}
          <GCMetaList t={t} book={b}/>
          <GCActionList t={t}/>
        </div>
      </window.Sheet>
    </window.TtsFrame>
  );
}

const GC_BOOK = {
  title: 'Pride and Prejudice', author: 'Jane Austen', year: 1813,
  format: 'EPUB', size: '1.2 MB', pages: 384, tags: ['Classic', 'Romance'],
};

Object.assign(window, {
  CoverMonogram, BookDetailsGeneratedSheet, gcToneFor, gcInitial, GC_TONES, GC_BOOK,
});
