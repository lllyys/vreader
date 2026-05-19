// Highlight-note edit surface — issue #914 / blocks feature #55 Edit slice.
//
// Reached from the Edit action on NoteCallout / NotePreviewSheet (feature #55).
// The inline `editing` mode in vreader-note-preview.jsx is a *preview* of how
// edit feels — but it is NOT the buildable editor surface. This file commits
// the real surface.
//
// Canonical form: HighlightNoteEditSheet.
//   • Keyboard-anchored half-sheet — sits ABOVE the iOS keyboard, not behind it.
//   • Header: [Cancel] · "Note" · [Save].  Save is enabled only when the draft
//     differs from the original; when the draft is empty AND original was not,
//     Save reads "Clear note" and is rendered in the destructive ink (red).
//   • Excerpt strip — italic quote w/ swatch bar, so the user always knows
//     which highlight they're noting (matters when the editor is opened from
//     the bottom-sheet preview, where the page is no longer visible).
//   • Body: a large Source Serif textarea, no border. Same font + size as
//     the read-mode note body in vreader-note-preview.jsx, so what-you-type
//     visually matches what-the-reader-will-see.
//   • Footer toolbar: char count + Delete-note destructive link (only when
//     editing an existing note, never on the empty/add path).
//
// CJK is first-class:
//   • Body font stack falls through to Source Han Serif / Songti SC / Noto
//     Serif SC for zh, Noto Serif JP / Yu Mincho for ja.
//   • CJK content gets a looser line-height (1.85 vs 1.55) because dense
//     CJK glyphs need the extra optical breathing room.
//   • lang= attribute on the textarea propagates to spell-check and IME
//     hints. The Done bar above the keyboard shows the active input source
//     so a user mid-pinyin always knows whether they're in compose mode.
//
// RTL is supported via dir="auto" — the textarea auto-flips when the first
// strong character is Arabic/Hebrew; Save / Cancel buttons do NOT mirror
// because they're chrome, not content.
//
// Save commits via HighlightPersisting.updateHighlightNote(highlightId:note:)
// — handed off to the host. Cancel with unsaved changes triggers a discard
// confirm. Cancel with a clean draft dismisses immediately.

// ─────────────────────────────────────────────────────
// Token + utils
// ─────────────────────────────────────────────────────
const NOTE_FONT_STACK_LATIN =
  '"Source Serif 4", Georgia, serif';
const NOTE_FONT_STACK_CJK =
  '"Source Han Serif SC", "Songti SC", "Noto Serif SC", "Noto Serif JP", "Yu Mincho", "Source Serif 4", Georgia, serif';

const HIGHLIGHT_SWATCH = {
  yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
};

function detectScript(s = '') {
  if (/[\u0590-\u08ff\ufb1d-\ufdff\ufe70-\ufefc]/.test(s)) return 'rtl';
  if (/[\u3000-\u303f\u3040-\u309f\u30a0-\u30ff\u4e00-\u9fff]/.test(s)) return 'cjk';
  return 'latin';
}

function noteFontFor(text) {
  return detectScript(text) === 'cjk' ? NOTE_FONT_STACK_CJK : NOTE_FONT_STACK_LATIN;
}
function noteLineHeightFor(text) {
  return detectScript(text) === 'cjk' ? 1.85 : 1.55;
}

// ─────────────────────────────────────────────────────
// HighlightNoteEditSheet — CANONICAL
// ─────────────────────────────────────────────────────
function HighlightNoteEditSheet({
  theme, highlight, mode = 'edit',
  state = 'idle',         // 'idle' | 'saving' | 'error'
  error = null,
  initial = null,         // override draft (for artboards); else falls back to highlight.note
  caretAtEnd = true,
  showKeyboard = true,
  keyboardHeight = 291,
  inputSource = 'English', // shown in keyboard accessory; flips to "拼音" / "日本語" on CJK
  imeComposing = null,     // when truthy, render an IME compose underline at end of draft
  onSave, onCancel,
}) {
  const t = theme;
  const original = highlight?.note || '';
  const [draft, setDraft] = React.useState(initial != null ? initial : original);
  const dirty = draft !== original;
  const willClear = original && draft.trim() === '';
  const isEmpty = !original;
  const swatch = HIGHLIGHT_SWATCH[highlight?.color] || HIGHLIGHT_SWATCH.yellow;
  const script = detectScript(draft || highlight?.text || '');

  const placeholder = isEmpty
    ? 'Write a note about this highlight…'
    : 'Note';

  // Sheet sits above keyboard. On no-keyboard variants the sheet extends to bottom.
  const sheetBottom = showKeyboard ? keyboardHeight : 0;

  return (
    <>
      {/* dim — tap to cancel */}
      <div onClick={() => !dirty && onCancel?.()} style={{
        position: 'absolute', inset: 0, zIndex: 200,
        background: 'rgba(0,0,0,0.32)',
        animation: 'fadeIn 0.18s ease-out',
      }}/>

      {/* sheet */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: sheetBottom, zIndex: 205,
        borderTopLeftRadius: 18, borderTopRightRadius: 18,
        background: t.isDark ? '#26231f' : '#fcf8f0',
        boxShadow: '0 -10px 32px rgba(0,0,0,0.32)',
        display: 'flex', flexDirection: 'column',
        maxHeight: `calc(100% - ${sheetBottom + 40}px)`,
        animation: 'slideUp 0.24s cubic-bezier(0.32, 0.72, 0, 1)',
        overflow: 'hidden',
      }}>
        {/* grabber */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '8px 0 4px' }}>
          <div style={{
            width: 36, height: 5, borderRadius: 3,
            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
          }}/>
        </div>

        {/* header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '6px 12px 10px',
          borderBottom: `0.5px solid ${t.rule}`,
        }}>
          <button onClick={onCancel} style={{
            background: 'none', border: 'none', padding: '6px 8px', cursor: 'pointer',
            fontFamily: 'inherit', fontSize: 15, color: t.accent, fontWeight: 400,
          }}>Cancel</button>

          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <div style={{
              width: 8, height: 8, borderRadius: 2, background: swatch,
              boxShadow: `0 0 0 2px ${swatch}33`,
            }}/>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 16, fontWeight: 600, color: t.ink,
            }}>{isEmpty ? 'New note' : 'Note'}</div>
          </div>

          <SaveButton theme={t}
            label={state === 'saving' ? 'Saving…' : willClear ? 'Clear' : 'Save'}
            disabled={!dirty || state === 'saving'}
            destructive={willClear}
            saving={state === 'saving'}
            onClick={() => onSave?.(draft)}/>
        </div>

        {/* error banner */}
        {state === 'error' && error && (
          <div style={{
            margin: '10px 14px 0',
            padding: '10px 12px', borderRadius: 10,
            background: t.isDark ? 'rgba(196,68,68,0.16)' : 'rgba(196,68,68,0.08)',
            border: `0.5px solid ${t.isDark ? 'rgba(232,140,140,0.4)' : 'rgba(196,68,68,0.3)'}`,
            display: 'flex', alignItems: 'flex-start', gap: 8,
            fontSize: 12.5, color: t.isDark ? '#e8a0a0' : '#9a3333',
            lineHeight: 1.4,
          }}>
            <div style={{
              width: 16, height: 16, borderRadius: 8, flexShrink: 0,
              background: t.isDark ? '#e8a0a0' : '#9a3333',
              color: t.isDark ? '#26231f' : '#fcf8f0',
              fontSize: 11, fontWeight: 700,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              fontFamily: 'serif',
            }}>!</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontWeight: 600, marginBottom: 1 }}>Couldn't save</div>
              <div style={{ opacity: 0.85 }}>{error}</div>
            </div>
            <button style={{
              background: 'none', border: 'none', padding: '0 0 0 4px', cursor: 'pointer',
              color: 'inherit', fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600,
              textDecoration: 'underline',
            }}>Retry</button>
          </div>
        )}

        {/* excerpt strip */}
        {highlight?.text && (
          <div style={{
            padding: '12px 18px 10px',
            display: 'flex', gap: 10, alignItems: 'flex-start',
            borderBottom: `0.5px solid ${t.rule}`,
            background: t.isDark ? 'rgba(255,255,255,0.02)' : 'rgba(0,0,0,0.015)',
          }}>
            <div style={{
              width: 3, alignSelf: 'stretch', borderRadius: 1.5,
              background: swatch, marginTop: 2,
            }}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{
                fontSize: 10, letterSpacing: 0.8, textTransform: 'uppercase',
                color: t.sub, fontWeight: 600, marginBottom: 4,
              }}>
                {highlight?.chapter || 'Chapter'} · p. {highlight?.page ?? '—'}
              </div>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 13, fontStyle: 'italic', color: t.ink, opacity: 0.78,
                lineHeight: 1.45,
                display: '-webkit-box', WebkitLineClamp: 2,
                WebkitBoxOrient: 'vertical', overflow: 'hidden',
              }}>"{highlight.text}"</div>
            </div>
          </div>
        )}

        {/* textarea */}
        <div style={{
          flex: 1, minHeight: 0, padding: '14px 18px 0',
          display: 'flex', flexDirection: 'column',
        }}>
          <NoteTextarea
            theme={t} value={draft} onChange={setDraft}
            placeholder={placeholder}
            caretAtEnd={caretAtEnd}
            imeComposing={imeComposing}
            script={script}
          />
        </div>

        {/* footer toolbar */}
        <div style={{
          padding: '8px 14px 10px',
          display: 'flex', alignItems: 'center', gap: 10,
          borderTop: `0.5px solid ${t.rule}`,
          fontSize: 12, color: t.sub,
        }}>
          <CharCount theme={t} value={draft}/>
          <div style={{ flex: 1 }}/>
          {!isEmpty && (
            <button onClick={() => { setDraft(''); }} style={{
              background: 'none', border: 'none', padding: '4px 6px', cursor: 'pointer',
              fontFamily: 'inherit', fontSize: 12.5, color: t.isDark ? '#e89090' : '#a83a3a',
              fontWeight: 500,
              display: 'inline-flex', alignItems: 'center', gap: 5,
            }}>
              <TrashGlyph size={12} color={t.isDark ? '#e89090' : '#a83a3a'}/>
              Delete note
            </button>
          )}
        </div>
      </div>

      {/* iOS-style keyboard (faux, just for fidelity) */}
      {showKeyboard && (
        <FakeIOSKeyboard theme={t} height={keyboardHeight}
          inputSource={inputSource} script={script}/>
      )}
    </>
  );
}

// ─────────────────────────────────────────────────────
// Note textarea — handles CJK font + IME compose hint
// ─────────────────────────────────────────────────────
function NoteTextarea({ theme, value, onChange, placeholder, caretAtEnd, imeComposing, script }) {
  const t = theme;
  const ref = React.useRef(null);

  React.useEffect(() => {
    if (caretAtEnd && ref.current) {
      const el = ref.current;
      el.focus();
      const len = el.value.length;
      try { el.setSelectionRange(len, len); } catch (e) {}
    }
  }, [caretAtEnd]);

  const cjk = script === 'cjk';
  const rtl = script === 'rtl';
  const fontFamily = cjk ? NOTE_FONT_STACK_CJK : NOTE_FONT_STACK_LATIN;

  return (
    <div style={{ position: 'relative', flex: 1, minHeight: 0 }}>
      <textarea
        ref={ref}
        value={value}
        onChange={(e) => onChange(e.target.value)}
        placeholder={placeholder}
        dir="auto"
        lang={cjk ? 'zh' : rtl ? 'ar' : undefined}
        spellCheck
        style={{
          width: '100%', height: '100%', minHeight: 0,
          padding: 0, border: 'none', outline: 'none',
          background: 'transparent', resize: 'none',
          fontFamily,
          fontSize: cjk ? 17 : 17,
          lineHeight: cjk ? 1.85 : 1.55,
          color: t.ink,
          caretColor: t.accent,
          textAlign: rtl ? 'right' : 'left',
        }}
      />
      {imeComposing && (
        // Visual approximation of the iOS IME compose underline.
        // In production the native textarea handles this; here we render an
        // overlay so the artboard reads correctly.
        <ImeComposeUnderline theme={t} text={value} compose={imeComposing}/>
      )}
    </div>
  );
}

// Crude visual approximation: a thin yellow underline beneath the last
// `compose.length` characters of the textarea content. Used in the CJK
// "IME compose" artboard only.
function ImeComposeUnderline({ theme, text, compose }) {
  const t = theme;
  // We just render a small label hinting the IME state, plus an underline-style
  // pill near the cursor position. (Pixel-accurate caret tracking against a
  // textarea is out of scope for an artboard.)
  return (
    <div style={{
      position: 'absolute', left: 0, bottom: 8,
      display: 'flex', alignItems: 'center', gap: 6,
      padding: '3px 8px', borderRadius: 100,
      background: t.isDark ? 'rgba(214,136,90,0.18)' : 'rgba(140,47,47,0.08)',
      fontSize: 10.5, fontWeight: 600, color: t.accent,
      letterSpacing: 0.4,
    }}>
      <div style={{
        width: 6, height: 6, borderRadius: 3, background: t.accent,
        animation: 'fadeIn 0.5s ease-in-out infinite alternate',
      }}/>
      Composing · "{compose}"
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Char count
// ─────────────────────────────────────────────────────
function CharCount({ theme, value }) {
  // CJK counts characters; Latin counts words.
  const cjk = detectScript(value) === 'cjk';
  if (!value) {
    return <span style={{ color: theme.sub, opacity: 0.6 }}>Empty</span>;
  }
  if (cjk) {
    const chars = [...value.replace(/\s+/g, '')].length;
    return <span style={{ color: theme.sub }}>{chars} 字</span>;
  }
  const words = value.trim().split(/\s+/).filter(Boolean).length;
  return (
    <span style={{ color: theme.sub }}>
      {words} {words === 1 ? 'word' : 'words'} · {value.length} ch
    </span>
  );
}

// ─────────────────────────────────────────────────────
// Save button — primary / destructive / disabled / saving
// ─────────────────────────────────────────────────────
function SaveButton({ theme, label, disabled, destructive, saving, onClick }) {
  const t = theme;
  const bg = disabled
    ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
    : destructive
      ? (t.isDark ? '#9a3333' : '#a83a3a')
      : t.accent;
  const fg = disabled
    ? (t.isDark ? 'rgba(216,210,197,0.4)' : 'rgba(29,26,20,0.35)')
    : '#fff';
  return (
    <button onClick={onClick} disabled={disabled} style={{
      padding: '7px 16px', borderRadius: 100, border: 'none',
      background: bg, color: fg,
      fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
      cursor: disabled ? 'default' : 'pointer',
      display: 'inline-flex', alignItems: 'center', gap: 6,
      minWidth: 64, justifyContent: 'center',
      transition: 'background 0.15s',
    }}>
      {saving && <Spinner size={12} color={fg}/>}
      {label}
    </button>
  );
}

function Spinner({ size = 12, color = '#fff' }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: size,
      border: `1.5px solid ${color}33`,
      borderTopColor: color,
      animation: 'spin 0.7s linear infinite',
    }}/>
  );
}

function TrashGlyph({ size = 12, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 14 14" fill="none">
      <path d="M2.5 4h9M6 2h2a1 1 0 011 1v1H5V3a1 1 0 011-1zM3.5 4l.6 8.2A1 1 0 005.1 13h3.8a1 1 0 001-0.8L10.5 4M6 7v3.5M8 7v3.5"
        stroke={color} strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

// ─────────────────────────────────────────────────────
// Discard-confirm alert — shown when Cancel pressed with unsaved changes
// ─────────────────────────────────────────────────────
function DiscardNoteAlert({ theme, addingNew, onKeep, onDiscard }) {
  const t = theme;
  return (
    <>
      <div style={{
        position: 'absolute', inset: 0, zIndex: 300,
        background: 'rgba(0,0,0,0.45)',
        animation: 'fadeIn 0.18s ease-out',
      }}/>
      <div style={{
        position: 'absolute', left: '50%', top: '46%', zIndex: 305,
        transform: 'translate(-50%, -50%)',
        width: 274, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(56,52,46,0.96)' : 'rgba(252,248,240,0.96)',
        backdropFilter: 'blur(20px)',
        boxShadow: '0 18px 50px rgba(0,0,0,0.45)',
        animation: 'popIn 0.2s cubic-bezier(0.32, 0.72, 0, 1)',
      }}>
        <div style={{ padding: '18px 18px 16px', textAlign: 'center' }}>
          <div style={{
            fontFamily: 'inherit', fontSize: 15, fontWeight: 600, color: t.ink,
            marginBottom: 6,
          }}>{addingNew ? 'Discard new note?' : 'Discard changes?'}</div>
          <div style={{
            fontSize: 12.5, color: t.sub, lineHeight: 1.4,
          }}>
            {addingNew
              ? 'Your note hasn\'t been saved. The highlight will stay.'
              : 'Your edits to this note will be lost. The highlight and the previously-saved note stay.'}
          </div>
        </div>
        <div style={{
          display: 'flex', borderTop: `0.5px solid ${t.rule}`,
        }}>
          <button onClick={onKeep} style={{
            flex: 1, padding: '12px 0', border: 'none', background: 'transparent',
            fontFamily: 'inherit', fontSize: 15, color: t.accent, fontWeight: 400,
            cursor: 'pointer',
          }}>Keep editing</button>
          <div style={{ width: 0.5, background: t.rule }}/>
          <button onClick={onDiscard} style={{
            flex: 1, padding: '12px 0', border: 'none', background: 'transparent',
            fontFamily: 'inherit', fontSize: 15,
            color: t.isDark ? '#e89090' : '#a83a3a', fontWeight: 600,
            cursor: 'pointer',
          }}>Discard</button>
        </div>
      </div>
    </>
  );
}

// ─────────────────────────────────────────────────────
// Saved toast — small confirmation after Save returns
// ─────────────────────────────────────────────────────
function NoteSavedToast({ theme, message = 'Note saved' }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', left: '50%', bottom: 60, zIndex: 320,
      transform: 'translateX(-50%)',
      padding: '8px 14px 8px 12px', borderRadius: 100,
      background: t.isDark ? 'rgba(40,40,38,0.92)' : 'rgba(28,26,22,0.9)',
      color: '#f4eee0',
      display: 'inline-flex', alignItems: 'center', gap: 8,
      fontSize: 13, fontWeight: 500,
      boxShadow: '0 8px 22px rgba(0,0,0,0.32)',
      backdropFilter: 'blur(12px)',
      animation: 'popIn 0.22s cubic-bezier(0.32, 0.72, 0, 1)',
    }}>
      <div style={{
        width: 18, height: 18, borderRadius: 9,
        background: '#5a9a6a',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="10" height="10" viewBox="0 0 14 14" fill="none">
          <path d="M3 7l3 3 5-6" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
        </svg>
      </div>
      {message}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// FullScreenNoteEditor — alternative form
// ─────────────────────────────────────────────────────
// For accessibility paths (VoiceOver) and very-long-form note authoring.
// Same content, occupies the whole screen, scrolls naturally. No keyboard
// shown in artboards since the input fills the page.
function FullScreenNoteEditor({ theme, highlight, initial = null, state = 'idle', onSave, onCancel }) {
  const t = theme;
  const original = highlight?.note || '';
  const [draft, setDraft] = React.useState(initial != null ? initial : original);
  const dirty = draft !== original;
  const willClear = original && draft.trim() === '';
  const isEmpty = !original;
  const swatch = HIGHLIGHT_SWATCH[highlight?.color] || HIGHLIGHT_SWATCH.yellow;
  const script = detectScript(draft);

  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 250,
      background: t.isDark ? '#26231f' : '#fcf8f0',
      display: 'flex', flexDirection: 'column',
      animation: 'slideUp 0.22s cubic-bezier(0.32, 0.72, 0, 1)',
    }}>
      {/* status bar mock */}
      <div style={{ height: 44 }}/>

      {/* header */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '4px 12px 10px',
        borderBottom: `0.5px solid ${t.rule}`,
      }}>
        <button onClick={onCancel} style={{
          background: 'none', border: 'none', padding: '6px 8px', cursor: 'pointer',
          fontFamily: 'inherit', fontSize: 15.5, color: t.accent,
        }}>Cancel</button>

        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 8, height: 8, borderRadius: 2, background: swatch,
            boxShadow: `0 0 0 2px ${swatch}33`,
          }}/>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 16, fontWeight: 600, color: t.ink,
          }}>{isEmpty ? 'New note' : 'Note'}</div>
        </div>

        <SaveButton theme={t}
          label={state === 'saving' ? 'Saving…' : willClear ? 'Clear' : 'Save'}
          disabled={!dirty || state === 'saving'}
          destructive={willClear}
          saving={state === 'saving'}
          onClick={() => onSave?.(draft)}/>
      </div>

      {/* excerpt */}
      {highlight?.text && (
        <div style={{
          padding: '14px 22px 12px', display: 'flex', gap: 10,
        }}>
          <div style={{
            width: 3, alignSelf: 'stretch', borderRadius: 1.5, background: swatch,
          }}/>
          <div style={{ flex: 1 }}>
            <div style={{
              fontSize: 10.5, letterSpacing: 0.8, textTransform: 'uppercase',
              color: t.sub, fontWeight: 600, marginBottom: 4,
            }}>
              {highlight.chapter || 'Chapter'} · p. {highlight.page ?? '—'}
            </div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14, fontStyle: 'italic', color: t.ink, opacity: 0.78,
              lineHeight: 1.45,
            }}>"{highlight.text}"</div>
          </div>
        </div>
      )}

      <div style={{ flex: 1, padding: '14px 22px 0', overflowY: 'auto' }} className="hide-scroll">
        <NoteTextarea
          theme={t} value={draft} onChange={setDraft}
          placeholder={isEmpty ? 'Write a note about this highlight…' : 'Note'}
          caretAtEnd
          script={script}
        />
      </div>

      {/* footer toolbar */}
      <div style={{
        padding: '10px 22px 18px',
        display: 'flex', alignItems: 'center', gap: 10,
        borderTop: `0.5px solid ${t.rule}`,
        fontSize: 12, color: t.sub,
      }}>
        <CharCount theme={t} value={draft}/>
        <div style={{ flex: 1 }}/>
        {!isEmpty && (
          <button style={{
            background: 'none', border: 'none', padding: '4px 6px', cursor: 'pointer',
            fontFamily: 'inherit', fontSize: 13, color: t.isDark ? '#e89090' : '#a83a3a',
            fontWeight: 500,
            display: 'inline-flex', alignItems: 'center', gap: 5,
          }}>
            <TrashGlyph size={12} color={t.isDark ? '#e89090' : '#a83a3a'}/>
            Delete note
          </button>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// FakeIOSKeyboard — pure visual fidelity, no real input
// ─────────────────────────────────────────────────────
function FakeIOSKeyboard({ theme, height = 291, inputSource = 'English', script = 'latin' }) {
  const t = theme;
  const dark = t.isDark;
  const bg = dark ? '#1d1d1f' : '#cfd2d8';
  const keyBg = dark ? '#5a5a5e' : '#fcfcfd';
  const fnBg = dark ? '#3e3e42' : '#abb1bc';
  const keyShadow = dark ? '0 1px 0 rgba(0,0,0,0.6)' : '0 1px 0 rgba(0,0,0,0.28)';
  const keyColor = dark ? '#fff' : '#1a1a1a';

  // For CJK we render the same QWERTY (Pinyin is QWERTY-based) but show
  // a candidate-strip on top.  Japanese we use Kana but still QWERTY-ish.
  const showCandidates = script === 'cjk';
  const rows = [
    ['q','w','e','r','t','y','u','i','o','p'],
    ['a','s','d','f','g','h','j','k','l'],
    ['z','x','c','v','b','n','m'],
  ];

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      height, background: bg, zIndex: 198,
      paddingTop: showCandidates ? 0 : 6,
      display: 'flex', flexDirection: 'column',
      borderTop: `0.5px solid ${dark ? 'rgba(0,0,0,0.5)' : 'rgba(0,0,0,0.18)'}`,
    }}>
      {/* IME candidate strip — only for CJK */}
      {showCandidates && (
        <div style={{
          display: 'flex', alignItems: 'center', gap: 4,
          padding: '6px 10px', height: 34,
          borderBottom: `0.5px solid ${dark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.08)'}`,
          background: dark ? '#222226' : '#dde1e8',
          overflow: 'hidden',
        }}>
          {(script === 'cjk' && inputSource.includes('日本') ? ['注釈','チューシャク','注釋','注解','ちゅうしゃく']
              : ['注释','注','住','驻','主释'])
            .map((c, i) => (
            <div key={i} style={{
              padding: '3px 9px', borderRadius: 6,
              background: i === 0 ? (dark ? '#2a6a4a' : '#3a8a5a') : 'transparent',
              color: i === 0 ? '#fff' : keyColor,
              fontFamily: NOTE_FONT_STACK_CJK, fontSize: 14, fontWeight: 500,
              whiteSpace: 'nowrap',
            }}>{c}</div>
          ))}
        </div>
      )}

      {/* input source pill (above first row, right) */}
      <div style={{
        display: 'flex', justifyContent: 'flex-end', padding: '4px 10px 2px',
      }}>
        <div style={{
          padding: '2px 8px', borderRadius: 100,
          background: dark ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.6)',
          fontSize: 9.5, fontWeight: 600, color: dark ? '#bbb' : '#555',
          fontFamily: script === 'cjk' ? NOTE_FONT_STACK_CJK : 'inherit',
          letterSpacing: 0.3,
        }}>{inputSource}</div>
      </div>

      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6, padding: '4px 4px 6px' }}>
        {rows.map((row, ri) => (
          <div key={ri} style={{
            display: 'flex', gap: 6, padding: ri === 1 ? '0 16px' : 0,
            justifyContent: 'center',
          }}>
            {ri === 2 && (
              <div style={{
                flex: 1.4, height: 38, borderRadius: 5,
                background: fnBg, boxShadow: keyShadow,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: keyColor, fontSize: 18,
              }}>⇧</div>
            )}
            {row.map((k, i) => (
              <div key={i} style={{
                flex: 1, height: 38, borderRadius: 5,
                background: keyBg, boxShadow: keyShadow,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: keyColor, fontSize: 16, fontWeight: 400,
              }}>{k}</div>
            ))}
            {ri === 2 && (
              <div style={{
                flex: 1.4, height: 38, borderRadius: 5,
                background: fnBg, boxShadow: keyShadow,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: keyColor, fontSize: 16,
              }}>⌫</div>
            )}
          </div>
        ))}
        {/* bottom row */}
        <div style={{ display: 'flex', gap: 6, justifyContent: 'center' }}>
          <div style={{
            width: 50, height: 38, borderRadius: 5,
            background: fnBg, boxShadow: keyShadow,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: keyColor, fontSize: 12, fontWeight: 500,
          }}>123</div>
          <div style={{
            width: 38, height: 38, borderRadius: 5,
            background: fnBg, boxShadow: keyShadow,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: keyColor, fontSize: 14,
          }}>🌐</div>
          <div style={{
            flex: 1, height: 38, borderRadius: 5,
            background: keyBg, boxShadow: keyShadow,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: keyColor, fontSize: 12, fontWeight: 400,
            fontFamily: script === 'cjk' ? NOTE_FONT_STACK_CJK : 'inherit',
          }}>{script === 'cjk' ? (inputSource.includes('日本') ? '空白' : '空格') : 'space'}</div>
          <div style={{
            width: 70, height: 38, borderRadius: 5,
            background: dark ? '#3a6a4a' : '#4a8c5e', boxShadow: keyShadow,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontSize: 12, fontWeight: 600,
          }}>return</div>
        </div>
        {/* home indicator */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '4px 0 0' }}>
          <div style={{
            width: 130, height: 4, borderRadius: 2,
            background: dark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.5)',
          }}/>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  HighlightNoteEditSheet,
  FullScreenNoteEditor,
  DiscardNoteAlert,
  NoteSavedToast,
  FakeIOSKeyboard,
  NOTE_FONT_STACK_LATIN,
  NOTE_FONT_STACK_CJK,
});
