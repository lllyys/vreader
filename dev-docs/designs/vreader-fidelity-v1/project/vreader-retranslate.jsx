// Per-chapter re-translation — issue #864 / feature #56 (4).
//
// Two surfaces, plus state badges:
//
//   1. The AFFORDANCE — where the user reaches "Re-translate this chapter".
//      Decision: the canonical place is a NEW row in the More popover, conditional on
//      `bilingualOn`. Putting it on the AA (Display) panel mixes a translation action
//      into a panel about typography. Putting it only on a chapter-list context menu
//      hides it behind a deep navigation step the user has to learn. The More popover
//      already carries bilingual mode's toggle — chapter re-translate belongs in the
//      same neighbourhood, one tap from the reader. We also ADD a TOC-list swipe
//      action (Re-translate / Mark as translated) for chapters other than the current
//      one, but that's the secondary path.
//
//   2. The PROVIDER-OVERRIDE PICKER — a half-sheet opened from the row above.
//      Pre-populates the provider + model + style that the bilingual mode setup
//      sheet established; the user can swap any of them just for this re-translation
//      without changing the default. Shows the estimated token cost before
//      committing, so the user can back out if it's expensive.
//
// State badges (rendered into the More-row sub-detail + the reader top-chrome
// pill + the TOC chapter row):
//   idle        — "Translated by Claude" (default state once bilingual is on)
//   running     — "Re-translating… 38%"          (spinner + percentage)
//   complete    — "Re-translated · 14m ago"      (transient toast-style)
//   error       — "Re-translate failed — retry"  (red-accent inline retry)
//
// The "complete" state lingers ~6 s then collapses back to idle.

// ────────────────────────────────────────────────────
// More-menu row (state-aware). Drop-in for the bilingual block in MorePopover when
// bilingualOn === true.
// ────────────────────────────────────────────────────
function ReTranslateMoreRow({ theme, state = 'idle', provider = 'Claude · Sonnet 4.5',
                              progress = 0, lastRun = '14m ago', onOpen }) {
  const t = theme;
  const sub = state === 'running'  ? `Re-translating… ${Math.round(progress)}%`
            : state === 'complete' ? `Re-translated · ${lastRun}`
            : state === 'error'    ? 'Last attempt failed — tap to retry'
            : `Translated by ${provider}`;

  const tint = state === 'error' ? '#c44' : t.accent;

  return (
    <button onClick={onOpen} style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px', width: '100%', border: 'none',
      background: 'transparent', cursor: 'pointer', textAlign: 'left',
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 8, flexShrink: 0,
        background: state === 'running' ? `${tint}26` : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative',
      }}>
        {state === 'running'
          ? <Spinner color={tint} size={14}/>
          : <Icons.Translate size={15} color={state === 'error' ? '#c44' : t.ink} stroke={1.7}/>}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, color: t.ink, fontWeight: 500, lineHeight: 1.2 }}>
          Re-translate this chapter
        </div>
        <div style={{
          fontSize: 11, color: state === 'error' ? '#c44' : t.sub, marginTop: 2, lineHeight: 1.2,
          fontWeight: state === 'error' ? 600 : 400,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{sub}</div>
      </div>
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </button>
  );
}

// ────────────────────────────────────────────────────
// Chapter-context-menu re-translate (TOC row swipe action). Renders as a revealed
// trailing affordance — width 88, colour-tinted, single tap.
// ────────────────────────────────────────────────────
function ChapterSwipeAction({ theme, label = 'Re-translate', onClick }) {
  const t = theme;
  return (
    <button onClick={onClick} style={{
      height: '100%', minWidth: 88, padding: '0 14px',
      border: 'none', cursor: 'pointer',
      background: t.accent, color: '#fff',
      display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 4,
      fontFamily: 'inherit',
    }}>
      <Icons.Translate size={17} color="#fff" stroke={1.8}/>
      <span style={{ fontSize: 10.5, fontWeight: 600 }}>{label}</span>
    </button>
  );
}

// ────────────────────────────────────────────────────
// Provider-override picker — half sheet
// ────────────────────────────────────────────────────
const PROVIDERS = [
  { id: 'claude', name: 'Claude',  models: ['Sonnet 4.5', 'Haiku 4.5', 'Opus 4'], strength: 'Best for nuance' },
  { id: 'openai', name: 'OpenAI',  models: ['GPT-5', 'GPT-5 Mini'], strength: 'Fast & balanced' },
  { id: 'gemini', name: 'Gemini',  models: ['2.5 Pro', '2.5 Flash'], strength: 'Cheapest' },
  { id: 'deepl',  name: 'DeepL',   models: ['Pro'], strength: 'No AI tone — faithful' },
  { id: 'local',  name: 'Local',   models: ['Qwen2.5-7B', 'Llama-3.1-8B'], strength: 'On-device, no cost' },
];
const STYLES = [
  { id: 'literal',  label: 'Literal',  sub: 'Closer to source structure' },
  { id: 'natural',  label: 'Natural',  sub: 'Reads like the target language' },
  { id: 'literary', label: 'Literary', sub: 'Preserves register and rhythm' },
];

function ReTranslatePickerSheet({ theme, chapterTitle = 'Chapter 6 · "The Bingleys"',
                                  targetLang = 'Chinese', value, onChange, onCancel, onSubmit,
                                  state = 'idle', progress = 0, error = null }) {
  const t = theme;
  const v = value || { provider: 'claude', model: 'Sonnet 4.5', style: 'natural', glossary: true };
  const update = (k, val) => onChange?.({ ...v, [k]: val });
  const prov = PROVIDERS.find(p => p.id === v.provider) || PROVIDERS[0];

  const tokenEst = 2380;
  const costMap = { claude: '$0.012', openai: '$0.010', gemini: '$0.003', deepl: '$0.008', local: 'Free' };
  const cost = costMap[v.provider];

  if (state === 'running') return <ReTranslateProgress theme={t} chapterTitle={chapterTitle} progress={progress} onCancel={onCancel}/>;

  return (
    <Sheet theme={t} onClose={onCancel} height={620} title="Re-translate chapter">
      <div style={{ padding: '6px 22px 28px' }}>
        {/* context strip */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 10,
          padding: '12px 14px', borderRadius: 12, marginTop: 6,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
        }}>
          <Icons.TOC size={16} color={t.sub} stroke={1.7}/>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14.5, fontStyle: 'italic', color: t.ink,
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            }}>{chapterTitle}</div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>
              English → {targetLang} · ~{tokenEst.toLocaleString()} tokens
            </div>
          </div>
        </div>

        {error && (
          <div style={{
            marginTop: 14, padding: '10px 12px', borderRadius: 10,
            background: 'rgba(196,68,68,0.08)', border: '0.5px solid rgba(196,68,68,0.35)',
            display: 'flex', gap: 10, alignItems: 'flex-start',
            fontSize: 12, color: '#c44', lineHeight: 1.4,
          }}>
            <Icons.Info size={14} color="#c44" stroke={2} style={{ flexShrink: 0, marginTop: 1 }}/>
            <span>{error}</span>
          </div>
        )}

        {/* provider list */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Provider</SectionLabel>
          <div style={{
            marginTop: 8, borderRadius: 14,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            overflow: 'hidden',
          }}>
            {PROVIDERS.map((p, i) => {
              const active = p.id === v.provider;
              return (
                <button key={p.id} onClick={() => update('provider', p.id) || update('model', p.models[0])} style={{
                  display: 'flex', alignItems: 'center', gap: 12, width: '100%',
                  padding: '11px 14px', border: 'none', background: 'transparent',
                  borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
                  cursor: 'pointer', textAlign: 'left',
                }}>
                  <ProviderGlyph id={p.id} theme={t} active={active}/>
                  <div style={{ flex: 1 }}>
                    <div style={{ fontSize: 14, color: t.ink, fontWeight: active ? 600 : 500 }}>{p.name}</div>
                    <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>{p.strength}</div>
                  </div>
                  {active && <Icons.Check size={16} color={t.accent} stroke={2.2}/>}
                </button>
              );
            })}
          </div>
        </div>

        {/* model picker (collapses to single chip if provider has 1 model) */}
        {prov.models.length > 1 && (
          <div style={{ marginTop: 18 }}>
            <SectionLabel theme={t}>Model</SectionLabel>
            <div style={{
              display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8,
            }}>
              {prov.models.map(m => (
                <button key={m} onClick={() => update('model', m)} style={{
                  padding: '6px 11px', borderRadius: 100, border: 'none',
                  fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
                  background: v.model === m ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
                  color: v.model === m ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
                  cursor: 'pointer',
                }}>{m}</button>
              ))}
            </div>
          </div>
        )}

        {/* style picker */}
        <div style={{ marginTop: 18 }}>
          <SectionLabel theme={t}>Style</SectionLabel>
          <div style={{
            display: 'flex', marginTop: 8, borderRadius: 12,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            padding: 3,
          }}>
            {STYLES.map(s => (
              <button key={s.id} onClick={() => update('style', s.id)} style={{
                flex: 1, padding: '9px 8px', borderRadius: 10, border: 'none',
                background: v.style === s.id ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                cursor: 'pointer', textAlign: 'center',
                boxShadow: v.style === s.id ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
              }}>
                <div style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>{s.label}</div>
                <div style={{ fontSize: 10, color: t.sub, marginTop: 1, lineHeight: 1.2 }}>{s.sub}</div>
              </button>
            ))}
          </div>
        </div>

        {/* keep-glossary toggle — re-uses any per-book term overrides from the previous run */}
        <button onClick={() => update('glossary', !v.glossary)} style={{
          display: 'flex', alignItems: 'center', gap: 10, width: '100%',
          marginTop: 16, padding: '10px 14px', borderRadius: 12, border: 'none',
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          cursor: 'pointer', textAlign: 'left',
        }}>
          <Icons.Note size={15} color={t.sub} stroke={1.7}/>
          <div style={{ flex: 1 }}>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500 }}>Keep term overrides</div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>
              Reuse 7 per-book glossary entries from the first translation
            </div>
          </div>
          <PillSwitch on={v.glossary} theme={t}/>
        </button>

        {/* CTA */}
        <div style={{
          marginTop: 18, display: 'flex', gap: 10, alignItems: 'center',
        }}>
          <div style={{
            flex: 1, fontSize: 11, color: t.sub, lineHeight: 1.4,
            textWrap: 'pretty',
          }}>
            Estimate: <span style={{ color: t.ink, fontWeight: 600 }}>{cost}</span>
            {v.provider !== 'local' && <span> · {tokenEst.toLocaleString()} tokens</span>}.
            Existing translation is kept until the new one is ready.
          </div>
          <button onClick={onSubmit} style={{
            padding: '12px 18px', borderRadius: 100, border: 'none',
            background: t.accent, color: '#fff',
            fontFamily: 'inherit', fontSize: 13.5, fontWeight: 600, cursor: 'pointer',
            boxShadow: `0 4px 14px ${t.accent}55`,
          }}>Re-translate</button>
        </div>
      </div>
    </Sheet>
  );
}

// In-progress half-sheet — replaces the picker when the user commits.
function ReTranslateProgress({ theme, chapterTitle, progress = 0, onCancel }) {
  const t = theme;
  return (
    <Sheet theme={t} onClose={onCancel} height={340} title="Re-translating">
      <div style={{
        padding: '8px 22px 28px', flex: 1,
        display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
      }}>
        <div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '12px 14px', borderRadius: 12, marginTop: 6,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
          }}>
            <Spinner color={t.accent} size={16}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 14.5, fontStyle: 'italic', color: t.ink,
                overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
              }}>{chapterTitle}</div>
              <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>
                Streaming paragraphs as they arrive…
              </div>
            </div>
          </div>

          <div style={{ marginTop: 22 }}>
            <div style={{
              height: 6, borderRadius: 3,
              background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
              position: 'relative', overflow: 'hidden',
            }}>
              <div style={{
                position: 'absolute', left: 0, top: 0, bottom: 0,
                width: `${progress}%`, background: t.accent,
                borderRadius: 3, transition: 'width 0.4s ease',
              }}/>
            </div>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              marginTop: 6, fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11, color: t.sub, fontVariantNumeric: 'tabular-nums',
            }}>
              <span>{Math.round(progress)}%</span>
              <span>~{Math.round((100 - progress) * 0.18)}s left</span>
            </div>
          </div>
        </div>

        <button onClick={onCancel} style={{
          marginTop: 22, padding: '12px 18px', borderRadius: 12, border: 'none',
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          color: t.ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 500, cursor: 'pointer',
        }}>Cancel</button>
      </div>
    </Sheet>
  );
}

function ProviderGlyph({ id, theme, active }) {
  const t = theme;
  const swatch = {
    claude: '#d97757', openai: '#10a37f', gemini: '#4285f4', deepl: '#0f2b46', local: '#5a5a5a',
  }[id] || '#888';
  const letter = { claude: 'C', openai: 'O', gemini: 'G', deepl: 'D', local: '⌂' }[id];
  return (
    <div style={{
      width: 28, height: 28, borderRadius: 7, flexShrink: 0,
      background: active ? swatch : `${swatch}26`,
      color: active ? '#fff' : swatch,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: '"Source Serif 4", Georgia, serif',
      fontSize: 14, fontWeight: 700,
    }}>{letter}</div>
  );
}

function Spinner({ color = '#888', size = 14 }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: '50%',
      border: `1.5px solid ${color}33`, borderTopColor: color,
      animation: 'spin 0.9s linear infinite',
    }}>
      <style>{`@keyframes spin { to { transform: rotate(360deg); } }`}</style>
    </div>
  );
}

function PillSwitch({ on, theme }) {
  return (
    <div style={{
      width: 34, height: 20, borderRadius: 10, flexShrink: 0,
      background: on ? '#3a6a5a' : (theme.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'),
      position: 'relative', transition: 'background 0.15s',
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 16 : 2,
        width: 16, height: 16, borderRadius: 8, background: '#fff',
        transition: 'left 0.15s',
        boxShadow: '0 1px 2px rgba(0,0,0,0.2)',
      }}/>
    </div>
  );
}

Object.assign(window, {
  ReTranslateMoreRow, ChapterSwipeAction,
  ReTranslatePickerSheet, ReTranslateProgress, Spinner, PROVIDERS, STYLES,
});
