// Issue #1363 / Feature #79 — AI provider editor: Base URL + Model field
// pre-fill / placeholder interaction.
//
// Source of truth for the real form:
//   AIProviderEditSheet.swift            (Cancel / title / Save; sections below)
//   AIProviderEditSheet+Sections.swift   (kind / name / Endpoint / Sampling /
//                                          API Key / Connection)
//   AISettingsViewModel+Editor.swift     (canSave = name non-empty AND
//                                          validateBaseURL == nil; empty = invalid)
//   ProviderKind.swift                   (OpenAI-compatible → api.openai.com/v1 ·
//                                          gpt-4o-mini · Anthropic → api.anthropic.com
//                                          · claude-sonnet-4-6 · endpointPathHint)
//
// Rendered in VReader's own design vocabulary (the same paper/dark theme,
// bottom Sheet, Source-Serif titles, #8c2f2f accent, rounded 14 cards and
// SectionLabel rows the other canvases use), NOT generic iOS chrome.

const APP_FONT = "'Inter', -apple-system, system-ui, sans-serif";
const SERIF = '"Source Serif 4", Georgia, serif';
const MONO = 'ui-monospace, "SF Mono", "Menlo", monospace';

// Derived token sets keyed to the reader's THEMES. Paper = light, Dark = dark.
const UI = {
  light: {
    bg: '#f4eee0', sheetBg: '#fcf8f0', card: '#ffffff',
    ink: '#1d1a14', sec: 'rgba(29,26,20,0.55)', ter: 'rgba(29,26,20,0.34)',
    sep: 'rgba(29,26,20,0.12)', tint: '#8c2f2f', placeholder: 'rgba(29,26,20,0.34)',
    green: '#3a6a5a', red: '#a8402f',
    fieldHi: 'rgba(140,47,47,0.18)', segBg: 'rgba(29,26,20,0.05)', segSel: '#ffffff',
    chipBg: 'rgba(140,47,47,0.10)', tagBg: 'rgba(140,47,47,0.12)',
    codeBg: 'rgba(29,26,20,0.06)', cardShadow: '0 1px 0 rgba(0,0,0,0.04)', isDark: false,
  },
  dark: {
    bg: '#1a1815', sheetBg: '#222020', card: 'rgba(255,255,255,0.04)',
    ink: '#d8d2c5', sec: 'rgba(216,210,197,0.5)', ter: 'rgba(216,210,197,0.3)',
    sep: 'rgba(216,210,197,0.12)', tint: '#d6885a', placeholder: 'rgba(216,210,197,0.32)',
    green: '#5a9a7a', red: '#e0775a',
    fieldHi: 'rgba(214,136,90,0.26)', segBg: 'rgba(255,255,255,0.06)', segSel: '#3a3530',
    chipBg: 'rgba(214,136,90,0.16)', tagBg: 'rgba(214,136,90,0.20)',
    codeBg: 'rgba(216,210,197,0.10)', cardShadow: 'none', isDark: true,
  },
};

const KIND = {
  openai: { name: 'OpenAI-compatible', baseURL: 'https://api.openai.com/v1', model: 'gpt-4o-mini',
    hintPath: '/chat/completions', hintEx: 'https://api.openai.com/v1' },
  anthropic: { name: 'Anthropic', baseURL: 'https://api.anthropic.com', model: 'claude-sonnet-4-6',
    hintPath: '/v1/messages', hintEx: 'https://api.anthropic.com' },
};

// One-time caret-blink + input reset
if (typeof document !== 'undefined' && !document.getElementById('apf-css')) {
  const s = document.createElement('style');
  s.id = 'apf-css';
  s.textContent = `
    @keyframes apfBlink { 0%,49%{opacity:1} 50%,100%{opacity:0} }
    @keyframes apfSpin { to { transform: rotate(360deg); } }
    .apf-spin{ animation: apfSpin .8s linear infinite; }
    .apf-caret{ display:inline-block; width:2px; height:18px; border-radius:1px;
      margin-left:1px; vertical-align:-3px; animation: apfBlink 1.06s step-end infinite; }
    .apf-input{ font-family:${APP_FONT}; font-size:15px;
      border:none; outline:none; background:transparent; text-align:right; padding:0; margin:0;
      width:100%; min-width:0; }
  `;
  document.head.appendChild(s);
}

// ── primitives ─────────────────────────────────────────────
function Sep({ ui, inset = 14 }) {
  return <div style={{ position: 'absolute', left: inset, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />;
}

function Code({ ui, children }) {
  return <span style={{
    fontFamily: MONO, fontSize: '0.88em', background: ui.codeBg,
    borderRadius: 4, padding: '1px 4px', color: ui.sec,
  }}>{children}</span>;
}

// SectionLabel — matches vreader-panels' SectionLabel.
function GroupHeader({ ui, children }) {
  return <div style={{
    fontFamily: APP_FONT, fontSize: 12, fontWeight: 600, color: ui.sec,
    letterSpacing: 0.8, textTransform: 'uppercase', padding: '0 2px',
  }}>{children}</div>;
}

function GroupFooter({ ui, children }) {
  return <div style={{
    fontFamily: APP_FONT, fontSize: 12, lineHeight: 1.45, color: ui.sec,
    padding: '8px 4px 0',
  }}>{children}</div>;
}

function Card({ ui, children, style }) {
  return <div style={{
    marginTop: 8, background: ui.card, borderRadius: 14, overflow: 'hidden',
    boxShadow: ui.cardShadow, ...style,
  }}>{children}</div>;
}

// 48px form row: left label + right content + bottom hairline.
function Row({ ui, label, last, focused, children, minH = 48 }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', minHeight: minH, padding: '0 14px',
      position: 'relative', fontFamily: APP_FONT, fontSize: 15,
      background: focused ? ui.fieldHi : 'transparent',
      boxShadow: focused ? `inset 0 0 0 1.5px ${ui.tint}` : 'none',
      borderRadius: focused ? 10 : 0, transition: 'background .15s',
    }}>
      {label != null && <div style={{ color: ui.sec, flexShrink: 0, marginRight: 10, whiteSpace: 'nowrap' }}>{label}</div>}
      <div style={{ flex: 1, minWidth: 0, display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 8 }}>
        {children}
      </div>
      {!last && !focused && <Sep ui={ui} />}
    </div>
  );
}

function ValueText({ ui, text, tone = 'value', caret, caretAt = 'end' }) {
  const ph = tone === 'placeholder';
  const node = tone === 'selected'
    ? <span style={{ background: ui.fieldHi, borderRadius: 3, padding: '1px 2px', color: ui.ink, whiteSpace: 'nowrap' }}>{text}</span>
    : <span style={{ color: ph ? ui.placeholder : ui.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{text}</span>;
  const caretEl = <span className="apf-caret" style={{ background: ui.tint }} />;
  return (
    <div style={{ display: 'flex', alignItems: 'center', minWidth: 0, fontFamily: APP_FONT, fontSize: 15 }}>
      {caret && caretAt === 'start' && caretEl}
      {node}
      {caret && caretAt === 'end' && caretEl}
    </div>
  );
}

function Tag({ ui, children, tone = 'tint' }) {
  return <span style={{
    fontFamily: APP_FONT, fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3,
    textTransform: 'uppercase',
    color: tone === 'tint' ? ui.tint : ui.sec,
    background: tone === 'tint' ? ui.tagBg : ui.codeBg,
    borderRadius: 5, padding: '2px 6px', flexShrink: 0, whiteSpace: 'nowrap',
  }}>{children}</span>;
}

// ── segmented kind picker (matches the reader Font/Layout pill toggles) ──
function Segmented({ ui, value = 'openai' }) {
  const opts = [['openai', 'OpenAI-compatible'], ['anthropic', 'Anthropic']];
  return (
    <div style={{
      display: 'flex', marginTop: 8, gap: 0, padding: 3, borderRadius: 12, background: ui.segBg,
    }}>
      {opts.map(([k, label]) => {
        const sel = k === value;
        return (
          <div key={k} style={{
            flex: 1, textAlign: 'center', padding: '9px 4px', borderRadius: 10,
            fontFamily: APP_FONT, fontSize: 13.5, fontWeight: sel ? 600 : 500,
            color: ui.ink, background: sel ? ui.segSel : 'transparent',
            boxShadow: sel ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
          }}>{label}</div>
        );
      })}
    </div>
  );
}

// ── sampling controls ──────────────────────────────────────
function SamplingGroup({ ui }) {
  const p = 0.7 / 2.0;
  return (
    <Card ui={ui}>
      <div style={{ padding: '12px 14px', position: 'relative' }}>
        <div style={{ display: 'flex', alignItems: 'center', fontFamily: APP_FONT, fontSize: 15 }}>
          <span style={{ color: ui.sec }}>Temperature</span>
          <span style={{ flex: 1 }} />
          <span style={{ color: ui.ink, fontVariantNumeric: 'tabular-nums' }}>0.7</span>
        </div>
        <div style={{ marginTop: 12, height: 4, borderRadius: 2, background: ui.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)', position: 'relative' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${p * 100}%`, background: ui.tint, borderRadius: 2 }} />
          <div style={{ position: 'absolute', left: `${p * 100}%`, top: '50%', width: 22, height: 22, borderRadius: 11, background: '#fff', transform: 'translate(-50%,-50%)', boxShadow: '0 1px 4px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.06)' }} />
        </div>
        <Sep ui={ui} />
      </div>
      <Row ui={ui} last>
        <div style={{ display: 'flex', alignItems: 'center', width: '100%', fontFamily: APP_FONT, fontSize: 15 }}>
          <span style={{ color: ui.ink, whiteSpace: 'nowrap' }}>Max Tokens: 2048</span>
          <span style={{ flex: 1 }} />
          <div style={{ display: 'flex', alignItems: 'stretch', borderRadius: 8, overflow: 'hidden', background: ui.segBg, height: 30 }}>
            <div style={{ width: 42, display: 'flex', alignItems: 'center', justifyContent: 'center', color: ui.ink, fontSize: 19 }}>−</div>
            <div style={{ width: 0.5, background: ui.sep }} />
            <div style={{ width: 42, display: 'flex', alignItems: 'center', justifyContent: 'center', color: ui.ink, fontSize: 19 }}>+</div>
          </div>
        </div>
      </Row>
    </Card>
  );
}

// ════════════════════════════════════════════════════════════
// EndpointFields — the heart of the design.
//   variant: 'today' | 'A' | 'B' | 'C'
//   state:   'rest' | 'focus' | 'typed' | 'edit'
// ════════════════════════════════════════════════════════════
function EndpointFields({ ui, variant, state, kind = 'openai' }) {
  const d = KIND[kind];
  const typedURL = 'https://openrouter.ai/api/v1';
  const typedModel = 'anthropic/claude-3.5-sonnet';
  const savedURL = 'https://api.deepseek.com/v1';
  const savedModel = 'deepseek-chat';

  let url, model, chip = null, resetLink = false, urlFocused = false;

  if (variant === 'today') {
    if (state === 'edit') { url = <ValueText ui={ui} text={savedURL} />; model = <ValueText ui={ui} text={savedModel} />; }
    else if (state === 'typed') { url = <ValueText ui={ui} text={typedURL} />; model = <ValueText ui={ui} text={typedModel} />; }
    else if (state === 'focus') { url = <ValueText ui={ui} text={d.baseURL} caret />; model = <ValueText ui={ui} text={d.model} />; urlFocused = true; }
    else { url = <ValueText ui={ui} text={d.baseURL} />; model = <ValueText ui={ui} text={d.model} />; }
  }

  if (variant === 'A') {
    if (state === 'edit') {
      url = <ValueText ui={ui} text={savedURL} />; model = <ValueText ui={ui} text={savedModel} />;
    } else if (state === 'typed') {
      url = <ValueText ui={ui} text={typedURL} />; model = <ValueText ui={ui} text={typedModel} />;
    } else if (state === 'focus') {
      url = <ValueText ui={ui} text={d.baseURL} tone="placeholder" caret caretAt="start" />; urlFocused = true;
      model = <><ValueText ui={ui} text={d.model} tone="placeholder" /><Tag ui={ui}>Default</Tag></>;
    } else {
      url = <><ValueText ui={ui} text={d.baseURL} tone="placeholder" /><Tag ui={ui}>Default</Tag></>;
      model = <><ValueText ui={ui} text={d.model} tone="placeholder" /><Tag ui={ui}>Default</Tag></>;
    }
  }

  if (variant === 'B') {
    if (state === 'edit') {
      url = <ValueText ui={ui} text={savedURL} />; model = <ValueText ui={ui} text={savedModel} />;
    } else if (state === 'typed') {
      url = <ValueText ui={ui} text={typedURL} />; model = <ValueText ui={ui} text={typedModel} />; resetLink = true;
    } else if (state === 'focus') {
      url = <ValueText ui={ui} text={d.baseURL} tone="selected" caret />; urlFocused = true;
      model = <ValueText ui={ui} text={d.model} />;
    } else {
      url = <ValueText ui={ui} text={d.baseURL} />; model = <ValueText ui={ui} text={d.model} />;
    }
  }

  if (variant === 'C') {
    if (state === 'edit') {
      url = <ValueText ui={ui} text={savedURL} />; model = <ValueText ui={ui} text={savedModel} />;
    } else if (state === 'typed') {
      url = <ValueText ui={ui} text={d.baseURL} />; model = <ValueText ui={ui} text={d.model} />; resetLink = true;
    } else if (state === 'focus') {
      url = <ValueText ui={ui} text="https://api.example.com/v1" tone="placeholder" caret caretAt="start" />; urlFocused = true;
      model = <ValueText ui={ui} text="e.g. gpt-4o-mini" tone="placeholder" />;
      chip = 'fill';
    } else {
      url = <ValueText ui={ui} text="https://api.example.com/v1" tone="placeholder" />;
      model = <ValueText ui={ui} text="e.g. gpt-4o-mini" tone="placeholder" />;
      chip = 'fill';
    }
  }

  return (
    <Card ui={ui}>
      <Row ui={ui} label="Base URL" focused={urlFocused}>{url}</Row>
      <Row ui={ui} label="Model" last={!chip && !resetLink}>{model}</Row>
      {chip === 'fill' && (
        <Row ui={ui} last>
          <div style={{ display: 'flex', width: '100%', justifyContent: 'flex-start' }}>
            <span style={{
              display: 'inline-flex', alignItems: 'center', gap: 6,
              fontFamily: APP_FONT, fontSize: 13.5, fontWeight: 500, color: ui.tint,
              background: ui.chipBg, borderRadius: 100, padding: '6px 12px',
            }}>
              <span style={{ fontSize: 15, lineHeight: 0, marginTop: -1 }}>＋</span>
              Use {KIND[kind].name} defaults
            </span>
          </div>
        </Row>
      )}
      {resetLink && (
        <Row ui={ui} last>
          <div style={{ display: 'flex', width: '100%', justifyContent: 'flex-start' }}>
            <span style={{ fontFamily: APP_FONT, fontSize: 13.5, fontWeight: 500, color: ui.tint }}>Reset to default</span>
          </div>
        </Row>
      )}
    </Card>
  );
}

function endpointFooter(ui, variant, kind = 'openai') {
  const d = KIND[kind];
  const pathHint = (
    <>Enter the base URL only — the app appends <Code ui={ui}>{d.hintPath}</Code>. Example: <Code ui={ui}>{d.hintEx}</Code>.</>
  );
  if (variant === 'A' || variant === 'C') {
    return (
      <>{pathHint}<br /><span style={{ color: ui.ink, opacity: ui.isDark ? 0.85 : 0.72 }}>
        Leave blank to use the {d.name} default ({d.model}). It’s stored on Save.
      </span></>
    );
  }
  return pathHint;
}

// ── standalone close-up: the Endpoint section in one state ──
function EndpointCard({ ui, variant, state, kind = 'openai', caption, width = 430 }) {
  return (
    <div style={{ width, height: '100%', background: ui.bg, padding: '18px 18px 20px', fontFamily: APP_FONT }}>
      {caption && (
        <div style={{ paddingBottom: 12, fontFamily: APP_FONT, fontSize: 11.5, fontWeight: 600, color: ui.tint, letterSpacing: 0.3 }}>
          {caption}
        </div>
      )}
      <GroupHeader ui={ui}>Endpoint</GroupHeader>
      <EndpointFields ui={ui} variant={variant} state={state} kind={kind} />
      <GroupFooter ui={ui}>{endpointFooter(ui, variant, kind)}</GroupFooter>
    </div>
  );
}

// ── phone + bottom sheet, in the app's vocabulary ──────────
function PhoneFrame({ ui, height = 880, children }) {
  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: ui.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
      fontFamily: APP_FONT, WebkitFontSmoothing: 'antialiased',
    }}>{children}</div>
  );
}

function AppSheet({ ui, title, leading, trailing, height = 844, children }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 200, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.35)' }}>
      <div style={{
        background: ui.sheetBg, height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)', display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
        </div>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 18px 12px', borderBottom: `0.5px solid ${ui.sep}`,
        }}>
          <div style={{ width: 60 }}>{leading}</div>
          <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: ui.ink, whiteSpace: 'nowrap' }}>{title}</div>
          <div style={{ width: 60, display: 'flex', justifyContent: 'flex-end' }}>{trailing}</div>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }} className="hide-scroll">{children}</div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════════════
// EditorSheet — the full AIProviderEditSheet in the app's style.
// ════════════════════════════════════════════════════════════
function EditorSheet({ ui, variant = 'A', state = 'rest', kind = 'openai', mode = 'add', test = 'enabled', keyEntered = true, height = 880 }) {
  const editMode = mode === 'edit' || state === 'edit';
  const eff = editMode ? 'edit' : state;
  const name = editMode ? 'DeepSeek' : 'OpenRouter';
  const saveEnabled = true; // name filled; A/C empty→default valid, B never empty
  // Test runs against live form state + the typed in-memory key — no Save first.
  const testEnabled = keyEntered && test !== 'disabled';
  const testResult = test === 'ok' || test === 'fail';

  const Cancel = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 15, color: ui.sec, cursor: 'pointer' }}>Cancel</button>;
  const Save = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, color: saveEnabled ? ui.tint : ui.ter, cursor: 'pointer' }}>Save</button>;

  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title={editMode ? 'Edit Provider' : 'Add Provider'} leading={Cancel} trailing={Save} height={height - 36}>
        <div style={{ padding: '16px 18px 32px' }}>
          {/* Provider Type */}
          <GroupHeader ui={ui}>Provider Type</GroupHeader>
          <Segmented ui={ui} value={kind} />

          {/* Name */}
          <div style={{ height: 20 }} />
          <GroupHeader ui={ui}>Name</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} last><ValueText ui={ui} text={name} tone={name ? 'value' : 'placeholder'} /></Row>
          </Card>

          {/* Endpoint */}
          <div style={{ height: 20 }} />
          <GroupHeader ui={ui}>Endpoint</GroupHeader>
          <EndpointFields ui={ui} variant={variant} state={eff} kind={kind} />
          <GroupFooter ui={ui}>{endpointFooter(ui, editMode ? 'edit' : variant, kind)}</GroupFooter>

          {/* Sampling */}
          <div style={{ height: 20 }} />
          <GroupHeader ui={ui}>Sampling</GroupHeader>
          <SamplingGroup ui={ui} />

          {/* API Key */}
          <div style={{ height: 20 }} />
          <GroupHeader ui={ui}>API Key</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} last={!editMode}>
              <div style={{ display: 'flex', alignItems: 'center', width: '100%' }}>
                {keyEntered
                  ? <span style={{ fontFamily: APP_FONT, fontSize: 16, letterSpacing: 2, color: ui.ink }}>{'•'.repeat(14)}</span>
                  : <span style={{ fontFamily: APP_FONT, fontSize: 15, color: ui.placeholder }}>Enter API Key</span>}
                <span style={{ flex: 1 }} />
                {editMode && keyEntered && (
                  <svg width="19" height="19" viewBox="0 0 24 24" fill="none">
                    <circle cx="12" cy="12" r="10" fill={ui.green} />
                    <path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none" />
                  </svg>
                )}
              </div>
            </Row>
            {editMode && (
              <Row ui={ui} last>
                <div style={{ display: 'flex', width: '100%', gap: 22, justifyContent: 'flex-start' }}>
                  <span style={{ fontFamily: APP_FONT, fontSize: 15, color: ui.tint }}>Save Key</span>
                  <span style={{ fontFamily: APP_FONT, fontSize: 15, color: ui.red }}>Delete Key</span>
                </div>
              </Row>
            )}
          </Card>
          {!editMode && (
            <GroupFooter ui={ui}>
              Saved to the keychain when you tap Save — but you can test it below first.
            </GroupFooter>
          )}

          {/* Connection — testable as soon as a key is entered, no Save first */}
          <div style={{ height: 20 }} />
          <GroupHeader ui={ui}>Connection</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} last={!testResult}>
              <div style={{ display: 'flex', width: '100%', justifyContent: 'flex-start' }}>
                <span style={{
                  display: 'inline-flex', alignItems: 'center', gap: 7,
                  fontFamily: APP_FONT, fontSize: 14, fontWeight: 600,
                  color: testEnabled ? ui.tint : ui.ter,
                  background: testEnabled ? ui.chipBg : 'transparent',
                  boxShadow: testEnabled ? 'none' : `inset 0 0 0 1px ${ui.sep}`,
                  borderRadius: 100, padding: '8px 15px',
                }}>
                  {test === 'testing' ? (
                    <svg className="apf-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.4" strokeLinecap="round">
                      <path d="M12 3a9 9 0 1 0 9 9" />
                    </svg>
                  ) : (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={testEnabled ? ui.tint : ui.ter} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M13 2L3 14h7l-1 8 10-12h-7l1-8z" />
                    </svg>
                  )}
                  {test === 'testing' ? 'Testing…' : 'Test Connection'}
                </span>
              </div>
            </Row>
            {testResult && (
              <Row ui={ui} last>
                <div style={{ display: 'flex', alignItems: 'center', gap: 7, width: '100%', justifyContent: 'flex-start' }}>
                  {test === 'ok' ? (
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" fill={ui.green} />
                      <path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none" />
                    </svg>
                  ) : (
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none">
                      <circle cx="12" cy="12" r="10" fill={ui.red} />
                      <path d="M8 8l8 8M16 8l-8 8" stroke="#fff" strokeWidth="2" strokeLinecap="round" />
                    </svg>
                  )}
                  <span style={{ fontFamily: APP_FONT, fontSize: 13.5, color: test === 'ok' ? ui.green : ui.red }}>
                    {test === 'ok' ? 'Connected — the provider responded successfully.' : 'Failed: 401 Unauthorized — check your API key.'}
                  </span>
                </div>
              </Row>
            )}
          </Card>
          {!testEnabled && (
            <GroupFooter ui={ui}>Enter an API key above to test — no need to save first.</GroupFooter>
          )}
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════════════
// LiveField — interactive specimen.
// ════════════════════════════════════════════════════════════
function LiveField({ ui, variant = 'A', kind = 'openai' }) {
  const d = KIND[kind];
  const [url, setUrl] = React.useState(variant === 'B' ? d.baseURL : '');
  const [model, setModel] = React.useState(variant === 'B' ? d.model : '');
  const [focus, setFocus] = React.useState(null);

  const effURL = url.trim() === '' ? d.baseURL : url.trim();
  const effModel = model.trim() === '' ? d.model : model.trim();

  const field = (val, set, nm, ph) => (
    <Row ui={ui} label={nm} last={nm === 'Model'} focused={focus === nm}>
      <input className="apf-input" style={{ color: ui.ink, caretColor: ui.tint }}
        value={val} placeholder={ph} onChange={(e) => set(e.target.value)}
        onFocus={(e) => { setFocus(nm); if (variant === 'B') e.target.select(); }}
        onBlur={() => setFocus(null)} spellCheck={false} autoCapitalize="off" autoCorrect="off" />
    </Row>
  );

  return (
    <div style={{ width: 430, height: '100%', background: ui.bg, padding: '18px 18px 20px', fontFamily: APP_FONT }}>
      <style>{`.apf-input::placeholder{ color:${ui.placeholder}; opacity:1; }`}</style>
      <GroupHeader ui={ui}>Endpoint — focus &amp; type</GroupHeader>
      <Card ui={ui}>
        {field(url, setUrl, 'Base URL', variant === 'C' ? 'https://api.example.com/v1' : d.baseURL)}
        {field(model, setModel, 'Model', variant === 'C' ? 'e.g. gpt-4o-mini' : d.model)}
      </Card>
      <GroupFooter ui={ui}>{endpointFooter(ui, variant, kind)}</GroupFooter>

      <div style={{ marginTop: 16, padding: '12px 14px', borderRadius: 14, background: ui.card, boxShadow: ui.cardShadow }}>
        <div style={{ fontFamily: APP_FONT, fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: ui.sec, marginBottom: 8 }}>
          What Save would store
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 6, fontFamily: APP_FONT, fontSize: 13.5 }}>
          <span style={{ color: ui.sec, width: 62 }}>Base URL</span>
          <span style={{ color: ui.ink, fontFamily: MONO, fontSize: 12.5 }}>{effURL}</span>
          {url.trim() === '' && <Tag ui={ui}>default</Tag>}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: APP_FONT, fontSize: 13.5 }}>
          <span style={{ color: ui.sec, width: 62 }}>Model</span>
          <span style={{ color: ui.ink, fontFamily: MONO, fontSize: 12.5 }}>{effModel}</span>
          {model.trim() === '' && <Tag ui={ui}>default</Tag>}
        </div>
      </div>
    </div>
  );
}

Object.assign(window, {
  UI, KIND, APP_FONT, SERIF, MONO,
  Sep, Code, GroupHeader, GroupFooter, Card, Row, ValueText, Tag,
  Segmented, SamplingGroup, EndpointFields, endpointFooter, EndpointCard,
  PhoneFrame, AppSheet, EditorSheet, LiveField,
});
