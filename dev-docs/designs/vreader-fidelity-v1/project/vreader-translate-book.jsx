// Translate entire book — issue #863 / feature #56 (3).
//
// Four surfaces:
//
//   1. ENTRY POINT — where the user starts a whole-book translation.
//      Canonical: a row in Book Details > Actions ("Translate entire book…").
//      Secondary: a long-press action on the library card (matches the iOS-standard
//      contextMenu on a list item; surfaces it without making the library card busy).
//      We deliberately do NOT add this to the More popover — it's a heavy, slow,
//      expensive action that shouldn't sit next to "Read aloud" and "Bookmarks".
//
//   2. CONFIRMATION ALERT — iOS-style alert with chapter count, token estimate,
//      provider cost, and a one-tap path to change provider before committing.
//      Destructive-feel actions get a confirmation; an action that costs the user
//      real money definitely does.
//
//   3. IN-PROGRESS STATUS — three places, in increasing detail:
//        a. A small badge clipped to the library cover (chip: "12 / 61").
//        b. A persistent banner across the top of any reader open on the book.
//        c. The translation-status sheet — opens when the user taps either of the
//           above. Shows a per-chapter list (queued / translating / done / failed),
//           current throughput, ETA, and the cancel affordance.
//
//   4. CANCEL — primary CTA at the bottom of the status sheet, with a confirmation
//      alert that explicitly tells the user nothing is lost ("12 of 61 chapters are
//      already translated and will stay cached"). Cancel is destructive in name but
//      not in effect — the alert disabuses the user of the assumption that they're
//      throwing work away.

// ────────────────────────────────────────────────────
// Action row — drop-in row for the Book Details Actions list
// ────────────────────────────────────────────────────
function TranslateBookActionRow({ theme, status = 'idle', progress = null,
                                  targetLang = 'Chinese', onOpen }) {
  const t = theme;
  const sub = status === 'translated'
    ? `Translated to ${targetLang} · 61 of 61 chapters`
    : status === 'running'
    ? `Translating to ${targetLang} · ${progress?.done ?? 12} of ${progress?.total ?? 61} chapters`
    : status === 'paused'
    ? `Paused at ${progress?.done ?? 12} of ${progress?.total ?? 61}`
    : `Pre-translate every chapter to ${targetLang}`;

  const ico = status === 'running'
    ? <Spinner color={t.accent} size={14}/>
    : status === 'translated'
    ? <Icons.Check size={16} color="#3a6a5a" stroke={2.2}/>
    : <Icons.Translate size={16} color={t.accent} stroke={1.8}/>;

  return (
    <button onClick={onOpen} style={{
      display: 'flex', alignItems: 'center', gap: 12, width: '100%',
      padding: '12px 14px', border: 'none', background: 'transparent',
      cursor: 'pointer', textAlign: 'left',
      borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8,
        background: status === 'translated' ? 'rgba(58,106,90,0.12)' : `${t.accent}14`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>{ico}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 14.5, color: t.ink, fontWeight: 500, lineHeight: 1.2,
        }}>Translate entire book…</div>
        <div style={{
          fontSize: 11.5, color: t.sub, marginTop: 2, lineHeight: 1.2,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{sub}</div>
      </div>
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </button>
  );
}

// ────────────────────────────────────────────────────
// Confirmation alert — iOS-style
// ────────────────────────────────────────────────────
function TranslateBookConfirmAlert({ theme, book, est = {}, provider = 'Claude · Sonnet 4.5',
                                     onChangeProvider, onCancel, onConfirm }) {
  const t = theme;
  const e = {
    chapters: 61, tokens: 142_000, cost: '$0.43', time: '~8 min', lang: 'Chinese',
    ...est,
  };
  return (
    <div onClick={onCancel} style={{
      position: 'absolute', inset: 0, zIndex: 200,
      background: 'rgba(0,0,0,0.45)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 18,
    }}>
      <div onClick={ev => ev.stopPropagation()} style={{
        width: 290, borderRadius: 18, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 16px 50px rgba(0,0,0,0.4)',
      }}>
        <div style={{ padding: '20px 22px 12px', textAlign: 'center' }}>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 17, fontWeight: 700, color: t.ink,
            lineHeight: 1.25, marginBottom: 8,
          }}>Translate the whole book?</div>
          <div style={{
            fontSize: 12.5, color: t.sub, lineHeight: 1.5, textWrap: 'pretty',
          }}>
            <span style={{
              fontFamily: '"Source Serif 4", Georgia, serif', fontStyle: 'italic', color: t.ink,
            }}>{book?.title || 'Pride and Prejudice'}</span>
            {' '}has{' '}<b style={{ color: t.ink }}>{e.chapters} chapters</b>. We estimate{' '}
            <b style={{ color: t.ink }}>{e.tokens.toLocaleString()} tokens</b>, around{' '}
            <b style={{ color: t.ink }}>{e.cost}</b> on your current AI plan, taking{' '}
            <b style={{ color: t.ink }}>{e.time}</b>.
          </div>
        </div>

        <button onClick={onChangeProvider} style={{
          display: 'flex', alignItems: 'center', gap: 10, width: '100%',
          padding: '11px 22px', border: 'none', background: 'transparent',
          borderTop: `0.5px solid ${t.rule}`, cursor: 'pointer', textAlign: 'left',
        }}>
          <ProviderGlyph id="claude" theme={t} active={true}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12, color: t.sub, fontWeight: 500 }}>Provider</div>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600, marginTop: 1 }}>{provider}</div>
          </div>
          <span style={{ fontSize: 12, color: t.accent, fontWeight: 600 }}>Change…</span>
        </button>

        <div style={{
          display: 'flex', borderTop: `0.5px solid ${t.rule}`,
        }}>
          <button onClick={onCancel} style={alertBtn(t)}>Not now</button>
          <button onClick={onConfirm} style={{ ...alertBtn(t),
            borderLeft: `0.5px solid ${t.rule}`,
            color: t.accent, fontWeight: 700,
          }}>Translate</button>
        </div>
      </div>
    </div>
  );
}

function alertBtn(t) {
  return {
    flex: 1, padding: '13px 0', border: 'none', background: 'transparent',
    fontFamily: 'inherit', fontSize: 15, color: t.accent, cursor: 'pointer',
  };
}

// ────────────────────────────────────────────────────
// Library-card status badge — clipped to bottom of the cover
// ────────────────────────────────────────────────────
function LibraryCardTranslateBadge({ progress, theme, status = 'running' }) {
  const t = theme;
  if (status === 'translated') {
    return (
      <div style={{
        position: 'absolute', top: 6, right: 6, zIndex: 5,
        width: 22, height: 22, borderRadius: 11,
        background: 'rgba(58,106,90,0.95)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        boxShadow: '0 2px 6px rgba(0,0,0,0.35)',
      }}>
        <Icons.Translate size={11} color="#fff" stroke={2.2}/>
      </div>
    );
  }
  if (status !== 'running') return null;
  const p = (progress?.done ?? 12) / (progress?.total ?? 61);
  return (
    <div style={{
      position: 'absolute', bottom: 6, left: 6, right: 6, zIndex: 5,
      padding: '5px 8px', borderRadius: 8,
      background: 'rgba(20,16,12,0.82)',
      backdropFilter: 'blur(8px)',
      display: 'flex', alignItems: 'center', gap: 6,
    }}>
      <Spinner color="#fff" size={10}/>
      <span style={{
        flex: 1, fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
        fontSize: 10, color: '#fff', fontWeight: 600, letterSpacing: 0.3,
      }}>{progress?.done ?? 12} / {progress?.total ?? 61}</span>
      <div style={{
        width: 50, height: 3, borderRadius: 2,
        background: 'rgba(255,255,255,0.18)', position: 'relative', overflow: 'hidden',
      }}>
        <div style={{
          position: 'absolute', left: 0, top: 0, bottom: 0,
          width: `${p * 100}%`, background: '#fff', borderRadius: 2,
        }}/>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Reader top-of-page banner — when the open book is being translated
// ────────────────────────────────────────────────────
function ReaderTranslateBanner({ theme, progress = { done: 12, total: 61 }, onOpen, onCancel }) {
  const t = theme;
  const p = progress.done / progress.total;
  return (
    <div style={{
      position: 'absolute', top: 88, left: 14, right: 14, zIndex: 25,
      padding: '8px 12px', borderRadius: 12,
      background: t.isDark ? 'rgba(40,38,34,0.94)' : 'rgba(252,248,240,0.96)',
      backdropFilter: 'blur(10px)',
      boxShadow: '0 4px 16px rgba(0,0,0,0.18), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)'),
      display: 'flex', alignItems: 'center', gap: 10,
    }}>
      <Spinner color={t.accent} size={13}/>
      <button onClick={onOpen} style={{
        flex: 1, background: 'none', border: 'none', padding: 0, cursor: 'pointer',
        textAlign: 'left', fontFamily: 'inherit',
      }}>
        <div style={{ fontSize: 12, color: t.ink, fontWeight: 600 }}>
          Translating to Chinese · {progress.done} / {progress.total}
        </div>
        <div style={{
          marginTop: 4, height: 3, borderRadius: 2,
          background: t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)',
          position: 'relative', overflow: 'hidden',
        }}>
          <div style={{
            position: 'absolute', left: 0, top: 0, bottom: 0,
            width: `${p * 100}%`, background: t.accent, borderRadius: 2,
          }}/>
        </div>
      </button>
      <button onClick={onCancel} aria-label="Cancel translation" style={{
        width: 24, height: 24, borderRadius: 12, padding: 0,
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
        border: 'none', cursor: 'pointer',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Close size={11} color={t.sub} stroke={2.4}/>
      </button>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Status sheet — per-chapter list + cancel
// ────────────────────────────────────────────────────
const SAMPLE_STATUS = [
  { ch: 1,  title: 'Bingley arrives at Netherfield',          state: 'done' },
  { ch: 2,  title: 'Mr. Bennet pays his call',                state: 'done' },
  { ch: 3,  title: 'The Meryton assembly',                    state: 'done' },
  { ch: 4,  title: 'Jane and Elizabeth in private',           state: 'done' },
  { ch: 5,  title: 'Sir William and Charlotte Lucas',         state: 'done' },
  { ch: 6,  title: 'Bingleys and Bennets visit Lucas Lodge',  state: 'done' },
  { ch: 7,  title: 'Officers in Meryton; Jane falls ill',     state: 'done' },
  { ch: 8,  title: 'Elizabeth at Netherfield',                state: 'done' },
  { ch: 9,  title: 'Mrs. Bennet visits Jane',                 state: 'done' },
  { ch: 10, title: 'Music in the drawing-room',               state: 'done' },
  { ch: 11, title: 'Bingley and Darcy on letter-writing',     state: 'done' },
  { ch: 12, title: 'Jane and Elizabeth return home',          state: 'done' },
  { ch: 13, title: 'Mr. Collins arrives',                     state: 'running', progress: 0.42 },
  { ch: 14, title: 'Mr. Collins reads aloud',                 state: 'queued' },
  { ch: 15, title: 'Walk to Meryton; Wickham introduced',     state: 'queued' },
  { ch: 16, title: 'Tea with the Phillipses',                 state: 'queued' },
];

function TranslateStatusSheet({ theme, book, items = SAMPLE_STATUS, throughput = '~3.2 ch/min',
                                eta = '6m 12s remaining', onCancelAll, onClose }) {
  const t = theme;
  const total = items.length;
  const done = items.filter(i => i.state === 'done').length;
  const running = items.find(i => i.state === 'running');

  return (
    <Sheet theme={t} onClose={onClose} height={720} title="Translating to Chinese">
      <div style={{ padding: '12px 18px 0' }}>
        {/* hero progress */}
        <div style={{
          padding: '14px 16px', borderRadius: 14,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
        }}>
          <div style={{
            display: 'flex', alignItems: 'baseline', gap: 4,
          }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 36, fontWeight: 600, color: t.ink,
              lineHeight: 1, letterSpacing: -0.8,
            }}>{done}</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 18, color: t.sub, fontWeight: 500,
            }}> / {total}</div>
            <div style={{ flex: 1 }}/>
            <div style={{
              fontSize: 11, color: t.sub, fontWeight: 500, letterSpacing: 0.3,
            }}>{eta}</div>
          </div>
          <div style={{
            marginTop: 10, height: 5, borderRadius: 3,
            background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
            position: 'relative', overflow: 'hidden',
          }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0,
              width: `${(done / total) * 100}%`, background: t.accent,
              borderRadius: 3, transition: 'width 0.4s ease',
            }}/>
          </div>
          <div style={{
            display: 'flex', justifyContent: 'space-between', marginTop: 8,
            fontSize: 11, color: t.sub,
          }}>
            <span>{throughput}</span>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 5,
            }}>
              <ProviderGlyph id="claude" theme={t} active/>
              Claude · Sonnet 4.5
            </span>
          </div>
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'auto', padding: '18px 8px 8px' }} className="hide-scroll">
        <SectionLabel theme={t} style={{ paddingLeft: 10 }}>Chapters</SectionLabel>
        <div style={{ marginTop: 8 }}>
          {items.map((it, i) => (
            <ChapterStatusRow key={it.ch} theme={t} item={it}
              last={i === items.length - 1}/>
          ))}
        </div>
      </div>

      <div style={{
        padding: '12px 18px 22px',
        borderTop: `0.5px solid ${t.rule}`,
        background: t.isDark ? '#222020' : '#fcf8f0',
      }}>
        <button onClick={onCancelAll} style={{
          width: '100%', padding: '13px 0', borderRadius: 14, border: 'none',
          background: t.isDark ? 'rgba(196,68,68,0.12)' : 'rgba(196,68,68,0.06)',
          color: '#c44', fontFamily: 'inherit', fontSize: 14.5, fontWeight: 600,
          cursor: 'pointer',
        }}>Cancel translation</button>
      </div>
    </Sheet>
  );
}

function ChapterStatusRow({ theme, item, last }) {
  const t = theme;
  const stateColor = item.state === 'done' ? '#3a6a5a'
                   : item.state === 'running' ? t.accent
                   : item.state === 'failed' ? '#c44'
                   : t.sub;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '10px 14px', borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 22, height: 22, borderRadius: 11, flexShrink: 0,
        background: item.state === 'done' ? '#3a6a5a'
                  : item.state === 'running' ? `${t.accent}26`
                  : item.state === 'failed' ? 'rgba(196,68,68,0.14)'
                  : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {item.state === 'done' && <Icons.Check size={11} color="#fff" stroke={2.5}/>}
        {item.state === 'running' && <Spinner color={t.accent} size={10}/>}
        {item.state === 'failed' && <Icons.Close size={9} color="#c44" stroke={2.5}/>}
        {item.state === 'queued' && (
          <span style={{ fontSize: 10, color: t.sub, fontFamily: 'ui-monospace, Menlo, monospace' }}>{item.ch}</span>
        )}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, color: item.state === 'queued' ? t.sub : t.ink,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          fontWeight: item.state === 'running' ? 600 : 500,
        }}>Ch. {item.ch} — {item.title}</div>
        {item.state === 'running' && (
          <div style={{
            marginTop: 4, height: 2, borderRadius: 1,
            background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
            position: 'relative', overflow: 'hidden',
          }}>
            <div style={{
              position: 'absolute', inset: 0,
              width: `${(item.progress || 0) * 100}%`, background: t.accent,
              borderRadius: 1,
            }}/>
          </div>
        )}
      </div>
      <div style={{
        fontSize: 10.5, color: stateColor, fontWeight: 600,
        letterSpacing: 0.4, textTransform: 'uppercase', flexShrink: 0,
      }}>{item.state === 'running' ? 'Now' : item.state === 'done' ? '' : item.state}</div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Cancel confirmation — disabuses the user
// ────────────────────────────────────────────────────
function TranslateCancelAlert({ theme, progress = { done: 12, total: 61 }, onKeep, onConfirm }) {
  const t = theme;
  return (
    <div onClick={onKeep} style={{
      position: 'absolute', inset: 0, zIndex: 250,
      background: 'rgba(0,0,0,0.45)',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      padding: 18,
    }}>
      <div onClick={ev => ev.stopPropagation()} style={{
        width: 290, borderRadius: 18, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 16px 50px rgba(0,0,0,0.4)',
      }}>
        <div style={{ padding: '20px 22px 14px', textAlign: 'center' }}>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 17, fontWeight: 700, color: t.ink,
            lineHeight: 1.25, marginBottom: 8,
          }}>Cancel translation?</div>
          <div style={{
            fontSize: 12.5, color: t.sub, lineHeight: 1.5, textWrap: 'pretty',
          }}>
            <b style={{ color: t.ink }}>{progress.done} of {progress.total}</b> chapters are already
            translated and will <b style={{ color: t.ink }}>stay cached</b> — you can resume
            from where you stopped any time. We won't be charged for the rest.
          </div>
        </div>
        <div style={{ display: 'flex', borderTop: `0.5px solid ${t.rule}` }}>
          <button onClick={onKeep} style={alertBtn(t)}>Keep translating</button>
          <button onClick={onConfirm} style={{
            ...alertBtn(t), borderLeft: `0.5px solid ${t.rule}`,
            color: '#c44', fontWeight: 700,
          }}>Cancel translation</button>
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  TranslateBookActionRow, TranslateBookConfirmAlert,
  LibraryCardTranslateBadge, ReaderTranslateBanner,
  TranslateStatusSheet, TranslateCancelAlert,
});
