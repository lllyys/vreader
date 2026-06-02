// In-reader AI-enable + consent affordance — issue #1394.
//
// Follow-up to feature #81 / #1380 (the in-reader AI Providers list reached from
// the bilingual "Set up" button). #81 lets a user add a provider + key in-reader
// — but BilingualAIReadiness.resolve needs ALL FOUR:
//     aiAssistant flag ON · AI consent granted · active provider · non-empty key
// On a fresh device the flag + consent default OFF, so a user who only adds a
// provider in-reader STILL sees "Set up" — the payoff only completes after a trip
// to Library → Settings → AI. This closes that gap inside the reader.
//
// CANONICAL (A): the scoped sheet reached from "Set up" becomes a "Set up
//   translation" surface that makes the full readiness legible and actionable in
//   one place — a 3-step readiness tracker, then the master AI toggle, then an
//   explicit full-disclosure consent card, then the #81 provider list. Consent is
//   never auto-granted: it requires its own toggle on a card that names exactly
//   what leaves the device. When all gates clear, the sheet shows the payoff and
//   popping back to Bilingual reads "Change…" instead of "Set up".
//
// ALTERNATIVES:
//   B — a guided 1·2·3 stepper (Enable → Consent → Provider), one step at a time.
//   C — a pre-flight enable+consent gate shown BEFORE the provider editor.
//
// Reuses: NavSheet, BilingualEngineStrip, ProviderRow (vreader-ai-provider-entry),
//   ShieldIcon (vreader-ai-toggles), Sheet, SectionLabel, PillSwitch, Icons, THEMES.

const RDY_BRAND  = '#8c2f2f';   // AI assistant tile (theme-independent brand)
const RDY_SHIELD = '#4a6a8a';   // consent / privacy tile
const RDY_GREEN  = '#3a6a5a';   // "satisfied" — matches PillSwitch ON
const RDY_MONO   = 'ui-monospace, "SF Mono", "Menlo", monospace';
const RDY_SERIF  = '"Source Serif 4", Georgia, serif';

// ════════════════════════════════════════════════════
// ReadinessTracker — the three gates as a connected progress row.
// states: 'done' | 'active' | 'todo'. The API-key gate rides inside the
// provider gate (a saved provider always carries a key), so three user-facing
// steps map to the four BilingualAIReadiness requirements.
// ════════════════════════════════════════════════════
function ReadinessTracker({ theme: t, ai, consent, provider }) {
  const steps = [
    { key: 'ai',       label: 'Turn on AI',  done: ai },
    { key: 'consent',  label: 'Allow data',  done: consent },
    { key: 'provider', label: 'Add provider', done: !!provider },
  ];
  // first not-done step is "active"
  const activeIdx = steps.findIndex(s => !s.done);
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', padding: '2px 2px 0' }}>
      {steps.map((s, i) => {
        const state = s.done ? 'done' : (i === activeIdx ? 'active' : 'todo');
        const circleBg = state === 'done' ? RDY_GREEN : (state === 'active' ? t.accent : 'transparent');
        const circleBorder = state === 'todo'
          ? `1.5px solid ${t.isDark ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.18)'}` : 'none';
        return (
          <React.Fragment key={s.key}>
            <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', width: 64, flexShrink: 0 }}>
              <div style={{
                width: 26, height: 26, borderRadius: 13, flexShrink: 0,
                background: circleBg, border: circleBorder,
                boxShadow: state === 'active' ? `0 0 0 3px ${t.accent}28` : 'none',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: state === 'todo' ? t.sub : '#fff',
                fontSize: 12, fontWeight: 700,
                transition: 'background 0.25s, box-shadow 0.25s',
              }}>
                {s.done ? <Icons.Check size={15} color="#fff" stroke={2.8}/> : (i + 1)}
              </div>
              <div style={{
                marginTop: 6, fontSize: 10.5, lineHeight: 1.2, textAlign: 'center',
                color: state === 'todo' ? t.sub : t.ink,
                fontWeight: state === 'active' ? 700 : 500,
              }}>{s.label}</div>
            </div>
            {i < steps.length - 1 && (
              <div style={{
                flex: 1, height: 2, borderRadius: 1, marginTop: 12,
                background: steps[i].done
                  ? RDY_GREEN
                  : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)'),
                transition: 'background 0.25s',
              }}/>
            )}
          </React.Fragment>
        );
      })}
    </div>
  );
}

// ════════════════════════════════════════════════════
// EnableAIRow — the master gate (aiAssistant flag). Colored-tile toggle row,
// same vocabulary as the shipped SettingsToggleRow / AI Provider row.
// ════════════════════════════════════════════════════
function EnableAIRow({ theme: t, on, onToggle, last }) {
  return (
    <button onClick={onToggle} style={{
      display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left',
      padding: '13px 14px', border: 'none', background: 'transparent', cursor: 'pointer',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`, fontFamily: 'inherit',
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0, background: RDY_BRAND,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Sparkle size={17} color="#fff" stroke={1.8}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15, color: t.ink }}>Enable AI assistant</div>
        <div style={{ fontSize: 11, color: t.sub, marginTop: 1, lineHeight: 1.35 }}>
          Powers translation, summaries, and asking about the text.
        </div>
      </div>
      <PillSwitch on={!!on} theme={t}/>
    </button>
  );
}

// ════════════════════════════════════════════════════
// ConsentDisclosureCard — full-disclosure consent (adapts #1068 Variant C to the
// bilingual context). A shield tile + explicit toggle, then a two-column ledger
// naming exactly what is sent vs. what stays on device. Consent is granted ONLY
// by this toggle — turning on the assistant does not imply it.
//   locked  → AI is still off; card is dimmed and non-interactive.
// ════════════════════════════════════════════════════
function ConsentDisclosureCard({ theme: t, on, onToggle, locked = false }) {
  return (
    <div style={{
      padding: '14px 16px 16px', borderRadius: 14,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      border: !locked && !on ? `0.5px solid ${t.accent}44` : `0.5px solid ${t.rule}`,
      opacity: locked ? 0.5 : 1,
      pointerEvents: locked ? 'none' : 'auto',
      transition: 'opacity 0.2s',
    }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
        <div style={{
          width: 30, height: 30, borderRadius: 8, flexShrink: 0, marginTop: 1, background: RDY_SHIELD,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <ShieldIcon size={17} color="#fff" stroke={1.8}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 15, color: t.ink }}>Allow AI data sharing</div>
          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 2, lineHeight: 1.4 }}>
            Required to translate — paragraphs are sent to your provider as you read.
          </div>
        </div>
        <button onClick={onToggle} disabled={locked} style={{
          background: 'none', border: 'none', padding: 0, cursor: locked ? 'default' : 'pointer',
        }}>
          <PillSwitch on={!!on} theme={t}/>
        </button>
      </div>

      <div style={{
        marginTop: 12, paddingTop: 12, borderTop: `0.5px solid ${t.rule}`,
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14,
      }}>
        <div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 5, marginBottom: 5,
            fontSize: 10, letterSpacing: 0.5, textTransform: 'uppercase',
            color: t.accent, fontWeight: 700,
          }}>
            <Icons.Send size={11} color={t.accent} stroke={2}/>Sent to provider
          </div>
          <div style={{ fontSize: 12, color: t.ink, lineHeight: 1.65 }}>
            Paragraphs being read<br/>Target language<br/>Surrounding context
          </div>
        </div>
        <div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 5, marginBottom: 5,
            fontSize: 10, letterSpacing: 0.5, textTransform: 'uppercase',
            color: RDY_GREEN, fontWeight: 700,
          }}>
            <ShieldIcon size={11} color={RDY_GREEN} stroke={2}/>Stays on device
          </div>
          <div style={{ fontSize: 12, color: t.ink, lineHeight: 1.65 }}>
            Library &amp; position<br/>Highlights &amp; notes<br/>Provider API keys
          </div>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// ReadyBanner — the all-gates-clear payoff, shown at the foot of the sheet.
// ════════════════════════════════════════════════════
function ReadyBanner({ theme: t, providerName = 'Claude' }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12, marginTop: 18,
      padding: '13px 15px', borderRadius: 14,
      background: `${RDY_GREEN}14`, border: `0.5px solid ${RDY_GREEN}55`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 15, flexShrink: 0, background: RDY_GREEN,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Check size={17} color="#fff" stroke={3}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: t.ink }}>Ready to translate</div>
        <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1, lineHeight: 1.35 }}>
          {providerName} is connected. Go back to turn on bilingual mode.
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Provider block — the #81 list, restated compactly so the readiness sheet owns
// its own layout. Empty → Add CTA; populated → rows + Add.
// ════════════════════════════════════════════════════
function ReadinessProviderBlock({ theme: t, providers = [], selectedId, onAdd, onSelect, locked }) {
  const empty = providers.length === 0;
  if (empty) {
    return (
      <button onClick={onAdd} disabled={locked} style={{
        display: 'flex', alignItems: 'center', gap: 12, width: '100%', textAlign: 'left',
        padding: '13px 14px', borderRadius: 14, cursor: locked ? 'default' : 'pointer',
        background: locked ? 'transparent' : `${t.accent}0e`,
        border: locked ? `0.5px dashed ${t.rule}` : `0.5px solid ${t.accent}44`,
        fontFamily: 'inherit', opacity: locked ? 0.5 : 1, transition: 'opacity 0.2s',
      }}>
        <div style={{
          width: 30, height: 30, borderRadius: 8, flexShrink: 0,
          background: locked ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)') : t.accent,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Plus size={18} color={locked ? t.sub : '#fff'} stroke={2.2}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 15, color: locked ? t.sub : t.ink, fontWeight: 500 }}>Add a provider</div>
          <div style={{ fontSize: 11, color: t.sub, marginTop: 1, lineHeight: 1.35 }}>
            Claude, OpenAI, or any compatible endpoint. Key stays in the keychain.
          </div>
        </div>
      </button>
    );
  }
  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
    }}>
      {providers.map(p => (
        <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
          selected={p.id === selectedId} onClick={() => onSelect && onSelect(p.id)}/>
      ))}
      <div onClick={onAdd} style={{
        display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', cursor: 'pointer',
      }}>
        <div style={{
          width: 30, height: 30, borderRadius: 8, flexShrink: 0,
          background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Plus size={18} color={t.accent} stroke={2.2}/>
        </div>
        <div style={{ flex: 1, fontSize: 15, color: t.accent, fontWeight: 500 }}>Add provider</div>
      </div>
    </div>
  );
}

// little uppercase mini-label with an inline state hint on the right
function StepLabel({ theme: t, children, hint, hintColor }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 8 }}>
      <SectionLabel theme={t}>{children}</SectionLabel>
      {hint && (
        <span style={{ fontSize: 10.5, fontWeight: 600, color: hintColor || t.sub, letterSpacing: 0.3 }}>{hint}</span>
      )}
    </div>
  );
}

// ════════════════════════════════════════════════════
// CANONICAL — ReadinessSheetBody
// gates: { ai, consent, provider }  (provider = null | providerObj)
// ════════════════════════════════════════════════════
function ReadinessSheetBody({ theme: t, ai, consent, provider, providers = [],
                              onEnableAI, onConsent, onAdd, onSelect }) {
  const allReady = ai && consent && !!provider;
  return (
    <div style={{ padding: '14px 18px 28px' }}>
      {/* why-you're-here — the bilingual thread, kept visible */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 12px', borderRadius: 10, marginBottom: 16,
        background: `${t.accent}10`, border: `0.5px solid ${t.accent}33`,
      }}>
        <div style={{
          width: 22, height: 22, borderRadius: 11, flexShrink: 0, background: `${t.accent}1f`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Translate size={13} color={t.accent} stroke={1.9}/>
        </div>
        <div style={{ fontSize: 11.5, color: t.ink, lineHeight: 1.35 }}>
          Three steps to translate <b style={{ fontWeight: 600 }}>this book</b> with AI — all without leaving the reader.
        </div>
      </div>

      <ReadinessTracker theme={t} ai={ai} consent={consent} provider={provider}/>

      {/* Step 1 — master gate */}
      <div style={{ marginTop: 20 }}>
        <StepLabel theme={t} hint={ai ? 'On' : null} hintColor={RDY_GREEN}>1 · AI assistant</StepLabel>
        <div style={{
          borderRadius: 14, overflow: 'hidden',
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
        }}>
          <EnableAIRow theme={t} on={ai} onToggle={onEnableAI} last/>
        </div>
        {!ai && (
          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, padding: '8px 4px 0' }}>
            Off everywhere by default. Turn it on to grant consent and connect a provider below.
          </div>
        )}
      </div>

      {/* Step 2 — explicit consent */}
      <div style={{ marginTop: 18 }}>
        <StepLabel theme={t} hint={consent ? 'Granted' : (ai ? 'Action needed' : null)}
          hintColor={consent ? RDY_GREEN : t.accent}>2 · Data &amp; privacy</StepLabel>
        <ConsentDisclosureCard theme={t} on={consent} onToggle={onConsent} locked={!ai}/>
      </div>

      {/* Step 3 — provider (reuses #81) */}
      <div style={{ marginTop: 18 }}>
        <StepLabel theme={t}
          hint={provider ? `${provider.name} · key saved` : (ai && consent ? 'Action needed' : null)}
          hintColor={provider ? RDY_GREEN : t.accent}>3 · Provider</StepLabel>
        <ReadinessProviderBlock theme={t} providers={providers} selectedId={provider && provider.id}
          onAdd={onAdd} onSelect={onSelect} locked={!ai}/>
      </div>

      {allReady && <ReadyBanner theme={t} providerName={provider.name}/>}
    </div>
  );
}

function ReadinessSheet({ theme, ai, consent, provider, providers, height = 720,
                          onBack, onEnableAI, onConsent, onAdd, onSelect }) {
  const t = theme || THEMES.paper;
  const allReady = ai && consent && !!provider;
  return (
    <NavSheet theme={t} height={height} title="Set up translation" backLabel="Bilingual" onBack={onBack}
      trailing={allReady ? <span style={{ fontSize: 15, fontWeight: 600, color: t.accent }}>Done</span> : null}>
      <ReadinessSheetBody theme={t} ai={ai} consent={consent} provider={provider} providers={providers || []}
        onEnableAI={onEnableAI} onConsent={onConsent} onAdd={onAdd} onSelect={onSelect}/>
    </NavSheet>
  );
}

// ════════════════════════════════════════════════════
// ALTERNATIVE B — guided stepper. One gate at a time with a dot header. Heavier
// and order-forcing: a returning user who only lacks consent still walks the
// whole rail, and the provider step re-presents the #81 editor mid-flow.
// step: 0 enable · 1 consent · 2 provider
// ════════════════════════════════════════════════════
function StepperSheet({ theme, step = 0, ai, consent, provider, onBack }) {
  const t = theme || THEMES.paper;
  const titles = ['Enable the assistant', 'Review data sharing', 'Connect a provider'];
  return (
    <NavSheet theme={t} height={640} title="Get ready" backLabel="Bilingual" onBack={onBack}>
      <div style={{ padding: '16px 20px 28px' }}>
        {/* dot rail */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, marginBottom: 18 }}>
          {[0, 1, 2].map(i => (
            <div key={i} style={{
              height: 6, borderRadius: 3, transition: 'all 0.2s',
              width: i === step ? 26 : 6,
              background: i < step ? RDY_GREEN : (i === step ? t.accent : (t.isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.12)')),
            }}/>
          ))}
        </div>
        <div style={{ fontFamily: RDY_SERIF, fontSize: 19, fontWeight: 600, color: t.ink, textAlign: 'center' }}>
          {titles[step]}
        </div>
        <div style={{ fontSize: 12.5, color: t.sub, textAlign: 'center', lineHeight: 1.45, maxWidth: 280, margin: '6px auto 20px' }}>
          Step {step + 1} of 3
        </div>

        {step === 0 && (
          <div style={{
            borderRadius: 14, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
          }}>
            <EnableAIRow theme={t} on={ai} onToggle={() => {}} last/>
          </div>
        )}
        {step === 1 && <ConsentDisclosureCard theme={t} on={consent} onToggle={() => {}}/>}
        {step === 2 && (
          <ReadinessProviderBlock theme={t} providers={provider ? [provider] : []} selectedId={provider && provider.id}
            onAdd={() => {}} onSelect={() => {}}/>
        )}

        <button style={{
          width: '100%', marginTop: 22, padding: '13px 0', borderRadius: 14, border: 'none',
          background: t.accent, color: '#fff', fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer',
          boxShadow: `0 4px 14px ${t.accent}55`,
        }}>{step < 2 ? 'Continue' : 'Finish'}</button>
        <div style={{ textAlign: 'center', marginTop: 12, fontSize: 13, color: t.sub }}>Back</div>
      </div>
    </NavSheet>
  );
}

// ════════════════════════════════════════════════════
// ALTERNATIVE C — pre-flight gate. Enable + consent must both be ON before the
// provider list/editor is reachable. Clean single consent moment, but front-loads
// privacy before the user has committed, and re-gates returning users.
// ════════════════════════════════════════════════════
function PreflightGateSheet({ theme, ai, consent, onBack }) {
  const t = theme || THEMES.paper;
  const ready = ai && consent;
  return (
    <NavSheet theme={t} height={680} title="Before you translate" backLabel="Bilingual" onBack={onBack}>
      <div style={{ padding: '16px 18px 28px' }}>
        <div style={{ textAlign: 'center', padding: '4px 8px 16px' }}>
          <div style={{
            width: 50, height: 50, borderRadius: 25, margin: '0 auto 12px',
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: `0 6px 18px ${t.accent}44`,
          }}>
            <Icons.Sparkle size={24} color="#fff" stroke={1.7}/>
          </div>
          <div style={{ fontFamily: RDY_SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>
            Two quick permissions
          </div>
          <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.5, maxWidth: 272, margin: '6px auto 0' }}>
            Bilingual mode uses AI to translate. Enable the assistant and allow data sharing, then add a provider.
          </div>
        </div>

        <div style={{
          borderRadius: 14, overflow: 'hidden', marginBottom: 14,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
        }}>
          <EnableAIRow theme={t} on={ai} onToggle={() => {}} last/>
        </div>
        <ConsentDisclosureCard theme={t} on={consent} onToggle={() => {}} locked={!ai}/>

        <button disabled={!ready} style={{
          width: '100%', marginTop: 20, padding: '13px 0', borderRadius: 14, border: 'none',
          background: ready ? t.accent : `${t.accent}40`, color: '#fff',
          fontFamily: 'inherit', fontSize: 15, fontWeight: 600,
          cursor: ready ? 'pointer' : 'default',
          boxShadow: ready ? `0 4px 14px ${t.accent}55` : 'none',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
        }}>
          Continue to add a provider
          <Icons.Chevron size={15} color="#fff" stroke={2.4}/>
        </button>
        {!ready && (
          <div style={{ textAlign: 'center', marginTop: 10, fontSize: 11.5, color: t.sub }}>
            Both switches are required to continue.
          </div>
        )}
      </div>
    </NavSheet>
  );
}

Object.assign(window, {
  RDY_BRAND, RDY_SHIELD, RDY_GREEN,
  ReadinessTracker, EnableAIRow, ConsentDisclosureCard, ReadyBanner,
  ReadinessProviderBlock, StepLabel,
  ReadinessSheetBody, ReadinessSheet,
  StepperSheet, PreflightGateSheet,
});
