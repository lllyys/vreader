// Collections delete affordance · issue #1875 (parent #1869 / feature #127 WI-5).
//
// The committed Android manage sheet (CollectionsManageSheet in
// vreader-library-android.jsx) ships list + inline-rename + create, and its
// EDIT mode shows a reorder drag-handle + a right-chevron disclosure on each
// user collection. That chevron was always meant to open a per-collection
// detail/edit screen — but that screen was never depicted, so DELETE had no
// design-grounded home. Feature #127 shipped WITHOUT delete and deferred it
// here (rule 51: no self-designed UI).
//
// This file designs the missing screen and the delete control on it.
//
// ────────────────────────────────────────────────────
// DECISION SUMMARY
// ────────────────────────────────────────────────────
//
// Surface · the edit-mode chevron opens a pushed "Edit Collection" screen
//   inside the same Collections sheet (back → Collections). It carries the
//   rename field (promoted out of the list's inline rename) and, as a
//   separate grouped card at the bottom, the destructive Delete control.
//   Grounded: the committed edit mode already routes user collections to this
//   chevron; system collections ("Currently Reading" / "Finished") show a
//   count instead and never reach it, so they stay non-deletable by
//   construction.
//
// Delete control · a left-aligned destructive row ("Delete Collection", trash
//   glyph) in its own card — the same shape as the editor's existing
//   "Delete Key" row (vreader-ai-provider-fields.jsx). NOT swipe-to-delete:
//   the committed edit mode owns the horizontal gesture for reorder
//   (drag-handle), so a swipe here would collide; and the row is a real
//   labelled control (VoiceOver / Switch Control land on it).
//
// Confirmation · YES, an inline two-step confirm — the exact vocabulary of
//   HPDeleteConfirm (vreader-highlight-popover.jsx #949) and NotesDeleteConfirm
//   (vreader-notes-delete.jsx #1103): title that names the target, one line of
//   body copy, paired Cancel / Delete pills in destructive ink, "Can't be
//   undone." Collections warrant the confirm (unlike a single highlight) because
//   the action drops every membership on the shelf at once. The confirm
//   replaces the delete card's content in place — no system alert — so the
//   user keeps their place.
//
// What delete does (stated in human terms in the footer + confirm body):
//   removes the collection + its membership rows only. The BOOKS stay in the
//   library — BookCollectionCrossRef FK is ON DELETE CASCADE, so only the
//   join rows drop. LibraryViewModel.deleteCollection resets the active
//   filter to "All".
//
// Failed delete · the row collapses to a tinted error chip with Retry
//   (re-invokes the repo call) — mirrors NotesRowError. No data was lost
//   because the delete transaction rolled back.
//
// Empty-after-last-delete · deleting the final collection returns to the list,
//   which shows a brief "Collection deleted" toast, then the sheet's empty
//   state. Because the shelf-bar and the Manage entry both hide when zero
//   collections exist (already handled in #127), this empty sheet is only
//   reachable transiently right after the last delete.

const CD_SANS = "'Inter', -apple-system, system-ui, sans-serif";
const CD_SERIF = '"Source Serif 4", Georgia, serif';

function cdDanger(ui) { return ui.isDark ? '#e0775a' : '#a8402f'; }

function CDTrash({ size = 19, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      stroke={color} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 7h16M9 7V5a1 1 0 011-1h4a1 1 0 011 1v2M6 7l1 13a1.6 1.6 0 001.6 1.5h6.8A1.6 1.6 0 0017 20l1-13M10 11v6M14 11v6"/>
    </svg>
  );
}
function CDSpinner({ size = 13, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
      style={{ animation: 'apfSpin .8s linear infinite' }}>
      <circle cx="12" cy="12" r="9" stroke={color} strokeOpacity="0.25" strokeWidth="2.6" />
      <path d="M12 3a9 9 0 019 9" stroke={color} strokeWidth="2.6" strokeLinecap="round" />
    </svg>
  );
}

// ─────────────────────────────────────────────────────
// Inline two-step confirm — HPDeleteConfirm / NotesDeleteConfirm vocabulary,
// re-toned to the sheet's form palette (ui.*). Replaces the delete card body.
// ─────────────────────────────────────────────────────
function CDDeleteConfirm({ ui, name, count, busy }) {
  const danger = cdDanger(ui);
  return (
    <div style={{ padding: '13px 15px 15px' }}>
      <div style={{ fontFamily: CD_SANS, fontSize: 14, fontWeight: 600, color: ui.ink, marginBottom: 3 }}>
        Delete “{name}”?
      </div>
      <div style={{ fontFamily: CD_SANS, fontSize: 12.5, lineHeight: 1.45, color: ui.sec, marginBottom: 13, textWrap: 'pretty' }}>
        The {count} {count === 1 ? 'book stays' : 'books stay'} in your library — only this shelf and its assignments are removed. Can’t be undone.
      </div>
      <div style={{ display: 'flex', gap: 9 }}>
        <button disabled={busy} style={{
          flex: 1, padding: '10px 0', borderRadius: 10,
          border: `0.5px solid ${ui.sep}`, background: 'transparent',
          fontFamily: CD_SANS, fontSize: 14, fontWeight: 500, color: ui.ink,
          cursor: busy ? 'default' : 'pointer', opacity: busy ? 0.4 : 1,
        }}>Cancel</button>
        <button disabled={busy} style={{
          flex: 1, padding: '10px 0', borderRadius: 10, border: 'none',
          background: danger, color: '#fff',
          fontFamily: CD_SANS, fontSize: 14, fontWeight: 600,
          cursor: busy ? 'default' : 'pointer',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
          opacity: busy ? 0.9 : 1,
        }}>
          {busy && <CDSpinner size={13} color="#fff" />}
          {busy ? 'Deleting…' : 'Delete'}
        </button>
      </div>
    </div>
  );
}

// Failed-delete chip — NotesRowError vocabulary.
function CDDeleteError({ ui }) {
  const danger = cdDanger(ui);
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '13px 15px' }}>
      <div style={{
        width: 20, height: 20, borderRadius: 10, flexShrink: 0, background: danger, color: '#fff',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="11" height="11" viewBox="0 0 14 14" fill="none">
          <path d="M7 3v5M7 10.5v.5" stroke="#fff" strokeWidth="1.7" strokeLinecap="round" />
        </svg>
      </div>
      <div style={{ flex: 1, fontFamily: CD_SANS, fontSize: 12.5, color: ui.ink, lineHeight: 1.35 }}>
        Couldn’t delete — nothing was removed.
      </div>
      <button style={{
        padding: '6px 14px', borderRadius: 100, border: `0.5px solid ${ui.sep}`,
        background: 'transparent', cursor: 'pointer',
        fontFamily: CD_SANS, fontSize: 12.5, fontWeight: 600, color: ui.ink,
      }}>Retry</button>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Shared sheet chrome with a back-nav header (wider leading than AppSheet,
// so "‹ Collections" fits). Matches AppSheet's grabber + serif title + rule.
// ─────────────────────────────────────────────────────
function NavSheet({ ui, title, onBackLabel = 'Collections', trailing, height, children }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 200, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.35)' }}>
      <div style={{
        background: ui.sheetBg, height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)', display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
        </div>
        <div style={{ display: 'flex', alignItems: 'center', padding: '14px 16px 12px', borderBottom: `0.5px solid ${ui.sep}`, position: 'relative' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 3, minWidth: 108 }}>
            <window.Icons.ChevronL size={22} color={ui.tint} />
            <span style={{ fontFamily: CD_SANS, fontSize: 15, color: ui.tint }}>{onBackLabel}</span>
          </div>
          <div style={{ position: 'absolute', left: 0, right: 0, textAlign: 'center', pointerEvents: 'none' }}>
            <span style={{ fontFamily: CD_SERIF, fontSize: 17, fontWeight: 600, color: ui.ink }}>{title}</span>
          </div>
          <div style={{ flex: 1 }} />
          <div style={{ minWidth: 60, display: 'flex', justifyContent: 'flex-end' }}>{trailing}</div>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }} className="hide-scroll">{children}</div>
      </div>
    </div>
  );
}

// ═════════════════════════════════════════════════════
// CollectionDetailSheet — the pushed "Edit Collection" screen.
//   state: 'rest' | 'renaming' | 'confirm' | 'deleting' | 'error'
// ═════════════════════════════════════════════════════
function CollectionDetailSheet({ ui, state = 'rest', name = 'Fiction', count = 5, height = 880 }) {
  const { Card, GroupHeader, GroupFooter, Sep } = window;
  const danger = cdDanger(ui);
  const renaming = state === 'renaming';
  const confirming = state === 'confirm';
  const deleting = state === 'deleting';
  const errored = state === 'error';
  const displayName = renaming ? 'Sci-Fi & Fantasy' : name;

  const Done = renaming
    ? <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: CD_SANS, fontSize: 15, fontWeight: 600, color: ui.tint, cursor: 'pointer' }}>Done</button>
    : null;

  return (
    <window.PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <NavSheet ui={ui} title="Edit Collection" trailing={Done} height={height - 36}>
        <div style={{ padding: '16px 18px 32px' }}>

          {/* NAME */}
          <GroupHeader ui={ui}>Name</GroupHeader>
          <Card ui={ui}>
            <div style={{
              display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 14px',
              borderRadius: 14,
              background: renaming ? ui.fieldHi : 'transparent',
              boxShadow: renaming ? `inset 0 0 0 1.5px ${ui.tint}` : 'none',
            }}>
              <window.Icons.Folder size={19} color={ui.tint} />
              <span style={{ flex: 1, fontFamily: CD_SANS, fontSize: 15.5, color: ui.ink, marginLeft: 11 }}>
                {displayName}
                {renaming && <span style={{ display: 'inline-block', width: 1.5, height: 17, background: ui.tint, verticalAlign: -3, marginLeft: 1 }} />}
              </span>
              {renaming
                ? <window.Icons.Close size={17} color={ui.ter} />
                : <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />}
            </div>
          </Card>
          <GroupFooter ui={ui}>
            {renaming
              ? 'The new name shows on the shelf-bar and everywhere this collection appears.'
              : `${count} books · tap to rename. Reorder shelves back in the list.`}
          </GroupFooter>

          {/* DELETE */}
          <div style={{ height: 26 }} />
          <Card ui={ui}>
            {confirming || deleting ? (
              <CDDeleteConfirm ui={ui} name={name} count={count} busy={deleting} />
            ) : errored ? (
              <CDDeleteError ui={ui} />
            ) : (
              <div style={{ display: 'flex', alignItems: 'center', gap: 11, minHeight: 52, padding: '0 15px' }}>
                <CDTrash size={19} color={danger} />
                <span style={{ fontFamily: CD_SANS, fontSize: 15.5, fontWeight: 500, color: danger }}>Delete Collection</span>
              </div>
            )}
          </Card>
          <GroupFooter ui={ui}>
            Deleting removes the collection and its shelf assignments. The {count} books stay in your library.
          </GroupFooter>
        </div>
      </NavSheet>
    </window.PhoneFrame>
  );
}

// ═════════════════════════════════════════════════════
// Manage list — outcome states. Reuses the committed sheet's row shape;
// `toast` shows the transient post-delete confirmation.
// ═════════════════════════════════════════════════════
function ManageListAfter({ ui, height = 880, toast }) {
  const { Card } = window;
  const cols = [
    { name: 'Currently Reading', n: 2, sys: true },
    { name: 'To Read', n: 8 },
    { name: 'Tech', n: 4 },
    { name: 'Finished', n: 11, sys: true },
  ];
  return (
    <window.PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <window.AppSheet ui={ui} title="Collections"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: CD_SANS, fontSize: 15, color: ui.sec }}>Done</button>}
        trailing={<span style={{ fontFamily: CD_SANS, fontSize: 15, fontWeight: 600, color: ui.tint }}>Edit</span>}
        height={height - 36}>
        <div style={{ padding: '14px 16px 32px' }}>
          <Card ui={ui}>
            {cols.map((c, i) => (
              <div key={c.name} style={{ display: 'flex', alignItems: 'center', minHeight: 52, padding: '0 14px', position: 'relative' }}>
                <window.Icons.Folder size={19} color={ui.tint} />
                <span style={{ flex: 1, fontFamily: CD_SANS, fontSize: 15.5, color: ui.ink, marginLeft: 11 }}>{c.name}</span>
                <span style={{ fontFamily: CD_SANS, fontSize: 13.5, color: ui.ter, fontVariantNumeric: 'tabular-nums' }}>{c.n}</span>
                {i < cols.length - 1 && <div style={{ position: 'absolute', left: 44, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
              </div>
            ))}
          </Card>
          <div style={{ height: 16 }} />
          <button style={{
            display: 'flex', alignItems: 'center', gap: 9, width: '100%', border: 'none', cursor: 'pointer',
            background: ui.card, borderRadius: 14, padding: '15px 14px', boxShadow: ui.cardShadow,
            fontFamily: CD_SANS, fontSize: 15.5, fontWeight: 500, color: ui.tint,
          }}>
            <window.Icons.Plus size={20} color={ui.tint} /> New Collection
          </button>
        </div>
      </window.AppSheet>

      {toast && (
        <div style={{
          position: 'absolute', left: 16, right: 16, bottom: 30, zIndex: 300,
          background: ui.isDark ? '#3a3530' : '#2c2822', borderRadius: 12,
          padding: '13px 16px', display: 'flex', alignItems: 'center', gap: 10,
          boxShadow: '0 8px 24px rgba(0,0,0,0.28)',
          fontFamily: CD_SANS,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">
            <circle cx="12" cy="12" r="10" fill={ui.isDark ? '#5a9a7a' : '#3a6a5a'} />
            <path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none" />
          </svg>
          <span style={{ flex: 1, fontSize: 14, color: '#f4eee0' }}>“{toast}” deleted</span>
        </div>
      )}
    </window.PhoneFrame>
  );
}

// Empty state — only reachable transiently right after the last delete.
function ManageEmpty({ ui, height = 880 }) {
  return (
    <window.PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <window.AppSheet ui={ui} title="Collections"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: CD_SANS, fontSize: 15, color: ui.sec }}>Done</button>}
        trailing={<span />}
        height={height - 36}>
        <div style={{ padding: '70px 40px 0', textAlign: 'center', display: 'flex', flexDirection: 'column', alignItems: 'center' }}>
          <div style={{
            width: 66, height: 66, borderRadius: 33, marginBottom: 20,
            background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.045)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <window.Icons.Folder size={30} color={ui.ter} />
          </div>
          <div style={{ fontFamily: CD_SERIF, fontSize: 20, fontWeight: 600, color: ui.ink, marginBottom: 8 }}>No collections yet</div>
          <div style={{ fontFamily: CD_SANS, fontSize: 13.5, lineHeight: 1.5, color: ui.sec, textWrap: 'pretty', maxWidth: 260 }}>
            Group books into shelves like Fiction or To&nbsp;Read. They appear across the top of your library.
          </div>
          <button style={{
            marginTop: 24, display: 'inline-flex', alignItems: 'center', gap: 8, border: 'none', cursor: 'pointer',
            background: ui.tint, borderRadius: 100, padding: '11px 20px',
            fontFamily: CD_SANS, fontSize: 15, fontWeight: 600, color: '#fff',
          }}>
            <window.Icons.Plus size={19} color="#fff" /> New Collection
          </button>
        </div>
      </window.AppSheet>
    </window.PhoneFrame>
  );
}

Object.assign(window, {
  CollectionDetailSheet, ManageListAfter, ManageEmpty,
  CDDeleteConfirm, CDDeleteError, NavSheet,
});
