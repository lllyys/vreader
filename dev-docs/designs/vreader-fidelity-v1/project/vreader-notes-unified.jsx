// HighlightsSheet — combined HighlightRecord + standalone AnnotationRecord — issue
// #860 / feature #62.
//
// The committed HighlightsSheetV2 models its filters on a single record type
// (HighlightRecord, with optional .note). Production has TWO record types:
//   • HighlightRecord     — a highlighted passage, optionally annotated.
//   • AnnotationRecord    — a STANDALONE note at a locator (no quoted passage).
// Shipping the committed design as-is would drop the standalone surface entirely.
//
// We pick option (2) from the issue — extend the design — because:
//   • Folding standalone notes into highlight-notes (option 1) is a data-model
//     change with a migration. Out of design scope, and the model is already wired.
//   • Deprecating the feature (option 3) deletes a working production surface and
//     breaks export / CloudKit shape — same scope issue, plus user-data loss.
//   • Extending the design is local — only this sheet changes.
//
// DESIGN CHANGES vs HighlightsSheetV2:
//
//   1. Filter chip set:
//        All · Highlights · Notes · Bookmarks
//
//      Same labels, new semantics — the chip-bar tab counts now reflect record
//      counts, not just `h.note`-based slices:
//        • Highlights  → HighlightRecord rows (passage; note optional)
//        • Notes       → BOTH AnnotationRecord rows AND HighlightRecord rows
//                        with a note. Notes are notes, regardless of anchor.
//        • All         → union, chronological
//        • Bookmarks   → unchanged
//
//   2. Two card components: HighlightCardV3 (passage card; identical visual to
//      the v2 design, no change) and StandaloneNoteCardV3 (NEW — quoted-passage
//      block is replaced with the note body in the lead position, the locator
//      becomes the meta row at top, and a small "standalone" pictogram
//      differentiates it).
//
//   3. The "All" filter merges the two card streams in a single chronological
//      list. The standalone card is visually distinct from the highlight card
//      (no coloured swatch, different lead — see below), so the user can scan
//      the list and tell what they're looking at at a glance.
//
//   4. Empty states unchanged from v2, but the "All" empty copy gains a hint
//      about standalone notes ("Long-press any passage to highlight or add a
//      note. Tap the note icon at a chapter to leave a standalone note.").
//
// The TOCSheet (Contents + Bookmarks) is unaffected by this issue — see
// vreader-annotations.jsx for the canonical version.

// Sample standalone notes that the existing fixture doesn't have.
const SAMPLE_STANDALONE = [
  {
    id: 's1', kind: 'standalone', chapter: 'Chapter 6', page: 47,
    date: 'Apr 18',
    body: 'Charlotte\'s pragmatism here is the inverse of Elizabeth\'s — \"happiness in marriage is entirely a matter of chance.\" Worth re-reading next to Lizzy\'s reaction.',
  },
  {
    id: 's2', kind: 'standalone', chapter: 'Chapter 11', page: 89,
    date: 'Yesterday',
    body: 'Note: the ball scene is the structural midpoint of the first volume. Track Darcy\'s reluctance vs. his actions.',
  },
];

const SAMPLE_HIGHLIGHTS_PLUS_NOTES = [
  { id: 'h1', kind: 'highlight', text: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    color: 'yellow', chapter: 'Chapter 1', page: 1, date: 'Apr 12' },
  { id: 'h2', kind: 'highlight', text: 'You take delight in vexing me. You have no compassion for my poor nerves.',
    color: 'pink', chapter: 'Chapter 1', page: 4, date: 'Apr 12',
    note: 'Mrs. Bennet\'s catchphrase. Austen lets her self-pity become its own punchline.' },
  { id: 'h3', kind: 'highlight', text: 'She is tolerable, but not handsome enough to tempt me.',
    color: 'blue', chapter: 'Chapter 3', page: 18, date: 'Apr 15',
    note: 'The line that sets up the whole arc.' },
];

// ────────────────────────────────────────────────────
// Unified sheet
// ────────────────────────────────────────────────────
function HighlightsSheetV3({ theme, highlights = SAMPLE_HIGHLIGHTS_PLUS_NOTES,
                             standalones = SAMPLE_STANDALONE,
                             filter: initialFilter = 'all', onClose, onJump }) {
  const t = theme;
  const [filter, setFilter] = React.useState(initialFilter);

  // record-type counts, per the design semantics doc above
  const allHighlights = highlights;
  const allNotes      = [...standalones, ...highlights.filter(h => h.note)];
  const counts = {
    all:        allHighlights.length + standalones.length,
    highlights: allHighlights.length,
    notes:      allNotes.length,
    bookmarks:  0,
  };

  // merged chronological stream for All. We trust the .date string ordering
  // for the demo; production sorts by record-creation timestamp.
  const allStream = React.useMemo(() => {
    const items = [
      ...highlights.map(h => ({ ...h, kind: 'highlight' })),
      ...standalones.map(s => ({ ...s, kind: 'standalone' })),
    ];
    // newest first — for fixture, reverse so the "Yesterday" / latest dated
    // items land near the top; production uses actual timestamps.
    return items.slice().reverse();
  }, [highlights, standalones]);

  const stream = filter === 'all'        ? allStream
              : filter === 'highlights'  ? allHighlights.map(h => ({ ...h, kind: 'highlight' }))
              : filter === 'notes'       ? allNotes.map(n => ({ ...n, kind: n.body ? 'standalone' : 'highlight' }))
              : [];

  return (
    <Sheet theme={t} onClose={onClose} height={680} title="Annotations"
      trailing={
        <button style={{
          background: 'none', border: 'none', padding: 6, cursor: 'pointer', display: 'flex',
        }} aria-label="Share annotations">
          <Icons.Share size={18} color={t.accent} stroke={1.8}/>
        </button>
      }>
      {/* filter chips */}
      <div style={{
        padding: '10px 18px 6px', display: 'flex', gap: 6, overflowX: 'auto',
      }} className="hide-scroll">
        {[
          { k: 'all',        label: 'All' },
          { k: 'highlights', label: 'Highlights' },
          { k: 'notes',      label: 'Notes' },
          { k: 'bookmarks',  label: 'Bookmarks' },
        ].map(o => {
          const active = filter === o.k;
          return (
            <button key={o.k} onClick={() => setFilter(o.k)} style={{
              padding: '6px 13px', borderRadius: 100, border: 'none',
              fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
              background: active ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
              color: active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
              cursor: 'pointer', display: 'inline-flex', alignItems: 'center', gap: 6,
              whiteSpace: 'nowrap',
            }}>
              <span>{o.label}</span>
              <span style={{
                fontSize: 10.5, opacity: 0.7,
                padding: '1px 5px', borderRadius: 100,
                background: active ? (t.isDark ? 'rgba(0,0,0,0.18)' : 'rgba(255,255,255,0.2)') : 'transparent',
              }}>{counts[o.k]}</span>
            </button>
          );
        })}
      </div>

      {/* card list */}
      {stream.length > 0 ? (
        <div style={{ padding: '8px 18px 24px' }}>
          {stream.map(item => item.kind === 'standalone'
            ? <StandaloneNoteCard key={item.id} t={t} note={item} onJump={onJump}/>
            : <HighlightCardV3   key={item.id} t={t} h={item}    onJump={onJump}/>)}
        </div>
      ) : (
        <EmptyState t={t}
          art={typeof EmptyHighlightsArt !== 'undefined' ? <EmptyHighlightsArt t={t}/> : null}
          title={
            filter === 'all'        ? 'No highlights or notes yet'
            : filter === 'highlights' ? 'No highlights yet'
            : filter === 'notes'      ? 'No notes yet'
            : 'No bookmarks yet'
          }
          body={
            filter === 'all'
              ? 'Long-press any passage to highlight or add a note. Or tap the note icon on a chapter to leave a standalone note that isn\'t tied to a passage.'
              : filter === 'bookmarks'
              ? 'Tap the bookmark icon in the top bar to save your place.'
              : filter === 'notes'
              ? 'Add a note to any highlight, or leave a standalone note at a chapter.'
              : 'Long-press any passage to highlight it. Pick a colour to keep them organised.'
          }
        />
      )}
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// HighlightCardV3 — identical to v2 visually, separated out for clarity
// ────────────────────────────────────────────────────
function HighlightCardV3({ t, h, onJump }) {
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
// StandaloneNoteCard — NEW. The note body is the hero; no quoted passage; a
// chapter+page locator and a small "pin" pictogram identify it as standalone.
// ────────────────────────────────────────────────────
function StandaloneNoteCard({ t, note, onJump }) {
  return (
    <div onClick={() => onJump?.(note)} style={{
      padding: '14px 0', borderBottom: `0.5px solid ${t.rule}`, cursor: 'pointer',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        marginBottom: 8, fontSize: 11, color: t.sub,
      }}>
        {/* standalone pictogram — a small filled note glyph distinguishes from
            highlight rows' colour swatch */}
        <div style={{
          width: 12, height: 12, borderRadius: 3,
          background: `${t.accent}22`, color: t.accent,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <svg width="7" height="8" viewBox="0 0 7 8">
            <path d="M0.5 0.5h5l1 1v6h-6z" fill="currentColor" opacity="0.9"/>
            <path d="M1.8 3h3.2M1.8 4.6h2.2" stroke={t.isDark ? '#2a2724' : '#fcf8f0'}
              strokeWidth="0.7"/>
          </svg>
        </div>
        <span>{note.chapter}</span>
        <span style={{ opacity: 0.5 }}>·</span>
        <span>p. {note.page}</span>
        <span style={{
          padding: '1px 6px', borderRadius: 100, marginLeft: 4,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          fontSize: 9.5, fontWeight: 600, letterSpacing: 0.6,
          textTransform: 'uppercase', color: t.sub,
        }}>Standalone</span>
        <span style={{ flex: 1 }}/>
        <span>{note.date}</span>
      </div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14.5, color: t.ink, lineHeight: 1.5, textWrap: 'pretty',
        paddingLeft: 12, borderLeft: `2px dashed ${t.accent}88`,
      }}>{note.body}</div>
    </div>
  );
}

Object.assign(window, {
  HighlightsSheetV3, HighlightCardV3, StandaloneNoteCard,
  SAMPLE_HIGHLIGHTS_PLUS_NOTES, SAMPLE_STANDALONE,
});
