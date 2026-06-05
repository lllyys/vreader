// Canvas artboards for #1483 — Tool activity / retrieval affordance in chat. Feature #91.
//
// When the assistant answers about a book it may run tools: search the text, open a
// specific chapter, look up a highlight. Today that work is invisible — the user sees a
// pause, then an answer, with no sense of what was consulted. #1483 surfaces it.
//
// CANONICAL: an in-bubble "activity strip" above the assistant's text.
//   • While working → a live status line ("Searching the text…") with a spinner, the
//     current tool's verb, and a count of steps done.
//   • When done → it collapses to a single quiet disclosure chip ("Looked at 3 sources")
//     that expands to a step timeline: each tool call as a row (verb · target · result).
//   • Citations the answer leans on stay as the existing footnote chips below the text;
//     the activity strip is the *process*, the citations are the *evidence*.
//
// This keeps the bubble calm by default (one chip) while making the retrieval auditable
// on demand — the disclosure pattern, not a permanent wall of logs.

const PW = 402;

// Tool steps for the sample answer
const STEPS = [
  { tool: 'search', verb: 'Searched the text', detail: '“Mr. Bennet visit Bingley”', result: '4 passages', icon: 'Search' },
  { tool: 'open',   verb: 'Opened',            detail: 'Chapter 1 · Vol. I',        result: 'read',       icon: 'Book' },
  { tool: 'open',   verb: 'Opened',            detail: 'Chapter 2 · Vol. I',        result: 'read',       icon: 'Book' },
];

// small glyphs
function Glyph({ name, size = 13, color = 'currentColor' }) {
  const common = { width: size, height: size, viewBox: '0 0 24 24', fill: 'none', stroke: color, strokeWidth: 1.8, strokeLinecap: 'round', strokeLinejoin: 'round' };
  if (name === 'Search') return <svg {...common}><circle cx="11" cy="11" r="7"/><path d="M21 21l-4-4"/></svg>;
  if (name === 'Book')   return <svg {...common}><path d="M4 5a2 2 0 012-2h12v18H6a2 2 0 01-2-2z"/><path d="M8 3v18"/></svg>;
  if (name === 'Bolt')   return <svg {...common}><path d="M13 3L5 14h6l-1 7 8-11h-6z"/></svg>;
  return null;
}

// ════════════════════════════════════════════════════
// In-progress strip (live)
// ════════════════════════════════════════════════════
function ActivityLive({ t, step = 1 }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 9, padding: '8px 12px', borderRadius: 12, marginBottom: 8,
      background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.035)',
      border: `0.5px solid ${t.rule}` }}>
      <CSpinner size={13} color={t.accent} stroke={2}/>
      <span style={{ fontSize: 12.5, color: t.ink, fontWeight: 500 }}>Searching the text…</span>
      <span style={{ marginLeft: 'auto', fontSize: 11, color: t.sub, fontVariantNumeric: 'tabular-nums' }}>step {step} of 3</span>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Collapsed disclosure chip
// ════════════════════════════════════════════════════
function ActivityChip({ t, open = false, count = 3 }) {
  return (
    <button style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 11px 6px 9px', borderRadius: 100,
      border: `0.5px solid ${t.rule}`, background: open ? (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.03)') : 'transparent',
      cursor: 'pointer', marginBottom: open ? 6 : 8, fontFamily: 'inherit' }}>
      <Glyph name="Bolt" size={12} color={t.accent}/>
      <span style={{ fontSize: 12, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap' }}>Looked at {count} sources</span>
      <Icons.ChevronD size={12} color={t.sub} stroke={2.2} style={{ transform: open ? 'rotate(180deg)' : 'none', transition: 'transform .15s' }}/>
    </button>
  );
}

// ════════════════════════════════════════════════════
// Expanded step timeline
// ════════════════════════════════════════════════════
function ActivityTimeline({ t }) {
  return (
    <div style={{ marginBottom: 8, padding: '4px 2px 2px', borderRadius: 12,
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)', border: `0.5px solid ${t.rule}` }}>
      {STEPS.map((s, i) => (
        <div key={i} style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '9px 12px',
          borderBottom: i < STEPS.length - 1 ? `0.5px solid ${t.rule}` : 'none' }}>
          <span style={{ width: 22, height: 22, borderRadius: 7, flexShrink: 0, marginTop: 1,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
            <Glyph name={s.icon} size={12} color={t.accent}/>
          </span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 12.5, color: t.ink }}>
              <span style={{ fontWeight: 600 }}>{s.verb}</span>{' '}
              <span style={{ color: t.sub }}>{s.detail}</span>
            </div>
          </div>
          <span style={{ fontSize: 11, color: t.sub, flexShrink: 0, display: 'inline-flex', alignItems: 'center', gap: 4, marginTop: 1 }}>
            <Icons.Check size={11} color={ACCENT_GREEN} stroke={2.4}/>{s.result}
          </span>
        </div>
      ))}
    </div>
  );
}

// ════════════════════════════════════════════════════
// Citation footnote chips (existing pattern, referenced)
// ════════════════════════════════════════════════════
function Citations({ t }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
      {['Ch. 1, ¶3', 'Ch. 1, ¶7', 'Ch. 2, ¶1'].map((c, i) => (
        <span key={i} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, padding: '3px 9px', borderRadius: 100,
          background: t.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.07)', color: t.accent, fontSize: 11, fontWeight: 600 }}>
          <span style={{ width: 13, height: 13, borderRadius: 7, background: t.accent, color: '#fff', fontSize: 8,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700 }}>{i + 1}</span>
          {c}
        </span>
      ))}
    </div>
  );
}

const ANSWER = 'He teases her because the visit is a foregone conclusion to him even as he pretends reluctance. Austen uses the exchange to set up their marriage: Mrs. Bennet’s anxious matchmaking against Mr. Bennet’s dry detachment — he has, in fact, already resolved to call on Bingley.';

// ════════════════════════════════════════════════════
// Error step (a tool failed)
// ════════════════════════════════════════════════════
function ActivityError({ t }) {
  return (
    <div style={{ marginBottom: 8, padding: '4px 2px 2px', borderRadius: 12,
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)', border: `0.5px solid ${t.rule}` }}>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '9px 12px', borderBottom: `0.5px solid ${t.rule}` }}>
        <span style={{ width: 22, height: 22, borderRadius: 7, flexShrink: 0, marginTop: 1, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <Glyph name="Search" size={12} color={t.accent}/>
        </span>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12.5, color: t.ink }}><span style={{ fontWeight: 600 }}>Searched the text</span> <span style={{ color: t.sub }}>“Bingley visit”</span></div>
        </div>
        <span style={{ fontSize: 11, color: ACCENT_GREEN, display: 'inline-flex', gap: 4, alignItems: 'center', marginTop: 1 }}><Icons.Check size={11} color={ACCENT_GREEN} stroke={2.4}/>4 passages</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 9, padding: '9px 12px' }}>
        <span style={{ width: 22, height: 22, borderRadius: 7, flexShrink: 0, marginTop: 1, background: 'rgba(192,68,58,0.12)', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icons.Alert size={12} color="#c0443a" stroke={2}/>
        </span>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 12.5, color: t.ink }}><span style={{ fontWeight: 600 }}>Couldn’t open</span> <span style={{ color: t.sub }}>Chapter 3</span></div>
          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>Not downloaded — answered from what was available.</div>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Chat body builder
// ════════════════════════════════════════════════════
function ToolChat({ t, variant = 'collapsed' }) {
  // variant: 'live' | 'collapsed' | 'expanded' | 'error'
  let above = null, footer = null, text = ANSWER, streaming = false;
  if (variant === 'live') { above = <ActivityLive t={t} step={2}/>; text = null; streaming = false; }
  if (variant === 'collapsed') { above = <ActivityChip t={t}/>; footer = <Citations t={t}/>; }
  if (variant === 'expanded') { above = <><ActivityChip t={t} open/><ActivityTimeline t={t}/></>; footer = <Citations t={t}/>; }
  if (variant === 'error') { above = <><ActivityChip t={t} open count={1}/><ActivityError t={t}/></>; }

  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '16px 18px 8px' }}>
      <UserBubble t={t} text="Why does Mr. Bennet tease his wife about visiting Bingley?"/>
      {variant === 'live'
        ? <AsstBubble t={t} above={above}><span style={{ color: t.sub, fontStyle: 'italic' }}>Working…</span></AsstBubble>
        : <AsstBubble t={t} above={above} text={text} footer={footer} streaming={streaming}/>}
    </div>
  );
}

function ToolChatScreen({ themeKey = 'paper', variant = 'collapsed' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <ToolChat t={t} variant={variant}/>
        <div style={{ borderTop: `0.5px solid ${t.rule}` }}><Composer t={t}/></div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// Rejected — full persistent log
// ════════════════════════════════════════════════════
function VerboseScreen({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <div style={{ flex: 1, overflow: 'hidden', padding: '16px 18px 8px' }}>
          <UserBubble t={t} text="Why does Mr. Bennet tease his wife about visiting Bingley?"/>
          <AsstBubble t={t} above={<div style={{ marginBottom: 8 }}><ActivityTimeline t={t}/></div>} text={ANSWER} footer={<Citations t={t}/>}/>
        </div>
        <div style={{ borderTop: `0.5px solid ${t.rule}` }}><Composer t={t}/></div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// CANVAS
// ════════════════════════════════════════════════════
function ToolActivityCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>
      <DCSection id="intro" title="Tool activity affordance · #1483"
        subtitle="Feature #91. The assistant runs tools to answer about a book — search the text, open chapters, check highlights. Today that work is invisible. This surfaces it as an in-bubble activity strip: a live status while working, collapsing to one quiet “Looked at N sources” chip that expands to a step timeline.">
        <DCPostIt top={-36} right={26} rotate={-2} width={340}>
          <b>Process vs. evidence.</b> The activity strip shows what the model <i>did</i>
          (searched, opened); the citation chips below the answer show what it <i>cited</i>.
          Keeping them separate stops the bubble from becoming a log dump.
        </DCPostIt>
      </DCSection>

      {/* A — lifecycle */}
      <DCSection id="A" title="A — Activity lifecycle (canonical)"
        subtitle="Live → a status line with spinner + step counter replaces the typing dots. Done → it collapses to a single disclosure chip so the answer stays the focus. Tap → the chip expands into a timeline of each tool call (verb · target · result).">
        <DCArtboard id="A-live" label="Working · live status" width={PW} height={760}>
          <ToolChatScreen themeKey="paper" variant="live"/>
        </DCArtboard>
        <DCArtboard id="A-collapsed" label="Done · collapsed chip" width={PW} height={760}>
          <ToolChatScreen themeKey="paper" variant="collapsed"/>
        </DCArtboard>
        <DCArtboard id="A-expanded" label="Expanded · step timeline" width={PW} height={760}>
          <ToolChatScreen themeKey="paper" variant="expanded"/>
        </DCArtboard>
      </DCSection>

      {/* States */}
      <DCSection id="S" title="S — Partial failure · dark"
        subtitle="When a tool fails (a chapter isn’t downloaded), the timeline marks that step in red and notes the model answered from what was available — the answer still ships, the gap is auditable.">
        <DCArtboard id="S-error" label="A tool failed" width={PW} height={760}>
          <ToolChatScreen themeKey="paper" variant="error"/>
        </DCArtboard>
        <DCArtboard id="S-dark-exp" label="Expanded · dark" width={PW} height={760}>
          <ToolChatScreen themeKey="dark" variant="expanded"/>
        </DCArtboard>
        <DCArtboard id="S-dark-live" label="Working · dark" width={PW} height={760}>
          <ToolChatScreen themeKey="dark" variant="live"/>
        </DCArtboard>
      </DCSection>

      {/* Anatomy */}
      <DCSection id="D" title="D — Strip states · true size"
        subtitle="Live status, collapsed chip, and one timeline row at 1:1.">
        <DCArtboard id="D-live" label="Live status line" width={360} height={80}>
          <AnatomyWrap pad={16}><ActivityLive t={THEMES.paper} step={2}/></AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-chip" label="Collapsed · expanded chip" width={360} height={90}>
          <AnatomyWrap pad={16}>
            <div style={{ display: 'flex', gap: 12, alignItems: 'center' }}>
              <ActivityChip t={THEMES.paper}/>
              <ActivityChip t={THEMES.paper} open/>
            </div>
          </AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-timeline" label="Step timeline" width={360} height={180}>
          <AnatomyWrap pad={16}><ActivityTimeline t={THEMES.paper}/></AnatomyWrap>
        </DCArtboard>
      </DCSection>

      {/* Rejected */}
      <DCSection id="B" title="B — Always-expanded log (rejected)"
        subtitle="Every tool call permanently expanded above each answer. Maximally transparent, but it buries the prose, makes short answers look heavy, and turns a 3-step retrieval into the loudest thing in the bubble.">
        <DCArtboard id="B-verbose" label="Permanent log" width={PW} height={760}>
          <VerboseScreen themeKey="paper"/>
        </DCArtboard>
        <DCPostIt bottom={-28} left={22} rotate={2} width={300}>
          Rejected: most readers don’t care how the answer was found — until they do. The
          collapsed chip respects that: calm by default, fully auditable on tap.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { ToolActivityCanvas });
