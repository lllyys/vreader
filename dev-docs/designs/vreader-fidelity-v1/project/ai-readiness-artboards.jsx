// Canvas artboards for issue #1394 — in-reader AI-enable + consent affordance for
// the bilingual "Set up" flow.
//
// Sections:
//   T — The gap: provider added in-reader (#81) but "Set up" persists (flag+consent off).
//   A — Canonical: the "Set up translation" readiness sheet, all gate states, paper.
//   A2 — Canonical across sepia / dark / oled.
//   B — Alternative: guided stepper.
//   C — Alternative: pre-flight enable+consent gate.
//   D — Flow + engine strip before/after.

const I1394_W = 402;
const I1394_H = 768;

const RDY_CLAUDE = { id: 'claude', name: 'Claude', model: 'claude-sonnet-4-6' };

// ── faded reader page behind the sheet ──
function I1394_ReaderPage({ t }) {
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '64px 26px 50px', opacity: 0.5 }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11,
        color: t.sub, letterSpacing: 2, textTransform: 'uppercase',
        textAlign: 'center', marginBottom: 14,
      }}>Chapter 1</div>
      {[
        'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
        'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families…',
        'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
      ].map((p, i) => (
        <p key={i} style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, lineHeight: 1.55, color: t.ink,
          margin: '0 0 12px', textIndent: i === 0 ? 0 : 18, textAlign: 'justify',
        }}>{p}</p>
      ))}
    </div>
  );
}

function I1394_TopChrome({ t }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      paddingTop: 30, paddingBottom: 8, zIndex: 5,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 2, color: t.accent, fontSize: 13.5, fontWeight: 500 }}>
          <Icons.ChevronL size={17} color={t.accent} stroke={2.2}/>Library
        </div>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 13.5,
          fontStyle: 'italic', fontWeight: 600, color: t.ink,
        }}>Pride and Prejudice</div>
        <div style={{ display: 'flex', gap: 2, color: t.ink, opacity: 0.85 }}>
          <Icons.Search size={16} color={t.ink} stroke={1.7}/>
          <Icons.More size={18} color={t.ink} stroke={1.7}/>
        </div>
      </div>
    </div>
  );
}

function RdyPhone({ themeKey, height = I1394_H, children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: I1394_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <I1394_ReaderPage t={t}/>
      <I1394_TopChrome t={t}/>
      {children}
    </div>
  );
}

// ── canonical readiness sheet, parameterised by gate state ──
function ReadinessArt({ themeKey, ai, consent, provider }) {
  const t = THEMES[themeKey];
  return (
    <RdyPhone themeKey={themeKey}>
      <ReadinessSheet theme={t} ai={ai} consent={consent} provider={provider}
        providers={provider ? [provider] : []}
        onBack={() => {}} onEnableAI={() => {}} onConsent={() => {}} onAdd={() => {}} onSelect={() => {}}/>
    </RdyPhone>
  );
}

// ── the gap: #81 provider sheet with a provider added, yet engine still "Set up" ──
function GapArt({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <RdyPhone themeKey={themeKey}>
      <BilingualSetupSheet theme={t} value={{ lang: 'Chinese', granularity: 'paragraph' }}
        onChange={() => {}} onClose={() => {}} aiConfigured={false}/>
    </RdyPhone>
  );
}

// ════════════════════════════════════════════════════
// Flow diagram
// ════════════════════════════════════════════════════
function RdyFlowStep({ t, n, title, sub, active, done }) {
  const bg = done ? '#3a6a5a' : (active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'));
  return (
    <div style={{
      width: 138, flexShrink: 0, padding: '12px 13px', borderRadius: 12,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      border: `0.5px solid ${active ? t.accent : t.rule}`,
      boxShadow: active ? `0 0 0 1.5px ${t.accent}55` : 'none',
    }}>
      <div style={{
        width: 22, height: 22, borderRadius: 11, marginBottom: 8,
        background: bg, color: (done || active) ? '#fff' : t.sub, fontSize: 12, fontWeight: 700,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{done ? <Icons.Check size={13} color="#fff" stroke={3}/> : n}</div>
      <div style={{ fontSize: 12.5, fontWeight: 600, color: t.ink, lineHeight: 1.25 }}>{title}</div>
      <div style={{ fontSize: 10.5, color: t.sub, lineHeight: 1.4, marginTop: 3 }}>{sub}</div>
    </div>
  );
}

function RdyFlowArrow({ t, label }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flexShrink: 0, width: 64 }}>
      <div style={{ fontSize: 9, color: t.sub, textAlign: 'center', lineHeight: 1.2 }}>{label}</div>
      <svg width="38" height="12" viewBox="0 0 40 12" fill="none" stroke={t.accent} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 6h32M30 2l5 4-5 4"/>
      </svg>
    </div>
  );
}

function RdyFlowDiagram({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{ width: 1080, padding: '28px 30px', background: t.bg, borderRadius: 12, border: `0.5px solid ${t.rule}` }}>
      <div style={{ fontSize: 12, color: t.sub, letterSpacing: 0.6, textTransform: 'uppercase', fontWeight: 600, marginBottom: 18 }}>
        BilingualAIReadiness — all four gates cleared in-reader, then pop back configured
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 2 }}>
        <RdyFlowStep t={t} n="1" title="Bilingual setup" sub="Engine: “Set up”" active/>
        <RdyFlowArrow t={t} label="push"/>
        <RdyFlowStep t={t} n="2" title="Turn on AI" sub="aiAssistant flag" done/>
        <RdyFlowArrow t={t} label="reveal"/>
        <RdyFlowStep t={t} n="3" title="Allow data" sub="explicit consent" done/>
        <RdyFlowArrow t={t} label="reveal"/>
        <RdyFlowStep t={t} n="4" title="Add provider" sub="provider + key" done/>
        <RdyFlowArrow t={t} label="pop"/>
        <RdyFlowStep t={t} n="5" title="Bilingual" sub="“Change…” — ready" active/>
      </div>
      <div style={{
        marginTop: 20, paddingTop: 18, borderTop: `0.5px dashed ${t.rule}`,
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 26,
      }}>
        <div>
          <div style={{ fontSize: 11, color: t.sub, letterSpacing: 0.5, textTransform: 'uppercase', fontWeight: 600, marginBottom: 10 }}>Engine strip — before (any gate unmet)</div>
          <BilingualEngineStrip theme={t} configured={false}/>
        </div>
        <div>
          <div style={{ fontSize: 11, color: t.sub, letterSpacing: 0.5, textTransform: 'uppercase', fontWeight: 600, marginBottom: 10 }}>Engine strip — after (all four cleared)</div>
          <BilingualEngineStrip theme={t} configured providerName="Claude" justChanged/>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
function CanvasRoot1394() {
  return (
    <DesignCanvas>
      <DCSection id="intro" title="In-reader AI-enable + consent · #1394"
        subtitle="#81 lets a user add a provider in-reader — but BilingualAIReadiness needs all four: aiAssistant flag ON · consent granted · provider · key. On a fresh device the flag + consent default OFF, so adding a provider alone still shows “Set up”. This closes that gap inside the reader, keeping consent an explicit action.">
        <DCPostIt top={-34} right={40} rotate={-2} width={336}>
          <b>Pick A.</b> Make the whole readiness legible on the one surface “Set up”
          already opens: a 3-step tracker, the master AI toggle, an explicit
          full-disclosure consent card, then the #81 provider list. B (a stepper)
          over-guides returning users; C (a pre-flight gate) front-loads privacy
          before the user has committed.
        </DCPostIt>
      </DCSection>

      <DCSection id="T" title="T — The gap (start point)"
        subtitle="After #81 the user can add a provider in-reader, yet a fresh user (flag + consent off) correctly still sees “Set up” on the engine strip. The configure-from-reader payoff doesn’t complete in one place — that’s what we’re closing.">
        <DCArtboard id="T1" label="Bilingual · engine still “Set up” · paper" width={I1394_W} height={I1394_H}>
          <GapArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="T2" label="Bilingual · engine still “Set up” · dark" width={I1394_W} height={I1394_H}>
          <GapArt themeKey="dark"/>
        </DCArtboard>
        <DCPostIt top={-34} right={40} rotate={2} width={248}>
          The provider persists and would work — but the flag + consent gates
          remain unsatisfied, so readiness stays false. Today the only fix is a
          trip to Library → Settings → AI.
        </DCPostIt>
      </DCSection>

      <DCSection id="A" title="A — “Set up translation” readiness sheet (canonical)"
        subtitle="Reached from “Set up”. A 3-step tracker frames the work; each gate is satisfied in place, top to bottom. Consent is granted only by its own toggle on a card that names exactly what leaves the device.">
        <DCArtboard id="A1" label="① Fresh — AI off, rest locked" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="paper" ai={false} consent={false} provider={null}/>
        </DCArtboard>
        <DCArtboard id="A2" label="② AI on — consent disclosure revealed" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="paper" ai={true} consent={false} provider={null}/>
        </DCArtboard>
        <DCArtboard id="A3" label="③ Consent granted — add provider next" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="paper" ai={true} consent={true} provider={null}/>
        </DCArtboard>
        <DCArtboard id="A4" label="④ All four cleared — Ready payoff" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="paper" ai={true} consent={true} provider={RDY_CLAUDE}/>
        </DCArtboard>
        <DCPostIt top={-34} right={40} rotate={-2} width={250}>
          The tracker doubles as an explainer — it answers “why am I still seeing
          Set up?” by showing exactly which gates remain.
        </DCPostIt>
      </DCSection>

      <DCSection id="A-add" title="A — provider step reuses the #81 editor"
        subtitle="“Add a provider” opens the canonical AIProviderEditSheet unchanged (provider + key). On save it becomes the bilingual engine and the tracker’s third gate clears.">
        <DCArtboard id="A5" label="Add Provider · canonical editor (reused) · light" width={I1394_W} height={I1394_H}>
          <EditorSheet ui={UI.light} variant="A" state="rest" mode="add" keyEntered height={I1394_H}/>
        </DCArtboard>
        <DCArtboard id="A6" label="Add Provider · canonical editor (reused) · dark" width={I1394_W} height={I1394_H}>
          <EditorSheet ui={UI.dark} variant="A" state="rest" mode="add" keyEntered height={I1394_H}/>
        </DCArtboard>
      </DCSection>

      <DCSection id="A-themes" title="A — canonical across themes"
        subtitle="The same sheet on sepia, dark, and OLED. Key states: the consent moment (AI on, consent pending) and the Ready payoff.">
        <DCArtboard id="AT1" label="Consent pending · sepia" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="sepia" ai={true} consent={false} provider={null}/>
        </DCArtboard>
        <DCArtboard id="AT2" label="Consent pending · dark" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="dark" ai={true} consent={false} provider={null}/>
        </DCArtboard>
        <DCArtboard id="AT3" label="Ready payoff · dark" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="dark" ai={true} consent={true} provider={RDY_CLAUDE}/>
        </DCArtboard>
        <DCArtboard id="AT4" label="Ready payoff · OLED" width={I1394_W} height={I1394_H}>
          <ReadinessArt themeKey="oled" ai={true} consent={true} provider={RDY_CLAUDE}/>
        </DCArtboard>
      </DCSection>

      <DCSection id="B" title="B — Guided stepper (alternative)"
        subtitle="One gate per screen with a dot rail. Clear for a first-timer, but it order-forces every visit: a returning user who only lacks consent still walks the whole rail, and step 3 re-presents the #81 editor mid-flow.">
        <DCArtboard id="B1" label="Step 1 · Enable" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="paper"><StepperSheet theme={THEMES.paper} step={0} ai={false} consent={false} provider={null} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
        <DCArtboard id="B2" label="Step 2 · Consent" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="paper"><StepperSheet theme={THEMES.paper} step={1} ai={true} consent={false} provider={null} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
        <DCArtboard id="B3" label="Step 3 · Provider" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="paper"><StepperSheet theme={THEMES.paper} step={2} ai={true} consent={true} provider={null} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
        <DCArtboard id="B4" label="Step 2 · Consent · dark" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="dark"><StepperSheet theme={THEMES.dark} step={1} ai={true} consent={false} provider={null} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
      </DCSection>

      <DCSection id="C" title="C — Pre-flight enable + consent gate (alternative)"
        subtitle="“Set up” first demands both switches before the provider list is reachable. One tidy consent moment, but it front-loads privacy before the user has committed to anything, and re-gates returning users who already granted it.">
        <DCArtboard id="C1" label="Gate · both off (continue disabled)" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="paper"><PreflightGateSheet theme={THEMES.paper} ai={false} consent={false} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
        <DCArtboard id="C2" label="Gate · both on (continue enabled)" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="paper"><PreflightGateSheet theme={THEMES.paper} ai={true} consent={true} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
        <DCArtboard id="C3" label="Gate · both on · dark" width={I1394_W} height={I1394_H}>
          <RdyPhone themeKey="dark"><PreflightGateSheet theme={THEMES.dark} ai={true} consent={true} onBack={() => {}}/></RdyPhone>
        </DCArtboard>
      </DCSection>

      <DCSection id="D" title="D — Readiness flow + engine strip"
        subtitle="The full four-gate path and the engine strip before / after, true size.">
        <DCArtboard id="D1" label="Flow + strip · paper" width={1080} height={440}>
          <RdyFlowDiagram themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="D2" label="Flow + strip · dark" width={1080} height={440}>
          <RdyFlowDiagram themeKey="dark"/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot1394 });
