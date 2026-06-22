// Issue #1798 / Feature #110 (Android Phase-3) — AI provider + bilingual + chat.
//
// iOS has bilingual interlinear translation (#56) + AI chat (#89); Android
// needs both UIs AND a user-configured provider credential. None of these were
// in a committed bundle (rule 51). Built in VReader's vocabulary; the provider
// editor itself is the already-designed EditorSheet (vreader-ai-provider-
// fields.jsx) — this file adds the provider LIST, the bilingual interlinear
// reader + setup, and the reader AI-chat / summary panel.
//
// One credential powers all three features, so the through-line is the four
// states the issue calls out: unconfigured → configured → in-flight → error.

const AI_SERIF = '"Source Serif 4", Georgia, serif';
const AI_SANS = "'Inter', -apple-system, system-ui, sans-serif";

// ── A · provider list (the gate for everything) ──────────────
function AiProviderList({ ui, state = 'configured', height = 880 }) {
  const unconf = state === 'unconfigured';
  const providers = [
    { name: 'Claude (Anthropic)', model: 'claude-sonnet-4-6', active: true, status: 'ok' },
    { name: 'OpenAI', model: 'gpt-4o-mini', active: false, status: 'ok' },
    { name: 'DeepSeek', model: 'deepseek-chat', active: false, status: 'fail' },
  ];
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg, display: 'flex', flexDirection: 'column' }}>
        <div style={{ height: 30 }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 14px 12px', borderBottom: `0.5px solid ${ui.sep}` }}>
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
          <div style={{ flex: 1, fontFamily: AI_SERIF, fontSize: 18, fontWeight: 600, color: ui.ink }}>AI Providers</div>
          <window.Icons.Plus size={24} color={ui.tint} />
        </div>
        <div className="hide-scroll" style={{ flex: 1, overflow: 'auto', padding: '14px 16px 32px' }}>
          {unconf ? (
            <>
              <div style={{ textAlign: 'center', padding: '36px 24px 10px' }}>
                <div style={{ width: 64, height: 64, borderRadius: 32, background: ui.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.09)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
                  <window.Icons.Sparkle size={30} color={ui.tint} />
                </div>
                <div style={{ fontFamily: AI_SERIF, fontSize: 21, color: ui.ink, marginBottom: 8 }}>Connect an AI provider</div>
                <div style={{ fontFamily: AI_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.55 }}>
                  One key unlocks bilingual translation, chat about a book, and chapter summaries. Your key is stored on-device only.
                </div>
              </div>
              <button style={{ width: '100%', border: 'none', cursor: 'pointer', background: ui.tint, color: '#fff', borderRadius: 13, padding: '14px 0', fontFamily: AI_SANS, fontSize: 15, fontWeight: 600, marginTop: 18 }}>Add a provider</button>
              <GroupFooter ui={ui}>Works with Anthropic, OpenAI-compatible endpoints, and local models.</GroupFooter>
            </>
          ) : (
            <>
              <GroupHeader ui={ui}>Providers</GroupHeader>
              <Card ui={ui}>
                {providers.map((p, i) => (
                  <div key={p.name} style={{ display: 'flex', alignItems: 'center', minHeight: 60, padding: '0 14px', position: 'relative' }}>
                    {p.active
                      ? <svg width="20" height="20" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="9" fill={ui.tint}/><path d="M8 12.3l3 3 5.5-6" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>
                      : <div style={{ width: 20, height: 20, borderRadius: 10, boxShadow: `inset 0 0 0 1.7px ${ui.sep}` }} />}
                    <div style={{ flex: 1, minWidth: 0, marginLeft: 12 }}>
                      <div style={{ fontFamily: AI_SANS, fontSize: 15.5, fontWeight: 500, color: ui.ink }}>{p.name}</div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
                        <span style={{ width: 7, height: 7, borderRadius: 4, background: p.status === 'ok' ? ui.green : ui.red }} />
                        <span style={{ fontFamily: window.MONO, fontSize: 11.5, color: p.status === 'ok' ? ui.sec : ui.red }}>{p.status === 'ok' ? p.model : '401 — key rejected'}</span>
                      </div>
                    </div>
                    <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />
                    {i < providers.length - 1 && <div style={{ position: 'absolute', left: 46, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
                  </div>
                ))}
              </Card>
              <GroupFooter ui={ui}>The selected provider is used for translation, chat, and summaries. Tap one to edit or test it.</GroupFooter>
            </>
          )}
        </div>
      </div>
    </PhoneFrame>
  );
}

// ── B · bilingual interlinear reader ─────────────────────────
const BL_PAIRS = [
  ['It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.', '凡是有钱的单身汉，总想娶位太太，这已成了一条举世公认的真理。'],
  ['However little known the feelings of such a man may be, this truth is so well fixed in the minds of the surrounding families…', '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情……'],
  ['…that he is considered as the rightful property of some one or other of their daughters.', '……却把他视作自己某一个女儿理所应得的一笔财产。'],
];

function BilingualReader({ themeKey = 'paper', state = 'on', height = 880 }) {
  const t = window.THEMES[themeKey];
  const trans = t.isDark ? '#d6885a' : '#8c2f2f';
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        <window.ReaderChrome t={t} />
        {state === 'inflight' && (
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 9, padding: '6px 0 10px' }}>
            <svg className="apf-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={trans} strokeWidth="2.6" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
            <span style={{ fontFamily: AI_SANS, fontSize: 12.5, fontWeight: 600, color: trans }}>Translating chapter… 38%</span>
          </div>
        )}
        <div style={{ flex: 1, overflow: 'hidden', padding: '6px 26px 0' }}>
          {state === 'error' ? (
            <div style={{ textAlign: 'center', padding: '90px 20px' }}>
              <div style={{ width: 58, height: 58, borderRadius: 29, background: t.isDark ? 'rgba(224,119,90,0.14)' : 'rgba(168,64,47,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 16px' }}>
                <window.Icons.Translate size={28} color={trans} />
              </div>
              <div style={{ fontFamily: AI_SERIF, fontSize: 18, color: t.ink, marginBottom: 8 }}>Couldn't translate</div>
              <div style={{ fontFamily: AI_SANS, fontSize: 13.5, color: t.sub, lineHeight: 1.5, marginBottom: 18 }}>Claude returned a 429 (rate limit). The original text is unchanged — try again or switch provider.</div>
              <button style={{ border: 'none', cursor: 'pointer', background: t.accent, color: '#fff', borderRadius: 11, padding: '10px 20px', fontFamily: AI_SANS, fontSize: 14, fontWeight: 600 }}>Retry</button>
            </div>
          ) : (
            <div style={{ fontFamily: AI_SERIF, fontSize: 18, lineHeight: 1.5, color: t.ink, textWrap: 'pretty' }}>
              {BL_PAIRS.map(([en, zh], i) => (
                <div key={i} style={{ marginBottom: 19 }}>
                  <div style={{ color: state === 'inflight' && i > 0 ? t.sub : t.ink, opacity: state === 'inflight' && i > 0 ? 0.5 : 1 }}>{en}</div>
                  {(state === 'on' || (state === 'inflight' && i === 0)) && (
                    <div style={{ color: trans, fontSize: 16, marginTop: 5, lineHeight: 1.5, paddingLeft: 11, borderLeft: `2px solid ${trans}`, opacity: 0.92 }}>{zh}</div>
                  )}
                </div>
              ))}
            </div>
          )}
        </div>
        {/* bilingual toggle in a mini More-popover footer */}
        {state !== 'error' && (
          <div style={{ margin: '0 14px 14px', background: t.chrome, borderRadius: 14, border: `0.5px solid ${t.rule}`, padding: '12px 15px', display: 'flex', alignItems: 'center', gap: 11 }}>
            <window.Icons.Translate size={20} color={t.accent} />
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: AI_SANS, fontSize: 14.5, fontWeight: 600, color: t.ink }}>Bilingual mode</div>
              <div style={{ fontFamily: AI_SANS, fontSize: 11.5, color: t.sub, marginTop: 1 }}>English → 中文 · Claude · Literary</div>
            </div>
            <div style={{ width: 46, height: 28, borderRadius: 14, background: t.accent, position: 'relative' }}>
              <div style={{ position: 'absolute', top: 2, left: 20, width: 24, height: 24, borderRadius: 12, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)' }} />
            </div>
          </div>
        )}
      </div>
    </window.TtsFrame>
  );
}

function BilingualSetupSheet({ ui, height = 880 }) {
  const Seg = ({ opts, sel }) => (
    <div style={{ display: 'flex', padding: 3, borderRadius: 12, background: ui.segBg, marginTop: 8 }}>
      {opts.map((o) => {
        const on = o === sel;
        return <div key={o} style={{ flex: 1, textAlign: 'center', padding: '9px 4px', borderRadius: 10, fontFamily: AI_SANS, fontSize: 13.5, fontWeight: on ? 600 : 500, color: ui.ink, background: on ? ui.segSel : 'transparent', boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>{o}</div>;
      })}
    </div>
  );
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title="Bilingual Mode"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: AI_SANS, fontSize: 15, color: ui.sec }}>Cancel</button>}
        trailing={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: AI_SANS, fontSize: 15, fontWeight: 600, color: ui.tint }}>Translate</button>}
        height={height - 36}>
        <div style={{ padding: '16px 18px 32px' }}>
          <GroupHeader ui={ui}>Languages</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} label="From"><ValueText ui={ui} text="English (detected)" /></Row>
            <Row ui={ui} label="To" last><ValueText ui={ui} text="中文 (Simplified)" /></Row>
          </Card>

          <div style={{ height: 18 }} />
          <GroupHeader ui={ui}>Provider</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} label="Provider"><ValueText ui={ui} text="Claude (Anthropic)" /></Row>
            <Row ui={ui} label="Model" last><ValueText ui={ui} text="claude-sonnet-4-6" /></Row>
          </Card>

          <div style={{ height: 18 }} />
          <GroupHeader ui={ui}>Style</GroupHeader>
          <Seg opts={['Literal', 'Natural', 'Literary']} sel="Literary" />
          <GroupFooter ui={ui}>Literary keeps tone and rhythm at the cost of word-for-word fidelity. The original is always kept — bilingual mode shows both.</GroupFooter>

          <div style={{ height: 18 }} />
          <Card ui={ui}>
            <Row ui={ui} label="Keep term overrides" last>
              <div style={{ width: 46, height: 28, borderRadius: 14, background: ui.tint, position: 'relative' }}>
                <div style={{ position: 'absolute', top: 2, left: 20, width: 24, height: 24, borderRadius: 12, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)' }} />
              </div>
            </Row>
          </Card>
          <GroupFooter ui={ui}>~$0.04 · 7,900 tokens for this chapter. Translations are cached per chapter.</GroupFooter>
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

// ── C · AI chat + summary panel ──────────────────────────────
function AiChatPanel({ themeKey = 'paper', state = 'idle', height = 880 }) {
  const t = window.THEMES[themeKey];
  const glass = t.isDark ? 'rgba(28,26,23,0.95)' : 'rgba(252,248,240,0.98)';
  const userBubble = t.isDark ? 'rgba(214,136,90,0.18)' : 'rgba(140,47,47,0.1)';
  const unconf = state === 'unconfigured';

  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0 }}>
        {/* dimmed reader behind */}
        <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', filter: 'blur(1.5px)', opacity: 0.5 }}>
          <window.StatusStrip t={t} />
          <window.ReaderChrome t={t} />
          <div style={{ padding: '6px 26px', fontFamily: AI_SERIF, fontSize: 18, lineHeight: 1.6, color: t.ink }}>
            It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.
          </div>
        </div>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.28)' }} />

        {/* chat sheet */}
        <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, top: 96, background: glass, backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)', borderTopLeftRadius: 22, borderTopRightRadius: 22, display: 'flex', flexDirection: 'column', boxShadow: '0 -8px 28px rgba(0,0,0,0.25)' }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
            <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '12px 18px 12px', borderBottom: `0.5px solid ${t.rule}` }}>
            <window.Icons.Sparkle size={20} color={t.accent} />
            <div style={{ flex: 1, fontFamily: AI_SERIF, fontSize: 16.5, fontWeight: 600, color: t.ink }}>{state === 'summary' ? 'Chapter summary' : 'Ask about this book'}</div>
            {!unconf && <span style={{ fontFamily: AI_SANS, fontSize: 11.5, fontWeight: 600, color: t.sub, background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(29,26,20,0.05)', borderRadius: 100, padding: '4px 9px' }}>Claude</span>}
          </div>

          <div className="hide-scroll" style={{ flex: 1, overflow: 'auto', padding: '16px 18px' }}>
            {unconf && (
              <div style={{ textAlign: 'center', padding: '50px 26px' }}>
                <div style={{ width: 60, height: 60, borderRadius: 30, background: t.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.09)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
                  <window.Icons.Sparkle size={28} color={t.accent} />
                </div>
                <div style={{ fontFamily: AI_SERIF, fontSize: 19, color: t.ink, marginBottom: 8 }}>Connect a provider first</div>
                <div style={{ fontFamily: AI_SANS, fontSize: 13.5, color: t.sub, lineHeight: 1.5, marginBottom: 18 }}>Chat and summaries need an AI provider. Add one in Settings — it takes a key and a minute.</div>
                <button style={{ border: 'none', cursor: 'pointer', background: t.accent, color: '#fff', borderRadius: 11, padding: '11px 20px', fontFamily: AI_SANS, fontSize: 14, fontWeight: 600 }}>Open AI settings</button>
              </div>
            )}

            {state === 'idle' && (
              <>
                <div style={{ fontFamily: AI_SANS, fontSize: 13, color: t.sub, marginBottom: 12 }}>Ask anything about what you're reading, or try:</div>
                {['Who is Mr. Bingley?', 'Explain this sentence', 'What themes appear in Chapter 1?', 'Summarize this chapter'].map((s) => (
                  <div key={s} style={{ display: 'inline-flex', alignItems: 'center', margin: '0 8px 8px 0', fontFamily: AI_SANS, fontSize: 13.5, fontWeight: 500, color: t.ink, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)', borderRadius: 100, padding: '9px 14px' }}>{s}</div>
                ))}
              </>
            )}

            {(state === 'inflight' || state === 'answer') && (
              <>
                <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 16 }}>
                  <div style={{ maxWidth: '78%', background: userBubble, borderRadius: '16px 16px 4px 16px', padding: '10px 14px', fontFamily: AI_SANS, fontSize: 14.5, color: t.ink, lineHeight: 1.45 }}>Who is Mr. Bingley and why does he matter?</div>
                </div>
                <div style={{ display: 'flex', gap: 9 }}>
                  <window.Icons.Sparkle size={18} color={t.accent} style={{ marginTop: 2, flexShrink: 0 }} />
                  <div style={{ flex: 1 }}>
                    {state === 'inflight' ? (
                      <div style={{ display: 'flex', gap: 5, padding: '6px 0' }}>
                        {[0, 1, 2].map((i) => <span key={i} style={{ width: 7, height: 7, borderRadius: 4, background: t.sub, opacity: 0.4 }} />)}
                      </div>
                    ) : (
                      <div style={{ fontFamily: AI_SERIF, fontSize: 15.5, color: t.ink, lineHeight: 1.58 }}>
                        Mr. Bingley is the wealthy, good-natured bachelor who has just leased Netherfield Park. He matters because his arrival sets the novel's marriage plot in motion — and his easy charm is the foil against which Darcy's reserve first reads as pride.
                        <span style={{ display: 'inline-block', width: 2, height: 16, background: t.accent, verticalAlign: -3, marginLeft: 2 }} />
                      </div>
                    )}
                  </div>
                </div>
              </>
            )}

            {state === 'summary' && (
              <>
                <div style={{ background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff', borderRadius: 14, padding: '15px 16px', boxShadow: t.isDark ? 'none' : '0 1px 3px rgba(0,0,0,0.05)' }}>
                  <div style={{ fontFamily: AI_SANS, fontSize: 11.5, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', color: t.sub, marginBottom: 9 }}>Chapter 1 · 4 key points</div>
                  {[
                    'The Bennet family learns the wealthy Mr. Bingley has leased nearby Netherfield Park.',
                    'Mrs. Bennet is determined to marry one of her five daughters to him.',
                    'Mr. Bennet teases his wife but agrees to call on Bingley.',
                    'Austen establishes her ironic narrator with the famous opening line.',
                  ].map((p, i) => (
                    <div key={i} style={{ display: 'flex', gap: 9, marginBottom: 9 }}>
                      <span style={{ width: 6, height: 6, borderRadius: 3, background: t.accent, marginTop: 7, flexShrink: 0 }} />
                      <span style={{ fontFamily: AI_SERIF, fontSize: 14.5, color: t.ink, lineHeight: 1.5 }}>{p}</span>
                    </div>
                  ))}
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 12, fontFamily: AI_SANS, fontSize: 12.5, color: t.sub }}>
                  <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={t.sub} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M3 12a9 9 0 1 0 3-6.7L3 8"/><path d="M3 3v5h5"/></svg>
                  Regenerate · Claude · cached
                </div>
              </>
            )}
          </div>

          {/* input bar */}
          {!unconf && state !== 'summary' && (
            <div style={{ padding: '10px 14px 16px', borderTop: `0.5px solid ${t.rule}`, display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{ flex: 1, display: 'flex', alignItems: 'center', height: 44, borderRadius: 22, padding: '0 16px', background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)' }}>
                <span style={{ fontFamily: AI_SANS, fontSize: 15, color: t.sub }}>Ask a question…</span>
              </div>
              <div style={{ width: 44, height: 44, borderRadius: 22, background: t.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <window.Icons.Send size={20} color="#fff" />
              </div>
            </div>
          )}
        </div>
      </div>
    </window.TtsFrame>
  );
}

Object.assign(window, { AiProviderList, BilingualReader, BilingualSetupSheet, AiChatPanel });
