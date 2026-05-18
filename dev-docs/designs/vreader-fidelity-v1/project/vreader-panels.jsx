// Panels & sheets: AI, TOC, Highlights, Reader Settings (Aa), App Settings

// ────────────────────────────────────────────────────
// Sheet wrapper — slides up from bottom
// ────────────────────────────────────────────────────
function Sheet({ theme, onClose, height = 560, children, title, leading, trailing }) {
  const t = theme || THEMES.paper;
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 200,
      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
      background: 'rgba(0,0,0,0.35)',
    }} onClick={onClose}>
      <div onClick={e => e.stopPropagation()} style={{
        background: t.isDark ? '#222020' : '#fcf8f0',
        height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{
            width: 36, height: 5, borderRadius: 3,
            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
          }}/>
        </div>
        {title && (
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '14px 18px 12px',
            borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
          }}>
            <div style={{ width: 50 }}>{leading}</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 17, fontWeight: 600, color: t.ink,
            }}>{title}</div>
            <div style={{ width: 50, display: 'flex', justifyContent: 'flex-end' }}>
              {trailing || (
                <button onClick={onClose} style={{
                  background: 'rgba(0,0,0,0.06)', border: 'none',
                  width: 28, height: 28, borderRadius: 14, padding: 0, cursor: 'pointer',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  <Icons.Close size={14} color={t.sub} stroke={2}/>
                </button>
              )}
            </div>
          </div>
        )}
        <div style={{ flex: 1, overflow: 'auto', display: 'flex', flexDirection: 'column', minHeight: 0 }} className="hide-scroll">
          {children}
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Reader display settings (Aa) — half sheet
// ────────────────────────────────────────────────────
function ReaderSettingsSheet({ theme, settings, onChange, onClose }) {
  const t = theme;
  const s = settings;
  const update = (k, v) => onChange({ ...s, [k]: v });

  return (
    <Sheet theme={t} onClose={onClose} title="Display" height={540}>
      <div style={{ padding: 18 }}>
        {/* Brightness */}
        <SliderRow theme={t} icon="sun"
          value={s.brightness} min={0.3} max={1} step={0.05}
          onChange={v => update('brightness', v)}/>

        {/* Theme selector */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Theme</SectionLabel>
          <div style={{ display: 'flex', gap: 10, marginTop: 10 }}>
            {Object.entries(THEMES).map(([key, th]) => (
              <button key={key} onClick={() => update('theme', key)} style={{
                flex: 1, padding: 0, border: 'none', cursor: 'pointer',
                background: 'transparent',
              }}>
                <div style={{
                  position: 'relative', width: '100%', aspectRatio: '1', borderRadius: 12,
                  background: th.image ? 'linear-gradient(135deg, #3a2818, #1a1410)' : th.bg,
                  overflow: 'hidden',
                  boxShadow: s.theme === key
                    ? `0 0 0 2.5px ${t.accent}, 0 0 0 4px ${t.isDark ? '#222020' : '#fcf8f0'}`
                    : `inset 0 0 0 0.5px ${t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)'}`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                }}>
                  {th.image ? (
                    <Icons.Image size={20} color="#e8b465" stroke={1.7}/>
                  ) : (
                    <div style={{
                      fontFamily: '"Source Serif 4", Georgia, serif',
                      fontSize: 20, fontWeight: 600, color: th.ink,
                    }}>Aa</div>
                  )}
                </div>
                <div style={{
                  marginTop: 6, fontSize: 11, color: t.sub,
                  fontWeight: s.theme === key ? 600 : 400,
                }}>{th.name}</div>
              </button>
            ))}
          </div>
        </div>

        {/* Font family */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Layout</SectionLabel>
          <div style={{
            display: 'flex', marginTop: 10, borderRadius: 12,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            padding: 3,
          }}>
            {[
              { k: 'paged',  label: 'Paged',  icon: 'paged' },
              { k: 'scroll', label: 'Scroll', icon: 'scroll' },
            ].map(o => (
              <button key={o.k} onClick={() => update('mode', o.k)} style={{
                flex: 1, padding: '10px 0', borderRadius: 10, border: 'none',
                background: (s.mode || 'paged') === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                color: t.ink, fontFamily: 'inherit', fontSize: 14, cursor: 'pointer',
                fontWeight: (s.mode || 'paged') === o.k ? 600 : 500,
                boxShadow: (s.mode || 'paged') === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
                display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
              }}>
                <LayoutGlyph mode={o.icon} color={t.ink} active={(s.mode || 'paged') === o.k}/>
                {o.label}
              </button>
            ))}
          </div>
        </div>

        {/* Font family */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Font</SectionLabel>
          <div style={{
            display: 'flex', marginTop: 10, borderRadius: 12,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            padding: 3,
          }}>
            {[
              { k: 'serif', label: 'Source Serif', font: '"Source Serif 4", Georgia, serif' },
              { k: 'sans', label: 'Inter', font: '"Inter", system-ui' },
            ].map(o => (
              <button key={o.k} onClick={() => update('fontFamily', o.k)} style={{
                flex: 1, padding: '10px 0', borderRadius: 10, border: 'none',
                background: s.fontFamily === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                fontFamily: o.font, fontSize: 15, color: t.ink, cursor: 'pointer',
                fontWeight: 500, transition: 'background 0.15s',
                boxShadow: s.fontFamily === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
              }}>{o.label}</button>
            ))}
          </div>
        </div>

        {/* Font size */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Size</SectionLabel>
          <SliderRow theme={t} aaSmall aaLarge
            value={s.fontSize} min={13} max={26} step={1}
            onChange={v => update('fontSize', v)}/>
        </div>

        {/* Line height */}
        <div style={{ marginTop: 18 }}>
          <SectionLabel theme={t}>Line spacing</SectionLabel>
          <SliderRow theme={t} iconLeft="lines-tight" iconRight="lines-loose"
            value={s.lineHeight} min={1.3} max={2.0} step={0.05}
            onChange={v => update('lineHeight', v)}/>
        </div>

        {/* Margin */}
        <div style={{ marginTop: 18 }}>
          <SectionLabel theme={t}>Margin</SectionLabel>
          <SliderRow theme={t} iconLeft="margin-narrow" iconRight="margin-wide"
            value={s.margin} min={16} max={48} step={2}
            onChange={v => update('margin', v)}/>
        </div>
      </div>
    </Sheet>
  );
}

function SectionLabel({ theme, children }) {
  return (
    <div style={{
      fontSize: 12, fontWeight: 600, color: theme.sub,
      letterSpacing: 0.8, textTransform: 'uppercase',
    }}>{children}</div>
  );
}

// Small inline pictogram for Paged vs Scroll layout — paged = open book, scroll = stacked pages.
function LayoutGlyph({ mode, color, active }) {
  const c = color || '#000';
  if (mode === 'paged') {
    return (
      <svg width="16" height="14" viewBox="0 0 16 14" fill="none">
        <rect x="0.5" y="1.5" width="6.5" height="11" rx="0.5" stroke={c} strokeWidth="1.2"/>
        <rect x="9" y="1.5" width="6.5" height="11" rx="0.5" stroke={c} strokeWidth="1.2"/>
        <path d="M2 5h4M2 7.5h4M2 10h3M10.5 5h4M10.5 7.5h4M10.5 10h3" stroke={c} strokeWidth="0.8" opacity="0.55"/>
      </svg>
    );
  }
  return (
    <svg width="16" height="14" viewBox="0 0 16 14" fill="none">
      <rect x="2.5" y="0.5" width="11" height="13" rx="1" stroke={c} strokeWidth="1.2"/>
      <path d="M5 3h6M5 5.5h6M5 8h6M5 10.5h4" stroke={c} strokeWidth="0.9"/>
      <path d="M0.7 4l1.6 1.6M0.7 10l1.6-1.6" stroke={c} strokeWidth="1" strokeLinecap="round" opacity="0.45"/>
      <path d="M15.3 4l-1.6 1.6M15.3 10l-1.6-1.6" stroke={c} strokeWidth="1" strokeLinecap="round" opacity="0.45"/>
    </svg>
  );
}

function SliderRow({ theme, value, min, max, step, onChange, icon, aaSmall, aaLarge, iconLeft, iconRight }) {
  const t = theme;
  const p = (value - min) / (max - min);
  const trackRef = React.useRef(null);
  const drag = (e) => {
    const rect = trackRef.current.getBoundingClientRect();
    const clientX = e.touches ? e.touches[0].clientX : e.clientX;
    const x = Math.max(0, Math.min(1, (clientX - rect.left) / rect.width));
    const v = min + Math.round((x * (max - min)) / step) * step;
    onChange(Math.max(min, Math.min(max, v)));
  };
  const startDrag = (e) => {
    drag(e);
    const move = (ev) => drag(ev);
    const up = () => { window.removeEventListener('mousemove', move); window.removeEventListener('mouseup', up); };
    window.addEventListener('mousemove', move);
    window.addEventListener('mouseup', up);
  };

  const renderIcon = (which) => {
    const c = t.sub;
    if (which === 'sun') return <Icons.Brightness size={16} color={c} stroke={1.7}/>;
    if (aaSmall) return <span style={{ fontFamily: 'serif', fontSize: 12, color: c }}>Aa</span>;
    if (which === 'lines-tight') return <svg width="16" height="12" viewBox="0 0 16 12"><path d="M0 2h16M0 6h16M0 10h16" stroke={c} strokeWidth="1.5"/></svg>;
    if (which === 'lines-loose') return <svg width="16" height="14" viewBox="0 0 16 14"><path d="M0 1h16M0 7h16M0 13h16" stroke={c} strokeWidth="1.5"/></svg>;
    if (which === 'margin-narrow') return <svg width="14" height="14" viewBox="0 0 14 14"><rect x="0" y="0" width="14" height="14" stroke={c} strokeWidth="1" fill="none"/><rect x="2" y="2" width="10" height="10" stroke={c} strokeWidth="0.5" fill="none" strokeDasharray="2 1"/></svg>;
    if (which === 'margin-wide') return <svg width="14" height="14" viewBox="0 0 14 14"><rect x="0" y="0" width="14" height="14" stroke={c} strokeWidth="1" fill="none"/><rect x="4" y="4" width="6" height="6" stroke={c} strokeWidth="0.5" fill="none" strokeDasharray="2 1"/></svg>;
    return null;
  };
  const renderIconRight = (which) => {
    const c = t.sub;
    if (aaLarge) return <span style={{ fontFamily: 'serif', fontSize: 22, color: c }}>Aa</span>;
    return renderIcon(which);
  };

  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderRadius: 14, marginTop: 8,
      background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
    }}>
      <div style={{ width: 24, display: 'flex', justifyContent: 'center' }}>
        {renderIcon(icon || iconLeft)}
      </div>
      <div ref={trackRef} onMouseDown={startDrag} onClick={drag} style={{
        flex: 1, height: 24, display: 'flex', alignItems: 'center', cursor: 'pointer',
      }}>
        <div style={{
          flex: 1, height: 4, borderRadius: 2,
          background: t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.1)',
          position: 'relative',
        }}>
          <div style={{
            position: 'absolute', left: 0, top: 0, bottom: 0, width: `${p * 100}%`,
            background: t.accent, borderRadius: 2,
          }}/>
          <div style={{
            position: 'absolute', left: `${p * 100}%`, top: '50%',
            width: 22, height: 22, borderRadius: 11, background: '#fff',
            transform: 'translate(-50%, -50%)',
            boxShadow: '0 1px 4px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.06)',
          }}/>
        </div>
      </div>
      <div style={{ width: 28, display: 'flex', justifyContent: 'center' }}>
        {renderIconRight(iconRight || (aaLarge ? 'aa-large' : null) || icon)}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// TOC Sheet
// ────────────────────────────────────────────────────
function TOCSheet({ theme, currentCh, onJump, onClose }) {
  const t = theme;
  const [tab, setTab] = React.useState('contents');
  return (
    <Sheet theme={t} onClose={onClose} title="Pride and Prejudice" height={620}>
      <div style={{ padding: '8px 18px 0' }}>
        <div style={{
          display: 'flex', borderRadius: 10, padding: 3,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
        }}>
          {[
            { k: 'contents', label: 'Contents' },
            { k: 'bookmarks', label: 'Bookmarks' },
          ].map(o => (
            <button key={o.k} onClick={() => setTab(o.k)} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, border: 'none',
              background: tab === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: t.ink, fontFamily: 'inherit', fontSize: 13, fontWeight: 500, cursor: 'pointer',
              boxShadow: tab === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{o.label}</button>
          ))}
        </div>
      </div>
      {tab === 'contents' ? (
        <div style={{ padding: '14px 8px' }}>
          {TOC.map(c => (
            <button key={c.ch} onClick={() => { onJump(c); onClose(); }} style={{
              display: 'flex', alignItems: 'baseline', gap: 14,
              padding: '12px 14px', width: '100%', border: 'none',
              background: c.ch === currentCh
                ? (t.isDark ? 'rgba(214,136,90,0.12)' : 'rgba(140,47,47,0.08)')
                : 'transparent',
              borderRadius: 10, cursor: 'pointer', textAlign: 'left',
            }}>
              <span style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 12, color: t.sub, fontWeight: 500,
                width: 24, textAlign: 'right',
              }}>{c.ch}</span>
              <span style={{
                flex: 1, fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 16, color: c.ch === currentCh ? t.accent : t.ink,
                fontWeight: c.ch === currentCh ? 600 : 400,
              }}>{c.title}</span>
              <span style={{ fontSize: 12, color: t.sub }}>p. {c.page}</span>
            </button>
          ))}
        </div>
      ) : (
        <div style={{ padding: '14px 18px' }}>
          {[
            { page: 1, chapter: 'Chapter 1', date: 'Apr 12', preview: 'It is a truth universally acknowledged…' },
            { page: 47, chapter: 'Chapter 6', date: 'Apr 18', preview: 'Charlotte\'s view on marriage' },
            { page: 89, chapter: 'Chapter 11', date: 'Yesterday', preview: 'The Netherfield ball' },
          ].map((b, i) => (
            <button key={i} onClick={onClose} style={{
              display: 'flex', alignItems: 'flex-start', gap: 12,
              padding: '14px 0', width: '100%', border: 'none', background: 'transparent',
              borderBottom: `0.5px solid ${t.rule}`, cursor: 'pointer', textAlign: 'left',
            }}>
              <Icons.Bookmark size={18} color={t.accent} stroke={1.7}/>
              <div style={{ flex: 1 }}>
                <div style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 14, fontStyle: 'italic', color: t.ink,
                  lineHeight: 1.3, marginBottom: 4,
                }}>{b.preview}</div>
                <div style={{ fontSize: 11, color: t.sub }}>{b.chapter} · p. {b.page} · {b.date}</div>
              </div>
              <Icons.Chevron size={14} color={t.sub} stroke={2}/>
            </button>
          ))}
        </div>
      )}
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// Highlights & notes
// ────────────────────────────────────────────────────
function HighlightsSheet({ theme, highlights, onClose }) {
  const t = theme;
  const colorMap = {
    yellow: '#f0d25a', pink: '#e88ca0', green: '#8cc88c', blue: '#8cb4e8',
  };
  return (
    <Sheet theme={t} onClose={onClose} height={620}
      title="Annotations"
      trailing={
        <button style={{
          background: 'none', border: 'none', padding: '4px 8px',
          color: t.accent, fontFamily: 'inherit', fontSize: 14, fontWeight: 500, cursor: 'pointer',
        }}>
          <Icons.Share size={18} color={t.accent} stroke={1.8}/>
        </button>
      }>
      <div style={{ padding: '8px 18px 4px', display: 'flex', gap: 6 }}>
        {['All', 'Highlights', 'Notes', 'Bookmarks'].map((f, i) => (
          <button key={f} style={{
            padding: '5px 12px', borderRadius: 100, border: 'none',
            fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
            background: i === 0 ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
            color: i === 0 ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
            cursor: 'pointer',
          }}>{f}</button>
        ))}
      </div>
      <div style={{ padding: '8px 18px 24px' }}>
        {highlights.map(h => (
          <div key={h.id} style={{
            padding: '14px 0', borderBottom: `0.5px solid ${t.rule}`,
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
        ))}
      </div>
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// AI Panel — Summary / Chat / Translate
// ────────────────────────────────────────────────────
function AISheet({ theme, mode = 'summary', context = null, book, onClose }) {
  const t = theme;
  const [tab, setTab] = React.useState(mode);
  return (
    <Sheet theme={t} onClose={onClose} height={650}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '14px 18px 4px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 28, height: 28, borderRadius: 14,
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Sparkle size={15} color="#fff" stroke={2}/>
          </div>
          <div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 17, fontWeight: 600, color: t.ink,
            }}>AI Assistant</div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: -1 }}>
              Claude · with this book's context
            </div>
          </div>
        </div>
        <button onClick={onClose} style={{
          background: 'rgba(0,0,0,0.06)', border: 'none',
          width: 28, height: 28, borderRadius: 14, padding: 0, cursor: 'pointer',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Close size={14} color={t.sub} stroke={2}/>
        </button>
      </div>

      <div style={{ padding: '12px 18px 0' }}>
        <div style={{
          display: 'flex', borderRadius: 10, padding: 3,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
        }}>
          {[
            { k: 'summary', label: 'Summarize' },
            { k: 'chat', label: 'Chat' },
            { k: 'translate', label: 'Translate' },
          ].map(o => (
            <button key={o.k} onClick={() => setTab(o.k)} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, border: 'none',
              background: tab === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: tab === o.k ? t.ink : t.sub,
              fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500, cursor: 'pointer',
              boxShadow: tab === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{o.label}</button>
          ))}
        </div>
      </div>

      <div style={{ flex: 1, overflow: 'hidden', minHeight: 0, display: 'flex' }}>
        {tab === 'summary' && <SummaryView theme={t} book={book}/>}
        {tab === 'chat' && <ChatView theme={t} book={book} context={context}/>}
        {tab === 'translate' && <TranslateView theme={t} book={book} context={context}/>}
      </div>
    </Sheet>
  );
}

function SummaryView({ theme, book }) {
  const t = theme;
  const [scope, setScope] = React.useState('section');
  return (
    <div style={{ padding: '16px 18px', flex: 1, overflow: 'auto' }} className="hide-scroll">
      <div style={{
        display: 'flex', gap: 6, marginBottom: 14,
      }}>
        {['Section', 'Chapter', 'Book so far'].map((s, i) => (
          <button key={s} onClick={() => setScope(s.toLowerCase())} style={{
            padding: '6px 12px', borderRadius: 100, border: 'none',
            fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
            whiteSpace: 'nowrap',
            background: scope === s.toLowerCase()
              ? t.accent
              : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
            color: scope === s.toLowerCase() ? '#fff' : t.ink,
            cursor: 'pointer',
          }}>{s}</button>
        ))}
      </div>

      <div style={{
        padding: 16, borderRadius: 14,
        background: t.isDark ? 'rgba(214,136,90,0.08)' : 'rgba(140,47,47,0.04)',
        border: `0.5px solid ${t.rule}`,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 6, marginBottom: 10,
          fontSize: 11, color: t.sub, fontWeight: 600, letterSpacing: 0.5,
          textTransform: 'uppercase',
        }}>
          <Icons.Sparkle size={11} color={t.accent} stroke={2}/>
          <span>Chapter 1 — Summary</span>
        </div>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 15, lineHeight: 1.55, color: t.ink,
        }}>
          The novel opens with the famous declaration that wealthy single men inevitably need wives.
          When Netherfield Park is rented by Mr. Bingley, a young gentleman of large fortune, Mrs. Bennet
          immediately schemes to introduce her five daughters. She presses her husband to visit Bingley,
          but Mr. Bennet, characteristically dry, deflects her with teasing irony. The chapter establishes
          the central comedy: a household of marriageable daughters, a mother defined by her nerves and
          matchmaking, and a father who finds amusement in her preoccupations.
        </div>
        <div style={{
          display: 'flex', gap: 8, marginTop: 14, paddingTop: 12,
          borderTop: `0.5px solid ${t.rule}`,
        }}>
          <button style={chipBtn(t)}><Icons.Note size={12} color={t.sub} stroke={1.7}/>Save</button>
          <button style={chipBtn(t)}><Icons.Share size={12} color={t.sub} stroke={1.7}/>Share</button>
          <button style={chipBtn(t)}>Regenerate</button>
        </div>
      </div>

      <SectionLabel theme={t} >Suggested questions</SectionLabel>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 8 }}>
        {[
          'Who are the Bennet daughters and how are they introduced?',
          'What is the tone established in the first paragraph?',
          'How does Austen characterize Mr. and Mrs. Bennet differently?',
        ].map((q, i) => (
          <button key={i} style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '12px 14px', borderRadius: 12, border: 'none',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            color: t.ink, fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 13.5, cursor: 'pointer', textAlign: 'left',
            boxShadow: '0 1px 0 rgba(0,0,0,0.03)',
          }}>
            <span>{q}</span>
            <Icons.Chevron size={14} color={t.sub} stroke={2}/>
          </button>
        ))}
      </div>
    </div>
  );
}

function chipBtn(t) {
  return {
    display: 'flex', alignItems: 'center', gap: 4,
    padding: '5px 10px', borderRadius: 100, border: 'none',
    background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)',
    color: t.sub, fontFamily: 'inherit', fontSize: 12, fontWeight: 500, cursor: 'pointer',
  };
}

function ChatView({ theme, book, context }) {
  const t = theme;
  const [messages, setMessages] = React.useState(() => {
    const init = [
      {
        role: 'assistant',
        text: 'Hi! I have this book\'s context loaded. Ask me anything about it — characters, themes, references, or to clarify a passage you\'re reading.'
      }
    ];
    if (context) {
      init.push({
        role: 'user', text: `What do you make of: "${context}"`, quoted: context
      });
      init.push({
        role: 'assistant',
        text: 'That line is the novel\'s thesis statement, delivered with deliberate irony. Austen presents it as universally accepted truth, but the rest of the chapter shows it\'s really the prejudice of mothers like Mrs. Bennet — not the men themselves. The reversal between the stated and actual subject of "wants" is the engine of the whole book.'
      });
    }
    return init;
  });
  const [draft, setDraft] = React.useState('');
  const scrollRef = React.useRef(null);

  React.useEffect(() => {
    if (scrollRef.current) scrollRef.current.scrollTop = scrollRef.current.scrollHeight;
  }, [messages]);

  const send = () => {
    if (!draft.trim()) return;
    const text = draft.trim();
    setMessages(m => [...m, { role: 'user', text }]);
    setDraft('');
    setTimeout(() => {
      setMessages(m => [...m, {
        role: 'assistant',
        text: 'Drawing on the book\'s context, here\'s a focused answer to your question. (Demo response — the production app calls your configured OpenAI-compatible endpoint and streams the actual response token by token.)',
      }]);
    }, 800);
  };

  return (
    <div style={{ display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
      <div ref={scrollRef} style={{
        flex: 1, overflow: 'auto', padding: '16px 18px 8px',
      }} className="hide-scroll">
        {messages.map((m, i) => (
          <ChatBubble key={i} message={m} theme={t}/>
        ))}
      </div>
      <div style={{
        padding: '8px 14px 16px',
        borderTop: `0.5px solid ${t.rule}`,
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '6px 6px 6px 14px', borderRadius: 22,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
        }}>
          <input value={draft} onChange={e => setDraft(e.target.value)}
                 onKeyDown={e => e.key === 'Enter' && send()}
                 placeholder="Ask about this book…" style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontFamily: 'inherit', fontSize: 14, color: t.ink,
          }}/>
          <button onClick={send} style={{
            width: 32, height: 32, borderRadius: 16, border: 'none',
            background: draft.trim() ? t.accent : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)'),
            color: '#fff', cursor: draft.trim() ? 'pointer' : 'default',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Send size={15} color="#fff" stroke={2}/>
          </button>
        </div>
      </div>
    </div>
  );
}

function ChatBubble({ message, theme }) {
  const t = theme;
  if (message.role === 'user') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 10 }}>
        <div style={{
          maxWidth: '80%',
          padding: '10px 14px', borderRadius: 18, borderTopRightRadius: 6,
          background: t.accent, color: '#fff',
          fontFamily: 'inherit', fontSize: 14, lineHeight: 1.4,
        }}>{message.text}</div>
      </div>
    );
  }
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
      <div style={{
        width: 24, height: 24, borderRadius: 12, flexShrink: 0,
        background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center', marginTop: 2,
      }}>
        <Icons.Sparkle size={12} color="#fff" stroke={2}/>
      </div>
      <div style={{
        padding: '4px 0', maxWidth: '85%',
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14.5, lineHeight: 1.5, color: t.ink,
      }}>{message.text}</div>
    </div>
  );
}

function TranslateView({ theme, book, context }) {
  const t = theme;
  const [lang, setLang] = React.useState('Chinese');
  const sourceText = context || 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.';
  const translations = {
    Chinese: '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
    Spanish: 'Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.',
    French: 'C\'est une vérité universellement reconnue qu\'un homme célibataire en possession d\'une bonne fortune doit avoir besoin d\'une épouse.',
    Japanese: '相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。',
  };

  return (
    <div style={{ padding: '14px 18px', flex: 1, overflow: 'auto' }} className="hide-scroll">
      <div style={{
        display: 'flex', gap: 6, marginBottom: 14, overflowX: 'auto',
      }} className="hide-scroll">
        {Object.keys(translations).concat(['German', 'Korean', 'Arabic']).map(l => (
          <button key={l} onClick={() => setLang(l)} style={{
            padding: '6px 12px', borderRadius: 100, border: 'none',
            fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
            background: lang === l ? t.accent : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
            color: lang === l ? '#fff' : t.ink,
            cursor: 'pointer', whiteSpace: 'nowrap',
          }}>{l}</button>
        ))}
      </div>

      <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
        <div style={{
          padding: 14, borderRadius: 14,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          border: `0.5px solid ${t.rule}`,
        }}>
          <div style={{
            fontSize: 10.5, letterSpacing: 1, textTransform: 'uppercase',
            color: t.sub, fontWeight: 600, marginBottom: 8,
          }}>English (Original)</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 15, lineHeight: 1.5, color: t.ink,
          }}>"{sourceText}"</div>
        </div>
        <div style={{
          padding: 14, borderRadius: 14,
          background: `linear-gradient(135deg, ${t.accent}1a, ${t.accent}0d)`,
          border: `0.5px solid ${t.accent}55`,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8,
          }}>
            <div style={{
              fontSize: 10.5, letterSpacing: 1, textTransform: 'uppercase',
              color: t.accent, fontWeight: 600,
            }}>{lang}</div>
            <button style={{
              background: 'none', border: 'none', padding: 0, cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 4,
              fontSize: 11, color: t.sub,
            }}>
              <Icons.Volume size={12} color={t.sub} stroke={1.7}/>
              <span>Speak</span>
            </button>
          </div>
          <div style={{
            fontFamily: lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean'
              ? '"Songti SC", "Source Han Serif", serif'
              : '"Source Serif 4", Georgia, serif',
            fontSize: 16, lineHeight: 1.55, color: t.ink,
          }}>{translations[lang] || 'Translation would appear here.'}</div>
        </div>

        <div style={{
          marginTop: 8, padding: 14, borderRadius: 14,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8,
            fontSize: 11, color: t.sub, fontWeight: 600, letterSpacing: 0.5,
            textTransform: 'uppercase',
          }}>
            <Icons.Sparkle size={11} color={t.accent} stroke={2}/>
            <span>Notes on the translation</span>
          </div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 13.5, lineHeight: 1.5, color: t.sub,
          }}>
            "Universally acknowledged" is rendered idiomatically — the Chinese version flips the construction to lead with the
            condition, which preserves Austen's irony but loses the slow build of the original sentence.
          </div>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// App Settings Sheet
// ────────────────────────────────────────────────────
function SettingsSheet({ theme, onClose, onOpenStats }) {
  const t = theme || THEMES.paper;
  const Row = ({ icon, color, title, detail, value, last, danger }) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8,
        background: color, display: 'flex', alignItems: 'center', justifyContent: 'center',
        flexShrink: 0,
      }}>{icon}</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontFamily: 'inherit', fontSize: 15, color: danger ? '#c44' : t.ink }}>{title}</div>
        {detail && <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>{detail}</div>}
      </div>
      {value !== undefined && (
        <div style={{ fontSize: 14, color: t.sub, marginRight: 4 }}>{value}</div>
      )}
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </div>
  );
  return (
    <Sheet theme={t} onClose={onClose} title="Settings" height={700}>
      <div style={{ padding: '16px 18px 32px' }}>
        {/* Profile */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 12,
          padding: 14, borderRadius: 14,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          marginBottom: 18,
        }}>
          <div style={{
            width: 48, height: 48, borderRadius: 24,
            background: `linear-gradient(135deg, ${t.accent}, #5a3a3a)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            color: '#fff', fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 20, fontWeight: 600,
          }}>L</div>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 16, fontWeight: 600, color: t.ink }}>lllyys</div>
            <div style={{ fontSize: 12, color: t.sub, marginTop: 1 }}>
              152 books · 41h read this month
            </div>
          </div>
          <button onClick={() => onOpenStats?.()} style={{
            padding: '6px 12px', borderRadius: 100, border: 'none',
            background: 'rgba(60,40,20,0.08)',
            fontSize: 12, color: t.ink, fontWeight: 500, cursor: 'pointer',
          }}>Stats</button>
        </div>

        {[
          { header: 'Cloud & Sync', items: [
            { icon: <Icons.Cloud size={17} color="#fff" stroke={1.8}/>, color: '#3a8ac8', title: 'WebDAV backup', detail: 'Nutstore · last sync 2h ago', value: 'On' },
            { icon: <Icons.Folder size={17} color="#fff" stroke={1.8}/>, color: '#7c6ad6', title: 'OPDS catalogs', value: '3' },
            { icon: <Icons.Library size={17} color="#fff" stroke={1.8}/>, color: '#3a6a5a', title: 'Book sources', detail: 'Legado-compatible scraping', value: '12' },
          ]},
          { header: 'AI', items: [
            { icon: <Icons.Sparkle size={17} color="#fff" stroke={1.8}/>, color: '#8c2f2f', title: 'AI provider', value: 'Claude' },
            { icon: <Icons.Translate size={17} color="#fff" stroke={1.8}/>, color: '#c87a3a', title: 'Translation languages', value: '9' },
          ]},
          { header: 'Reading', items: [
            { icon: <Icons.Volume size={17} color="#fff" stroke={1.8}/>, color: '#3a3a8c', title: 'Text-to-speech', detail: 'System voice · 1.0×' },
            { icon: <Icons.Note size={17} color="#fff" stroke={1.8}/>, color: '#a8804a', title: 'Replacement rules', value: '5' },
            { icon: <span style={{
              fontFamily: 'serif', fontSize: 14, color: '#fff', fontWeight: 600
            }}>简</span>, color: '#3a6a5a', title: 'Chinese conversion', value: 'Off' },
          ]},
          { header: 'About', items: [
            { icon: <span style={{ fontFamily: 'serif', fontSize: 13, color: '#fff', fontWeight: 700 }}>?</span>, color: '#5a5a5a', title: 'Help & feedback' },
            { icon: <Icons.Note size={17} color="#fff" stroke={1.8}/>, color: '#999', title: 'Version', value: '2.4.1' },
          ]},
        ].map((section, si) => (
          <div key={si} style={{ marginBottom: 18 }}>
            <SectionLabel theme={t}>{section.header}</SectionLabel>
            <div style={{
              marginTop: 8, borderRadius: 14,
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
              overflow: 'hidden',
              boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
            }}>
              {section.items.map((it, i) => (
                <Row key={i} {...it} last={i === section.items.length - 1}/>
              ))}
            </div>
          </div>
        ))}
      </div>
    </Sheet>
  );
}

Object.assign(window, { Sheet, ReaderSettingsSheet, TOCSheet, HighlightsSheet, AISheet, SettingsSheet });
