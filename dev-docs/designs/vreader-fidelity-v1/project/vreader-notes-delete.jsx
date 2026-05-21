// HighlightsSheet — delete affordance · issue #1103 (parent bug #249 / #1080).
//
// The committed HighlightsSheetV3 (vreader-notes-unified.jsx) renders highlight
// + standalone-note cards that are tap-to-jump only. There is no way to delete
// a row from the review surface — the regression bug #249 calls this out.
//
// Rule 51 blocks a self-designed fix. The Codex Gate-4 audit on the worktree
// fix branch (019e47fd-9b06-79d3-b011-4f460107f005) rejected `.contextMenu`
// as the only mechanism — context-menus on app content are not the
// "system-chrome restoration" exemption. So we ship a committed surface.
//
// ────────────────────────────────────────────────────
// DECISION SUMMARY
// ────────────────────────────────────────────────────
//
// Canonical · trailing `⋯` icon-button on each card → small popover with
//   Edit · Copy · Delete. Reasons:
//     1. Keeps the v3 card layout intact. Shape (a) `List` + `.swipeActions`
//        from the issue would force a wholesale reskin into iOS List rows
//        with new separators / padding / background — a visible regression
//        on a surface that just got committed.
//     2. Discoverable as a real button. VoiceOver + Reduce-Motion + Switch
//        Control paths land on a labelled control; no gesture-only paths.
//     3. Extends the already-committed `HPDeleteConfirm` vocabulary from
//        `vreader-highlight-popover.jsx` (issue #949). The destructive ink,
//        the Cancel/Delete pill pair, and the body copy ("Can't be undone")
//        are the same primitives. The issue body explicitly asks "should
//        the review sheet match?" — yes.
//
// Secondary · iOS-native left-swipe revealing the same Edit + Delete
//   destinations. Same destinations, gesture instead of tap. Surfaced
//   because iOS users expect it on review lists (Mail / Notes / Reminders).
//   NOT the only path — discovery + accessibility ride on the menu button.
//
// Confirmation · inline row-replacement strip. The card's lead content
//   (color swatch + excerpt block, or the note body) is briefly replaced by
//   "Delete this highlight? · Cancel · Delete". Mirrors HPDeleteConfirm
//   directly. No system-modal alert — the destructive surface stays inside
//   the row so the user keeps their place in the list.
//
// Edit · handoff, not re-implementation.
//     - HighlightCardV4 → Edit jumps to the passage and opens the existing
//       HighlightActionCard in `mode='editing'`. The sheet does NOT embed a
//       textarea (the existing popover is the one editor surface for notes
//       on highlights — see issue #949).
//     - StandaloneNoteCardV4 → Edit jumps to the locator and opens the
//       standalone-note editor (legacy AnnotationEditSheet → HighlightNote
//       EditSheet; issue #914). Same handoff pattern.
//
// Failed delete · row body collapses to an error chip with Retry + Undo
//   (Undo restores the row to its pre-tap state; Retry re-invokes the
//   PersistenceActor call). 3-second auto-dismiss to the default row state
//   so the list doesn't carry a stale error.
//
// Empty-after-delete · the HighlightsSheetV3 empty state re-flows naturally
//   when the stream length hits 0. No new copy.

// ─────────────────────────────────────────────────────
// Theme-resolved helpers
// ─────────────────────────────────────────────────────
const ND_SWATCH = (typeof HP_SWATCH !== 'undefined') ? HP_SWATCH
  : { yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8' };

function ndDanger(t) { return t.isDark ? '#e89090' : '#a83a3a'; }
function ndAmber(t)  { return t.isDark ? '#e0a85a' : '#a8742a'; }

// Local glyphs — small, stroke 1.5, sized for 14–16 px row-action targets.
function NDTrashGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
      stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 6h14M8 3h4a1 1 0 011 1v2H7V4a1 1 0 011-1zM5 6l1 11a1.5 1.5 0 001.5 1.5h5A1.5 1.5 0 0014 17l1-11M9 9v6M11 9v6"/>
    </svg>
  );
}
function NDPencilGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
      stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M13 3l4 4-9 9H4v-4z"/><path d="M11 5l4 4"/>
    </svg>
  );
}
function NDCopyGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <rect x="6" y="6" width="11" height="12" rx="2" stroke={color} strokeWidth="1.4"/>
      <path d="M3 14V4a1 1 0 011-1h9" stroke={color} strokeWidth="1.4" strokeLinecap="round"/>
    </svg>
  );
}
function NDMoreGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20">
      <circle cx="4.5" cy="10" r="1.4" fill={color}/>
      <circle cx="10"  cy="10" r="1.4" fill={color}/>
      <circle cx="15.5" cy="10" r="1.4" fill={color}/>
    </svg>
  );
}
function NDSpinner({ size = 14, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" style={{ animation: 'spin 0.9s linear infinite' }}>
      <circle cx="10" cy="10" r="7" stroke={color} strokeOpacity="0.22" strokeWidth="2" fill="none"/>
      <path d="M10 3a7 7 0 017 7" stroke={color} strokeWidth="2" strokeLinecap="round" fill="none"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────
// Trailing ⋯ icon button — the canonical visible affordance
// ─────────────────────────────────────────────────────
// Lives in the meta row, replacing nothing — it appears AFTER the date as a
// secondary target. 28×28 hit target, 16-glyph. Stays visible at rest
// (no hover-reveal) so it's discoverable on a touch device.
function NotesMoreButton({ t, onTap, active = false, label = 'More actions' }) {
  return (
    <button onClick={(e) => { e.stopPropagation(); onTap?.(e); }}
      aria-label={label}
      style={{
        width: 28, height: 28, padding: 0, marginLeft: 4, marginRight: -6,
        borderRadius: 14, border: 'none', cursor: 'pointer',
        background: active
          ? (t.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.07)')
          : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>
      <NDMoreGlyph size={16} color={t.sub}/>
    </button>
  );
}

// ─────────────────────────────────────────────────────
// NotesActionMenu — small popover with Edit · Copy · Delete
// ─────────────────────────────────────────────────────
// Anchored to the ⋯ button's bottom-right corner (right-aligned so it never
// runs off the screen on a phone-width sheet). 168 px wide. Three items.
// Delete uses destructive ink and a divider above to separate destructive
// from safe.
function NotesActionMenu({ t, onEdit, onCopy, onDelete, onClose, kind = 'highlight' }) {
  const danger = ndDanger(t);
  const editLabel = kind === 'standalone' ? 'Edit note' : 'Edit note…';
  const copyLabel = kind === 'standalone' ? 'Copy note' : 'Copy quote';
  const delLabel  = kind === 'standalone' ? 'Delete note' : 'Delete highlight';

  const item = (label, glyph, on, opts = {}) => (
    <button onClick={(e) => { e.stopPropagation(); on?.(); }} style={{
      display: 'flex', alignItems: 'center', gap: 11, width: '100%',
      padding: '9px 12px', border: 'none', background: 'transparent',
      cursor: 'pointer', textAlign: 'left',
      fontFamily: 'inherit', fontSize: 13.5, color: opts.danger ? danger : t.ink,
      fontWeight: opts.danger ? 600 : 500,
      borderTop: opts.divider
        ? `0.5px solid ${t.rule}` : 'none',
    }}>
      {glyph({ size: 15, color: opts.danger ? danger : t.ink })}
      <span style={{ flex: 1 }}>{label}</span>
    </button>
  );

  return (
    <>
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, zIndex: 90, background: 'transparent',
      }}/>
      <div style={{
        position: 'absolute', right: 14, zIndex: 95,
        width: 184, padding: '4px 0', borderRadius: 12,
        background: t.isDark ? '#2f2c28' : '#fdf9ec',
        boxShadow: '0 14px 30px rgba(0,0,0,0.28), 0 0 0 0.5px '
          + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.10)'),
        animation: 'ndMenuIn 0.16s cubic-bezier(0.32, 0.72, 0, 1)',
        transformOrigin: 'top right',
      }}>
        {item(editLabel, NDPencilGlyph, onEdit)}
        {item(copyLabel, NDCopyGlyph, onCopy)}
        {item(delLabel, NDTrashGlyph, onDelete, { danger: true, divider: true })}
      </div>
    </>
  );
}

// ─────────────────────────────────────────────────────
// NotesDeleteConfirm — inline row-replacement strip
// ─────────────────────────────────────────────────────
// Replaces the card's lead content (excerpt or note body) with a
// confirmation strip. Mirrors HPDeleteConfirm vocabulary: short copy that
// names what's lost, paired Cancel / Delete buttons with destructive ink.
//
// The meta row stays — the user sees WHICH row they're about to destroy.
function NotesDeleteConfirm({ t, kind, onCancel, onConfirm, busy = false }) {
  const danger = ndDanger(t);
  const isStandalone = kind === 'standalone';
  return (
    <div style={{
      borderRadius: 10,
      background: t.isDark ? 'rgba(232,144,144,0.06)' : 'rgba(168,58,58,0.04)',
      padding: '10px 12px 12px',
      border: `0.5px solid ${t.isDark ? 'rgba(232,144,144,0.22)' : 'rgba(168,58,58,0.16)'}`,
    }}>
      <div style={{
        fontFamily: 'inherit', fontSize: 13, color: t.ink,
        fontWeight: 500, marginBottom: 2,
      }}>
        {isStandalone ? 'Delete this note?' : 'Delete this highlight?'}
      </div>
      <div style={{
        fontSize: 11.5, color: t.sub, lineHeight: 1.4, marginBottom: 10,
        textWrap: 'pretty',
      }}>
        {isStandalone
          ? "The note comes off the chapter. Can't be undone."
          : "The color, the note, and the underline come off the page. Can't be undone."}
      </div>
      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={onCancel} disabled={busy} style={{
          flex: 1, padding: '7px 0', borderRadius: 8,
          border: `0.5px solid ${t.rule}`, background: 'transparent',
          fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500,
          color: t.ink, cursor: busy ? 'default' : 'pointer',
          opacity: busy ? 0.4 : 1,
        }}>Cancel</button>
        <button onClick={onConfirm} disabled={busy} style={{
          flex: 1, padding: '7px 0', borderRadius: 8, border: 'none',
          background: danger, color: '#fff',
          fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600,
          cursor: busy ? 'default' : 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          gap: 6, opacity: busy ? 0.85 : 1,
        }}>
          {busy && <NDSpinner size={12} color="#fff"/>}
          {busy ? 'Deleting…' : 'Delete'}
        </button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// NotesRowError — failed delete
// ─────────────────────────────────────────────────────
// Replaces the row's lead content with a tinted error chip + Retry + Undo.
// Undo restores the row to its pre-tap state (the persistence call hasn't
// committed if it failed). Retry re-invokes the call.
function NotesRowError({ t, message = "Couldn't delete. Tap retry.", onRetry, onUndo }) {
  const danger = ndDanger(t);
  return (
    <div style={{
      borderRadius: 10,
      background: t.isDark ? 'rgba(232,144,144,0.08)' : 'rgba(168,58,58,0.06)',
      padding: '10px 12px',
      display: 'flex', alignItems: 'center', gap: 10,
      border: `0.5px solid ${t.isDark ? 'rgba(232,144,144,0.26)' : 'rgba(168,58,58,0.20)'}`,
    }}>
      <div style={{
        width: 18, height: 18, borderRadius: 9, flexShrink: 0,
        background: danger, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="10" height="10" viewBox="0 0 14 14" fill="none">
          <path d="M7 3v5M7 10.5v.5" stroke="#fff" strokeWidth="1.6" strokeLinecap="round"/>
        </svg>
      </div>
      <div style={{
        flex: 1, fontSize: 12, color: t.ink, lineHeight: 1.35,
      }}>{message}</div>
      <button onClick={onRetry} style={{
        padding: '4px 10px', borderRadius: 100, border: `0.5px solid ${t.rule}`,
        background: 'transparent', cursor: 'pointer',
        fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, color: t.ink,
      }}>Retry</button>
      <button onClick={onUndo} style={{
        padding: '4px 10px', borderRadius: 100, border: 'none',
        background: 'transparent', cursor: 'pointer',
        fontFamily: 'inherit', fontSize: 11.5, fontWeight: 500, color: t.sub,
      }}>Undo</button>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Swipe-revealed action drawer
// ─────────────────────────────────────────────────────
// The card slides left to reveal Edit (amber) + Delete (destructive ink)
// trailing buttons. Visual only — gesture handling is in the SwiftUI host.
// Buttons are 64 px wide each; together they take 128 px of trailing space.
function NotesSwipeActions({ t, onEdit, onDelete }) {
  const danger = ndDanger(t);
  const amber = ndAmber(t);
  const cell = (bg, glyph, label, on) => (
    <button onClick={on} style={{
      width: 64, height: '100%', padding: 0, border: 'none', cursor: 'pointer',
      background: bg, color: '#fff',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', gap: 4,
      fontFamily: 'inherit', fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3,
    }}>
      {glyph}
      <span>{label}</span>
    </button>
  );
  return (
    <div style={{
      position: 'absolute', right: 0, top: 0, bottom: 0,
      display: 'flex', alignItems: 'stretch',
      borderRadius: 0, overflow: 'hidden',
    }}>
      {cell(amber,  <NDPencilGlyph size={17} color="#fff"/>, 'Edit',   onEdit)}
      {cell(danger, <NDTrashGlyph  size={17} color="#fff"/>, 'Delete', onDelete)}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// HighlightCardV4 — V3 card + trailing ⋯ + state machine
// ─────────────────────────────────────────────────────
// Props:
//   state     — 'default' | 'menu-open' | 'confirming' | 'deleting'
//              | 'error' | 'swipe-revealed' | 'dim-after-delete'
//   onJump, onMore, onEdit, onCopy, onDelete, onConfirmDelete, onCancelDelete
function HighlightCardV4({ t, h, state = 'default',
                          onJump, onMore, onEdit, onCopy, onDelete,
                          onConfirmDelete, onCancelDelete, onRetry, onUndo }) {
  const colorMap = ND_SWATCH;
  const swatch = colorMap[h.color] || colorMap.yellow;
  const isDeleting = state === 'deleting';
  const isError    = state === 'error';
  const isConfirm  = state === 'confirming';
  const isMenu     = state === 'menu-open';
  const isSwipe    = state === 'swipe-revealed';
  const isDim      = state === 'dim-after-delete';

  return (
    <div style={{
      position: 'relative',
      padding: '14px 0', borderBottom: `0.5px solid ${t.rule}`,
      opacity: isDim ? 0.35 : 1,
      transition: 'opacity 0.2s',
    }}>
      {/* Trailing swipe-action drawer */}
      {isSwipe && <NotesSwipeActions t={t} onEdit={onEdit} onDelete={onDelete}/>}

      <div onClick={() => !isConfirm && !isMenu && onJump?.(h)} style={{
        cursor: isConfirm || isMenu ? 'default' : 'pointer',
        transform: isSwipe ? 'translateX(-128px)' : 'none',
        transition: 'transform 0.18s cubic-bezier(0.32, 0.72, 0, 1)',
        background: t.isDark ? '#222020' : '#fcf8f0',
      }}>
        {/* Meta row */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          marginBottom: 8, fontSize: 11, color: t.sub,
        }}>
          <div style={{
            width: 10, height: 10, borderRadius: 2, background: swatch,
            flexShrink: 0,
          }}/>
          <span>{h.chapter}</span>
          <span style={{ opacity: 0.5 }}>·</span>
          <span>p. {h.page}</span>
          <span style={{ flex: 1 }}/>
          {isDeleting ? (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <NDSpinner size={12} color={t.sub}/>
              <span>Deleting…</span>
            </span>
          ) : (
            <>
              <span>{h.date}</span>
              {!isSwipe && (
                <NotesMoreButton t={t} active={isMenu}
                  onTap={onMore} label={`Actions for highlight on ${h.chapter}`}/>
              )}
            </>
          )}
        </div>

        {/* Body — varies by state */}
        {isConfirm ? (
          <NotesDeleteConfirm t={t} kind="highlight"
            onCancel={onCancelDelete} onConfirm={onConfirmDelete}/>
        ) : isError ? (
          <NotesRowError t={t} onRetry={onRetry} onUndo={onUndo}/>
        ) : (
          <>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14.5, fontStyle: 'italic', color: t.ink, lineHeight: 1.45,
              borderLeft: `2px solid ${swatch}`, paddingLeft: 12,
              opacity: isDeleting ? 0.55 : 1,
            }}>"{h.text}"</div>
            {h.note && (
              <div style={{
                fontFamily: 'inherit', fontSize: 13, color: t.sub,
                marginTop: 8, lineHeight: 1.4, paddingLeft: 14,
                display: 'flex', gap: 6, alignItems: 'flex-start',
                opacity: isDeleting ? 0.55 : 1,
              }}>
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none"
                  stroke={t.sub} strokeWidth="1.7" strokeLinecap="round"
                  strokeLinejoin="round" style={{ marginTop: 2, flexShrink: 0 }}>
                  <path d="M5 4h11l4 4v12H5z"/><path d="M9 11h7M9 15h5"/>
                </svg>
                <span>{h.note}</span>
              </div>
            )}
          </>
        )}
      </div>

      {/* Action menu — anchored to the ⋯ button, right-aligned */}
      {isMenu && (
        <div style={{ position: 'absolute', top: 28, right: 0, zIndex: 95 }}>
          <NotesActionMenu t={t} kind="highlight"
            onEdit={onEdit} onCopy={onCopy} onDelete={onDelete}
            onClose={() => onCancelDelete?.()}/>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// StandaloneNoteCardV4 — V3 standalone card + trailing ⋯ + state machine
// ─────────────────────────────────────────────────────
function StandaloneNoteCardV4({ t, note, state = 'default',
                                onJump, onMore, onEdit, onCopy, onDelete,
                                onConfirmDelete, onCancelDelete, onRetry, onUndo }) {
  const isDeleting = state === 'deleting';
  const isError    = state === 'error';
  const isConfirm  = state === 'confirming';
  const isMenu     = state === 'menu-open';
  const isSwipe    = state === 'swipe-revealed';
  const isDim      = state === 'dim-after-delete';

  return (
    <div style={{
      position: 'relative',
      padding: '14px 0', borderBottom: `0.5px solid ${t.rule}`,
      opacity: isDim ? 0.35 : 1,
      transition: 'opacity 0.2s',
    }}>
      {isSwipe && <NotesSwipeActions t={t} onEdit={onEdit} onDelete={onDelete}/>}

      <div onClick={() => !isConfirm && !isMenu && onJump?.(note)} style={{
        cursor: isConfirm || isMenu ? 'default' : 'pointer',
        transform: isSwipe ? 'translateX(-128px)' : 'none',
        transition: 'transform 0.18s cubic-bezier(0.32, 0.72, 0, 1)',
        background: t.isDark ? '#222020' : '#fcf8f0',
      }}>
        {/* Meta row */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          marginBottom: 8, fontSize: 11, color: t.sub,
        }}>
          <div style={{
            width: 12, height: 12, borderRadius: 3,
            background: `${t.accent}22`, color: t.accent,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            flexShrink: 0,
          }}>
            <svg width="7" height="8" viewBox="0 0 7 8">
              <path d="M0.5 0.5h5l1 1v6h-6z" fill="currentColor" opacity="0.9"/>
              <path d="M1.8 3h3.2M1.8 4.6h2.2" stroke={t.isDark ? '#2a2724' : '#fcf8f0'} strokeWidth="0.7"/>
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
          {isDeleting ? (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}>
              <NDSpinner size={12} color={t.sub}/>
              <span>Deleting…</span>
            </span>
          ) : (
            <>
              <span>{note.date}</span>
              {!isSwipe && (
                <NotesMoreButton t={t} active={isMenu}
                  onTap={onMore} label={`Actions for standalone note on ${note.chapter}`}/>
              )}
            </>
          )}
        </div>

        {isConfirm ? (
          <NotesDeleteConfirm t={t} kind="standalone"
            onCancel={onCancelDelete} onConfirm={onConfirmDelete}/>
        ) : isError ? (
          <NotesRowError t={t} onRetry={onRetry} onUndo={onUndo}
            message="Couldn't delete the note. Tap retry."/>
        ) : (
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 14.5, color: t.ink, lineHeight: 1.5, textWrap: 'pretty',
            paddingLeft: 12, borderLeft: `2px dashed ${t.accent}88`,
            opacity: isDeleting ? 0.55 : 1,
          }}>{note.body}</div>
        )}
      </div>

      {isMenu && (
        <div style={{ position: 'absolute', top: 28, right: 0, zIndex: 95 }}>
          <NotesActionMenu t={t} kind="standalone"
            onEdit={onEdit} onCopy={onCopy} onDelete={onDelete}
            onClose={() => onCancelDelete?.()}/>
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// HighlightsSheetV4 — sheet that uses V4 cards
// ─────────────────────────────────────────────────────
// Identical chrome to HighlightsSheetV3 (vreader-notes-unified.jsx); the
// only change is which card components it instantiates. State for the
// per-row interaction lives on the sheet so only ONE row can be in a
// non-default state at any moment (menu-open / confirming / etc.).
function HighlightsSheetV4({ theme, highlights = (typeof SAMPLE_HIGHLIGHTS_PLUS_NOTES !== 'undefined' ? SAMPLE_HIGHLIGHTS_PLUS_NOTES : []),
                             standalones = (typeof SAMPLE_STANDALONE !== 'undefined' ? SAMPLE_STANDALONE : []),
                             filter: initialFilter = 'all', onClose, onJump,
                             // forced-state injection for canvas artboards
                             forcedRowId = null, forcedState = null }) {
  const t = theme;
  const [filter, setFilter] = React.useState(initialFilter);
  const [rowState, setRowState] = React.useState({ id: forcedRowId, state: forcedState });

  // Drive forced state from props (artboards set this and never mutate)
  React.useEffect(() => {
    if (forcedRowId != null) setRowState({ id: forcedRowId, state: forcedState });
  }, [forcedRowId, forcedState]);

  const allHighlights = highlights;
  const allNotes      = [...standalones, ...highlights.filter(h => h.note)];
  const counts = {
    all:        allHighlights.length + standalones.length,
    highlights: allHighlights.length,
    notes:      allNotes.length,
    bookmarks:  0,
  };

  const allStream = React.useMemo(() => {
    const items = [
      ...highlights.map(h => ({ ...h, kind: 'highlight' })),
      ...standalones.map(s => ({ ...s, kind: 'standalone' })),
    ];
    return items.slice().reverse();
  }, [highlights, standalones]);

  const stream = filter === 'all'        ? allStream
              : filter === 'highlights'  ? allHighlights.map(h => ({ ...h, kind: 'highlight' }))
              : filter === 'notes'       ? allNotes.map(n => ({ ...n, kind: n.body ? 'standalone' : 'highlight' }))
              : [];

  const stateFor = (id) => rowState.id === id ? rowState.state : 'default';
  const handlers = (id) => ({
    onMore:          () => setRowState({ id, state: 'menu-open' }),
    onCancelDelete:  () => setRowState({ id: null, state: null }),
    onDelete:        () => setRowState({ id, state: 'confirming' }),
    onConfirmDelete: () => setRowState({ id, state: 'deleting' }),
    onEdit:          () => setRowState({ id: null, state: null }),
    onCopy:          () => setRowState({ id: null, state: null }),
    onRetry:         () => setRowState({ id, state: 'deleting' }),
    onUndo:          () => setRowState({ id: null, state: null }),
    onJump:          (x) => onJump?.(x),
  });

  return (
    <Sheet theme={t} onClose={onClose} height={680} title="Annotations">
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

      {stream.length > 0 ? (
        <div style={{ padding: '8px 18px 24px' }}>
          {stream.map(item => item.kind === 'standalone'
            ? <StandaloneNoteCardV4 key={item.id} t={t} note={item}
                state={stateFor(item.id)} {...handlers(item.id)}/>
            : <HighlightCardV4 key={item.id} t={t} h={item}
                state={stateFor(item.id)} {...handlers(item.id)}/>)}
        </div>
      ) : (
        typeof EmptyState !== 'undefined' && typeof EmptyHighlightsArt !== 'undefined' ? (
          <EmptyState t={t}
            art={<EmptyHighlightsArt t={t}/>}
            title={
              filter === 'all'          ? 'No highlights or notes yet'
              : filter === 'highlights' ? 'No highlights yet'
              : filter === 'notes'      ? 'No notes yet'
              : 'No bookmarks yet'
            }
            body={
              filter === 'all'
                ? "Long-press any passage to highlight or add a note. Or tap the note icon on a chapter to leave a standalone note that isn't tied to a passage."
                : filter === 'bookmarks'
                ? 'Tap the bookmark icon in the top bar to save your place.'
                : filter === 'notes'
                ? 'Add a note to any highlight, or leave a standalone note at a chapter.'
                : 'Long-press any passage to highlight it. Pick a colour to keep them organised.'
            }
          />
        ) : null
      )}
    </Sheet>
  );
}

Object.assign(window, {
  HighlightsSheetV4,
  HighlightCardV4,
  StandaloneNoteCardV4,
  NotesActionMenu,
  NotesDeleteConfirm,
  NotesRowError,
  NotesSwipeActions,
  NotesMoreButton,
  NDTrashGlyph, NDPencilGlyph, NDCopyGlyph, NDMoreGlyph, NDSpinner,
});
