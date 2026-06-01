// Canvas artboards for issue #1343 —
// Highlight-landing locate/flash indicator (feature #74).
//
// When the reader jumps to a saved highlight from the Notes/Highlights list,
// the persisted wash already paints at the spot — the gap is a transient
// "here it is" cue. Today handleNavigateToLocator sets a temp highlight == the
// persisted range and setHighlightRanges(persisted:active:) dedups it away, so
// nothing happens.
//
// Decision: the "locate bloom" — a single confident value-lift of the wash +
// a same-hue focus ring + soft glow that blooms once and settles. NOT a strobe.
//
// Sections:
//   1. Decision        — live looping bloom, Paper + Dark, annotated
//   2. Keyframes       — rest → peak → mid-decay → settled (the curve, frozen)
//   3. Candidates      — bloom (pick) vs strobe / hard-flash / wash-only / margin-tick
//   4. Colour          — bloom preserves the highlight's own hue (4 colours)
//   5. Across themes    — peak across all five themes (Photo is the stress case)
//   6. Off-screen       — scroll-to-prominent, then bloom (3 frames)
//   7. Reduce-Motion    — static hold + single opacity fade, no movement
//   8. Spec card        — binding motion + token contract

// ─────────────────────────────────────────────────────
// Tokens — washes match vreader-reader.jsx Segments, swatches match HP_SWATCH
// ─────────────────────────────────────────────────────
const HL_WASH  = { yellow: [240,210,90], pink: [232,140,160], green: [140,200,140], blue: [140,180,232] };
const HL_SOLID = { yellow: '#f0d25a',    pink: '#e88ca0',     green: '#8cc88c',     blue: '#8cb4e8' };
const REST_A = 0.42;   // persisted resting alpha
const PEAK_A = 0.86;   // bloom peak alpha

const RL_FONT  = '"Inter", system-ui, -apple-system, sans-serif';
const RL_SERIF = '"Source Serif 4", Georgia, serif';
const RL_MONO  = '"SF Mono", "JetBrains Mono", Menlo, monospace';

function rl_rgba(color, a) { const w = HL_WASH[color] || HL_WASH.yellow; return `rgba(${w[0]},${w[1]},${w[2]},${a})`; }
function rl_glowA(t) { return t.isDark ? 0.85 : 0.55; }

// Frozen inline style for a given phase — drives the keyframe artboards.
//   rest / settle  → identical to the persisted wash (the "no cue" baseline)
//   peak           → max bloom
//   decay          → ~half way back
function landingStyle(color, t, phase) {
  const solid = HL_SOLID[color] || HL_SOLID.yellow;
  const ga = rl_glowA(t);
  const rest = { background: rl_rgba(color, REST_A), boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.04)' };
  if (phase === 'peak') return {
    background: rl_rgba(color, PEAK_A),
    boxShadow: `0 0 0 1.6px ${solid}, 0 0 16px 3px ${rl_rgba(color, ga)}`,
  };
  if (phase === 'decay') return {
    background: rl_rgba(color, (REST_A + PEAK_A) / 2),
    boxShadow: `0 0 0 1px ${solid}, 0 0 9px 1px ${rl_rgba(color, ga * 0.5)}`,
  };
  return rest; // rest | settle
}

const HL_SPAN_BASE = {
  padding: '0 2px', borderRadius: 3,
  WebkitBoxDecorationBreak: 'clone', boxDecorationBreak: 'clone',
  cursor: 'default',
};

// ─────────────────────────────────────────────────────
// Frozen highlighted phrase
// ─────────────────────────────────────────────────────
function FrozenMark({ color = 'yellow', t, phase, children }) {
  return <span style={{ ...HL_SPAN_BASE, color: t.ink, ...landingStyle(color, t, phase) }}>{children}</span>;
}

// ─────────────────────────────────────────────────────
// Live looping bloom — injects its own @keyframes so each instance is isolated.
// The active part of the cycle is ~1.5s; the rest of the cycle is dwell so the
// designer sees it fire, settle, and fire again (in-app it fires ONCE).
// ─────────────────────────────────────────────────────
function LocateBloom({ color = 'yellow', t, children, cycle = 4.6, kind = 'bloom' }) {
  const uid = React.useId().replace(/[:]/g, '');
  const solid = HL_SOLID[color] || HL_SOLID.yellow;
  const ga = rl_glowA(t);
  const name = `hlLocate_${kind}_${uid}`;
  const restBox = 'inset 0 -1px 0 rgba(0,0,0,0.04)';

  // Active window 0→32% of the cycle ≈ 1.47s of 4.6s.
  // 0–3% rise (~140ms) · 3–8% hold · 8–32% decay · 32–100% rest.
  let css;
  if (kind === 'strobe') {
    // rejected candidate — visualised so the canvas can show what we DIDN'T pick
    css = `@keyframes ${name}{
      0%,100%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      6%{background:${rl_rgba(color,PEAK_A)};box-shadow:0 0 0 1.4px ${solid};}
      12%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      18%{background:${rl_rgba(color,PEAK_A)};box-shadow:0 0 0 1.4px ${solid};}
      24%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      30%{background:${rl_rgba(color,PEAK_A)};box-shadow:0 0 0 1.4px ${solid};}
      36%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
    }`;
  } else if (kind === 'flash') {
    // rejected — hard flash to white erases the hue for a beat
    css = `@keyframes ${name}{
      0%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      3%{background:rgba(255,255,255,0.92);box-shadow:0 0 14px 4px rgba(255,255,255,0.7);}
      8%{background:rgba(255,255,255,0.85);box-shadow:0 0 10px 2px rgba(255,255,255,0.5);}
      32%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      100%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
    }`;
  } else if (kind === 'washonly') {
    // alternate — brighten with no ring / glow
    css = `@keyframes ${name}{
      0%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      3%{background:${rl_rgba(color,PEAK_A)};box-shadow:${restBox};}
      8%{background:${rl_rgba(color,PEAK_A)};box-shadow:${restBox};}
      32%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      100%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
    }`;
  } else {
    // committed — bloom
    css = `@keyframes ${name}{
      0%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      3%{background:${rl_rgba(color,PEAK_A)};box-shadow:0 0 0 1.6px ${solid},0 0 18px 4px ${rl_rgba(color,ga)};}
      8%{background:${rl_rgba(color,PEAK_A)};box-shadow:0 0 0 1.5px ${solid},0 0 15px 3px ${rl_rgba(color,ga*0.85)};}
      32%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
      100%{background:${rl_rgba(color,REST_A)};box-shadow:${restBox};}
    }`;
  }

  return (
    <>
      <style>{css}</style>
      <span style={{
        ...HL_SPAN_BASE, color: t.ink,
        animation: `${name} ${cycle}s cubic-bezier(0.22,1,0.36,1) infinite`,
      }}>{children}</span>
    </>
  );
}

// ─────────────────────────────────────────────────────
// Reduce-motion fallback — static hold then a single opacity fade. No movement.
// ─────────────────────────────────────────────────────
function ReducedHold({ color = 'yellow', t, children, cycle = 4.6 }) {
  const uid = React.useId().replace(/[:]/g, '');
  const solid = HL_SOLID[color] || HL_SOLID.yellow;
  const name = `hlReduced_${uid}`;
  // peak is a SEPARATE overlay span; we only fade its opacity. No transform.
  const css = `@keyframes ${name}{
    0%{opacity:0;}
    1%{opacity:1;}
    26%{opacity:1;}
    33%{opacity:0;}
    100%{opacity:0;}
  }`;
  return (
    <span style={{ position: 'relative', ...HL_SPAN_BASE, color: t.ink, background: rl_rgba(color, REST_A), boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.04)' }}>
      {children}
      <style>{css}</style>
      <span aria-hidden style={{
        position: 'absolute', inset: 0, borderRadius: 3, pointerEvents: 'none',
        background: rl_rgba(color, PEAK_A), boxShadow: `0 0 0 1.6px ${solid}`,
        animation: `${name} ${cycle}s steps(1, end) infinite`,
      }}/>
    </span>
  );
}

// ─────────────────────────────────────────────────────
// Reader phone frame — faithful chrome + a page of P&P with one saved highlight
// in paragraph 2. `mark` is a render-prop returning the emphasis span.
// ─────────────────────────────────────────────────────
const RF_W = 390, RF_H = 720;

function ReaderFrame({ themeKey = 'paper', mark, topOffset = 0, clipNote = null, originPulse = false }) {
  const t = THEMES[themeKey];
  const ff = RL_SERIF;
  const phrase = 'he is considered as the rightful property of some one or other of their daughters';

  const para = (children, i, first) => (
    <p key={i} style={{
      fontFamily: ff, fontSize: 17, lineHeight: 1.6, color: t.ink, margin: 0,
      marginBottom: 11, textIndent: first ? 0 : 24, textAlign: 'justify', hyphens: 'auto',
    }}>{children}</p>
  );

  return (
    <div style={{
      width: RF_W, height: RF_H, position: 'relative', overflow: 'hidden',
      background: t.image ? '#2a2520' : t.bg, color: t.ink, borderRadius: 20,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 16px 46px rgba(0,0,0,0.4)',
    }}>
      {t.image && (
        <div style={{ position: 'absolute', inset: 0, opacity: 0.5,
          background: 'radial-gradient(ellipse at 22% 28%, rgba(216,136,90,0.18) 0%, transparent 55%), radial-gradient(ellipse at 78% 72%, rgba(122,58,31,0.2) 0%, transparent 55%)' }}/>
      )}

      {/* status bar */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, height: 44, zIndex: 10,
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 24px 6px', fontSize: 13, fontWeight: 600, color: t.ink }}>
        <span>9:41</span>
        <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
          <svg width="14" height="10" viewBox="0 0 14 10"><circle cx="2" cy="9" r="1" fill={t.ink}/><circle cx="6" cy="7" r="1" fill={t.ink}/><circle cx="10" cy="5" r="1" fill={t.ink}/><circle cx="14" cy="3" r="1" fill={t.ink}/></svg>
          <span style={{ fontSize: 10 }}>100%</span>
        </span>
      </div>

      {/* top chrome */}
      <div style={{ position: 'absolute', top: 44, left: 0, right: 0, paddingTop: 6, paddingBottom: 12, zIndex: 10,
        background: t.image ? 'rgba(0,0,0,0.5)' : t.chrome, borderBottom: `0.5px solid ${t.rule}` }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: t.accent, fontSize: 15, fontWeight: 500 }}>
            <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library
          </div>
          <div style={{ fontFamily: ff, fontSize: 14, fontStyle: 'italic', fontWeight: 600, color: t.ink }}>Pride and Prejudice</div>
          <div style={{ display: 'flex' }}>
            <Icons.Search size={18} color={t.ink} stroke={1.7} style={{ margin: 9 }}/>
            <Icons.Bookmark size={18} color={t.ink} stroke={1.7} style={{ margin: 9 }}/>
            <Icons.More size={20} color={t.ink} stroke={1.7} style={{ margin: 8 }}/>
          </div>
        </div>
      </div>

      {/* page content */}
      <div style={{ position: 'absolute', top: 88, bottom: 136, left: 26, right: 26, overflow: 'hidden' }}>
        <div style={{ transform: `translateY(${topOffset}px)` }}>
          <div style={{ fontFamily: ff, fontSize: 13, color: t.sub, letterSpacing: 2,
            textTransform: 'uppercase', textAlign: 'center', marginBottom: 18, marginTop: 4, fontWeight: 500 }}>Chapter 1</div>
          {para(<>
            <span style={{ fontFamily: ff, fontSize: 44, lineHeight: 0.85, float: 'left', marginRight: 6, marginTop: 4, color: t.accent, fontWeight: 600 }}>I</span>
            t is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.
          </>, 0, true)}
          {para(<>
            However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that {mark ? mark(phrase) : phrase}.
          </>, 1)}
          {para('“My dear Mr. Bennet,” said his lady to him one day, “have you heard that Netherfield Park is let at last?”', 2)}
          {para('Mr. Bennet replied that he had not.', 3)}
          {para('“But it is,” returned she; “for Mrs. Long has just been here, and she told me all about it.”', 4)}
        </div>
      </div>

      {clipNote && (
        <div style={{ position: 'absolute', left: 14, right: 14, bottom: 150, zIndex: 40,
          padding: '7px 12px', borderRadius: 10, background: 'rgba(168,58,58,0.94)', color: '#fff',
          fontFamily: RL_FONT, fontSize: 11, fontWeight: 600, textAlign: 'center',
          boxShadow: '0 4px 12px rgba(0,0,0,0.3)' }}>{clipNote}</div>
      )}

      {/* bottom chrome */}
      <div style={{ position: 'absolute', bottom: 0, left: 0, right: 0, paddingBottom: 28, paddingTop: 14, zIndex: 10,
        background: t.image ? 'rgba(0,0,0,0.55)' : t.chrome, borderTop: `0.5px solid ${t.rule}` }}>
        <div style={{ padding: '0 22px', marginBottom: 14 }}>
          <div style={{ height: 3, borderRadius: 2, background: t.rule, position: 'relative' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '34%', background: t.accent, borderRadius: 2 }}/>
            <div style={{ position: 'absolute', left: '34%', top: '50%', width: 14, height: 14, borderRadius: 7, background: t.accent, transform: 'translate(-50%,-50%)' }}/>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: t.sub, marginTop: 4 }}>
            <span>Page 147</span><span>285 pages left in book</span>
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-around', padding: '0 12px' }}>
          {[
            { ico: Icons.TOC, l: 'Contents' },
            { ico: Icons.Highlighter, l: 'Notes', origin: true },
            { ico: Icons.Aa, l: 'Display' },
            { ico: Icons.Sparkle, l: 'AI', accent: true },
          ].map((b, i) => (
            <div key={i} style={{ position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, padding: '4px 12px' }}>
              <b.ico size={22} color={b.accent ? t.accent : t.ink} stroke={1.8}/>
              <span style={{ fontSize: 10, color: b.accent ? t.accent : t.sub, fontWeight: 500 }}>{b.l}</span>
              {originPulse && b.origin && (
                <div style={{ position: 'absolute', top: 0, right: 6, width: 7, height: 7, borderRadius: 4, background: t.accent, boxShadow: `0 0 0 3px ${t.accent}33` }}/>
              )}
            </div>
          ))}
        </div>
      </div>

      {/* home indicator */}
      <div style={{ position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 100, zIndex: 12,
        background: t.isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.32)' }}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Annotation chips / post-its
// ─────────────────────────────────────────────────────
function RLChip({ tone = 'info', children }) {
  const map = {
    pick:   { bg: 'rgba(42,122,68,0.96)', fg: '#fff' },
    reject: { bg: 'rgba(168,58,58,0.94)', fg: '#fff' },
    alt:    { bg: 'rgba(166,120,40,0.96)', fg: '#fff' },
    info:   { bg: 'rgba(40,36,30,0.88)', fg: '#fff' },
  }[tone];
  return (
    <span style={{ display: 'inline-flex', alignItems: 'center', gap: 6, padding: '4px 10px', borderRadius: 100,
      background: map.bg, color: map.fg, fontSize: 11, fontWeight: 700, letterSpacing: 0.3, fontFamily: RL_FONT,
      boxShadow: '0 3px 9px rgba(0,0,0,0.16)' }}>{children}</span>
  );
}
function RLNote({ top, left, right, bottom, tone, children }) {
  return <div style={{ position: 'absolute', top, left, right, bottom, zIndex: 30 }}><RLChip tone={tone}>{children}</RLChip></div>;
}

// A frozen "phase strip" caption under the keyframe frames.
function PhaseTag({ label, ms, t = THEMES.paper }) {
  return (
    <div style={{ position: 'absolute', top: 14, left: 14, zIndex: 30, display: 'flex', flexDirection: 'column', gap: 4 }}>
      <RLChip tone="info">{label}</RLChip>
      <span style={{ fontFamily: RL_MONO, fontSize: 11, color: '#fff', opacity: 0.8, paddingLeft: 4,
        textShadow: '0 1px 3px rgba(0,0,0,0.6)' }}>{ms}</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Candidate card — one treatment, live, with verdict
// ─────────────────────────────────────────────────────
function CandidateCard({ themeKey = 'paper', kind, name, verdict, why }) {
  const t = THEMES[themeKey];
  const sentence = 'that he is considered as the rightful property of some one or other of their daughters.';
  const lead = 'However little known the feelings of such a man, this truth is so well fixed in the minds of the surrounding families, ';
  const idx = sentence.indexOf('he is considered as the rightful property of some one or other of their daughters');
  const before = 'that ';
  const markText = 'he is considered as the rightful property of some one or other of their daughters';
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: t.bg, borderRadius: 0,
      padding: '22px 24px 20px', fontFamily: RL_FONT, position: 'relative', overflow: 'hidden' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 4 }}>
        <div style={{ fontFamily: RL_SERIF, fontSize: 19, fontWeight: 700, color: t.ink }}>{name}</div>
        <RLChip tone={verdict === 'pick' ? 'pick' : verdict === 'alt' ? 'alt' : 'reject'}>
          {verdict === 'pick' ? 'RECOMMEND' : verdict === 'alt' ? 'ALT' : 'REJECT'}
        </RLChip>
      </div>
      <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.45, marginBottom: 18, maxWidth: 440, textWrap: 'pretty' }}>{why}</div>
      <div style={{ background: t.image ? 'rgba(0,0,0,0.35)' : (t.isDark ? '#21201c' : t.paper), borderRadius: 12,
        padding: '20px 22px', boxShadow: `inset 0 0 0 0.5px ${t.rule}` }}>
        <p style={{ fontFamily: RL_SERIF, fontSize: 17, lineHeight: 1.62, color: t.ink, margin: 0, textAlign: 'justify' }}>
          {before}
          <LocateBloom color="yellow" t={t} kind={kind}>{markText}</LocateBloom>
          {'.'}
        </p>
      </div>
      <div style={{ position: 'absolute', bottom: 14, right: 18, fontFamily: RL_MONO, fontSize: 10.5, color: t.sub, opacity: 0.7 }}>preview loops · fires once in-app</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding contract
// ─────────────────────────────────────────────────────
function RLSpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '150px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 13.5, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: RL_MONO, background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: RL_FONT, overflow: 'auto' }}>
      <div style={{ fontFamily: RL_SERIF, fontSize: 25, fontWeight: 700, marginBottom: 4 }}>Locate bloom — binding spec</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 16, maxWidth: 600 }}>
        Resolves #1343. The fixer reads one token bag; the emphasis renders as a third range layer, not a deduped temp highlight.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>The no-op fix</div>
        <div style={valStyle}>
          <span style={code}>setHighlightRanges(persisted:active:)</span> gains a third arg:
          <span style={code}>landing</span>. It is <b>not</b> deduped against <span style={code}>persisted</span>, so a
          transient range equal to a saved one still renders. Closes the dedup the issue describes.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Curve</div>
        <div style={valStyle}>
          rise <b>140ms</b> ease-out <span style={code}>cubic-bezier(0.22,1,0.36,1)</span> · hold <b>~220ms</b> ·
          decay <b>~1140ms</b> ease-in-out. <b>Total ≈ 1.5s</b>, single fire. Any tap / page-turn / scroll cancels to resting.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Layers</div>
        <div style={valStyle}>
          (1) wash value-lift <span style={code}>α 0.42 → 0.86 → 0.42</span>, same hue.
          (2) ring <span style={code}>0 0 0 1.6px {'{solidSwatch}'}</span> + glow <span style={code}>0 0 16px 3px {'{hue}'}</span>,
          applied with <span style={code}>box-decoration-break: clone</span> so it traces every line-fragment.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Hue, not accent</div>
        <div style={valStyle}>
          The bloom uses the highlight's OWN colour ({HL_COLOR_LIST}). Never recoloured to <span style={code}>t.accent</span> —
          the colour is the highlight's identity.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Theme knob</div>
        <div style={valStyle}>
          glow alpha = <span style={code}>{'{hue}'} @ 0.55</span> light family · <span style={code}>@ 0.85</span> dark family.
          Ring stays the solid swatch on both — it never depends on the wash to read. Photo is the stress case.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Off-screen</div>
        <div style={valStyle}>
          Reposition the range into the reading band (~38% from top), settle, then bloom. Never bloom a clipped range.
          Paged → paginate; Scroll → smooth-scroll to <span style={code}>scrollEnd</span>.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Reduce-Motion</div>
        <div style={valStyle}>
          <span style={code}>prefers-reduced-motion</span> / in-app setting → wash snaps to peak + solid outline,
          holds 1.2s, single <b>opacity</b> fade out (320ms). No transform, glow-spread, or loop. Reposition becomes an instant jump.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>State</div>
        <div style={valStyle}>
          <span style={code}>ReaderViewModel.landingHighlight = {'{ id, nonce }'}</span>, set by
          <span style={code}>handleNavigateToLocator</span>, cleared on next interaction. Re-tap a row → bump nonce → re-fire.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Source of truth</div>
        <div style={valStyle}>
          <span style={code}>docs/features.md</span> row #74. Token bag <span style={code}>LocateBloom</span> mirrors the
          auto-turn ribbon token in <span style={code}>reader-navigation.md</span>.
        </div>
      </div>
    </div>
  );
}
const HL_COLOR_LIST = 'yellow · pink · green · blue';

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function HighlightLandingCanvas() {
  return (
    <DesignCanvas style={{ background: '#0f0d0c' }}>

      {/* ─── 1. Decision ─── */}
      <DCSection id="decision"
        title="#1343 — Highlight-landing locate indicator · the locate bloom"
        subtitle="Jump to a saved highlight from the Notes list and the persisted wash is already there — the gap is a transient ‘here it is’ cue (today it's deduped to a no-op). Decision: a single confident bloom — the wash brightens, a same-hue ring + soft glow blooms once and settles. Not a strobe. Previews loop; in-app it fires once.">
        <DCArtboard id="dec-paper" label="Paper · locate bloom (looping preview)" width={RF_W} height={RF_H}>
          <ReaderFrame themeKey="paper" originPulse
            mark={(txt) => <LocateBloom color="yellow" t={THEMES.paper} kind="bloom">{txt}</LocateBloom>}/>
        </DCArtboard>
        <DCArtboard id="dec-dark" label="Dark · locate bloom (looping preview)" width={RF_W} height={RF_H}>
          <ReaderFrame themeKey="dark" originPulse
            mark={(txt) => <LocateBloom color="yellow" t={THEMES.dark} kind="bloom">{txt}</LocateBloom>}/>
        </DCArtboard>
        <DCPostIt top={-34} right={30} rotate={2} width={272}>
          One bloom, ~1.5&nbsp;s, then the page is just a page. The wash is the hero (its own hue brightens); the ring + glow are the locator. A strobe would read as an <i>alert</i>, not “found it.”
        </DCPostIt>
      </DCSection>

      {/* ─── 2. Keyframes ─── */}
      <DCSection id="keyframes"
        title="The curve · four frozen keyframes"
        subtitle="Rest is identical to the persisted highlight (the ‘no cue’ baseline the issue flags). Rise to peak in ~140ms, hold, then a slow decay back to rest over ~1.1s. The settle dissolves into the highlight that was already on the page.">
        {[
          { ph: 'rest',  lab: 'Rest · persisted', ms: 't = 0ms  (no cue — today)', tone: 'reject' },
          { ph: 'peak',  lab: 'Peak · bloom',     ms: 't ≈ 140–360ms', tone: 'pick' },
          { ph: 'decay', lab: 'Mid-decay',        ms: 't ≈ 800ms', tone: 'info' },
          { ph: 'rest',  lab: 'Settled',          ms: 't ≈ 1500ms', tone: 'info' },
        ].map((k, i) => (
          <DCArtboard key={i} id={`kf-${i}`} label={k.lab} width={RF_W} height={RF_H}>
            <div style={{ position: 'relative', width: '100%', height: '100%' }}>
              <ReaderFrame themeKey="paper"
                mark={(txt) => <FrozenMark color="yellow" t={THEMES.paper} phase={k.ph}>{txt}</FrozenMark>}/>
              <PhaseTag label={k.lab} ms={k.ms}/>
            </div>
          </DCArtboard>
        ))}
        <DCPostIt top={-30} left={20} rotate={-2} width={240}>
          Frame 1 and frame 4 are pixel-identical — that's the point. The cue is entirely in the <i>transition</i>, and it leaves no residue.
        </DCPostIt>
      </DCSection>

      {/* ─── 3. Candidates ─── */}
      <DCSection id="candidates"
        title="Treatments explored"
        subtitle="The issue's menu — pulse / flash / glow / scroll-to-prominent — measured against ‘reads as found-it, not as an alert.’ Each preview loops the treatment on the same passage.">
        <DCArtboard id="cand-bloom" label="Bloom — brighten + hue ring + glow" width={520} height={300}>
          <CandidateCard themeKey="paper" kind="bloom" name="Locate bloom" verdict="pick"
            why="Wash brightens in its own hue, a crisp swatch ring + soft glow bloom once and settle. Draws the eye without ever reading as an error. The committed treatment."/>
        </DCArtboard>
        <DCArtboard id="cand-strobe" label="Strobe — repeated pulse" width={520} height={300}>
          <CandidateCard themeKey="paper" kind="strobe" name="Strobe pulse" verdict="reject"
            why="Blinks 3× on landing. Reads as a notification badge or an error state — the loudest thing in a quiet reading app. Fights the one-shot tap-hint + skeleton cues we already designed."/>
        </DCArtboard>
        <DCArtboard id="cand-flash" label="Hard flash — to white" width={520} height={300}>
          <CandidateCard themeKey="paper" kind="flash" name="Hard flash" verdict="reject"
            why="A white flash erases the highlight's colour for a beat — destroying exactly the thing the reader navigated to. Also harsh on OLED / dark."/>
        </DCArtboard>
        <DCArtboard id="cand-wash" label="Wash-only — brighten, no ring" width={520} height={300}>
          <CandidateCard themeKey="paper" kind="washonly" name="Wash-only brighten" verdict="alt"
            why="Gentle and on-brand, but on a page already full of warm wash it can be missed — the value-lift alone is subtle. The ring is what makes it locate. Viable low-key fallback."/>
        </DCArtboard>
        <DCPostIt top={-30} right={30} rotate={2} width={256}>
          Scroll-to-prominent isn't a rival treatment — it's the <i>delivery</i> for the off-screen case (§6). The bloom still fires once the target lands in the band.
        </DCPostIt>
      </DCSection>

      {/* ─── 4. Colour ─── */}
      <DCSection id="colour"
        title="Colour interaction · the bloom keeps the highlight's hue"
        subtitle="The reader navigated to a specific note they made in a specific colour. The bloom brightens and rings that same hue — it never swaps to the theme accent. Peak frame, all four highlight colours, Paper.">
        {['yellow','pink','green','blue'].map(c => (
          <DCArtboard key={c} id={`col-${c}`} label={`${c[0].toUpperCase()}${c.slice(1)} highlight · peak`} width={520} height={150}>
            <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: THEMES.paper.paper,
              display: 'flex', alignItems: 'center', padding: '0 30px' }}>
              <p style={{ fontFamily: RL_SERIF, fontSize: 17, lineHeight: 1.62, color: THEMES.paper.ink, margin: 0, textAlign: 'justify' }}>
                this truth is so well fixed in the minds of the surrounding families, that <FrozenMark color={c} t={THEMES.paper} phase="peak">he is considered the rightful property of some one or other of their daughters</FrozenMark>.
              </p>
            </div>
          </DCArtboard>
        ))}
      </DCSection>

      {/* ─── 5. Across themes ─── */}
      <DCSection id="themes"
        title="Across the five themes · peak"
        subtitle="The wash + ring + glow must read on Paper / Sepia (light) and Dark / OLED / Photo (dark). The glow alpha lifts on dark themes (0.55 → 0.85); the solid swatch ring is the same crisp colour on both, so it never depends on the dim wash. Photo is the stress case.">
        {['paper','sepia','dark','oled','image'].map(k => (
          <DCArtboard key={k} id={`th-${k}`} label={`${THEMES[k].name} · peak`} width={520} height={150}>
            <div style={{ width: '100%', height: '100%', boxSizing: 'border-box',
              background: THEMES[k].image ? '#2a2520' : THEMES[k].paper,
              position: 'relative', display: 'flex', alignItems: 'center', padding: '0 30px' }}>
              {THEMES[k].image && <div style={{ position: 'absolute', inset: 0,
                background: 'radial-gradient(ellipse at 25% 30%, rgba(216,136,90,0.2) 0%, transparent 55%), radial-gradient(ellipse at 80% 70%, rgba(122,58,31,0.22) 0%, transparent 55%)' }}/>}
              <p style={{ position: 'relative', fontFamily: RL_SERIF, fontSize: 16.5, lineHeight: 1.62, color: THEMES[k].ink, margin: 0, textAlign: 'justify' }}>
                this truth is so well fixed in the minds of the families, that <FrozenMark color="yellow" t={THEMES[k]} phase="peak">he is considered the rightful property of some one or other of their daughters</FrozenMark>.
              </p>
            </div>
          </DCArtboard>
        ))}
        <DCPostIt top={-30} left={20} rotate={-2} width={236}>
          On Dark/OLED/Photo the resting wash is dim — the brighter glow + the solid ring carry the cue. The ring is the constant across all five.
        </DCPostIt>
      </DCSection>

      {/* ─── 6. Off-screen ─── */}
      <DCSection id="offscreen"
        title="Off-screen at landing · scroll-to-prominent, then bloom"
        subtitle="A saved range can land clipped — split across the page break or jammed under the chrome. Blooming a half-visible highlight is worse than no cue. Reposition into the reading band (~38% from top), settle, then bloom.">
        <DCArtboard id="off-before" label="① Landing · range clipped under chrome (don't bloom here)" width={RF_W} height={RF_H}>
          <ReaderFrame themeKey="paper" topOffset={372}
            clipNote="↓ Saved range lands clipped at the page edge ↓"
            mark={(txt) => <FrozenMark color="yellow" t={THEMES.paper} phase="rest">{txt}</FrozenMark>}/>
        </DCArtboard>
        <DCArtboard id="off-reposition" label="② Reposition into the reading band (~38% from top)" width={RF_W} height={RF_H}>
          <ReaderFrame themeKey="paper" topOffset={0}
            mark={(txt) => <FrozenMark color="yellow" t={THEMES.paper} phase="rest">{txt}</FrozenMark>}/>
        </DCArtboard>
        <DCArtboard id="off-bloom" label="③ Settled in band → bloom fires" width={RF_W} height={RF_H}>
          <ReaderFrame themeKey="paper" topOffset={0}
            mark={(txt) => <FrozenMark color="yellow" t={THEMES.paper} phase="peak">{txt}</FrozenMark>}/>
        </DCArtboard>
        <DCPostIt top={-30} right={30} rotate={2} width={250}>
          The band keeps the target where the eye already reads — not at the very top or bottom edge, where it's technically on-screen but easy to miss.
        </DCPostIt>
      </DCSection>

      {/* ─── 7. Reduce-Motion ─── */}
      <DCSection id="reduced"
        title="Reduce-Motion fallback · hold + single fade"
        subtitle="prefers-reduced-motion (and the in-app Reduce Motion setting) swap the bloom for a static hold: wash snaps to peak + a solid outline, holds ~1.2s, then a single opacity fade — no scale, no glow-spread, no loop. Reposition becomes an instant jump. Left: the held emphasis. Right: the looping fade-out preview.">
        <DCArtboard id="rm-hold" label="Static hold · peak + solid outline (no movement)" width={520} height={150}>
          <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: THEMES.paper.paper,
            display: 'flex', alignItems: 'center', padding: '0 30px' }}>
            <p style={{ fontFamily: RL_SERIF, fontSize: 17, lineHeight: 1.62, color: THEMES.paper.ink, margin: 0, textAlign: 'justify' }}>
              this truth is so well fixed in the minds of the surrounding families, that <span style={{ ...HL_SPAN_BASE, color: THEMES.paper.ink, background: rl_rgba('yellow', PEAK_A), boxShadow: `0 0 0 1.6px ${HL_SOLID.yellow}` }}>he is considered the rightful property of some one or other of their daughters</span>.
            </p>
          </div>
        </DCArtboard>
        <DCArtboard id="rm-fade" label="Opacity fade-out only (looping preview)" width={520} height={150}>
          <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: THEMES.paper.paper,
            display: 'flex', alignItems: 'center', padding: '0 30px' }}>
            <p style={{ fontFamily: RL_SERIF, fontSize: 17, lineHeight: 1.62, color: THEMES.paper.ink, margin: 0, textAlign: 'justify' }}>
              this truth is so well fixed in the minds of the surrounding families, that <ReducedHold color="yellow" t={THEMES.paper}>he is considered the rightful property of some one or other of their daughters</ReducedHold>.
            </p>
          </div>
        </DCArtboard>
        <DCArtboard id="rm-dark" label="Reduce-Motion · Dark · static hold" width={520} height={150}>
          <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: THEMES.dark.paper,
            display: 'flex', alignItems: 'center', padding: '0 30px' }}>
            <p style={{ fontFamily: RL_SERIF, fontSize: 17, lineHeight: 1.62, color: THEMES.dark.ink, margin: 0, textAlign: 'justify' }}>
              this truth is so well fixed in the minds of the surrounding families, that <span style={{ ...HL_SPAN_BASE, color: THEMES.dark.ink, background: rl_rgba('yellow', PEAK_A), boxShadow: `0 0 0 1.6px ${HL_SOLID.yellow}` }}>he is considered the rightful property of some one or other of their daughters</span>.
            </p>
          </div>
        </DCArtboard>
      </DCSection>

      {/* ─── 8. Spec ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what the fixer builds against.">
        <DCArtboard id="spec-card" label="" width={760} height={640}>
          <RLSpecCard/>
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { HighlightLandingCanvas });
