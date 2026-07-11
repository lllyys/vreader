// Android annotations review-card per-card affordances · issue #1902
// (blocks feature #132 — Android reader nav chrome, annotations review sheet;
//  parity box B/F).
//
// The committed Android review sheet (AnnotationsSheet in
// vreader-android-annotations.jsx) renders HighlightCard / StandaloneNoteCard /
// BookmarkCard as tap-to-jump-only rows. Copy/Share exist ONLY on the in-reader
// SelectionPopover (a different surface), and only a sheet-level Share is drawn.
// There is NO per-card ⋯ overflow → Edit / Copy / Delete on Android — that menu
// is the iOS HighlightsSheetV4 surface (vreader-notes-delete.jsx #1103). So
// per-card Copy/Share and Edit / Delete-from-sheet have no Android depiction.
// Feature #132 ships without them (sheet-level Share + tap-to-jump only). This
// file designs the Android depiction so a follow-up can add them.
//
// ────────────────────────────────────────────────────
// DECISION SUMMARY
// ────────────────────────────────────────────────────
//
// Canonical · a per-card ACTION ROW under the card body — the two verbs the
//   issue names as missing (Copy · Share) as labelled targets, plus a trailing
//   ⋯ overflow that carries the destructive + edit verbs (Edit · Delete). This
//   is the Android-idiomatic split: frequent, safe actions are one tap on a
//   visible control; Edit/Delete live behind the overflow so a mis-tap can't
//   mutate. It also re-uses the SelectionPopover's own Copy/Share vocabulary,
//   so the reader and the review sheet speak the same language.
//
// Alternate · a trailing ⋯ overflow ONLY (Material "more" affordance in the
//   meta row) carrying Edit · Copy · Share · Delete — denser, and 1:1 with the
//   committed iOS ⋯ menu. Shown for comparison; not canonical because it hides
//   the two most-used verbs behind a second tap on a touch device.
//
// Overflow menu · Material dropdown anchored to the ⋯. Edit · Copy · Share,
//   then a divider, then Delete in destructive ink. Bookmark cards get a
//   reduced menu (Copy · Share · Delete — no Edit; there's nothing to edit on a
//   bookmark; bookmark deletion is scoped to its own issue #1903).
//
// Delete · inline row-replacement confirm — the SAME vocabulary as the iOS
//   NotesDeleteConfirm (#1103) and the collections-delete confirm (#1875):
//   a target-named title, one line naming what's lost, a Cancel / Delete pill
//   pair in destructive ink. No system dialog — the confirm replaces the card
//   body so the user keeps their place in the list.
//
// Failure · the body collapses to a tinted error chip with Retry (re-invokes
//   the delete) + Undo (restores the row; nothing committed on failure).
//
// Note-edit entry · Edit swaps the card body for an inline compose field
//   (Android annotations already compose notes inline in the SelectionPopover),
//   with Cancel / Save. Standalone-note Edit needs an updateNote /
//   updateNoteContent API (flagged in the issue) — the design is API-ready.

const AA_SANS = "'Inter', -apple-system, system-ui, sans-serif";
const AA_SERIF = '"Source Serif 4", Georgia, serif';

function aaDanger(ui) { return ui.isDark ? '#e0775a' : '#a8402f'; }

// Local glyphs (stroke 1.6, 24-box) — Copy / Share / Edit / Trash / More / dot.
function AAGlyph({ name, size = 18, color = 'currentColor' }) {
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none',
    stroke: color, strokeWidth: 1.7, strokeLinecap: 'round', strokeLinejoin: 'round' };
  if (name === 'copy') return <svg {...common}><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 012-2h8"/></svg>;
  if (name === 'share') return <svg {...common}><path d="M12 3v13M8 7l4-4 4 4M5 14v5a2 2 0 002 2h10a2 2 0 002-2v-5"/></svg>;
  if (name === 'edit') return <svg {...common}><path d="M13 4l7 7-9 9H4v-7z"/><path d="M11 6l7 7"/></svg>;
  if (name === 'trash') return <svg {...common}><path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1.6 1.6 0 001.6 1.5h6.8A1.6 1.6 0 0017 20l1-13M10 11v6M14 11v6"/></svg>;
  if (name === 'more') return <svg width={size} height={size} viewBox="0 0 24 24"><circle cx="12" cy="5" r="1.6" fill={color}/><circle cx="12" cy="12" r="1.6" fill={color}/><circle cx="12" cy="19" r="1.6" fill={color}/></svg>;
  return null;
}
function AASpinner({ size = 13, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" style={{ animation: 'apfSpin .8s linear infinite' }}>
      <circle cx="12" cy="12" r="9" stroke={color} strokeOpacity="0.25" strokeWidth="2.6" />
      <path d="M12 3a9 9 0 019 9" stroke={color} strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  );
}

// ── the per-card action row: Copy · Share ······ ⋯ ───────────
function AAActionRow({ ui, onMenu }) {
  const btn = (name, label) => (
    <button style={{
      display: 'inline-flex', alignItems: 'center', gap: 7, border: 'none', cursor: 'pointer',
      background: 'transparent', padding: '7px 10px', borderRadius: 9,
      fontFamily: AA_SANS, fontSize: 13, fontWeight: 500, color: ui.sec,
    }}>
      <AAGlyph name={name} size={16} color={ui.sec} />{label}
    </button>
  );
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 2, marginTop: 10, paddingTop: 9,
      borderTop: `0.5px solid ${ui.sep}`, marginLeft: -6,
    }}>
      {btn('copy', 'Copy')}
      {btn('share', 'Share')}
      <span style={{ flex: 1 }} />
      <button aria-label="More actions" onClick={onMenu} style={{
        width: 32, height: 32, borderRadius: 16, border: 'none', cursor: 'pointer',
        background: 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <AAGlyph name="more" size={18} color={ui.sec} />
      </button>
    </div>
  );
}

// ── Material overflow menu (Edit · Copy · Share · Delete) ─────
function AAOverflowMenu({ ui, kind = 'highlight' }) {
  const danger = aaDanger(ui);
  const items = [];
  if (kind !== 'bookmark') items.push({ name: 'edit', label: kind === 'standalone' ? 'Edit note' : 'Edit note' });
  items.push({ name: 'copy', label: kind === 'bookmark' ? 'Copy link' : 'Copy quote' });
  items.push({ name: 'share', label: 'Share' });
  items.push({ name: 'trash', label: kind === 'standalone' ? 'Delete note' : kind === 'bookmark' ? 'Delete bookmark' : 'Delete highlight', danger: true, divider: true });
  return (
    <div style={{
      position: 'absolute', top: 4, right: 4, zIndex: 50, minWidth: 188, padding: '6px 0',
      borderRadius: 14, background: ui.isDark ? '#2f2c28' : '#fdf9ec',
      boxShadow: '0 14px 34px rgba(0,0,0,0.30), 0 0 0 0.5px ' + (ui.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      transformOrigin: 'top right',
    }}>
      {items.map((it) => (
        <div key={it.name} style={{
          display: 'flex', alignItems: 'center', gap: 13, padding: '11px 16px',
          borderTop: it.divider ? `0.5px solid ${ui.sep}` : 'none',
          fontFamily: AA_SANS, fontSize: 14.5, fontWeight: it.danger ? 600 : 500,
          color: it.danger ? danger : ui.ink,
        }}>
          <AAGlyph name={it.name} size={17} color={it.danger ? danger : ui.ink} />
          <span>{it.label}</span>
        </div>
      ))}
    </div>
  );
}

// ── inline delete confirm — NotesDeleteConfirm vocabulary, ui-toned ──
function AADeleteConfirm({ ui, kind = 'highlight', busy }) {
  const danger = aaDanger(ui);
  const title = kind === 'standalone' ? 'Delete this note?' : kind === 'bookmark' ? 'Delete this bookmark?' : 'Delete this highlight?';
  const body = kind === 'standalone'
    ? "The note comes off the chapter. Can’t be undone."
    : kind === 'bookmark'
    ? "The saved place is removed. Can’t be undone."
    : "The colour, the note, and the underline come off the page. Can’t be undone.";
  return (
    <div style={{
      marginTop: 10, borderRadius: 11, padding: '12px 13px 13px',
      background: ui.isDark ? 'rgba(224,119,90,0.08)' : 'rgba(168,64,47,0.05)',
      border: `0.5px solid ${ui.isDark ? 'rgba(224,119,90,0.24)' : 'rgba(168,64,47,0.18)'}`,
    }}>
      <div style={{ fontFamily: AA_SANS, fontSize: 13.5, fontWeight: 600, color: ui.ink, marginBottom: 3 }}>{title}</div>
      <div style={{ fontFamily: AA_SANS, fontSize: 12, lineHeight: 1.45, color: ui.sec, marginBottom: 12, textWrap: 'pretty' }}>{body}</div>
      <div style={{ display: 'flex', gap: 8 }}>
        <button disabled={busy} style={{
          flex: 1, padding: '9px 0', borderRadius: 9, border: `0.5px solid ${ui.sep}`,
          background: 'transparent', fontFamily: AA_SANS, fontSize: 13, fontWeight: 500,
          color: ui.ink, cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.4 : 1,
        }}>Cancel</button>
        <button disabled={busy} style={{
          flex: 1, padding: '9px 0', borderRadius: 9, border: 'none', background: danger, color: '#fff',
          fontFamily: AA_SANS, fontSize: 13, fontWeight: 600, cursor: busy ? 'default' : 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7, opacity: busy ? 0.9 : 1,
        }}>
          {busy && <AASpinner size={12} color="#fff" />}
          {busy ? 'Deleting…' : 'Delete'}
        </button>
      </div>
    </div>
  );
}

// ── failed-delete chip — Retry + Undo (NotesRowError vocabulary) ──
function AARowError({ ui, kind = 'highlight' }) {
  const danger = aaDanger(ui);
  return (
    <div style={{
      marginTop: 10, borderRadius: 11, padding: '11px 12px',
      display: 'flex', alignItems: 'center', gap: 10,
      background: ui.isDark ? 'rgba(224,119,90,0.10)' : 'rgba(168,64,47,0.07)',
      border: `0.5px solid ${ui.isDark ? 'rgba(224,119,90,0.28)' : 'rgba(168,64,47,0.22)'}`,
    }}>
      <div style={{ width: 20, height: 20, borderRadius: 10, flexShrink: 0, background: danger, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <svg width="11" height="11" viewBox="0 0 14 14" fill="none"><path d="M7 3v5M7 10.5v.5" stroke="#fff" strokeWidth="1.7" strokeLinecap="round" /></svg>
      </div>
      <div style={{ flex: 1, fontFamily: AA_SANS, fontSize: 12, color: ui.ink, lineHeight: 1.35 }}>
        Couldn’t delete — {kind === 'standalone' ? 'the note' : kind === 'bookmark' ? 'the bookmark' : 'the highlight'} is still here.
      </div>
      <button style={{ padding: '5px 12px', borderRadius: 100, border: `0.5px solid ${ui.sep}`, background: 'transparent',
        cursor: 'pointer', fontFamily: AA_SANS, fontSize: 12, fontWeight: 600, color: ui.ink }}>Retry</button>
      <button style={{ padding: '5px 10px', borderRadius: 100, border: 'none', background: 'transparent',
        cursor: 'pointer', fontFamily: AA_SANS, fontSize: 12, fontWeight: 500, color: ui.sec }}>Undo</button>
    </div>
  );
}

// ── inline note editor (Edit entry) ──────────────────────────
function AANoteEditor({ ui, color, text }) {
  const c = window.HL_COLORS.find((x) => x.key === color) || window.HL_COLORS[0];
  return (
    <div style={{ marginTop: 10 }}>
      <div style={{
        background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', borderRadius: 10,
        padding: '10px 12px', fontFamily: AA_SANS, fontSize: 13.5, color: ui.ink, lineHeight: 1.5,
        boxShadow: `inset 0 0 0 1.5px ${ui.tint}`, minHeight: 58,
      }}>
        {text}<span style={{ display: 'inline-block', width: 1.5, height: 15, background: ui.tint, verticalAlign: -2, marginLeft: 1 }} />
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginTop: 11 }}>
        {color != null && window.HL_COLORS.map((cc) => (
          <div key={cc.key} style={{ width: 22, height: 22, borderRadius: 11, background: cc.dot,
            boxShadow: cc.key === color ? `0 0 0 2px ${ui.card}, 0 0 0 3.5px ${cc.dot}` : 'none' }} />
        ))}
        <span style={{ flex: 1 }} />
        <button style={{ border: 'none', background: 'transparent', fontFamily: AA_SANS, fontSize: 13.5, fontWeight: 500, color: ui.sec, padding: '6px 8px', cursor: 'pointer' }}>Cancel</button>
        <button style={{ border: 'none', background: ui.tint, color: '#fff', fontFamily: AA_SANS, fontSize: 13.5, fontWeight: 600, borderRadius: 9, padding: '7px 16px', cursor: 'pointer' }}>Save</button>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════
// AACard — a review card + affordance + per-card state machine.
//   kind       : 'highlight' | 'standalone' | 'bookmark'
//   affordance : 'row' (canonical) | 'overflow' (alternate)
//   state      : 'default' | 'menu' | 'confirm' | 'deleting' | 'error' | 'editing'
// ═════════════════════════════════════════════════════
function AACard({ ui, rec, affordance = 'row', state = 'default' }) {
  const kind = rec.kind;
  const danger = aaDanger(ui);
  const menu = state === 'menu';
  const confirm = state === 'confirm';
  const deleting = state === 'deleting';
  const errored = state === 'error';
  const editing = state === 'editing';
  const c = kind === 'highlight' ? (window.HL_COLORS.find((x) => x.key === rec.color) || window.HL_COLORS[0]) : null;

  // left rule
  const rule = kind === 'highlight'
    ? { width: 4, borderRadius: 2, background: c.rule }
    : kind === 'standalone'
    ? { width: 4, borderRadius: 2, background: `repeating-linear-gradient(${ui.tint} 0 4px, transparent 4px 8px)` }
    : null;

  const bodyDim = deleting ? 0.5 : 1;

  return (
    <div style={{ background: ui.card, borderRadius: 14, padding: '14px 15px', boxShadow: ui.cardShadow, position: 'relative', marginBottom: 10 }}>
      {menu && <AAOverflowMenu ui={ui} kind={kind} />}
      <div style={{ display: 'flex', gap: kind === 'bookmark' ? 12 : 12 }}>
        {rule && <div style={{ flexShrink: 0, ...rule }} />}
        {kind === 'bookmark' && <window.Icons.BookmarkFilled size={20} color={ui.tint} style={{ flexShrink: 0, marginTop: 1 }} />}

        <div style={{ flex: 1, minWidth: 0 }}>
          {/* meta row (overflow affordance lives here) */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginBottom: kind === 'bookmark' ? 3 : 8, fontFamily: AA_SANS, fontSize: 12, color: ui.ter }}>
            {kind === 'standalone' && (
              <span style={{ fontFamily: AA_SANS, fontSize: 9.5, fontWeight: 700, letterSpacing: 0.5, color: ui.tint, background: ui.tagBg, borderRadius: 5, padding: '2px 6px' }}>STANDALONE</span>
            )}
            <span>{rec.meta}</span>
            {kind === 'highlight' && rec.note != null && <span style={{ color: ui.tint, fontWeight: 600 }}>· Note</span>}
            <span style={{ flex: 1 }} />
            {deleting ? (
              <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, color: ui.sec }}>
                <AASpinner size={12} color={ui.sec} />Deleting…
              </span>
            ) : affordance === 'overflow' && !confirm && !errored && !editing ? (
              <button aria-label="More actions" style={{
                width: 30, height: 30, marginRight: -6, borderRadius: 15, border: 'none', cursor: 'pointer',
                background: menu ? (ui.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.06)') : 'transparent',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <AAGlyph name="more" size={17} color={ui.sec} />
              </button>
            ) : null}
          </div>

          {/* body */}
          {confirm ? (
            <AADeleteConfirm ui={ui} kind={kind} />
          ) : deleting ? (
            <AADeleteConfirm ui={ui} kind={kind} busy />
          ) : errored ? (
            <AARowError ui={ui} kind={kind} />
          ) : editing ? (
            <>
              <div style={{ fontFamily: AA_SERIF, fontSize: 15, lineHeight: 1.5, color: ui.ink, opacity: kind === 'highlight' ? 1 : 0.5 }}>
                {kind === 'highlight' ? rec.quote : null}
              </div>
              <AANoteEditor ui={ui} color={kind === 'highlight' ? rec.color : null} text={rec.note || rec.body} />
            </>
          ) : (
            <>
              {kind === 'bookmark' ? (
                <div style={{ fontFamily: AA_SERIF, fontSize: 15, color: ui.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis', opacity: bodyDim }}>{rec.label}</div>
              ) : kind === 'standalone' ? (
                <div style={{ fontFamily: AA_SERIF, fontSize: 15.5, lineHeight: 1.52, color: ui.ink, opacity: bodyDim }}>{rec.body}</div>
              ) : (
                <>
                  <div style={{ fontFamily: AA_SERIF, fontSize: 15.5, lineHeight: 1.5, color: ui.ink, opacity: bodyDim }}>{rec.quote}</div>
                  {rec.note != null && (
                    <div style={{ marginTop: 9, paddingTop: 9, borderTop: `0.5px solid ${ui.sep}`, fontFamily: AA_SANS, fontSize: 13.5, lineHeight: 1.5, color: ui.sec, opacity: bodyDim }}>{rec.note}</div>
                  )}
                </>
              )}
              {/* action row affordance */}
              {affordance === 'row' && <AAActionRow ui={ui} />}
            </>
          )}
        </div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════
// AnnotationsSheetV2 — the committed review sheet, now with per-card
// affordances. One row can be forced into a non-default state.
// ═════════════════════════════════════════════════════
const AA_RECORDS = [
  { id: 'h1', kind: 'highlight', color: 'yellow',
    quote: '“She was a woman of mean understanding, little information, and uncertain temper.”',
    note: "Austen's irony lands in the dependent clause.", meta: 'Ch. 1 · Apr 18' },
  { id: 'n1', kind: 'standalone',
    body: 'Track how often weather forces the plot — Jane’s cold at Netherfield is the first.', meta: 'Ch. 7 · Apr 19' },
  { id: 'h2', kind: 'highlight', color: 'green',
    quote: '“It is a truth universally acknowledged…”', note: null, meta: 'Ch. 1 · Apr 18' },
  { id: 'b1', kind: 'bookmark',
    label: '“…the rightful property of some one or other of their daughters.”', meta: 'Ch. 1 · 14%' },
];

function AnnotationsSheetV2({ ui, affordance = 'row', forcedId = 'h1', forcedState = 'default', height = 880 }) {
  return (
    <window.PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <window.AppSheet ui={ui} title="Annotations"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: AA_SANS, fontSize: 15, color: ui.sec }}>Close</button>}
        trailing={<window.Icons.Share size={20} color={ui.tint} />}
        height={height - 36}>
        <div style={{ padding: '12px 16px 32px' }}>
          <div style={{ marginBottom: 10 }}>
            <div style={{ fontFamily: AA_SERIF, fontStyle: 'italic', fontSize: 19, color: ui.ink }}>Pride and Prejudice</div>
            <div style={{ fontFamily: AA_SANS, fontSize: 12.5, color: ui.sec, marginTop: 2 }}>12 highlights · 4 notes · 3 bookmarks</div>
          </div>
          <window.FilterChips ui={ui} active="All" />
          <div style={{ height: 12 }} />
          {AA_RECORDS.map((rec) => (
            <AACard key={rec.id} ui={ui} rec={rec} affordance={affordance}
              state={rec.id === forcedId ? forcedState : 'default'} />
          ))}
        </div>
      </window.AppSheet>
    </window.PhoneFrame>
  );
}

Object.assign(window, {
  AACard, AnnotationsSheetV2, AAOverflowMenu, AADeleteConfirm, AARowError,
  AAActionRow, AANoteEditor, AA_RECORDS,
});
