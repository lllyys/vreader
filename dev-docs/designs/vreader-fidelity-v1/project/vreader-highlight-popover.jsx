// Unified highlight-action popover — issue #949.
//
// One surface, one gesture, every format. Replaces:
//   • vreader-note-preview.jsx NoteCallout / NotePreviewSheet (read-only, EPUB/AZW3)
//   • vreader-reader.jsx HighlightActionPopover (color + edit + actions, TXT/MD/PDF)
//
// Why merge: prior to #949 we shipped two highlight-tap models. EPUB tapped to
// a read-only note preview (Share / Open-in-panel, no Delete). TXT/MD/PDF
// tapped to a bare "Delete Highlight" UIMenu. Same gesture, two destinations,
// no one-step delete on EPUB. This file commits the unified surface.
//
// Canonical form: HighlightActionCard, anchored to the tapped passage with a
// pointer notch (inherits the #55 anchored-to-content gesture). Bottom sheet
// variant for long notes (clamp + "Expand") and VoiceOver.
//
// Composition, top to bottom:
//   1. Meta row     — color swatch · "HIGHLIGHT" · chapter/date · close ×
//   2. Excerpt      — italic serif with colored left bar (clamp 2 lines)
//   3. Note region  — three modes:
//        reading    — serif body, tap to edit (or "Read more" on long notes)
//        empty      — italic "Add a note…" CTA
//        editing    — inline textarea + Save/Cancel (Save commits and returns
//                     to reading; full editor opens via the long-form path)
//   4. Color row    — 4 highlight colors; current has accent ring
//   5. Action row   — Copy · Share · Delete (destructive ink on Delete only)
//
// Edit semantics: this card embeds the *short-form* note editor — same field
// for tiny edits, no keyboard-anchored sheet. When the note is long or the
// platform routes to VoiceOver, the Edit affordance promotes to the
// committed full editor (vreader-note-editor.jsx HighlightNoteEditSheet)
// rather than expanding inline.
//
// The Delete action always destroys the highlight (excerpt + note + color);
// to keep the highlight but remove only the note, users hit Edit, clear the
// text, and Save (which reads "Clear note" in destructive ink). Spec'd in
// vreader-note-editor.jsx.

// ─────────────────────────────────────────────────────
// Tokens shared with the editor surface
// ─────────────────────────────────────────────────────
const HP_SWATCH = {
  yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
};
const HP_COLORS = ['yellow', 'pink', 'green', 'blue'];

const HP_FONT_LATIN = '"Source Serif 4", Georgia, serif';
const HP_FONT_CJK   = '"Source Han Serif SC", "Songti SC", "Noto Serif SC", "Noto Serif JP", "Yu Mincho", "Source Serif 4", Georgia, serif';

function hpScript(s = '') {
  if (/[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufefc]/.test(s)) return 'rtl';
  if (/[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]/.test(s)) return 'cjk';
  return 'latin';
}
function hpFontFor(s) { return hpScript(s) === 'cjk' ? HP_FONT_CJK : HP_FONT_LATIN; }
function hpLhFor(s) { return hpScript(s) === 'cjk' ? 1.7 : 1.5; }

// ─────────────────────────────────────────────────────
// HighlightActionCard — anchored, canonical
// ─────────────────────────────────────────────────────
// Props
//   theme        — ReaderThemeV2 token bag
//   highlight    — { id, color, chapter, page, date, text, note }
//   anchorRect   — { left, top, width, height, containerW } in local coords
//   side         — 'above' | 'below'  (preferred; auto-flipped by caller)
//   mode         — 'reading' | 'editing' | 'confirm-delete'
//   pressedColor — color key currently being applied (transient press feedback)
//   showDim      — render the backdrop scrim (true for artboards, host can suppress)
//   onChangeColor / onEdit / onSaveNote / onCancelEdit / onCopy / onShare
//   onDelete / onConfirmDelete / onClose
function HighlightActionCard({
  theme, highlight, anchorRect, side = 'above',
  mode = 'reading', pressedColor = null,
  showDim = true,
  draftOverride = null,
  onChangeColor, onEdit, onSaveNote, onCancelEdit,
  onCopy, onShare, onDelete, onConfirmDelete, onClose,
}) {
  const t = theme;
  const swatch = HP_SWATCH[highlight?.color] || HP_SWATCH.yellow;
  const editing = mode === 'editing';
  const confirming = mode === 'confirm-delete';
  const hasNote = !!(highlight && highlight.note);

  // Position math — card is fixed-width; pointer notch tracks anchor centre.
  const cardW = 320;
  const margin = 14;
  const colW = anchorRect?.containerW || 402;
  const anchorCx = anchorRect ? anchorRect.left + anchorRect.width / 2 : colW / 2;
  const left = Math.max(margin, Math.min(colW - cardW - margin, anchorCx - cardW / 2));
  const notchLeft = Math.max(18, Math.min(cardW - 32, anchorCx - left - 7));

  const cardTop = side === 'above'
    ? (anchorRect?.top ?? 200) - 14
    : (anchorRect?.top ?? 200) + (anchorRect?.height ?? 22) + 14;
  const transform = side === 'above' ? 'translateY(-100%)' : 'translateY(0)';

  return (
    <>
      {showDim && (
        <div onClick={onClose} style={{
          position: 'absolute', inset: 0, zIndex: 80,
          background: 'rgba(0,0,0,0.18)',
          backdropFilter: 'blur(0.5px)',
          animation: 'fadeIn 0.18s ease-out',
        }}/>
      )}

      <div style={{
        position: 'absolute', left, top: cardTop, transform,
        width: cardW, zIndex: 85,
        animation: 'popIn 0.2s cubic-bezier(0.32, 0.72, 0, 1)',
      }}>
        <div style={{
          borderRadius: 16, overflow: 'hidden',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: '0 14px 40px rgba(0,0,0,0.28), 0 0 0 0.5px '
            + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}>
          <HPMetaRow theme={t} highlight={highlight} swatch={swatch} onClose={onClose}/>
          <HPExcerpt theme={t} highlight={highlight} swatch={swatch}/>

          {confirming ? (
            <HPDeleteConfirm theme={t}
              onCancel={() => onCancelEdit?.()}
              onConfirm={onConfirmDelete}/>
          ) : (
            <>
              <HPNoteRegion theme={t} highlight={highlight}
                editing={editing}
                draftOverride={draftOverride}
                onEdit={onEdit} onSave={onSaveNote} onCancelEdit={onCancelEdit}/>
              {!editing && (
                <HPColorRow theme={t} highlight={highlight}
                  pressed={pressedColor} onChangeColor={onChangeColor}/>
              )}
              {!editing && (
                <HPActionRow theme={t}
                  hasNote={hasNote}
                  onCopy={onCopy} onShare={onShare} onDelete={onDelete}/>
              )}
            </>
          )}
        </div>

        {/* pointer notch */}
        <div style={{
          position: 'absolute', left: notchLeft,
          [side === 'above' ? 'bottom' : 'top']: -6,
          width: 14, height: 14, transform: 'rotate(45deg)',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: side === 'above'
            ? `1px 1px 0 0 ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`
            : `-1px -1px 0 0 ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
        }}/>
      </div>
    </>
  );
}

// ─────────────────────────────────────────────────────
// Meta row — swatch · "HIGHLIGHT" · chapter · date · close
// ─────────────────────────────────────────────────────
function HPMetaRow({ theme, highlight, swatch, onClose }) {
  const t = theme;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '11px 12px 8px 14px',
    }}>
      <div style={{
        width: 9, height: 9, borderRadius: 2, background: swatch,
        boxShadow: `0 0 0 2px ${swatch}33`, flexShrink: 0,
      }}/>
      <span style={{
        fontSize: 10.5, color: t.sub, fontWeight: 600,
        letterSpacing: 0.8, textTransform: 'uppercase',
      }}>Highlight</span>
      {(highlight?.chapter || highlight?.date) && (
        <span style={{
          fontSize: 11, color: t.sub, opacity: 0.7,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>
          · {[highlight.chapter, highlight.date].filter(Boolean).join(' · ')}
        </span>
      )}
      <div style={{ flex: 1 }}/>
      <button onClick={onClose} aria-label="Dismiss" style={{
        width: 24, height: 24, borderRadius: 12, padding: 0,
        border: 'none', cursor: 'pointer',
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="10" height="10" viewBox="0 0 14 14" fill="none">
          <path d="M3 3l8 8M11 3l-8 8" stroke={t.sub} strokeWidth="2" strokeLinecap="round"/>
        </svg>
      </button>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Excerpt strip — italic serif w/ colored left bar
// ─────────────────────────────────────────────────────
function HPExcerpt({ theme, highlight, swatch }) {
  const t = theme;
  if (!highlight?.text) return null;
  const script = hpScript(highlight.text);
  return (
    <div style={{
      padding: '0 14px 10px 14px',
      display: 'flex', gap: 10, alignItems: 'stretch',
    }}>
      <div style={{
        width: 3, borderRadius: 1.5, background: swatch, flexShrink: 0,
      }}/>
      <div style={{
        flex: 1, minWidth: 0,
        fontFamily: script === 'cjk' ? HP_FONT_CJK : HP_FONT_LATIN,
        fontSize: 12.5, fontStyle: 'italic', color: t.ink, opacity: 0.85,
        lineHeight: script === 'cjk' ? 1.6 : 1.45,
        display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
        overflow: 'hidden', textAlign: script === 'rtl' ? 'right' : 'left',
      }}>"{highlight.text}"</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Note region — reading / empty / editing
// ─────────────────────────────────────────────────────
function HPNoteRegion({ theme, highlight, editing, draftOverride, onEdit, onSave, onCancelEdit }) {
  const t = theme;
  const note = highlight?.note || '';
  const [draft, setDraft] = React.useState(draftOverride != null ? draftOverride : note);
  const script = hpScript(draft || note);

  if (editing) {
    return (
      <div style={{
        margin: '0 12px 10px',
        padding: '10px 12px 8px',
        borderRadius: 10,
        background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.035)',
        border: `1px solid ${t.accent}44`,
      }}>
        <textarea
          value={draft} onChange={(e) => setDraft(e.target.value)}
          placeholder="Write a note…"
          autoFocus dir="auto" rows={4}
          style={{
            width: '100%', border: 'none', outline: 'none',
            background: 'transparent', resize: 'none',
            fontFamily: script === 'cjk' ? HP_FONT_CJK : HP_FONT_LATIN,
            fontSize: 14, lineHeight: script === 'cjk' ? 1.75 : 1.5,
            color: t.ink, caretColor: t.accent,
          }}/>
        <div style={{
          display: 'flex', justifyContent: 'space-between', alignItems: 'center',
          marginTop: 6, paddingTop: 6,
          borderTop: `0.5px solid ${t.rule}`,
        }}>
          <span style={{ fontSize: 10.5, color: t.sub, fontFamily: 'inherit' }}>
            Larger editor available from <span style={{
              fontStyle: 'italic', color: t.sub,
            }}>Expand</span>
          </span>
          <div style={{ display: 'flex', gap: 4 }}>
            <button onClick={onCancelEdit} style={hpGhostBtn(t)}>Cancel</button>
            <button onClick={() => onSave?.(draft)} style={hpPrimaryBtn(t)}>Save</button>
          </div>
        </div>
      </div>
    );
  }

  if (!note) {
    return (
      <button onClick={onEdit} style={{
        display: 'block', width: 'calc(100% - 24px)', margin: '0 12px 10px',
        padding: '10px 12px', textAlign: 'left', cursor: 'pointer',
        borderRadius: 10, border: `1px dashed ${t.rule}`, background: 'transparent',
        fontFamily: HP_FONT_LATIN, fontSize: 13, fontStyle: 'italic',
        color: t.sub, lineHeight: 1.4,
      }}>
        <span style={{ marginRight: 6 }}>＋</span>
        Add a note…
      </button>
    );
  }

  // reading-mode note — full body, clamped to ~6 lines with read-more on overflow
  const long = note.length > 220;
  return (
    <button onClick={onEdit} style={{
      display: 'block', width: 'calc(100% - 24px)', margin: '0 12px 10px',
      padding: '8px 12px 10px', textAlign: script === 'rtl' ? 'right' : 'left',
      cursor: 'pointer', borderRadius: 10, border: 'none',
      background: t.isDark ? 'rgba(255,255,255,0.035)' : 'rgba(0,0,0,0.025)',
    }}>
      <div style={{
        fontFamily: script === 'cjk' ? HP_FONT_CJK : HP_FONT_LATIN,
        fontSize: 14, lineHeight: hpLhFor(note), color: t.ink,
        textWrap: 'pretty',
        display: '-webkit-box', WebkitLineClamp: 6, WebkitBoxOrient: 'vertical',
        overflow: 'hidden',
        direction: script === 'rtl' ? 'rtl' : 'ltr',
      }}>{note}</div>
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'center',
        marginTop: 6,
      }}>
        <span style={{
          fontSize: 10.5, color: t.sub, fontWeight: 600, letterSpacing: 0.6,
          textTransform: 'uppercase', fontFamily: 'inherit',
        }}>{long ? 'Read more · Edit' : 'Tap to edit'}</span>
        <HPEditGlyph color={t.sub}/>
      </div>
    </button>
  );
}

function HPEditGlyph({ color }) {
  return (
    <svg width="11" height="11" viewBox="0 0 14 14" fill="none">
      <path d="M9 2l3 3-7 7H2v-3z" stroke={color} strokeWidth="1.3"
        strokeLinejoin="round" strokeLinecap="round"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────
// Color row — palette + selected indicator + press state
// ─────────────────────────────────────────────────────
function HPColorRow({ theme, highlight, pressed, onChangeColor }) {
  const t = theme;
  const current = highlight?.color || 'yellow';
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '4px 14px 10px',
    }}>
      {HP_COLORS.map((c) => {
        const isCurrent = c === current;
        const isPressed = c === pressed;
        return (
          <button key={c} onClick={() => onChangeColor?.(c)} aria-label={`${c} highlight`}
            style={{
              width: 30, height: 30, borderRadius: 15, padding: 0,
              background: HP_SWATCH[c],
              border: isCurrent
                ? `2.5px solid ${t.accent}`
                : '2px solid rgba(255,255,255,0.45)',
              boxShadow: isPressed
                ? `0 0 0 4px ${HP_SWATCH[c]}55, 0 2px 4px rgba(0,0,0,0.18)`
                : '0 1px 3px rgba(0,0,0,0.18)',
              cursor: 'pointer',
              transform: isPressed ? 'scale(0.94)' : isCurrent ? 'scale(1.06)' : 'none',
              transition: 'transform 0.12s, box-shadow 0.12s',
              position: 'relative',
            }}>
            {isCurrent && (
              <svg width="14" height="14" viewBox="0 0 14 14" fill="none"
                   style={{ position: 'absolute', left: 6, top: 6 }}>
                <path d="M3 7l3 3 5-6" stroke="rgba(0,0,0,0.55)"
                  strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
              </svg>
            )}
          </button>
        );
      })}
      <div style={{ flex: 1 }}/>
      <span style={{
        fontSize: 10.5, color: t.sub, fontWeight: 600, letterSpacing: 0.5,
        textTransform: 'uppercase',
      }}>Color</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Action row — Copy · Share · Delete
// ─────────────────────────────────────────────────────
function HPActionRow({ theme, hasNote, onCopy, onShare, onDelete }) {
  const t = theme;
  const danger = t.isDark ? '#e89090' : '#a83a3a';
  const items = [
    { key: 'copy',  label: 'Copy',   on: onCopy,   glyph: HPCopyGlyph },
    { key: 'share', label: 'Share',  on: onShare,  glyph: HPShareGlyph },
    { key: 'del',   label: 'Delete', on: onDelete, glyph: HPTrashGlyph, danger: true },
  ];
  return (
    <div style={{
      display: 'flex', gap: 4, padding: '6px 6px 8px',
      borderTop: `0.5px solid ${t.rule}`,
    }}>
      {items.map((b) => (
        <button key={b.key} onClick={b.on} style={{
          flex: 1, display: 'flex', flexDirection: 'column',
          alignItems: 'center', gap: 4, padding: '8px 4px',
          borderRadius: 10, border: 'none', background: 'transparent',
          cursor: 'pointer', color: b.danger ? danger : t.ink,
        }}>
          <b.glyph size={16} color={b.danger ? danger : t.ink}/>
          <span style={{
            fontSize: 10.5, fontWeight: 600, letterSpacing: 0.2,
          }}>{b.label}</span>
        </button>
      ))}
    </div>
  );
}

function HPCopyGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none">
      <rect x="6" y="6" width="11" height="12" rx="2"
        stroke={color} strokeWidth="1.4"/>
      <path d="M3 14V4a1 1 0 011-1h9" stroke={color} strokeWidth="1.4"
        strokeLinecap="round"/>
    </svg>
  );
}
function HPShareGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
      stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M10 2v11M6 6l4-4 4 4M4 12v5a2 2 0 002 2h8a2 2 0 002-2v-5"/>
    </svg>
  );
}
function HPTrashGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 20 20" fill="none"
      stroke={color} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round">
      <path d="M3 6h14M8 3h4a1 1 0 011 1v2H7V4a1 1 0 011-1zM5 6l1 11a1.5 1.5 0 001.5 1.5h5A1.5 1.5 0 0014 17l1-11M9 9v6M11 9v6"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────
// Delete confirmation — inline replacement for action row
// ─────────────────────────────────────────────────────
function HPDeleteConfirm({ theme, onCancel, onConfirm }) {
  const t = theme;
  const danger = t.isDark ? '#e89090' : '#a83a3a';
  return (
    <div style={{
      borderTop: `0.5px solid ${t.rule}`,
      padding: '12px 14px 14px',
    }}>
      <div style={{
        fontFamily: 'inherit', fontSize: 13, color: t.ink,
        fontWeight: 500, marginBottom: 4,
      }}>Delete this highlight?</div>
      <div style={{
        fontSize: 11.5, color: t.sub, lineHeight: 1.4, marginBottom: 10,
      }}>The color, the note, and the underline come off the page. Can't be undone.</div>
      <div style={{ display: 'flex', gap: 8 }}>
        <button onClick={onCancel} style={{
          flex: 1, padding: '8px 0', borderRadius: 8,
          border: `0.5px solid ${t.rule}`, background: 'transparent',
          fontFamily: 'inherit', fontSize: 13, fontWeight: 500,
          color: t.ink, cursor: 'pointer',
        }}>Cancel</button>
        <button onClick={onConfirm} style={{
          flex: 1, padding: '8px 0', borderRadius: 8, border: 'none',
          background: danger, color: '#fff',
          fontFamily: 'inherit', fontSize: 13, fontWeight: 600,
          cursor: 'pointer',
        }}>Delete</button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// HighlightActionSheet — bottom-anchored fallback
// ─────────────────────────────────────────────────────
// When: VoiceOver path, or anchor would overflow viewport (very short page,
// very long note), or compact screen sizes (iPhone SE). Identical content;
// just no pointer notch.
function HighlightActionSheet({
  theme, highlight, mode = 'reading', pressedColor = null,
  showDim = true,
  draftOverride = null,
  onChangeColor, onEdit, onSaveNote, onCancelEdit,
  onCopy, onShare, onDelete, onConfirmDelete, onClose,
}) {
  const t = theme;
  const swatch = HP_SWATCH[highlight?.color] || HP_SWATCH.yellow;
  const editing = mode === 'editing';
  const confirming = mode === 'confirm-delete';
  const hasNote = !!(highlight && highlight.note);

  return (
    <>
      {showDim && (
        <div onClick={onClose} style={{
          position: 'absolute', inset: 0, zIndex: 80,
          background: 'rgba(0,0,0,0.28)',
          animation: 'fadeIn 0.18s ease-out',
        }}/>
      )}
      <div style={{
        position: 'absolute', left: 12, right: 12, bottom: 18, zIndex: 85,
        borderRadius: 18, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 18px 50px rgba(0,0,0,0.36), 0 0 0 0.5px '
          + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        animation: 'slideUp 0.22s cubic-bezier(0.32, 0.72, 0, 1)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', padding: '6px 0 0' }}>
          <div style={{
            width: 36, height: 5, borderRadius: 3,
            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
          }}/>
        </div>

        <HPMetaRow theme={t} highlight={highlight} swatch={swatch} onClose={onClose}/>
        <HPExcerpt theme={t} highlight={highlight} swatch={swatch}/>

        {confirming ? (
          <HPDeleteConfirm theme={t}
            onCancel={() => onCancelEdit?.()}
            onConfirm={onConfirmDelete}/>
        ) : (
          <>
            <HPNoteRegion theme={t} highlight={highlight} editing={editing}
              draftOverride={draftOverride}
              onEdit={onEdit} onSave={onSaveNote} onCancelEdit={onCancelEdit}/>
            {!editing && (
              <HPColorRow theme={t} highlight={highlight}
                pressed={pressedColor} onChangeColor={onChangeColor}/>
            )}
            {!editing && (
              <HPActionRow theme={t}
                hasNote={hasNote}
                onCopy={onCopy} onShare={onShare} onDelete={onDelete}/>
            )}
          </>
        )}
      </div>
    </>
  );
}

// ─────────────────────────────────────────────────────
// Small button styles
// ─────────────────────────────────────────────────────
function hpGhostBtn(t) {
  return {
    padding: '6px 12px', borderRadius: 8, border: 'none',
    background: 'transparent', color: t.sub,
    fontFamily: 'inherit', fontSize: 13, fontWeight: 500, cursor: 'pointer',
  };
}
function hpPrimaryBtn(t) {
  return {
    padding: '6px 14px', borderRadius: 8, border: 'none',
    background: t.accent, color: '#fff',
    fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer',
  };
}

Object.assign(window, {
  HighlightActionCard,
  HighlightActionSheet,
  HP_SWATCH,
  HP_COLORS,
});
