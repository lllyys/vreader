// Annotations sheets — feature #60 follow-up (#793)
// Decision: SPLIT into two canonical sheets (per design bundle).
//
//   TOCSheetV2          — Contents / Bookmarks (navigation)
//   HighlightsSheetV2   — All / Highlights / Notes / Bookmarks (review)
//
// Each surface gets a proper empty state. The reader's bottom chrome routes
// Contents → TOCSheetV2 and Notes → HighlightsSheetV2.

// ────────────────────────────────────────────────────
// TOC Sheet — Contents + Bookmarks
// ────────────────────────────────────────────────────
function TOCSheetV2({ theme, book, currentCh, tab: initialTab = 'contents',
                     toc = null, bookmarks = null, onJump, onOpenSearch, onClose }) {
  const t = theme;
  const [tab, setTab] = React.useState(initialTab);
  const tocItems = toc || TOC;
  const bms = bookmarks ?? [
    { page: 1, chapter: 'Chapter 1', date: 'Apr 12', preview: 'It is a truth universally acknowledged…' },
    { page: 47, chapter: 'Chapter 6', date: 'Apr 18', preview: 'Charlotte\'s view on marriage' },
    { page: 89, chapter: 'Chapter 11', date: 'Yesterday', preview: 'The Netherfield ball' },
  ];

  return (
    <Sheet theme={t} onClose={onClose} title={book?.title || 'Pride and Prejudice'} height={640}>
      <div style={{ padding: '8px 18px 0' }}>
        <div style={{
          display: 'flex', borderRadius: 10, padding: 3,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
        }}>
          {[
            { k: 'contents', label: 'Contents', count: tocItems.length },
            { k: 'bookmarks', label: 'Bookmarks', count: bms.length },
          ].map(o => (
            <button key={o.k} onClick={() => setTab(o.k)} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, border: 'none',
              background: tab === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: t.ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 500,
              cursor: 'pointer', display: 'inline-flex', justifyContent: 'center',
              alignItems: 'center', gap: 6,
              boxShadow: tab === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>
              <span>{o.label}</span>
              <span style={{
                fontSize: 10.5, color: t.sub, fontWeight: 500,
                padding: '1px 6px', borderRadius: 100,
                background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
              }}>{o.count}</span>
            </button>
          ))}
        </div>
      </div>

      {tab === 'contents' && tocItems.length > 0 && (
        <div style={{ padding: '14px 8px' }}>
          {tocItems.map(c => (
            <button key={c.ch} onClick={() => { onJump?.(c); onClose?.(); }} style={{
              display: 'flex', alignItems: 'baseline', gap: 14,
              padding: '12px 14px', width: '100%', border: 'none',
              background: c.ch === currentCh
                ? (t.isDark ? `${t.accent}1f` : `${t.accent}10`)
                : 'transparent',
              borderRadius: 10, cursor: 'pointer', textAlign: 'left',
            }}>
              <span style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 12, color: t.sub, fontWeight: 500,
                width: 24, textAlign: 'right',
              }}>{c.ch}</span>
              <span style={{
                flex: 1, fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 16, color: c.ch === currentCh ? t.accent : t.ink,
                fontWeight: c.ch === currentCh ? 600 : 400,
              }}>{c.title}</span>
              <span style={{ fontSize: 12, color: t.sub }}>p. {c.page}</span>
            </button>
          ))}
        </div>
      )}
      {tab === 'contents' && tocItems.length === 0 && (
        <EmptyState t={t}
          art={<EmptyTOCArt t={t}/>}
          title="No table of contents"
          body="This book doesn't ship a TOC. Use the scrubber to flip pages, or Search to jump to a passage."
          cta={onOpenSearch && { label: 'Open Search', icon: Icons.Search, onClick: () => { onClose?.(); onOpenSearch?.(); } }}
        />
      )}

      {tab === 'bookmarks' && bms.length > 0 && (
        <div style={{ padding: '14px 18px' }}>
          {bms.map((b, i) => (
            <button key={i} onClick={() => { onJump?.({ ch: 1, page: b.page }); onClose?.(); }} style={{
              display: 'flex', alignItems: 'flex-start', gap: 12,
              padding: '14px 0', width: '100%', border: 'none', background: 'transparent',
              borderBottom: i === bms.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
              cursor: 'pointer', textAlign: 'left',
            }}>
              <Icons.BookmarkFilled size={18} color={t.accent} stroke={1.7}/>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 14, fontStyle: 'italic', color: t.ink,
                  lineHeight: 1.3, marginBottom: 4,
                  overflow: 'hidden', textOverflow: 'ellipsis',
                  display: '-webkit-box', WebkitLineClamp: 1, WebkitBoxOrient: 'vertical',
                }}>{b.preview}</div>
                <div style={{ fontSize: 11, color: t.sub }}>{b.chapter} · p. {b.page} · {b.date}</div>
              </div>
              <Icons.Chevron size={14} color={t.sub} stroke={2}/>
            </button>
          ))}
        </div>
      )}
      {tab === 'bookmarks' && bms.length === 0 && (
        <EmptyState t={t}
          art={<EmptyBookmarkArt t={t}/>}
          title="No bookmarks yet"
          body="Tap the bookmark icon in the top bar to save your place. Bookmarks let you jump back instantly."
        />
      )}
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// Highlights Sheet — Annotations with All / Highlights / Notes / Bookmarks filters
// ────────────────────────────────────────────────────
function HighlightsSheetV2({ theme, highlights, filter: initialFilter = 'all', onClose, onJump }) {
  const t = theme;
  const [filter, setFilter] = React.useState(initialFilter);

  const all = highlights || [];
  const counts = {
    all: all.length,
    highlights: all.filter(h => !h.note).length,
    notes: all.filter(h => h.note).length,
    bookmarks: 0, // shown in HighlightsSheet's filter row too per design note §2
  };
  const filtered = filter === 'all' ? all
    : filter === 'highlights' ? all.filter(h => !h.note)
    : filter === 'notes' ? all.filter(h => h.note)
    : [];

  return (
    <Sheet theme={t} onClose={onClose} height={640} title="Annotations"
      trailing={
        <button style={{
          background: 'none', border: 'none', padding: 6,
          cursor: 'pointer', display: 'flex',
        }} aria-label="Share annotations">
          <Icons.Share size={18} color={t.accent} stroke={1.8}/>
        </button>
      }>
      <div style={{
        padding: '10px 18px 6px', display: 'flex', gap: 6, overflowX: 'auto',
      }} className="hide-scroll">
        {[
          { k: 'all', label: 'All' },
          { k: 'highlights', label: 'Highlights' },
          { k: 'notes', label: 'Notes' },
          { k: 'bookmarks', label: 'Bookmarks' },
        ].map(o => {
          const active = filter === o.k;
          return (
            <button key={o.k} onClick={() => setFilter(o.k)} style={{
              padding: '6px 13px', borderRadius: 100, border: 'none',
              fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
              background: active ? t.ink
                : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
              color: active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
              cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 6,
              whiteSpace: 'nowrap',
            }}>
              <span>{o.label}</span>
              <span style={{
                fontSize: 10.5, opacity: 0.7,
                padding: '1px 5px', borderRadius: 100,
                background: active
                  ? (t.isDark ? 'rgba(0,0,0,0.18)' : 'rgba(255,255,255,0.2)')
                  : 'transparent',
              }}>{counts[o.k]}</span>
            </button>
          );
        })}
      </div>

      {filtered.length > 0 ? (
        <div style={{ padding: '8px 18px 24px' }}>
          {filtered.map(h => <HighlightCard key={h.id} t={t} h={h} onJump={onJump}/>)}
        </div>
      ) : (
        <EmptyState t={t}
          art={<EmptyHighlightsArt t={t}/>}
          title={
            filter === 'all' ? 'No highlights or notes yet'
            : filter === 'highlights' ? 'No highlights yet'
            : filter === 'notes' ? 'No notes yet'
            : 'No bookmarks yet'
          }
          body={
            filter === 'bookmarks'
              ? 'Tap the bookmark icon in the top bar to save your place.'
              : 'Long-press any passage to highlight or add a note. Your annotations live here.'
          }
        />
      )}
    </Sheet>
  );
}

function HighlightCard({ t, h, onJump }) {
  const colorMap = {
    yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
  };
  return (
    <div onClick={() => onJump?.(h)} style={{
      padding: '14px 0', borderBottom: `0.5px solid ${t.rule}`, cursor: 'pointer',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        marginBottom: 8, fontSize: 11, color: t.sub,
      }}>
        <div style={{
          width: 10, height: 10, borderRadius: 2,
          background: colorMap[h.color] || colorMap.yellow,
        }}/>
        <span>{h.chapter}</span>
        <span style={{ opacity: 0.5 }}>·</span>
        <span>p. {h.page}</span>
        <span style={{ flex: 1 }}/>
        <span>{h.date}</span>
      </div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14.5, fontStyle: 'italic', color: t.ink, lineHeight: 1.45,
        borderLeft: `2px solid ${colorMap[h.color] || colorMap.yellow}`,
        paddingLeft: 12,
      }}>"{h.text}"</div>
      {h.note && (
        <div style={{
          fontFamily: 'inherit', fontSize: 13, color: t.sub,
          marginTop: 8, lineHeight: 1.4, paddingLeft: 14,
          display: 'flex', gap: 6, alignItems: 'flex-start',
        }}>
          <Icons.Note size={13} color={t.sub} stroke={1.7} style={{ marginTop: 2, flexShrink: 0 }}/>
          <span>{h.note}</span>
        </div>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// Empty state
// ────────────────────────────────────────────────────
function EmptyState({ t, art, title, body, cta }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '24px 36px 56px', textAlign: 'center', gap: 16,
    }}>
      <div style={{ width: 96, height: 96, opacity: 0.85 }}>{art}</div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 18, fontWeight: 600, color: t.ink, lineHeight: 1.2,
      }}>{title}</div>
      <div style={{
        fontSize: 13, color: t.sub, lineHeight: 1.5, maxWidth: 280,
        textWrap: 'pretty',
      }}>{body}</div>
      {cta && (
        <button onClick={cta.onClick} style={{
          marginTop: 4, display: 'inline-flex', alignItems: 'center', gap: 6,
          padding: '8px 14px', borderRadius: 100, border: 'none',
          background: t.accent, color: '#fff',
          fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, cursor: 'pointer',
        }}>
          {cta.icon && <cta.icon size={13} color="#fff" stroke={2}/>}
          {cta.label}
        </button>
      )}
    </div>
  );
}

// Empty-state illustrations — drawn from the design vocabulary (covers, pages, bookmarks).
// Not characters; just abstracted versions of the in-app objects.
function EmptyTOCArt({ t }) {
  return (
    <svg viewBox="0 0 96 96" width="96" height="96">
      <rect x="14" y="14" width="68" height="68" rx="4" fill="none"
        stroke={t.rule} strokeWidth="1.5" strokeDasharray="3 3"/>
      <path d="M28 32h26M28 42h32M28 52h22M28 62h28" stroke={t.sub} strokeWidth="2" strokeLinecap="round" opacity="0.5"/>
      <circle cx="68" cy="32" r="5" fill={t.accent} opacity="0.85"/>
    </svg>
  );
}

function EmptyBookmarkArt({ t }) {
  return (
    <svg viewBox="0 0 96 96" width="96" height="96">
      <rect x="20" y="14" width="56" height="72" rx="3" fill={t.isDark ? '#2a2724' : '#fcf8f0'}
        stroke={t.rule} strokeWidth="1.5"/>
      <path d="M30 26h36M30 36h32M30 46h28M30 56h34M30 66h22" stroke={t.sub} strokeWidth="1.5" strokeLinecap="round" opacity="0.35"/>
      <path d="M52 6v32l8-6 8 6V6z" fill={t.accent} opacity="0.95"/>
    </svg>
  );
}

function EmptyHighlightsArt({ t }) {
  return (
    <svg viewBox="0 0 96 96" width="96" height="96">
      <rect x="12" y="20" width="72" height="14" rx="3" fill={`${t.accent}33`}/>
      <rect x="12" y="42" width="56" height="14" rx="3" fill={t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)'}/>
      <rect x="12" y="64" width="64" height="14" rx="3" fill={t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)'}/>
      <path d="M70 6l10 10-30 30-12 2 2-12z" fill={t.accent} opacity="0.9"/>
    </svg>
  );
}

Object.assign(window, {
  TOCSheetV2, HighlightsSheetV2, EmptyState,
  EmptyTOCArt, EmptyBookmarkArt, EmptyHighlightsArt,
});
