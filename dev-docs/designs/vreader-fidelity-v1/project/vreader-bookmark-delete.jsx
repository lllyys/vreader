// Android bookmark row deletion (swipe / long-press / confirm) · issue #1903
// (blocks feature #135 — Android bookmarks, split from #132; parity box F).
//
// The committed bookmark rows are tap-to-jump-only: the TOC/Bookmarks sheet
// rows (vreader-panels.jsx TOCSheet → Bookmarks tab) and the annotations
// review BookmarkCard (vreader-android-annotations.jsx) draw NO delete
// affordance. The committed iOS delete design (vreader-notes-delete.jsx)
// explicitly scopes its ⋯ Edit/Copy/Delete menu to highlight + standalone-note
// cards, NOT bookmarks. So bookmark delete has no design-grounded control and
// feature #135 ships create + jump + list without it. This file designs the
// Android bookmark-delete interaction so a follow-up can add it.
//
// Rendered in the reader THEMES vocabulary (window.THEMES + the committed Sheet
// from vreader-panels.jsx), because the TOC/Bookmarks sheet is a reader-chrome
// surface. The same confirm applies to the annotations BookmarkCard (see #1902,
// which already routes that card's ⋯ → the ui-toned confirm).
//
// ────────────────────────────────────────────────────
// DECISION SUMMARY
// ────────────────────────────────────────────────────
//
// Affordance · BOTH, as Android users expect on a list:
//   1. Swipe the row left → a destructive Delete panel slides in from the
//      trailing edge (trash glyph + "Delete"). Releasing past threshold does
//      NOT auto-destroy — it parks the row open; the Delete panel is the tap
//      target. (No blind full-swipe-dismiss: a bookmark is cheap to lose track
//      of, and the surface is a list you scan, not an inbox you triage.)
//   2. Long-press the row → a small Material menu (Copy link · Share · Delete).
//      This is the discoverable + accessible path (TalkBack / Switch Access
//      land on labelled items), and it's where Copy/Share live too.
//
// Confirm · a Material centre dialog — "Delete bookmark?" + the passage it
//   marks + Cancel / Delete (destructive ink). Bookmarks earn a real dialog
//   (not the inline row-confirm the annotation cards use) because a swipe or a
//   long-press-Delete is easy to trigger by accident, and the row is about to
//   leave the list entirely. Copy in the dialog names the passage so you know
//   which place you're forgetting.
//
// Failure · the delete is optimistic — the row animates out immediately and a
//   Snackbar appears ("Bookmark deleted · Undo"). If the persistence call
//   fails, the Snackbar swaps to an error ("Couldn't delete · Retry") and the
//   row animates back in. Undo restores the row before the call, so a
//   fat-fingered delete is always recoverable.

const BM_SANS = "'Inter', -apple-system, system-ui, sans-serif";
const BM_SERIF = '"Source Serif 4", Georgia, serif';

function bmDanger(t) { return t.isDark ? '#e0775a' : '#a8402f'; }

const BOOKMARKS = [
  { id: 'bm1', page: 1, chapter: 'Chapter 1', date: 'Apr 12', pct: '0%',
    preview: 'It is a truth universally acknowledged…' },
  { id: 'bm2', page: 47, chapter: 'Chapter 6', date: 'Apr 18', pct: '31%',
    preview: 'Charlotte’s view on marriage' },
  { id: 'bm3', page: 89, chapter: 'Chapter 11', date: 'Yesterday', pct: '58%',
    preview: 'The Netherfield ball' },
];

// ── the swipe-behind destructive panel ──────────────────────
function BMDeletePanel({ t, revealed }) {
  const danger = bmDanger(t);
  return (
    <div style={{
      position: 'absolute', top: 6, bottom: 6, right: 0, width: 88,
      background: danger, borderRadius: 12,
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 3,
      opacity: revealed ? 1 : 0, transition: 'opacity .15s',
    }}>
      <svg width="19" height="19" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
        <path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1.6 1.6 0 001.6 1.5h6.8A1.6 1.6 0 0017 20l1-13M10 11v6M14 11v6"/>
      </svg>
      <span style={{ fontFamily: BM_SANS, fontSize: 11, fontWeight: 600, color: '#fff' }}>Delete</span>
    </div>
  );
}

// ── long-press Material menu ─────────────────────────────────
function BMLongPressMenu({ t }) {
  const danger = bmDanger(t);
  const rowBg = t.isDark ? '#2f2c28' : '#fdf9ec';
  const items = [
    { name: 'copy', label: 'Copy link' },
    { name: 'share', label: 'Share' },
    { name: 'trash', label: 'Delete', danger: true, divider: true },
  ];
  const glyph = (name, color) => {
    const common = { width: 17, height: 17, viewBox: '0 0 24 24', fill: 'none', stroke: color, strokeWidth: 1.7, strokeLinecap: 'round', strokeLinejoin: 'round' };
    if (name === 'copy') return <svg {...common}><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 012-2h8"/></svg>;
    if (name === 'share') return <svg {...common}><path d="M12 3v13M8 7l4-4 4 4M5 14v5a2 2 0 002 2h10a2 2 0 002-2v-5"/></svg>;
    return <svg {...common}><path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1.6 1.6 0 001.6 1.5h6.8A1.6 1.6 0 0017 20l1-13M10 11v6M14 11v6"/></svg>;
  };
  return (
    <div style={{
      position: 'absolute', top: 44, right: 16, zIndex: 60, minWidth: 184, padding: '6px 0',
      borderRadius: 14, background: rowBg,
      boxShadow: '0 16px 36px rgba(0,0,0,0.34), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
    }}>
      {items.map((it) => (
        <div key={it.name} style={{
          display: 'flex', alignItems: 'center', gap: 13, padding: '11px 16px',
          borderTop: it.divider ? `0.5px solid ${t.rule}` : 'none',
          fontFamily: BM_SANS, fontSize: 14.5, fontWeight: it.danger ? 600 : 500,
          color: it.danger ? danger : t.ink,
        }}>
          {glyph(it.name, it.danger ? danger : t.ink)}
          <span>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

// ── a bookmark row ───────────────────────────────────────────
// state: 'default' | 'swipe' | 'menu' | 'pressed'
function BookmarkRow({ t, bm, state = 'default', last }) {
  const swipe = state === 'swipe';
  const pressed = state === 'pressed' || state === 'menu';
  return (
    <div style={{ position: 'relative' }}>
      <BMDeletePanel t={t} revealed={swipe} />
      <div style={{
        position: 'relative', display: 'flex', alignItems: 'flex-start', gap: 12,
        padding: '14px 4px', borderRadius: 12,
        borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
        background: pressed ? (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.035)') : (t.isDark ? '#21201c' : '#fcf8f0'),
        transform: swipe ? 'translateX(-96px)' : 'none',
        transition: 'transform .2s cubic-bezier(.32,.72,0,1)',
      }}>
        <window.Icons.BookmarkFilled size={18} color={t.accent} style={{ marginTop: 1, flexShrink: 0 }} />
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: BM_SERIF, fontSize: 14.5, fontStyle: 'italic', color: t.ink, lineHeight: 1.3, marginBottom: 4 }}>{bm.preview}</div>
          <div style={{ fontFamily: BM_SANS, fontSize: 11, color: t.sub }}>{bm.chapter} · p. {bm.page} · {bm.date}</div>
        </div>
        <window.Icons.Chevron size={14} color={t.sub} stroke={2} style={{ marginTop: 3, flexShrink: 0 }} />
      </div>
    </div>
  );
}

// ── Material centre confirm dialog ───────────────────────────
function BMConfirmDialog({ t, bm, busy }) {
  const danger = bmDanger(t);
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 300, background: 'rgba(0,0,0,0.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 28 }}>
      <div style={{
        width: '100%', maxWidth: 320, background: t.isDark ? '#2b2823' : '#fcf8f0', borderRadius: 20,
        padding: '22px 22px 16px', boxShadow: '0 24px 60px rgba(0,0,0,0.4)',
      }}>
        <div style={{ fontFamily: BM_SERIF, fontSize: 19, fontWeight: 600, color: t.ink, marginBottom: 8 }}>Delete bookmark?</div>
        <div style={{ fontFamily: BM_SANS, fontSize: 13.5, lineHeight: 1.5, color: t.sub, textWrap: 'pretty' }}>
          The saved place at{' '}
          <span style={{ fontStyle: 'italic', color: t.ink, fontFamily: BM_SERIF }}>“{bm.preview}”</span>{' '}
          ({bm.chapter} · p. {bm.page}) is removed. Your reading position isn’t affected.
        </div>
        <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 6, marginTop: 20 }}>
          <button style={{ border: 'none', background: 'transparent', cursor: 'pointer', fontFamily: BM_SANS, fontSize: 14, fontWeight: 600, color: t.accent, padding: '10px 14px', borderRadius: 10 }}>Cancel</button>
          <button style={{ border: 'none', background: 'transparent', cursor: 'pointer', fontFamily: BM_SANS, fontSize: 14, fontWeight: 600, color: danger, padding: '10px 14px', borderRadius: 10, display: 'inline-flex', alignItems: 'center', gap: 7 }}>
            {busy && <svg width="13" height="13" viewBox="0 0 24 24" fill="none" style={{ animation: 'apfSpin .8s linear infinite' }}><circle cx="12" cy="12" r="9" stroke={danger} strokeOpacity="0.25" strokeWidth="2.6"/><path d="M12 3a9 9 0 019 9" stroke={danger} strokeWidth="2.6" strokeLinecap="round"/></svg>}
            Delete
          </button>
        </div>
      </div>
    </div>
  );
}

// ── Snackbar (deleted-with-undo / failure-with-retry) ────────
function BMSnackbar({ t, variant = 'deleted' }) {
  const danger = bmDanger(t);
  const err = variant === 'error';
  return (
    <div style={{
      position: 'absolute', left: 16, right: 16, bottom: 24, zIndex: 320,
      background: t.isDark ? '#3a3530' : '#2c2822', borderRadius: 12,
      padding: '13px 12px 13px 16px', display: 'flex', alignItems: 'center', gap: 10,
      boxShadow: '0 8px 24px rgba(0,0,0,0.3)', fontFamily: BM_SANS,
    }}>
      {err && (
        <svg width="17" height="17" viewBox="0 0 24 24" fill="none" style={{ flexShrink: 0 }}><circle cx="12" cy="12" r="10" fill={danger}/><path d="M12 7v6M12 16v.01" stroke="#fff" strokeWidth="2" strokeLinecap="round"/></svg>
      )}
      <span style={{ flex: 1, fontSize: 13.5, color: '#f4eee0' }}>{err ? 'Couldn’t delete bookmark' : 'Bookmark deleted'}</span>
      <button style={{ border: 'none', background: 'transparent', cursor: 'pointer', fontFamily: BM_SANS, fontSize: 13.5, fontWeight: 700, color: err ? '#f0b090' : '#e8b465', padding: '4px 10px' }}>
        {err ? 'Retry' : 'Undo'}
      </button>
    </div>
  );
}

// ═════════════════════════════════════════════════════
// BookmarksSheet — the committed TOC/Bookmarks sheet, Bookmarks tab, with
// the delete interaction layered on. Rendered inside a reader frame.
//   forcedId / rowState — put one row into swipe / menu / pressed
//   dialog  — 'confirm' | 'deleting'      (Material centre dialog)
//   snackbar — 'deleted' | 'error'
// ═════════════════════════════════════════════════════
function BookmarksSheet({ themeKey = 'paper', rowId = null, rowState = 'default', dialog = null, snackbar = null, height = 880 }) {
  const t = window.THEMES[themeKey];
  const dialogBm = BOOKMARKS.find((b) => b.id === (rowId || 'bm2')) || BOOKMARKS[1];
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        <window.ReaderChrome t={t} />
        <div style={{ flex: 1 }} />
      </div>

      {/* dim + bottom sheet */}
      <div style={{ position: 'absolute', inset: 0, zIndex: 200, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.35)' }}>
        <div style={{
          background: t.isDark ? '#222020' : '#fcf8f0', height: height - 200,
          borderTopLeftRadius: 22, borderTopRightRadius: 22, boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
          display: 'flex', flexDirection: 'column', overflow: 'hidden', position: 'relative',
        }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
            <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '14px 18px 12px', borderBottom: `0.5px solid ${t.rule}` }}>
            <div style={{ fontFamily: BM_SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>Pride and Prejudice</div>
          </div>
          {/* tab strip */}
          <div style={{ padding: '10px 18px 4px' }}>
            <div style={{ display: 'flex', borderRadius: 10, padding: 3, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
              {[['Contents', false], ['Bookmarks', true]].map(([label, on]) => (
                <div key={label} style={{
                  flex: 1, textAlign: 'center', padding: '7px 0', borderRadius: 8,
                  background: on ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                  color: on ? t.ink : t.sub, fontFamily: BM_SANS, fontSize: 13, fontWeight: on ? 600 : 500,
                  boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
                }}>{label}</div>
              ))}
            </div>
          </div>
          <div style={{ flex: 1, overflow: 'auto', padding: '8px 18px 18px' }} className="hide-scroll">
            {BOOKMARKS.map((bm, i) => (
              <BookmarkRow key={bm.id} t={t} bm={bm}
                state={bm.id === rowId ? rowState : 'default'} last={i === BOOKMARKS.length - 1} />
            ))}
          </div>

          {/* long-press menu overlays the sheet */}
          {rowState === 'menu' && rowId && <BMLongPressMenu t={t} />}
        </div>
      </div>

      {dialog && <BMConfirmDialog t={t} bm={dialogBm} busy={dialog === 'deleting'} />}
      {snackbar && <BMSnackbar t={t} variant={snackbar} />}
    </window.TtsFrame>
  );
}

Object.assign(window, {
  BookmarksSheet, BookmarkRow, BMConfirmDialog, BMSnackbar, BMLongPressMenu, BOOKMARKS,
});
