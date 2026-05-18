// Note-preview presenter — issue #865 / feature #55.
//
// Tap an annotated-text passage → reveal the attached note inline.
// Differs from the existing HighlightActionPopover (feature #53) in three ways:
//   (1) The note is the HERO — large serif body, no action grid stealing focus.
//   (2) The surface is anchored to the tapped passage (pointer notch), not the bottom
//       of the screen — keeps the read-the-note loop visually adjacent to the text.
//   (3) The dismiss is a single tap anywhere outside, plus a small × — no destructive
//       actions live here. Edit / delete / color stay on the long-press popover, so
//       a casual "what did I write?" tap can't accidentally mutate state.
//
// Two presenter forms:
//   • Anchored NoteCallout — preferred. Floats above (or below, if no space) the
//     passage with a small pointer notch.
//   • NotePreviewSheet — fallback for very long notes (> ~6 lines) or VoiceOver path.
//     A short half-sheet anchored to the bottom; same content, more breathing room.
//
// State machine (presenter-internal):
//   reading → editing  (tap "Edit note" — handed off to highlight-action popover in
//                       the live reader; rendered inline here so a designer can see
//                       the edit-mode treatment without leaving the surface)
//   reading → empty    (note was deleted; show the empty/no-note CTA)
//   empty    → editing
//
// Empty/no-note state: the issue spec requires it. In production this happens when a
// highlight was created without a note (color-only highlight), or the note was
// cleared. The surface still acknowledges the tap — silence would feel broken — and
// offers a one-tap path to "Add a note…".

// ────────────────────────────────────────────────────
// Anchored note callout — canonical form
// ────────────────────────────────────────────────────
function NoteCallout({ theme, highlight, anchorRect, side = 'above',
                       mode = 'reading', onEdit, onDelete, onClose }) {
  const t = theme;
  const colorMap = {
    yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
  };
  const swatch = colorMap[highlight?.color] || colorMap.yellow;
  const isEmpty = mode === 'empty' || (mode === 'reading' && !highlight?.note);
  const editing = mode === 'editing';

  // Position math — for artboards, anchorRect is a synthetic rect in local coords.
  // The card has a max-width that leaves a comfortable margin on either side of the
  // reader column; the pointer notch tracks the centre of the anchor.
  const cardW = 304;
  const margin = 18;
  const colW = anchorRect?.containerW || 402;
  const anchorCx = anchorRect ? anchorRect.left + anchorRect.width / 2 : colW / 2;
  const left = Math.max(margin, Math.min(colW - cardW - margin, anchorCx - cardW / 2));
  const notchLeft = anchorCx - left - 7;

  const cardTop = side === 'above'
    ? anchorRect.top - 12 // sits above; transform pushes up by height
    : anchorRect.top + anchorRect.height + 12;
  const transform = side === 'above' ? 'translateY(-100%)' : 'translateY(0)';

  const [draft, setDraft] = React.useState(highlight?.note || '');

  return (
    <>
      {/* dim — tap to dismiss */}
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, zIndex: 80,
        background: 'rgba(0,0,0,0.18)',
        backdropFilter: 'blur(0.5px)',
        animation: 'fadeIn 0.18s ease-out',
      }}/>

      {/* the callout */}
      <div style={{
        position: 'absolute', left, top: cardTop, transform,
        width: cardW, zIndex: 85,
        animation: 'popIn 0.2s cubic-bezier(0.32, 0.72, 0, 1)',
      }}>
        <div style={{
          borderRadius: 14, overflow: 'hidden',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: '0 14px 40px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}>
          {/* meta row — color swatch, "Note", date, dismiss */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 8,
            padding: '11px 14px 8px',
          }}>
            <div style={{
              width: 8, height: 8, borderRadius: 2, background: swatch,
              boxShadow: `0 0 0 2px ${swatch}33`, flexShrink: 0,
            }}/>
            <span style={{
              fontSize: 10.5, color: t.sub, fontWeight: 600,
              letterSpacing: 0.8, textTransform: 'uppercase',
            }}>{isEmpty ? 'Highlight' : 'Note'}</span>
            {highlight?.date && (
              <span style={{ fontSize: 11, color: t.sub, opacity: 0.7 }}>
                · {highlight.date}
              </span>
            )}
            <div style={{ flex: 1 }}/>
            <button onClick={onClose} aria-label="Dismiss" style={{
              width: 22, height: 22, borderRadius: 11, padding: 0,
              border: 'none', background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
              display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer',
            }}>
              <Icons.Close size={11} color={t.sub} stroke={2.2}/>
            </button>
          </div>

          {/* tiny excerpt of the highlighted passage — anchors the user mentally */}
          {highlight?.text && (
            <div style={{
              padding: '0 14px 10px',
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 11.5, fontStyle: 'italic', color: t.sub,
              lineHeight: 1.4, borderLeft: `2px solid ${swatch}`, marginLeft: 14,
              paddingLeft: 10,
              overflow: 'hidden', display: '-webkit-box',
              WebkitLineClamp: 1, WebkitBoxOrient: 'vertical',
            }}>"{highlight.text}"</div>
          )}

          {/* note body — the hero */}
          {editing ? (
            <div style={{ padding: '4px 14px 12px' }}>
              <textarea
                autoFocus value={draft} onChange={e => setDraft(e.target.value)}
                rows={4} placeholder="Write a note…"
                style={{
                  width: '100%', border: 'none', outline: 'none',
                  background: 'transparent', resize: 'none',
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 15, lineHeight: 1.5, color: t.ink,
                }}/>
              <div style={{ display: 'flex', justifyContent: 'flex-end', gap: 8, marginTop: 6 }}>
                <button onClick={onClose} style={ghostBtn(t)}>Cancel</button>
                <button onClick={() => onEdit?.(draft)} style={primaryBtn(t)}>Save</button>
              </div>
            </div>
          ) : isEmpty ? (
            <div style={{
              padding: '4px 14px 14px',
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14, fontStyle: 'italic', color: t.sub, lineHeight: 1.5,
            }}>
              No note attached. <button onClick={onEdit} style={{
                background: 'none', border: 'none', padding: 0, cursor: 'pointer',
                color: t.accent, fontFamily: 'inherit', fontSize: 'inherit',
                fontStyle: 'italic', fontWeight: 600,
              }}>Add one…</button>
            </div>
          ) : (
            <div style={{
              padding: '4px 14px 12px',
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 15, lineHeight: 1.55, color: t.ink,
              textWrap: 'pretty',
              maxHeight: 180, overflowY: 'auto',
            }} className="hide-scroll">
              {highlight.note}
            </div>
          )}

          {/* edit handoff row — only when we have a note and aren't editing */}
          {!isEmpty && !editing && (
            <div style={{
              display: 'flex', gap: 4, padding: '4px 6px 6px',
              borderTop: `0.5px solid ${t.rule}`,
            }}>
              <CalloutAction icon={Icons.Note}      label="Edit"   onClick={onEdit}  theme={t}/>
              <CalloutAction icon={Icons.Share}     label="Share"  onClick={onClose} theme={t}/>
              <CalloutAction icon={Icons.Highlighter} label="Open in panel" onClick={onClose} theme={t}/>
            </div>
          )}
        </div>

        {/* pointer notch */}
        <div style={{
          position: 'absolute', left: Math.max(14, Math.min(cardW - 28, notchLeft)),
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

function CalloutAction({ icon: Ico, label, onClick, theme }) {
  const t = theme;
  return (
    <button onClick={onClick} style={{
      flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center',
      gap: 3, padding: '6px 4px', border: 'none', background: 'transparent',
      borderRadius: 8, cursor: 'pointer', color: t.ink,
    }}>
      <Ico size={15} color={t.ink} stroke={1.7}/>
      <span style={{ fontSize: 10, fontWeight: 500, color: t.sub }}>{label}</span>
    </button>
  );
}

function ghostBtn(t) {
  return {
    padding: '6px 12px', borderRadius: 8, border: 'none',
    background: 'transparent', color: t.sub,
    fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500, cursor: 'pointer',
  };
}
function primaryBtn(t) {
  return {
    padding: '6px 14px', borderRadius: 8, border: 'none',
    background: t.accent, color: '#fff',
    fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, cursor: 'pointer',
  };
}

// ────────────────────────────────────────────────────
// Fallback: bottom-anchored sheet for long notes
// ────────────────────────────────────────────────────
function NotePreviewSheet({ theme, highlight, onEdit, onClose }) {
  const t = theme;
  const colorMap = {
    yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
  };
  const swatch = colorMap[highlight?.color] || colorMap.yellow;
  return (
    <Sheet theme={t} onClose={onClose} height={420} title="Note">
      <div style={{ padding: '14px 22px 28px' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13, fontStyle: 'italic', color: t.sub,
          lineHeight: 1.45, paddingLeft: 12, borderLeft: `2px solid ${swatch}`,
          marginBottom: 18, overflow: 'hidden', display: '-webkit-box',
          WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
        }}>"{highlight.text}"</div>

        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 17, lineHeight: 1.55, color: t.ink, textWrap: 'pretty',
        }}>{highlight.note}</div>

        <div style={{
          marginTop: 22, paddingTop: 14, borderTop: `0.5px solid ${t.rule}`,
          display: 'flex', gap: 10, justifyContent: 'flex-end',
        }}>
          <button onClick={onClose} style={ghostBtn(t)}>Done</button>
          <button onClick={onEdit} style={primaryBtn(t)}>Edit note</button>
        </div>
      </div>
    </Sheet>
  );
}

Object.assign(window, { NoteCallout, NotePreviewSheet });
