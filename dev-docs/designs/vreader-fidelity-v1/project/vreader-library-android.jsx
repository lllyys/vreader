// Issue #1802 / Feature #110 (Android Phase-3) — library management.
//
// iOS has collections and library search; Android's Room layer can back them,
// but the collections-management + search UI were design-gated (rule 51).
// Built in VReader's vocabulary (reader THEMES for the surface, the shared
// form tokens for the management sheets). Covers are typographic — a tonal
// card + serif title — not illustrated art.
//
// Surfaces:
//   A. Library with a collections shelf-bar (All / a horizontal chip row) +
//      the 2-up cover grid; the collection-filtered view (scoped header).
//   B. Collections management sheet (reorder / rename / delete / new) and the
//      per-book Assign sheet (checklist + create-new inline).
//   C. Search: empty (recents + suggestions), results, no-results.

const LIB_SERIF = '"Source Serif 4", Georgia, serif';
const LIB_SANS = "'Inter', -apple-system, system-ui, sans-serif";

const BOOKS = [
  { t: 'Pride and Prejudice', a: 'Jane Austen', bg: '#6e2b2b', fg: '#f3e7d8', pct: 42 },
  { t: 'Designing Data-Intensive Applications', a: 'Martin Kleppmann', bg: '#244f4a', fg: '#e8ddc8', pct: 18 },
  { t: 'The Pragmatic Programmer', a: 'Hunt & Thomas', bg: '#2f3a46', fg: '#dfe4e8', pct: 76 },
  { t: 'The Beginning of Infinity', a: 'David Deutsch', bg: '#8a6a1f', fg: '#f6ecd2', pct: 9 },
  { t: 'Sapiens', a: 'Yuval Noah Harari', bg: '#4a2f46', fg: '#e8d8e4', pct: 100 },
  { t: 'Dune', a: 'Frank Herbert', bg: '#2f4630', fg: '#dfe8d8', pct: 0 },
];

const COLLECTIONS = ['All', 'Currently Reading', 'To Read', 'Fiction', 'Tech', 'Finished'];

// typographic cover
function Cover({ b, w = 116, showProgress }) {
  const h = Math.round(w * 1.5);
  return (
    <div style={{ width: w, flexShrink: 0 }}>
      <div style={{
        width: w, height: h, borderRadius: 8, background: b.bg, position: 'relative', overflow: 'hidden',
        boxShadow: '0 2px 6px rgba(0,0,0,0.2), inset 0 0 0 0.5px rgba(255,255,255,0.06)',
        padding: '13px 12px', display: 'flex', flexDirection: 'column',
      }}>
        <div style={{ position: 'absolute', left: 0, top: 12, bottom: 12, width: 3, background: 'rgba(255,255,255,0.18)' }} />
        <div style={{ fontFamily: LIB_SERIF, fontWeight: 600, fontSize: w < 100 ? 13 : 15, lineHeight: 1.2, color: b.fg, textWrap: 'pretty' }}>{b.t}</div>
        <div style={{ flex: 1 }} />
        <div style={{ fontFamily: LIB_SANS, fontSize: 9.5, fontWeight: 500, letterSpacing: 0.3, color: b.fg, opacity: 0.72, textTransform: 'uppercase' }}>{b.a}</div>
        {showProgress && b.pct > 0 && b.pct < 100 && (
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 3, background: 'rgba(0,0,0,0.25)' }}>
            <div style={{ height: '100%', width: `${b.pct}%`, background: 'rgba(255,255,255,0.85)' }} />
          </div>
        )}
      </div>
    </div>
  );
}

function LibTopBar({ t, title, trailing }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 18px 12px', flexShrink: 0 }}>
      <div style={{ flex: 1, fontFamily: LIB_SERIF, fontSize: 26, fontWeight: 700, color: t.ink }}>{title}</div>
      {trailing}
    </div>
  );
}

function CollectionBar({ t, active = 'All' }) {
  return (
    <div className="hide-scroll" style={{ display: 'flex', gap: 8, padding: '0 18px 12px', overflowX: 'auto', flexShrink: 0 }}>
      {COLLECTIONS.map((c) => {
        const on = c === active;
        return (
          <span key={c} style={{
            flexShrink: 0, fontFamily: LIB_SANS, fontSize: 13.5, fontWeight: on ? 700 : 500,
            color: on ? t.bg : t.ink, background: on ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)'),
            borderRadius: 100, padding: '8px 15px', whiteSpace: 'nowrap',
          }}>{c}</span>
        );
      })}
    </div>
  );
}

function CoverGrid({ t, books = BOOKS }) {
  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '4px 18px 0' }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '22px 18px' }}>
        {books.map((b, i) => (
          <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-start', gap: 8 }}>
            <Cover b={b} w={152} showProgress />
            <div style={{ width: 152 }}>
              <div style={{ fontFamily: LIB_SERIF, fontSize: 14, fontWeight: 600, color: t.ink, lineHeight: 1.25, textWrap: 'pretty' }}>{b.t}</div>
              <div style={{ fontFamily: LIB_SANS, fontSize: 11.5, color: t.sub, marginTop: 2 }}>{b.a}</div>
            </div>
          </div>
        ))}
      </div>
    </div>
  );
}

// ── A · library + collection-filtered ────────────────────────
function LibraryScreen({ themeKey = 'paper', scope = 'all', height = 880 }) {
  const t = window.THEMES[themeKey];
  const filtered = scope === 'collection' ? [BOOKS[0], BOOKS[2]] : BOOKS;
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        {scope === 'collection' ? (
          <>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 16px 4px', flexShrink: 0 }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.8 }}><path d="M15 6l-6 6 6 6"/></svg>
              <span style={{ fontFamily: LIB_SANS, fontSize: 14, color: t.sub }}>Library</span>
            </div>
            <div style={{ padding: '2px 18px 12px', flexShrink: 0 }}>
              <div style={{ fontFamily: LIB_SERIF, fontSize: 25, fontWeight: 700, color: t.ink }}>Currently Reading</div>
              <div style={{ fontFamily: LIB_SANS, fontSize: 12.5, color: t.sub, marginTop: 2 }}>2 books · edit collection</div>
            </div>
          </>
        ) : (
          <>
            <LibTopBar t={t} title="Library" trailing={
              <div style={{ display: 'flex', gap: 4 }}>
                <div style={{ width: 40, height: 40, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><window.Icons.Search size={22} color={t.ink} /></div>
                <div style={{ width: 40, height: 40, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' }}><window.Icons.More size={22} color={t.ink} /></div>
              </div>
            } />
            <CollectionBar t={t} active="All" />
          </>
        )}
        <CoverGrid t={t} books={filtered} />
      </div>
    </window.TtsFrame>
  );
}

// ── search states ────────────────────────────────────────────
function SearchScreen({ themeKey = 'paper', state = 'results', height = 880 }) {
  const t = window.THEMES[themeKey];
  const q = state === 'empty' ? '' : state === 'noresults' ? 'thermodynamics' : 'pra';
  const results = [BOOKS[2], BOOKS[0]];
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        {/* search field */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '4px 16px 12px', flexShrink: 0 }}>
          <div style={{
            flex: 1, display: 'flex', alignItems: 'center', gap: 9, height: 42, borderRadius: 12, padding: '0 13px',
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)',
            boxShadow: state !== 'empty' ? `inset 0 0 0 1.5px ${t.accent}` : 'none',
          }}>
            <window.Icons.Search size={19} color={t.sub} />
            {q
              ? <span style={{ fontFamily: LIB_SANS, fontSize: 15.5, color: t.ink }}>{q}<span style={{ display: 'inline-block', width: 1.5, height: 18, background: t.accent, verticalAlign: -3, marginLeft: 1 }} /></span>
              : <span style={{ fontFamily: LIB_SANS, fontSize: 15.5, color: t.sub }}>Search title, author, or text…</span>}
            <span style={{ flex: 1 }} />
            {q && <window.Icons.Close size={18} color={t.sub} />}
          </div>
          <span style={{ fontFamily: LIB_SANS, fontSize: 15, color: t.accent, fontWeight: 500 }}>Cancel</span>
        </div>

        <div style={{ flex: 1, overflow: 'hidden', padding: '0 18px' }}>
          {state === 'empty' && (
            <>
              <div style={{ fontFamily: LIB_SANS, fontSize: 12, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: t.sub, margin: '6px 2px 10px' }}>Recent</div>
              {['pragmatic', 'austen', 'data-intensive'].map((r) => (
                <div key={r} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 2px', borderBottom: `0.5px solid ${t.rule}` }}>
                  <window.Icons.Timer size={18} color={t.sub} />
                  <span style={{ flex: 1, fontFamily: LIB_SANS, fontSize: 15, color: t.ink }}>{r}</span>
                  <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={t.sub} strokeWidth="2" strokeLinecap="round"><path d="M7 17L17 7M9 7h8v8"/></svg>
                </div>
              ))}
              <div style={{ fontFamily: LIB_SANS, fontSize: 12, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: t.sub, margin: '20px 2px 10px' }}>Browse collections</div>
              <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8 }}>
                {COLLECTIONS.slice(1).map((c) => (
                  <span key={c} style={{ fontFamily: LIB_SANS, fontSize: 13.5, fontWeight: 500, color: t.ink, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)', borderRadius: 100, padding: '8px 14px' }}>{c}</span>
                ))}
              </div>
            </>
          )}

          {state === 'results' && (
            <>
              <div style={{ fontFamily: LIB_SANS, fontSize: 12.5, color: t.sub, margin: '4px 2px 12px' }}>2 books · 1 in-text match</div>
              {results.map((b, i) => (
                <div key={i} style={{ display: 'flex', gap: 13, padding: '8px 0 16px', borderBottom: `0.5px solid ${t.rule}`, marginBottom: 12 }}>
                  <Cover b={b} w={62} />
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: LIB_SERIF, fontSize: 16, fontWeight: 600, color: t.ink, lineHeight: 1.25 }}>
                      {hl(b.t, 'Pra', t)}
                    </div>
                    <div style={{ fontFamily: LIB_SANS, fontSize: 12.5, color: t.sub, marginTop: 3 }}>{b.a}</div>
                    {i === 0 && (
                      <div style={{ marginTop: 8, fontFamily: LIB_SERIF, fontSize: 13, color: t.sub, lineHeight: 1.45, fontStyle: 'italic' }}>
                        "…the {hlPlain('pragmatic', t)} programmer is quick to adapt…" — Ch. 1
                      </div>
                    )}
                  </div>
                </div>
              ))}
            </>
          )}

          {state === 'noresults' && (
            <div style={{ textAlign: 'center', padding: '70px 30px' }}>
              <div style={{ width: 60, height: 60, borderRadius: 30, background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
                <window.Icons.Search size={28} color={t.sub} />
              </div>
              <div style={{ fontFamily: LIB_SERIF, fontSize: 19, color: t.ink, marginBottom: 8 }}>No matches for "{q}"</div>
              <div style={{ fontFamily: LIB_SANS, fontSize: 14, color: t.sub, lineHeight: 1.5 }}>
                Search looks across titles, authors, and the text of downloaded books. Try a different term.
              </div>
            </div>
          )}
        </div>
      </div>
    </window.TtsFrame>
  );
}

// inline-highlight a query match in a title
function hl(text, q, t) {
  const i = text.toLowerCase().indexOf(q.toLowerCase());
  if (i < 0) return text;
  const wash = t.isDark ? 'rgba(214,136,90,0.3)' : 'rgba(140,47,47,0.16)';
  return <>{text.slice(0, i)}<span style={{ background: wash, borderRadius: 2 }}>{text.slice(i, i + q.length)}</span>{text.slice(i + q.length)}</>;
}
function hlPlain(text, t) {
  const wash = t.isDark ? 'rgba(214,136,90,0.3)' : 'rgba(140,47,47,0.16)';
  return <span style={{ background: wash, borderRadius: 2, fontStyle: 'normal' }}>{text}</span>;
}

// ── B · collections management + assign ──────────────────────
function CollectionsManageSheet({ ui, mode = 'list', height = 880 }) {
  const cols = [
    { name: 'Currently Reading', n: 2, sys: true },
    { name: 'To Read', n: 8 },
    { name: 'Fiction', n: 5 },
    { name: 'Tech', n: 4 },
    { name: 'Finished', n: 11, sys: true },
  ];
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title="Collections"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: LIB_SANS, fontSize: 15, color: ui.sec }}>Done</button>}
        trailing={<span style={{ fontFamily: LIB_SANS, fontSize: 15, fontWeight: 600, color: ui.tint }}>Edit</span>}
        height={height - 36}>
        <div style={{ padding: '14px 16px 32px' }}>
          <Card ui={ui}>
            {cols.map((c, i) => (
              <div key={c.name} style={{ display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 14px', position: 'relative' }}>
                {mode === 'edit' && <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={ui.ter} strokeWidth="2" strokeLinecap="round" style={{ marginRight: 12 }}><path d="M4 8h16M4 16h16"/></svg>}
                <window.Icons.Folder size={19} color={ui.tint} />
                <span style={{ flex: 1, fontFamily: LIB_SANS, fontSize: 15.5, color: ui.ink, marginLeft: 11 }}>{c.name}</span>
                {mode === 'edit' && !c.sys
                  ? <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />
                  : <span style={{ fontFamily: LIB_SANS, fontSize: 13.5, color: ui.ter, fontVariantNumeric: 'tabular-nums' }}>{c.n}</span>}
                {i < cols.length - 1 && <div style={{ position: 'absolute', left: 44, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
              </div>
            ))}
          </Card>

          <div style={{ height: 16 }} />
          {mode === 'create' ? (
            <Card ui={ui}>
              <div style={{ display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 14px', boxShadow: `inset 0 0 0 1.5px ${ui.tint}`, borderRadius: 14 }}>
                <window.Icons.Folder size={19} color={ui.tint} />
                <span style={{ flex: 1, fontFamily: LIB_SANS, fontSize: 15.5, color: ui.ink, marginLeft: 11 }}>Philosophy<span style={{ display: 'inline-block', width: 1.5, height: 17, background: ui.tint, verticalAlign: -3, marginLeft: 1 }} /></span>
                <span style={{ fontFamily: LIB_SANS, fontSize: 14, fontWeight: 600, color: ui.tint }}>Add</span>
              </div>
            </Card>
          ) : (
            <button style={{
              display: 'flex', alignItems: 'center', gap: 9, width: '100%', border: 'none', cursor: 'pointer',
              background: ui.card, borderRadius: 14, padding: '15px 14px', boxShadow: ui.cardShadow,
              fontFamily: LIB_SANS, fontSize: 15.5, fontWeight: 500, color: ui.tint,
            }}>
              <window.Icons.Plus size={20} color={ui.tint} /> New Collection
            </button>
          )}
          <GroupFooter ui={ui}>"Currently Reading" and "Finished" update automatically from your reading progress and can't be deleted.</GroupFooter>
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

function AssignSheet({ ui, height = 880 }) {
  const cols = [
    { name: 'Currently Reading', on: true },
    { name: 'To Read', on: false },
    { name: 'Fiction', on: true },
    { name: 'Tech', on: false },
  ];
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <div style={{ position: 'absolute', inset: 0, zIndex: 200, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.35)' }}>
        <div style={{ background: ui.sheetBg, borderTopLeftRadius: 22, borderTopRightRadius: 22, padding: '8px 0 24px', boxShadow: '0 -8px 28px rgba(0,0,0,0.25)' }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 4, paddingBottom: 10 }}>
            <div style={{ width: 36, height: 5, borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '0 18px 14px' }}>
            <Cover b={BOOKS[0]} w={44} />
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontFamily: LIB_SERIF, fontSize: 16, fontWeight: 600, color: ui.ink }}>Add to Collection</div>
              <div style={{ fontFamily: LIB_SANS, fontSize: 12.5, color: ui.sec, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Pride and Prejudice</div>
            </div>
          </div>
          <div style={{ padding: '0 16px' }}>
            <Card ui={ui}>
              {cols.map((c, i) => (
                <div key={c.name} style={{ display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 14px', position: 'relative' }}>
                  <window.Icons.Folder size={19} color={ui.sec} />
                  <span style={{ flex: 1, fontFamily: LIB_SANS, fontSize: 15.5, color: ui.ink, marginLeft: 11 }}>{c.name}</span>
                  {c.on
                    ? <svg width="22" height="22" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill={ui.tint}/><path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>
                    : <div style={{ width: 22, height: 22, borderRadius: 11, boxShadow: `inset 0 0 0 1.7px ${ui.sep}` }} />}
                  {i < cols.length - 1 && <div style={{ position: 'absolute', left: 44, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
                </div>
              ))}
            </Card>
            <button style={{ display: 'flex', alignItems: 'center', gap: 9, width: '100%', border: 'none', cursor: 'pointer', background: 'transparent', padding: '15px 4px 4px', fontFamily: LIB_SANS, fontSize: 15, fontWeight: 500, color: ui.tint }}>
              <window.Icons.Plus size={19} color={ui.tint} /> New Collection…
            </button>
          </div>
        </div>
      </div>
    </PhoneFrame>
  );
}

Object.assign(window, {
  BOOKS, COLLECTIONS, Cover, LibraryScreen, SearchScreen,
  CollectionsManageSheet, AssignSheet,
});
