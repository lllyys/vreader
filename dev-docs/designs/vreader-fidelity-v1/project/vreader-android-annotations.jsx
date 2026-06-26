// Issue #1801 / Feature #110 (Android Phase-3) — highlights + annotations.
//
// iOS has highlights, bookmarks and notes with a review surface; Android's
// persistence (Room) can carry them, but the reader selection→highlight UI and
// the annotations review/list UI were design-gated (rule 51). Built in
// VReader's own vocabulary (reader THEMES for the in-page surfaces, the shared
// form UI tokens for the review sheets) so it reads as the same product.
//
// Two surfaces:
//   A. In-reader text selection → a floating action popover: 5 highlight
//      colors, add-note, copy, share. Tapping an existing highlight re-opens
//      the same popover with Edit/Delete. Note compose is inline.
//   B. The annotations review list — per-book and library-wide. Three record
//      kinds (highlight / standalone note / bookmark), a filter chip row, and
//      empty + edit states. Mirrors the iOS HighlightsSheet decisions (#860).

const ANN_SERIF = '"Source Serif 4", Georgia, serif';
const ANN_SANS = "'Inter', -apple-system, system-ui, sans-serif";

// Highlight palette — book-friendly muted tones, shared by popover + cards.
const HL_COLORS = [
  { key: 'yellow', dot: '#e6b800', wash: 'rgba(230,184,0,0.28)', rule: '#d9a800' },
  { key: 'green',  dot: '#5a9a6e', wash: 'rgba(90,154,110,0.26)', rule: '#5a9a6e' },
  { key: 'blue',   dot: '#5c8fc4', wash: 'rgba(92,143,196,0.26)', rule: '#5c8fc4' },
  { key: 'pink',   dot: '#cf7a9a', wash: 'rgba(207,122,154,0.26)', rule: '#cf7a9a' },
  { key: 'red',    dot: '#b5503f', wash: 'rgba(181,80,63,0.24)', rule: '#b5503f' },
];

// ── in-reader selection / popover ────────────────────────────
// modes: 'select' (just-selected, color + actions) · 'colors' · 'note'
//        'editHL' (tapped an existing highlight)
function SelectionReader({ themeKey = 'paper', mode = 'select', height = 880 }) {
  const t = window.THEMES[themeKey];
  const selBg = t.isDark ? 'rgba(92,143,196,0.4)' : 'rgba(92,143,196,0.34)';
  const selColor = HL_COLORS[0];
  const existing = mode === 'editHL';

  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        <window.ReaderChrome t={t} />
        <div style={{ flex: 1, position: 'relative', padding: '6px 26px 0', overflow: 'hidden' }}>
          <div style={{ fontFamily: ANN_SERIF, fontSize: 18.5, lineHeight: 1.62, color: t.ink, textWrap: 'pretty' }}>
            <p style={{ margin: '0 0 17px' }}>
              Mr. Bennet was so odd a mixture of quick parts, sarcastic humour, reserve, and caprice, that the experience of three-and-twenty years had been insufficient to make his wife understand his character.
            </p>
            <p style={{ margin: '0 0 17px', position: 'relative' }}>
              Her mind was less difficult to develop.{' '}
              <span style={{
                background: existing ? selColor.wash : selBg,
                boxShadow: existing ? `inset 2px 0 0 ${selColor.rule}` : 'none',
                borderRadius: 2, padding: '1px 2px', position: 'relative',
              }}>
                {!existing && <span style={{ position: 'absolute', left: -3, top: -3, width: 9, height: 9, borderRadius: 5, background: '#5c8fc4' }} />}
                She was a woman of mean understanding, little information, and uncertain temper.
                {!existing && <span style={{ position: 'absolute', right: -3, bottom: -3, width: 9, height: 9, borderRadius: 5, background: '#5c8fc4' }} />}
              </span>{' '}
              When she was discontented, she fancied herself nervous.
            </p>
            <p style={{ margin: 0, color: t.sub }}>
              The business of her life was to get her daughters married; its solace was visiting and news.
            </p>
          </div>

          {/* the floating popover, anchored under the selection */}
          <div style={{ position: 'absolute', left: 24, right: 24, top: 232, display: 'flex', justifyContent: 'center' }}>
            <SelectionPopover t={t} mode={mode} />
          </div>
        </div>
      </div>
    </window.TtsFrame>
  );
}

function SelectionPopover({ t, mode }) {
  const card = t.isDark ? '#2c2926' : '#ffffff';
  const divider = t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(29,26,20,0.1)';
  const ActionBtn = ({ icon, label, danger }) => (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, padding: '4px 12px', minWidth: 52 }}>
      <span style={{ color: danger ? '#b5503f' : t.ink, opacity: 0.9 }}>{icon}</span>
      <span style={{ fontFamily: ANN_SANS, fontSize: 11, fontWeight: 500, color: danger ? '#b5503f' : t.sub }}>{label}</span>
    </div>
  );
  const ic = (name, c) => { const I = window.Icons[name]; return <I size={20} color={c || t.ink} stroke={1.7} />; };

  return (
    <div style={{
      background: card, borderRadius: 16, boxShadow: '0 8px 30px rgba(0,0,0,0.28), 0 0 0 0.5px rgba(0,0,0,0.06)',
      position: 'relative', maxWidth: 340,
    }}>
      {/* color row */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px', justifyContent: 'center' }}>
        {HL_COLORS.map((c, i) => (
          <div key={c.key} style={{
            width: 28, height: 28, borderRadius: 14, background: c.dot,
            boxShadow: (mode === 'editHL' ? i === 4 : i === 0) ? `0 0 0 2.5px ${card}, 0 0 0 4.5px ${c.dot}` : 'none',
          }} />
        ))}
        <div style={{ width: 0.5, height: 26, background: divider, margin: '0 2px' }} />
        <div style={{
          width: 28, height: 28, borderRadius: 14, border: `1.5px dashed ${t.sub}`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', color: t.sub, fontSize: 16,
        }}>+</div>
      </div>
      <div style={{ height: 0.5, background: divider }} />
      {/* action row */}
      {mode === 'note' ? (
        <div style={{ padding: '12px 14px 14px', width: 312 }}>
          <div style={{ fontFamily: ANN_SANS, fontSize: 11, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', color: t.sub, marginBottom: 8 }}>Add note</div>
          <div style={{
            background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', borderRadius: 10, padding: '10px 12px',
            fontFamily: ANN_SERIF, fontSize: 15, color: t.ink, minHeight: 64, lineHeight: 1.5,
          }}>
            Austen's irony lands in the dependent clause<span style={{ display: 'inline-block', width: 1.5, height: 17, background: t.accent, verticalAlign: -3, marginLeft: 1 }} />
          </div>
          <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 11 }}>
            <button style={{ border: 'none', background: 'transparent', color: t.sub, fontFamily: ANN_SANS, fontSize: 14, fontWeight: 500, padding: '7px 12px' }}>Cancel</button>
            <button style={{ border: 'none', background: t.accent, color: '#fff', fontFamily: ANN_SANS, fontSize: 14, fontWeight: 600, borderRadius: 9, padding: '7px 16px' }}>Save</button>
          </div>
        </div>
      ) : (
        <div style={{ display: 'flex', alignItems: 'center', padding: '8px 6px', gap: 0 }}>
          {mode === 'editHL' ? (
            <>
              <ActionBtn icon={ic('Note')} label="Note" />
              <ActionBtn icon={ic('Copy')} label="Copy" />
              <ActionBtn icon={ic('Share')} label="Share" />
              <ActionBtn icon={ic('Close', '#b5503f')} label="Remove" danger />
            </>
          ) : (
            <>
              <ActionBtn icon={ic('Highlighter')} label="Highlight" />
              <ActionBtn icon={ic('Note')} label="Note" />
              <ActionBtn icon={ic('Copy')} label="Copy" />
              <ActionBtn icon={ic('Translate')} label="Translate" />
              <ActionBtn icon={ic('Share')} label="Share" />
            </>
          )}
        </div>
      )}
      {/* downward notch */}
      <div style={{ position: 'absolute', bottom: -7, left: '50%', transform: 'translateX(-50%) rotate(45deg)', width: 14, height: 14, background: card, borderRadius: 3 }} />
    </div>
  );
}

// ── annotation cards ─────────────────────────────────────────
function FilterChips({ ui, active = 'All' }) {
  const chips = ['All', 'Highlights', 'Notes', 'Bookmarks'];
  return (
    <div style={{ display: 'flex', gap: 8, padding: '2px 0 4px', flexWrap: 'wrap' }}>
      {chips.map((c) => {
        const on = c === active;
        return (
          <span key={c} style={{
            fontFamily: ANN_SANS, fontSize: 13, fontWeight: on ? 600 : 500,
            color: on ? ui.bg : ui.ink, background: on ? ui.ink : (ui.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)'),
            borderRadius: 100, padding: '7px 14px',
          }}>{c}</span>
        );
      })}
    </div>
  );
}

function HighlightCard({ ui, color, quote, note, meta, editing }) {
  const c = HL_COLORS.find((x) => x.key === color) || HL_COLORS[0];
  return (
    <div style={{ background: ui.card, borderRadius: 14, padding: '14px 15px', boxShadow: ui.cardShadow, position: 'relative', marginBottom: 10 }}>
      <div style={{ display: 'flex', gap: 12 }}>
        <div style={{ width: 4, borderRadius: 2, background: c.rule, flexShrink: 0 }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: ANN_SERIF, fontSize: 15.5, lineHeight: 1.5, color: ui.ink }}>{quote}</div>
          {note != null && !editing && (
            <div style={{ marginTop: 9, paddingTop: 9, borderTop: `0.5px solid ${ui.sep}`, fontFamily: ANN_SANS, fontSize: 13.5, lineHeight: 1.5, color: ui.sec }}>{note}</div>
          )}
          {editing && (
            <div style={{ marginTop: 9 }}>
              <div style={{ background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', borderRadius: 9, padding: '9px 11px', fontFamily: ANN_SANS, fontSize: 13.5, color: ui.ink, lineHeight: 1.5, boxShadow: `inset 0 0 0 1.5px ${ui.tint}` }}>
                {note}<span style={{ display: 'inline-block', width: 1.5, height: 15, background: ui.tint, verticalAlign: -2, marginLeft: 1 }} />
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 11 }}>
                {HL_COLORS.map((cc, i) => (
                  <div key={cc.key} style={{ width: 22, height: 22, borderRadius: 11, background: cc.dot, boxShadow: cc.key === color ? `0 0 0 2px ${ui.card}, 0 0 0 3.5px ${cc.dot}` : 'none' }} />
                ))}
                <span style={{ flex: 1 }} />
                <span style={{ fontFamily: ANN_SANS, fontSize: 13.5, color: ui.sec, fontWeight: 500 }}>Cancel</span>
                <span style={{ fontFamily: ANN_SANS, fontSize: 13.5, color: ui.tint, fontWeight: 600 }}>Save</span>
              </div>
            </div>
          )}
          {!editing && (
            <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 9, fontFamily: ANN_SANS, fontSize: 12, color: ui.ter }}>
              <span>{meta}</span>
              {note != null && <span style={{ color: ui.tint, fontWeight: 600 }}>· Note</span>}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function StandaloneNoteCard({ ui, body, meta }) {
  return (
    <div style={{ background: ui.card, borderRadius: 14, padding: '14px 15px', boxShadow: ui.cardShadow, position: 'relative', marginBottom: 10 }}>
      <div style={{ display: 'flex', gap: 12 }}>
        <div style={{ width: 4, borderRadius: 2, flexShrink: 0, background: `repeating-linear-gradient(${ui.tint} 0 4px, transparent 4px 8px)` }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: ANN_SERIF, fontSize: 15.5, lineHeight: 1.52, color: ui.ink }}>{body}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 9 }}>
            <span style={{ fontFamily: ANN_SANS, fontSize: 9.5, fontWeight: 700, letterSpacing: 0.5, color: ui.tint, background: ui.tagBg, borderRadius: 5, padding: '2px 6px' }}>STANDALONE</span>
            <span style={{ fontFamily: ANN_SANS, fontSize: 12, color: ui.ter }}>{meta}</span>
          </div>
        </div>
      </div>
    </div>
  );
}

function BookmarkCard({ ui, label, meta }) {
  return (
    <div style={{ background: ui.card, borderRadius: 14, padding: '13px 15px', boxShadow: ui.cardShadow, marginBottom: 10, display: 'flex', alignItems: 'center', gap: 12 }}>
      <window.Icons.BookmarkFilled size={20} color={ui.tint} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: ANN_SERIF, fontSize: 15, color: ui.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{label}</div>
        <div style={{ fontFamily: ANN_SANS, fontSize: 12, color: ui.ter, marginTop: 2 }}>{meta}</div>
      </div>
    </div>
  );
}

// ── the review sheet (per-book or library-wide) ──────────────
function AnnotationsSheet({ ui, scope = 'book', state = 'populated', height = 880 }) {
  const empty = state === 'empty';
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title={scope === 'book' ? 'Annotations' : 'All Annotations'}
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: ANN_SANS, fontSize: 15, color: ui.sec }}>Close</button>}
        trailing={<window.Icons.Share size={20} color={ui.tint} />}
        height={height - 36}>
        <div style={{ padding: '12px 16px 32px' }}>
          {scope === 'book' && (
            <div style={{ marginBottom: 10 }}>
              <div style={{ fontFamily: ANN_SERIF, fontStyle: 'italic', fontSize: 19, color: ui.ink }}>Pride and Prejudice</div>
              <div style={{ fontFamily: ANN_SANS, fontSize: 12.5, color: ui.sec, marginTop: 2 }}>{empty ? 'No annotations yet' : '12 highlights · 4 notes · 3 bookmarks'}</div>
            </div>
          )}
          <FilterChips ui={ui} active="All" />
          <div style={{ height: 12 }} />

          {empty ? (
            <div style={{ textAlign: 'center', padding: '64px 30px' }}>
              <div style={{ width: 60, height: 60, borderRadius: 30, background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
                <window.Icons.Highlighter size={28} color={ui.ter} />
              </div>
              <div style={{ fontFamily: ANN_SERIF, fontSize: 19, color: ui.ink, marginBottom: 8 }}>Nothing saved yet</div>
              <div style={{ fontFamily: ANN_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.5 }}>
                Press and hold a passage to highlight it, or tap the note icon on a chapter to jot a standalone note.
              </div>
            </div>
          ) : scope === 'library' ? (
            <>
              <BookGroupHeader ui={ui} title="Pride and Prejudice" count="19" />
              <HighlightCard ui={ui} color="yellow" quote={'"She was a woman of mean understanding, little information, and uncertain temper."'} note="Austen's irony lands in the dependent clause." meta="Ch. 1 · Apr 18" />
              <StandaloneNoteCard ui={ui} body="Track how often weather forces the plot — Jane's cold at Netherfield is the first." meta="Ch. 7 · Apr 19" />
              <BookGroupHeader ui={ui} title="The Beginning of Infinity" count="11" />
              <HighlightCard ui={ui} color="blue" quote={'"Problems are inevitable… Problems are soluble."'} meta="Ch. 3 · Apr 12" />
            </>
          ) : (
            <>
              <HighlightCard ui={ui} color="yellow" quote={'"She was a woman of mean understanding, little information, and uncertain temper."'} note="Austen's irony lands in the dependent clause." meta="Ch. 1 · Apr 18" editing={state === 'edit'} />
              {state !== 'edit' && <>
                <StandaloneNoteCard ui={ui} body="Track how often weather forces the plot — Jane's cold at Netherfield is the first major instance." meta="Ch. 7 · Apr 19" />
                <HighlightCard ui={ui} color="green" quote={'"It is a truth universally acknowledged…"'} meta="Ch. 1 · Apr 18" />
                <BookmarkCard ui={ui} label={'"…the rightful property of some one or other of their daughters."'} meta="Ch. 1 · 14%" />
                <HighlightCard ui={ui} color="pink" quote={'"A lady\'s imagination is very rapid; it jumps from admiration to love…"'} note="Foreshadows Elizabeth's own leaps to judgment." meta="Ch. 6 · Apr 20" />
              </>}
            </>
          )}
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

function BookGroupHeader({ ui, title, count }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 8, margin: '6px 2px 10px' }}>
      <span style={{ fontFamily: ANN_SERIF, fontStyle: 'italic', fontSize: 16, color: ui.ink }}>{title}</span>
      <span style={{ flex: 1, height: 0.5, background: ui.sep }} />
      <span style={{ fontFamily: ANN_SANS, fontSize: 12, color: ui.ter, fontVariantNumeric: 'tabular-nums' }}>{count}</span>
    </div>
  );
}

Object.assign(window, {
  HL_COLORS, SelectionReader, SelectionPopover, AnnotationsSheet,
  HighlightCard, StandaloneNoteCard, BookmarkCard, FilterChips,
});
