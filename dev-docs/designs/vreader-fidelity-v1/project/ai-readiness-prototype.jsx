// Clickable happy-path prototype for issue #1394 — the in-reader AI-enable +
// consent affordance. Walks the full readiness loop end to end:
//   Bilingual "Set up" → readiness sheet (AI off) → turn on AI → grant consent
//   → add provider (canonical editor) → all four gates clear → back to Bilingual
//   configured → turn on bilingual mode → bilingual reader page.
//
// State persists to localStorage so a refresh keeps your place in the flow.

const PROTO_KEY = 'vreader.1394.proto';
const PROTO_W = 402, PROTO_H = 800;
const PROTO_MONO = 'ui-monospace, "SF Mono", "Menlo", monospace';

const PROTO_PROVIDER = { id: 'claude', name: 'Claude', model: 'claude-sonnet-4-6' };

function loadProto() {
  try { return JSON.parse(localStorage.getItem(PROTO_KEY)) || {}; } catch (e) { return {}; }
}

// Bilingual setup sheet replica wired to live state (reuses the engine strip styling
// from BilingualEngineStrip, plus a compact target-language preview + CTA).
function ProtoBilingualSheet({ t, configured, onSetup, onTurnOn, justChanged }) {
  return (
    <Sheet theme={t} title="Bilingual mode" height={560} onClose={() => {}}>
      <div style={{ padding: '12px 22px 28px' }}>
        <BilingualPreview t={t} lang="Chinese"/>
        <div style={{ marginTop: 22 }}>
          <BilingualEngineStrip theme={t} configured={configured} providerName="Claude"
            onSetup={onSetup} justChanged={justChanged}/>
        </div>
        <button onClick={configured ? onTurnOn : onSetup} style={{
          width: '100%', marginTop: 22, padding: '14px 0', borderRadius: 14, border: 'none',
          background: configured ? t.accent : `${t.accent}55`, color: '#fff',
          fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer',
          boxShadow: configured ? `0 4px 14px ${t.accent}55` : 'none',
        }}>Turn on bilingual mode</button>
        {!configured && (
          <div style={{ textAlign: 'center', marginTop: 10, fontSize: 11.5, color: t.sub }}>
            Set up an AI translation engine first.
          </div>
        )}
      </div>
    </Sheet>
  );
}

// faded reader page behind sheets
function ProtoReaderBG({ t, bilingual }) {
  if (bilingual) {
    return (
      <div style={{ position: 'absolute', inset: 0, padding: '64px 26px 50px' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11, color: t.sub,
          letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center', marginBottom: 16,
        }}>Chapter 1</div>
        <p style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 15, lineHeight: 1.55, color: t.ink, margin: '0 0 4px' }}>
          It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.
        </p>
        <p style={{ fontFamily: '"Songti SC", "Source Han Serif", serif', fontSize: 13.5, lineHeight: 1.6, color: t.sub, margin: '0 0 16px', paddingLeft: 12, borderLeft: `2px solid ${t.accent}55` }}>
          凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。
        </p>
        <p style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 15, lineHeight: 1.55, color: t.ink, margin: '0 0 4px', textIndent: 18 }}>
          However little known the feelings or views of such a man may be on his first entering a neighbourhood…
        </p>
        <p style={{ fontFamily: '"Songti SC", "Source Han Serif", serif', fontSize: 13.5, lineHeight: 1.6, color: t.sub, margin: 0, paddingLeft: 12, borderLeft: `2px solid ${t.accent}55` }}>
          这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何…
        </p>
      </div>
    );
  }
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '64px 26px 50px', opacity: 0.5 }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11, color: t.sub,
        letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center', marginBottom: 14,
      }}>Chapter 1</div>
      {[
        'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
        'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families…',
      ].map((p, i) => (
        <p key={i} style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14, lineHeight: 1.55, color: t.ink,
          margin: '0 0 12px', textIndent: i === 0 ? 0 : 18, textAlign: 'justify',
        }}>{p}</p>
      ))}
    </div>
  );
}

function ProtoChrome({ t, bilingual }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, paddingTop: 30, paddingBottom: 8, zIndex: 5,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 2, color: t.accent, fontSize: 13.5, fontWeight: 500 }}>
          <Icons.ChevronL size={17} color={t.accent} stroke={2.2}/>Library
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <span style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 13.5, fontStyle: 'italic', fontWeight: 600, color: t.ink }}>Pride and Prejudice</span>
          {bilingual && <BilingualPill theme={t} lang="Chinese"/>}
        </div>
        <div style={{ display: 'flex', gap: 2, color: t.ink, opacity: 0.85 }}>
          <Icons.Search size={16} color={t.ink} stroke={1.7}/>
          <Icons.More size={18} color={t.ink} stroke={1.7}/>
        </div>
      </div>
    </div>
  );
}

// minimal in-flow provider editor (a focused stand-in for the canonical
// AIProviderEditSheet — enough to "save" a provider and clear the gate).
function ProtoEditor({ t, onCancel, onSave }) {
  const [key, setKey] = React.useState('');
  const seg = ['Claude', 'OpenAI', 'Custom'];
  return (
    <NavSheet theme={t} height={620} title="Add provider" backLabel="Back" onBack={onCancel}>
      <div style={{ padding: '16px 18px 28px' }}>
        <SectionLabel theme={t}>Provider</SectionLabel>
        <div style={{
          display: 'flex', marginTop: 10, borderRadius: 12, padding: 3,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
        }}>
          {seg.map((s, i) => (
            <div key={s} style={{
              flex: 1, textAlign: 'center', padding: '9px 4px', borderRadius: 9,
              fontSize: 13, fontWeight: i === 0 ? 600 : 500, color: t.ink,
              background: i === 0 ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{s}</div>
          ))}
        </div>

        <SectionLabel theme={t}><span style={{ display: 'block', marginTop: 20 }}>API key</span></SectionLabel>
        <div style={{
          marginTop: 10, padding: '12px 14px', borderRadius: 12,
          background: t.isDark ? 'rgba(255,255,255,0.05)' : '#fff', border: `0.5px solid ${t.rule}`,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <span style={{ fontSize: 13.5, color: t.sub, flexShrink: 0, fontFamily: PROTO_MONO }}>sk-</span>
          <input value={key} onChange={e => setKey(e.target.value)} placeholder="paste your key" autoFocus style={{
            flex: 1, border: 'none', outline: 'none', background: 'transparent',
            fontFamily: PROTO_MONO, fontSize: 13.5, color: t.ink,
          }}/>
        </div>
        <div style={{ fontSize: 11, color: t.sub, lineHeight: 1.45, padding: '8px 4px 0' }}>
          Stored in the device keychain — never synced. Type anything here to continue the demo.
        </div>

        <button onClick={() => onSave(PROTO_PROVIDER)} disabled={!key.trim()} style={{
          width: '100%', marginTop: 22, padding: '13px 0', borderRadius: 14, border: 'none',
          background: key.trim() ? t.accent : `${t.accent}40`, color: '#fff',
          fontFamily: 'inherit', fontSize: 15, fontWeight: 600,
          cursor: key.trim() ? 'pointer' : 'default',
          boxShadow: key.trim() ? `0 4px 14px ${t.accent}55` : 'none',
        }}>Save provider</button>
      </div>
    </NavSheet>
  );
}

function Proto1394() {
  const saved = loadProto();
  const [themeKey, setThemeKey] = React.useState(saved.themeKey || 'paper');
  const [screen, setScreen] = React.useState(saved.screen || 'bilingual'); // bilingual | readiness | editor | reader
  const [ai, setAi] = React.useState(!!saved.ai);
  const [consent, setConsent] = React.useState(!!saved.consent);
  const [provider, setProvider] = React.useState(saved.provider || null);
  const [justChanged, setJustChanged] = React.useState(false);

  const t = THEMES[themeKey];
  const configured = ai && consent && !!provider;

  React.useEffect(() => {
    localStorage.setItem(PROTO_KEY, JSON.stringify({ themeKey, screen, ai, consent, provider }));
  }, [themeKey, screen, ai, consent, provider]);

  const reset = () => { setAi(false); setConsent(false); setProvider(null); setScreen('bilingual'); setJustChanged(false); };

  return (
    <div style={{
      minHeight: '100vh', width: '100%',
      background: '#e9e5dd', display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center', gap: 18, padding: '28px 0',
    }}>
      {/* controls */}
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{ display: 'flex', gap: 4, background: '#fff', borderRadius: 100, padding: 4, boxShadow: '0 1px 3px rgba(0,0,0,0.1)' }}>
          {['paper', 'sepia', 'dark', 'oled'].map(k => (
            <button key={k} onClick={() => setThemeKey(k)} style={{
              border: 'none', cursor: 'pointer', borderRadius: 100, padding: '6px 13px',
              fontFamily: 'Inter, sans-serif', fontSize: 12, fontWeight: 600, textTransform: 'capitalize',
              background: themeKey === k ? '#1d1a14' : 'transparent',
              color: themeKey === k ? '#fff' : 'rgba(0,0,0,0.55)',
            }}>{k}</button>
          ))}
        </div>
        <button onClick={reset} style={{
          border: 'none', cursor: 'pointer', borderRadius: 100, padding: '8px 14px',
          fontFamily: 'Inter, sans-serif', fontSize: 12, fontWeight: 600,
          background: '#fff', color: 'rgba(0,0,0,0.55)', boxShadow: '0 1px 3px rgba(0,0,0,0.1)',
        }}>↺ Restart flow</button>
      </div>

      {/* phone */}
      <div style={{
        width: PROTO_W, height: PROTO_H, position: 'relative', overflow: 'hidden',
        background: t.bg, borderRadius: 30, boxShadow: '0 24px 60px rgba(0,0,0,0.3)',
        border: '1px solid rgba(0,0,0,0.1)',
      }}>
        <ProtoReaderBG t={t} bilingual={screen === 'reader'}/>
        <ProtoChrome t={t} bilingual={screen === 'reader'}/>

        {screen === 'bilingual' && (
          <ProtoBilingualSheet t={t} configured={configured} justChanged={justChanged}
            onSetup={() => { setJustChanged(false); setScreen('readiness'); }}
            onTurnOn={() => setScreen('reader')}/>
        )}

        {screen === 'readiness' && (
          <ReadinessSheet theme={t} ai={ai} consent={consent} provider={provider}
            providers={provider ? [provider] : []}
            height={720}
            onBack={() => setScreen('bilingual')}
            onEnableAI={() => { const next = !ai; setAi(next); if (!next) setConsent(false); }}
            onConsent={() => setConsent(c => !c)}
            onAdd={() => setScreen('editor')}
            onSelect={() => {}}/>
        )}

        {screen === 'editor' && (
          <ProtoEditor t={t}
            onCancel={() => setScreen('readiness')}
            onSave={(p) => { setProvider(p); setScreen('readiness'); }}/>
        )}

        {/* When everything's ready inside the readiness sheet, a footer CTA pops to return */}
        {screen === 'readiness' && configured && (
          <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 300, padding: '0 18px 22px', pointerEvents: 'none' }}>
            <button onClick={() => { setJustChanged(true); setScreen('bilingual'); }} style={{
              width: '100%', padding: '14px 0', borderRadius: 14, border: 'none', pointerEvents: 'auto',
              background: t.accent, color: '#fff', fontFamily: 'Inter, sans-serif', fontSize: 15, fontWeight: 600,
              cursor: 'pointer', boxShadow: `0 6px 20px ${t.accent}88`,
            }}>Back to bilingual setup ›</button>
          </div>
        )}
      </div>

      <div style={{ fontFamily: 'Inter, sans-serif', fontSize: 12, color: 'rgba(0,0,0,0.4)', maxWidth: PROTO_W, textAlign: 'center', lineHeight: 1.5 }}>
        {screen === 'bilingual' && !configured && 'Tap “Set up” on the translation engine to begin.'}
        {screen === 'readiness' && !ai && 'Turn on the AI assistant to unlock consent + provider.'}
        {screen === 'readiness' && ai && !consent && 'Grant data sharing — the explicit consent step.'}
        {screen === 'readiness' && ai && consent && !provider && 'Add a provider to clear the last gate.'}
        {screen === 'readiness' && configured && 'All four gates cleared — head back to turn on bilingual.'}
        {screen === 'editor' && 'Type any key, then Save.'}
        {screen === 'bilingual' && configured && 'Engine reads “Change…”. Turn on bilingual mode.'}
        {screen === 'reader' && 'Bilingual mode is on — translations render inline.'}
      </div>
    </div>
  );
}

Object.assign(window, { Proto1394 });
