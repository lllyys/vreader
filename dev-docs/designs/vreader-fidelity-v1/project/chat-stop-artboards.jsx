// Canvas artboards for #1476 — Stop control on the AI input bar. Feature #87.
//
// CANONICAL: the composer's send button morphs IN PLACE into a stop button while a
// response is in flight. Same 32px disc, same position — only the glyph + a sweeping
// activity ring change. Tapping it aborts the request. This is the chat-app convention
// (one primary control that is always the right thing to press), and it keeps the bar
// from gaining width or a second button that's dead 95% of the time.
//
// The send disc already has three resting looks across the app; we formalise them:
//   disabled  — empty input. Neutral disc, muted arrow. Not pressable.
//   send      — has input. Accent disc, white arrow. Submits.
//   stop      — request in flight. Accent disc, white square + sweeping ring. Aborts.
//
// Summarize / Translate have no text field, so their in-flight stop rides on the
// generate/regenerate control instead — same square glyph, same meaning.

const PW = 402;

// ── Stop glyph (filled rounded square) ──
function StopGlyph({ size = 12, color = '#fff' }) {
  const r = Math.round(size * 0.22);
  return (
    <svg width={size} height={size} viewBox="0 0 24 24"><rect x="5" y="5" width="14" height="14" rx={r} fill={color}/></svg>
  );
}

// ── The morphing primary control ──
// state: 'disabled' | 'send' | 'stop'
function PrimaryControl({ t, state = 'send', size = 32 }) {
  const accent = t.accent;
  const neutral = t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.10)';
  const bg = state === 'disabled' ? neutral : accent;
  const arrowColor = state === 'disabled' ? (t.isDark ? 'rgba(255,255,255,0.4)' : 'rgba(0,0,0,0.35)') : '#fff';
  return (
    <div style={{
      width: size, height: size, borderRadius: size / 2, background: bg, position: 'relative',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      transition: 'background .2s ease', flexShrink: 0,
    }}>
      {state === 'stop' && <ActivityRing size={size} color="#fff"/>}
      <div style={{ opacity: state === 'stop' ? 0 : 1, transition: 'opacity .15s', position: 'absolute' }}>
        <Icons.Send size={Math.round(size * 0.47)} color={arrowColor} stroke={2}/>
      </div>
      <div style={{ opacity: state === 'stop' ? 1 : 0, transition: 'opacity .15s', position: 'absolute' }}>
        <StopGlyph size={Math.round(size * 0.34)} color="#fff"/>
      </div>
    </div>
  );
}

// Indeterminate sweep around the disc — the "working" signal.
function ActivityRing({ size = 32, color = '#fff' }) {
  const r = size / 2 - 2;
  const c = 2 * Math.PI * r;
  return (
    <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`} style={{ position: 'absolute', inset: 0, animation: 'stopspin 0.9s linear infinite' }}>
      <style>{`@keyframes stopspin { to { transform: rotate(360deg); } } svg{transform-origin:center;transform-box:fill-box;}`}</style>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} strokeOpacity="0.85"
        strokeWidth="2" strokeLinecap="round" strokeDasharray={`${c * 0.28} ${c}`}/>
    </svg>
  );
}

// ── Composer wired to the morph control ──
function StopComposer({ t, state }) {
  // state: 'disabled' | 'send' | 'stop'
  const map = {
    disabled: { placeholder: 'Ask about this book…', value: null },
    send:     { placeholder: '', value: 'Why does Mr. Bennet tease his wife about visiting Bingley?' },
    stop:     { placeholder: 'Stop to type a new question…', value: null },
  };
  const m = map[state];
  return (
    <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
      <Composer t={t} placeholder={m.placeholder} value={m.value} disabled={state === 'stop'}
        button={<PrimaryControl t={t} state={state}/>}/>
    </div>
  );
}

// ── Messages tuned for each input state ──
function StopMessages({ t, phase = 'idle' }) {
  // phase: 'idle' | 'thinking' | 'streaming' | 'stopped'
  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '16px 18px 8px' }}>
      <AsstBubble t={t} text="Hi! I’ve got this book’s context loaded. Ask me anything about it — characters, themes, references, or to clarify a passage you’re reading."/>
      {phase !== 'idle' && (
        <UserBubble t={t} text="Why does Mr. Bennet tease his wife about visiting Bingley?"/>
      )}
      {phase === 'thinking' && (
        <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
          <Avatar t={t}/>
          <div style={{ padding: '8px 0' }}><TypingDots t={t}/></div>
        </div>
      )}
      {phase === 'streaming' && (
        <AsstBubble t={t} streaming
          text="It’s how Austen draws the marriage between them: she is all anxious matchmaking, he deflects with dry irony. The teasing signals he sees through the social"/>
      )}
      {phase === 'stopped' && (
        <AsstBubble t={t}
          text="It’s how Austen draws the marriage between them: she is all anxious matchmaking, he deflects with dry irony. The teasing signals he sees through the social"
          footer={<StoppedNote t={t}/>}/>
      )}
    </div>
  );
}

function Avatar({ t }) {
  return (
    <div style={{ width: 24, height: 24, borderRadius: 12, flexShrink: 0, marginTop: 2,
      background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
      display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Icons.Sparkle size={12} color="#fff" stroke={2}/>
    </div>
  );
}

function TypingDots({ t }) {
  return (
    <div style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
      <style>{`@keyframes stopdot { 0%,80%,100% { opacity:.25; transform:translateY(0);} 40% { opacity:1; transform:translateY(-2px);} }`}</style>
      {[0, 1, 2].map(i => (
        <span key={i} style={{ width: 6, height: 6, borderRadius: 3, background: t.sub,
          animation: `stopdot 1.1s ${i * 0.15}s ease-in-out infinite` }}/>
      ))}
    </div>
  );
}

function StoppedNote({ t }) {
  return (
    <div style={{ display: 'inline-flex', alignItems: 'center', gap: 6, marginTop: 8,
      padding: '4px 10px', borderRadius: 100, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
      <StopGlyph size={11} color={t.sub}/>
      <span style={{ fontSize: 11.5, color: t.sub, fontWeight: 500 }}>Stopped · tap to ask again</span>
    </div>
  );
}

// ── Full chat screen ──
function StopChatScreen({ themeKey = 'paper', state = 'disabled', phase = 'idle' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <StopMessages t={t} phase={phase}/>
        <StopComposer t={t} state={state}/>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// Summarize / Translate in-flight — stop rides the generate control
// ════════════════════════════════════════════════════
function SummarizeScreen({ themeKey = 'paper', generating = true }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="summary">
        <div style={{ padding: '16px 18px', flex: 1, overflow: 'hidden' }}>
          <div style={{ display: 'flex', gap: 6, marginBottom: 14 }}>
            {['Section', 'Chapter', 'Book so far'].map((s, i) => (
              <span key={s} style={{ padding: '6px 12px', borderRadius: 100, fontSize: 12, fontWeight: 500,
                background: i === 1 ? t.accent : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
                color: i === 1 ? '#fff' : t.ink }}>{s}</span>
            ))}
          </div>
          <div style={{ padding: 16, borderRadius: 14,
            background: t.isDark ? 'rgba(214,136,90,0.08)' : 'rgba(140,47,47,0.04)',
            border: `0.5px solid ${t.rule}` }}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
              <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: t.sub, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
                <Icons.Sparkle size={11} color={t.accent} stroke={2}/>
                <span>Chapter 1 — Summary</span>
              </div>
              {/* the stop control: a compact pill while generating */}
              <button style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '5px 11px 5px 9px',
                borderRadius: 100, border: `0.5px solid ${t.rule}`, background: t.isDark ? 'rgba(255,255,255,0.05)' : '#fff',
                color: t.ink, cursor: 'pointer', fontFamily: 'inherit' }}>
                <span style={{ position: 'relative', width: 16, height: 16, display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
                  <ActivityRing size={16} color={t.accent}/>
                  <StopGlyph size={8} color={t.accent}/>
                </span>
                <span style={{ fontSize: 12, fontWeight: 600 }}>Stop</span>
              </button>
            </div>
            {/* streaming text + skeleton tail */}
            <div style={{ fontFamily: SERIF, fontSize: 15, lineHeight: 1.55, color: t.ink }}>
              The novel opens with the famous declaration that wealthy single men inevitably need wives. When Netherfield Park is rented by Mr. Bingley,<Caret t={t}/>
            </div>
            <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 8 }}>
              {[1, 0.92, 0.6].map((w, i) => (
                <div key={i} style={{ height: 9, width: `${w * 100}%`, borderRadius: 5,
                  background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}/>
              ))}
            </div>
          </div>
        </div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// Rejected alternate — a separate stop button beside send
// ════════════════════════════════════════════════════
function SeparateStopScreen({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <StopMessages t={t} phase="streaming"/>
        <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
          <div style={{ padding: '6px 14px 16px' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 6px 6px 14px', borderRadius: 22,
              background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)' }}>
              <span style={{ flex: 1, fontSize: 14, color: t.sub }}>Ask about this book…</span>
              <button style={{ width: 32, height: 32, borderRadius: 16, border: `1px solid ${t.accent}`,
                background: 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center', cursor: 'pointer' }}>
                <StopGlyph size={11} color={t.accent}/>
              </button>
              <PrimaryControl t={t} state="disabled"/>
            </div>
          </div>
        </div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// CANVAS
// ════════════════════════════════════════════════════
function ChatStopCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>
      <DCSection id="intro" title="AI input-bar Stop control · #1476"
        subtitle="Feature #87. The send disc morphs in place into a stop control while a reply is in flight — same disc, same spot, only the glyph + a sweeping activity ring change. One primary control that is always the correct thing to press. Summarize / Translate have no text field, so their stop rides the generate control instead.">
        <DCPostIt top={-36} right={28} rotate={-2} width={336}>
          <b>Morph, don’t add.</b> A second permanent stop button is dead 95% of the
          time and widens the bar; a stop banner floats away from where the thumb already
          is. The disc the user just tapped to send is exactly where they reach to stop.
        </DCPostIt>
      </DCSection>

      {/* ── A — canonical states ── */}
      <DCSection id="A" title="A — Three input-bar states (canonical)"
        subtitle="Disabled → empty input, neutral disc + muted arrow. Send → input present, accent disc + arrow. Stop → request in flight, accent disc + square + sweeping ring; the field is dimmed and reads “Stop to type a new question.”">
        <DCArtboard id="A-disabled" label="Disabled · empty input" width={PW} height={760}>
          <StopChatScreen themeKey="paper" state="disabled" phase="idle"/>
        </DCArtboard>
        <DCArtboard id="A-send" label="Send · input present" width={PW} height={760}>
          <StopChatScreen themeKey="paper" state="send" phase="idle"/>
        </DCArtboard>
        <DCArtboard id="A-thinking" label="Stop · thinking (no tokens yet)" width={PW} height={760}>
          <StopChatScreen themeKey="paper" state="stop" phase="thinking"/>
        </DCArtboard>
        <DCArtboard id="A-streaming" label="Stop · streaming reply" width={PW} height={760}>
          <StopChatScreen themeKey="paper" state="stop" phase="streaming"/>
        </DCArtboard>
        <DCArtboard id="A-stopped" label="After stop · partial kept" width={PW} height={760}>
          <StopChatScreen themeKey="paper" state="disabled" phase="stopped"/>
        </DCArtboard>
      </DCSection>

      {/* ── dark ── */}
      <DCSection id="dark" title="Across themes"
        subtitle="The disc uses the live theme accent; the ring and square are always white on it, so the control reads identically on Paper, Sepia, Dark and OLED.">
        <DCArtboard id="d-stream" label="Streaming · dark" width={PW} height={760}>
          <StopChatScreen themeKey="dark" state="stop" phase="streaming"/>
        </DCArtboard>
        <DCArtboard id="d-send" label="Send · sepia" width={PW} height={760}>
          <StopChatScreen themeKey="sepia" state="send" phase="idle"/>
        </DCArtboard>
        <DCArtboard id="d-stopped" label="After stop · dark" width={PW} height={760}>
          <StopChatScreen themeKey="dark" state="disabled" phase="stopped"/>
        </DCArtboard>
      </DCSection>

      {/* ── Anatomy ── */}
      <DCSection id="btn" title="The control · true size"
        subtitle="32px disc at 1:1. Glyphs cross-fade and the ring fades in; the disc never changes size or position, so the morph reads as the same object changing mode — not a swap.">
        <DCArtboard id="btn-states" label="disabled · send · stop" width={360} height={150}>
          <AnatomyWrap pad={20}>
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-around' }}>
              {[['disabled', 'Disabled'], ['send', 'Send'], ['stop', 'Stop']].map(([s, label]) => (
                <div key={s} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 10 }}>
                  <PrimaryControl t={THEMES.paper} state={s}/>
                  <span style={{ fontSize: 11.5, color: 'rgba(29,26,20,0.6)', fontFamily: SANS, fontWeight: 500 }}>{label}</span>
                </div>
              ))}
            </div>
          </AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="btn-flow" label="send → stop → idle" width={360} height={150}>
          <AnatomyWrap pad={20} bg="#fcf8f0">
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 14 }}>
              <PrimaryControl t={THEMES.paper} state="send"/>
              <Arrow/>
              <PrimaryControl t={THEMES.paper} state="stop"/>
              <Arrow/>
              <PrimaryControl t={THEMES.paper} state="disabled"/>
            </div>
          </AnatomyWrap>
        </DCArtboard>
      </DCSection>

      {/* ── Summarize / Translate ── */}
      <DCSection id="other" title="Summarize · in-flight stop"
        subtitle="The Summarize and Translate tabs have no composer, so the stop attaches to the card that’s being generated — a compact “Stop” pill with the same square + ring glyph. Stopping keeps whatever text already streamed.">
        <DCArtboard id="sum-gen" label="Summarize · generating + Stop" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" generating/>
        </DCArtboard>
        <DCArtboard id="sum-gen-dark" label="Summarize · generating · dark" width={PW} height={760}>
          <SummarizeScreen themeKey="dark" generating/>
        </DCArtboard>
      </DCSection>

      {/* ── Rejected ── */}
      <DCSection id="rej" title="B — Separate stop button (rejected)"
        subtitle="A persistent outline stop button to the left of a disabled send disc. Honest, but it leaves dead chrome on the bar at all other times and splits the “primary action” into two targets the thumb has to choose between.">
        <DCArtboard id="rej-paper" label="Two buttons" width={PW} height={760}>
          <SeparateStopScreen themeKey="paper"/>
        </DCArtboard>
        <DCPostIt bottom={-30} left={24} rotate={2} width={300}>
          Rejected: when streaming ends, the stop button has to disappear and the send
          disc re-enable — two moving parts where the morph has one. Discoverability is
          no better, and the bar is wider for nothing.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

function Arrow() {
  return (
    <svg width="22" height="14" viewBox="0 0 22 14" fill="none" style={{ opacity: 0.4 }}>
      <path d="M1 7h18M15 2l5 5-5 5" stroke="#5a4a3a" strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round"/>
    </svg>
  );
}

Object.assign(window, { ChatStopCanvas });
