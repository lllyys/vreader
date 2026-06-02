// Canvas artboards for issue #1380 — in-reader AI Providers entry from the
// bilingual "Set up" button.
//
// Sections:
//   T — Trigger: the bilingual sheet, engine unconfigured, "Set up".
//   A — Canonical: scoped AI Providers sheet pushed in the bilingual flow
//       (empty → editor → populated → return to Bilingual configured), + dark.
//   B — Alternative: deep-link into the full SettingsView.
//   C — Alternative: inline expansion of the engine strip.
//   D — Anatomy: the navigation flow + engine strip before/after.

const I1380_W = 402;
const I1380_H = 768;

// ── self-contained reader page behind the sheet ──
function I1380_FakeReaderPage({ t }) {
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

function I1380_TopChrome({ t }) {
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

// Phone shell — faded reader page + top chrome, sheet rendered as child.
function EntryPhone({ themeKey, height = I1380_H, chrome = true, children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: I1380_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <I1380_FakeReaderPage t={t}/>
      {chrome && <I1380_TopChrome t={t}/>}
      {children}
    </div>
  );
}

// ── sample provider data ──
const I1380_ONE = [{ id: 'claude', name: 'Claude', model: 'claude-sonnet-4-6' }];
const I1380_MANY = [
  { id: 'claude', name: 'Claude', model: 'claude-sonnet-4-6' },
  { id: 'or', name: 'OpenRouter', model: 'anthropic/claude-3.5-sonnet' },
  { id: 'ds', name: 'DeepSeek', model: 'deepseek-chat' },
];

// ════════════════════════════════════════════════════
// Trigger + canonical artboards
// ════════════════════════════════════════════════════
function TriggerArt({ themeKey, configured = false }) {
  const t = THEMES[themeKey];
  return (
    <EntryPhone themeKey={themeKey}>
      <BilingualSetupSheet theme={t} value={{ lang: 'Chinese', granularity: 'paragraph' }}
        onChange={() => {}} onClose={() => {}} aiConfigured={configured}/>
    </EntryPhone>
  );
}

function ProvidersArt({ themeKey, providers = [], selectedId }) {
  const t = THEMES[themeKey];
  return (
    <EntryPhone themeKey={themeKey}>
      <AIProvidersSheet theme={t} providers={providers} selectedId={selectedId}
        onBack={() => {}} onAdd={() => {}} onSelect={() => {}}
        trailing={providers.length ? <span style={{ fontSize: 15, fontWeight: 600, color: t.accent }}>Done</span> : null}/>
    </EntryPhone>
  );
}

function EditorArt({ ui }) {
  // The canonical AIProviderEditSheet, reused unchanged (vreader-ai-provider-fields.jsx).
  return <EditorSheet ui={ui} variant="A" state="rest" mode="add" keyEntered height={I1380_H}/>;
}

function InlineArt({ themeKey, expanded }) {
  const t = THEMES[themeKey];
  return (
    <EntryPhone themeKey={themeKey}>
      <Sheet theme={t} title="Bilingual mode" height={expanded ? 640 : 560} onClose={() => {}}>
        <div style={{ padding: '14px 22px 28px' }}>
          <BilingualPreview t={t} lang="Chinese"/>
          <div style={{ marginTop: 22 }}>
            <EngineStripInline theme={t} expanded={expanded}/>
          </div>
          <button style={{
            width: '100%', marginTop: 22, padding: '13px 0', borderRadius: 14, border: 'none',
            background: expanded ? `${t.accent}55` : t.accent, color: '#fff',
            fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer',
          }}>Turn on bilingual mode</button>
        </div>
      </Sheet>
    </EntryPhone>
  );
}

function DeepLinkArt({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <EntryPhone themeKey={themeKey}>
      <FullSettingsDeepLink theme={t}/>
    </EntryPhone>
  );
}

// ── anatomy: navigation flow ──
function FlowStep({ t, n, title, sub, active }) {
  return (
    <div style={{
      width: 150, flexShrink: 0, padding: '12px 13px', borderRadius: 12,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      border: `0.5px solid ${active ? t.accent : t.rule}`,
      boxShadow: active ? `0 0 0 1.5px ${t.accent}55` : 'none',
    }}>
      <div style={{
        width: 22, height: 22, borderRadius: 11, marginBottom: 8,
        background: active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'),
        color: active ? '#fff' : t.sub, fontSize: 12, fontWeight: 700,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{n}</div>
      <div style={{ fontSize: 13, fontWeight: 600, color: t.ink, lineHeight: 1.25 }}>{title}</div>
      <div style={{ fontSize: 11, color: t.sub, lineHeight: 1.4, marginTop: 3 }}>{sub}</div>
    </div>
  );
}

function FlowArrow({ t, label }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 4, flexShrink: 0, width: 70 }}>
      <div style={{ fontSize: 9.5, color: t.sub, textAlign: 'center', lineHeight: 1.2 }}>{label}</div>
      <svg width="40" height="12" viewBox="0 0 40 12" fill="none" stroke={t.accent} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
        <path d="M2 6h32M30 2l5 4-5 4"/>
      </svg>
    </div>
  );
}

function NavFlowDiagram({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 980, padding: '28px 30px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ fontSize: 12, color: t.sub, letterSpacing: 0.6, textTransform: 'uppercase', fontWeight: 600, marginBottom: 18 }}>
        Navigation model — push within the bilingual sheet, editor modal on top, pop back configured
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 4 }}>
        <FlowStep t={t} n="1" title="Bilingual setup" sub="Engine: “Set up”" active/>
        <FlowArrow t={t} label="push ‹ Bilingual"/>
        <FlowStep t={t} n="2" title="AI Providers" sub="Empty → Add provider"/>
        <FlowArrow t={t} label="present modal"/>
        <FlowStep t={t} n="3" title="Add Provider" sub="Canonical editor"/>
        <FlowArrow t={t} label="Save · pop"/>
        <FlowStep t={t} n="4" title="Bilingual setup" sub="Engine configured" active/>
      </div>
      <div style={{
        marginTop: 20, paddingTop: 18, borderTop: `0.5px dashed ${t.rule}`,
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 26,
      }}>
        <div>
          <div style={{ fontSize: 11, color: t.sub, letterSpacing: 0.5, textTransform: 'uppercase', fontWeight: 600, marginBottom: 10 }}>Engine strip — before</div>
          <BilingualEngineStrip theme={t} configured={false}/>
        </div>
        <div>
          <div style={{ fontSize: 11, color: t.sub, letterSpacing: 0.5, textTransform: 'uppercase', fontWeight: 600, marginBottom: 10 }}>Engine strip — after (returned, just changed)</div>
          <BilingualEngineStrip theme={t} configured providerName="Claude" justChanged/>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
function CanvasRoot1380() {
  return (
    <DesignCanvas>
      <DCSection id="intro" title="In-reader AI Providers entry · #1380"
        subtitle="Wiring the bilingual “Set up” button to a real AI Providers surface — which does not exist in-reader today. Three approaches across themes, plus the navigation model.">
        <DCPostIt top={-34} right={40} rotate={-2} width={320}>
          <b>Pick A.</b> A scoped AI Providers sheet pushed inside the bilingual
          flow — reuses the canonical editor, keeps the reader context, and pops
          back to Bilingual with the engine ready. B dumps the reader into all of
          Settings; C can’t host the real editor without diverging.
        </DCPostIt>
      </DCSection>

      <DCSection id="T" title="T — Trigger (start point)"
        subtitle="The bilingual setup sheet after Bug #301: engine unconfigured, “Set up” shown. onOpenSettings currently dismisses the sheet — this is what we’re wiring.">
        <DCArtboard id="T1" label="Bilingual · “Set up” · paper" width={I1380_W} height={I1380_H}>
          <TriggerArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="T2" label="Bilingual · “Set up” · dark" width={I1380_W} height={I1380_H}>
          <TriggerArt themeKey="dark"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="A" title="A — Scoped AI Providers sheet (canonical)"
        subtitle="“Set up” pushes the provider list inside the same sheet (‹ Bilingual). Empty → canonical editor → populated → pop back to Bilingual, engine configured.">
        <DCArtboard id="A1" label="① AI Providers · empty + Add CTA" width={I1380_W} height={I1380_H}>
          <ProvidersArt themeKey="paper" providers={[]}/>
        </DCArtboard>
        <DCArtboard id="A2" label="② Add Provider · canonical editor (reused)" width={I1380_W} height={I1380_H}>
          <EditorArt ui={UI.light}/>
        </DCArtboard>
        <DCArtboard id="A3" label="③ AI Providers · populated · In use" width={I1380_W} height={I1380_H}>
          <ProvidersArt themeKey="paper" providers={I1380_ONE} selectedId="claude"/>
        </DCArtboard>
        <DCArtboard id="A4" label="④ Return to Bilingual · configured (payoff)" width={I1380_W} height={I1380_H}>
          <TriggerArt themeKey="paper" configured/>
        </DCArtboard>

        <DCPostIt top={-34} right={40} rotate={2} width={250}>
          The empty state (①) is a one-tap shortcut into the editor, so the extra
          nav level costs nothing when there are zero providers — and is correct
          when the user already has some.
        </DCPostIt>
      </DCSection>

      <DCSection id="A-dark" title="A — canonical · dark + change-later"
        subtitle="Dark theme, and the “Change…” entry point: same sheet, populated, current provider checked, switching the selection.">
        <DCArtboard id="A5" label="AI Providers · empty · dark" width={I1380_W} height={I1380_H}>
          <ProvidersArt themeKey="dark" providers={[]}/>
        </DCArtboard>
        <DCArtboard id="A6" label="AI Providers · populated · dark" width={I1380_W} height={I1380_H}>
          <ProvidersArt themeKey="dark" providers={I1380_ONE} selectedId="claude"/>
        </DCArtboard>
        <DCArtboard id="A7" label="Reached via “Change…” · switch among many" width={I1380_W} height={I1380_H}>
          <ProvidersArt themeKey="paper" providers={I1380_MANY} selectedId="or"/>
        </DCArtboard>
        <DCArtboard id="A8" label="Editor · dark" width={I1380_W} height={I1380_H}>
          <EditorArt ui={UI.dark}/>
        </DCArtboard>
      </DCSection>

      <DCSection id="B" title="B — Deep-link into full SettingsView (alternative)"
        subtitle="Present the whole app Settings modally over the reader, scrolled + highlighted to the AI section. Reuses the Library path verbatim — but drops the reader into all of Settings and loses the bilingual thread.">
        <DCArtboard id="B1" label="Full Settings · AI highlighted · paper" width={I1380_W} height={I1380_H}>
          <DeepLinkArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="B2" label="Full Settings · AI highlighted · dark" width={I1380_W} height={I1380_H}>
          <DeepLinkArt themeKey="dark"/>
        </DCArtboard>
        <DCPostIt top={-34} right={40} rotate={-2} width={250}>
          Cloud & Sync, OPDS, Book sources, TTS — none of what the user came for.
          And closing Settings lands back in the reader with the bilingual sheet
          gone, so the “turn on bilingual” thread is lost.
        </DCPostIt>
      </DCSection>

      <DCSection id="C" title="C — Inline expansion (alternative)"
        subtitle="“Set up” expands the engine strip in place into a minimal provider + key form. Tightest loop, but can’t host the real editor (base URL, model, sampling, saved-key, test) without diverging.">
        <DCArtboard id="C1" label="Strip · collapsed" width={I1380_W} height={I1380_H}>
          <InlineArt themeKey="paper" expanded={false}/>
        </DCArtboard>
        <DCArtboard id="C2" label="Strip · expanded (minimal form)" width={I1380_W} height={I1380_H}>
          <InlineArt themeKey="paper" expanded={true}/>
        </DCArtboard>
        <DCArtboard id="C3" label="Expanded · dark" width={I1380_W} height={I1380_H}>
          <InlineArt themeKey="dark" expanded={true}/>
        </DCArtboard>
      </DCSection>

      <DCSection id="D" title="D — Navigation model + engine strip"
        subtitle="The push/modal/pop flow and the engine strip before/after, true size.">
        <DCArtboard id="D1" label="Flow + strip · paper" width={980} height={420}>
          <NavFlowDiagram themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="D2" label="Flow + strip · dark" width={980} height={420}>
          <NavFlowDiagram themeKey="dark"/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot1380 });
