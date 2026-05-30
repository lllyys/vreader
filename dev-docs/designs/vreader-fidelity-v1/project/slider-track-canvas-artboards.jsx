// Canvas artboards for issue #1273 —
// Paper / Sepia slider-track (rail) contrast for the Reader Display panel.
//
// Carves out the one design-needs sub-symptom of Bug #285 (GH #1265):
// the SettingsSliderRow UNFILLED track reads as "no rail" on the cream
// sheet in the light-family themes.
//
// The committed value (vreader-panels.jsx · SliderRow):
//     track = t.isDark ? rgba(255,255,255,0.1) : rgba(0,0,0,0.1)
// Over the panel's #fcf8f0 sheet that computes to ~1.25:1 — a cold,
// pure-black smudge that disappears into warm cream.
//
// Decision: introduce a real `t.sliderTrack` token (Rule 51 — the fixer
// needs a token, not an invented opacity). Light family = ink @ 22%,
// which tracks each theme's own warmth and lifts the rail to a clearly
// legible weight without the heavy 3:1 slab. The high-contrast accent
// fill (~7:1) + white thumb already carry value/state, so WCAG 1.4.11 is
// satisfied; the rail is decorative extent, tuned for aesthetics.
//
// Sections:
//   1. Decision        — recommended Paper / Sepia panels, the token
//   2. The bug         — current rail, measured, annotated
//   3. Candidates      — current · rule-token · ink@22 · ink@32, measured
//   4. Thumb positions — default · dragging · min · max (the explicit ask)
//   5. Across themes    — paper/sepia change · dark/OLED confirmed unchanged
//   6. Spec card        — binding token contract

// ─────────────────────────────────────────────────────
// Colour / contrast helpers (sRGB WCAG 2.x)
// ─────────────────────────────────────────────────────
function stParse(c) {
  if (c[0] === '#') {
    let h = c.slice(1);
    if (h.length === 3) h = h.split('').map(x => x + x).join('');
    return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16), a: 1 };
  }
  const m = c.match(/rgba?\(([^)]+)\)/);
  const p = m[1].split(',').map(s => parseFloat(s.trim()));
  return { r: p[0], g: p[1], b: p[2], a: p[3] === undefined ? 1 : p[3] };
}
function stOver(fg, a, bg) { return [0, 1, 2].map(i => Math.round(bg[i] * (1 - a) + fg[i] * a)); }
function stLum([r, g, b]) {
  const f = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function stRatio(a, b) {
  const L1 = stLum(a), L2 = stLum(b);
  const hi = Math.max(L1, L2), lo = Math.min(L1, L2);
  return (hi + 0.05) / (lo + 0.05);
}
function stWithAlpha(hex, a) { const c = stParse(hex); return `rgba(${c.r},${c.g},${c.b},${a})`; }

// The sheet surface (Sheet hardcodes these) and the row container overlay.
function stSheetRGB(t) { return t.isDark ? [34, 32, 32] : [252, 248, 240]; } // #222020 / #fcf8f0
function stRowOverlay(t) { return t.isDark ? { c: [255, 255, 255], a: 0.05 } : { c: [0, 0, 0], a: 0.04 }; }
function stRowBg(t) { const o = stRowOverlay(t); return stOver(o.c, o.a, stSheetRGB(t)); }

// Measured contrast of a rail string against its row container surface.
function stRailRatio(railStr, t) {
  const rowBg = stRowBg(t);
  const r = stParse(railStr);
  const solid = stOver([r.r, r.g, r.b], r.a, rowBg);
  return stRatio(solid, rowBg);
}

// ─────────────────────────────────────────────────────
// The recommended token & the light-family candidates
// ─────────────────────────────────────────────────────
const SLIDER_TRACK = {            // proposed t.sliderTrack
  paper: 'rgba(29,26,20,0.22)',   // ink @ 22%
  sepia: 'rgba(58,41,19,0.22)',   // ink @ 22%
  dark:  'rgba(216,210,197,0.12)',// unchanged weight (bug doesn't apply)
  oled:  'rgba(185,182,176,0.12)',// unchanged weight
};
const RAIL_CURRENT = { paper: 'rgba(0,0,0,0.10)', sepia: 'rgba(0,0,0,0.10)', dark: 'rgba(255,255,255,0.10)', oled: 'rgba(255,255,255,0.10)' };

const CANDIDATES = [
  { key: 'current', name: 'Current', note: 'black @ 10% · committed',
    paper: 'rgba(0,0,0,0.10)', sepia: 'rgba(0,0,0,0.10)', verdict: 'reject',
    why: 'Cold pure-black at low alpha dissolves into warm cream. The bug.' },
  { key: 'rule', name: 'rule token', note: 'reuse the hairline token',
    paper: THEMES.paper.rule, sepia: THEMES.sepia.rule, verdict: 'reject',
    why: 'Warmer, but `rule` is the divider weight — barely above current.' },
  { key: 'ink22', name: 'ink @ 22%', note: 'warm · token-derived',
    paper: 'rgba(29,26,20,0.22)', sepia: 'rgba(58,41,19,0.22)', verdict: 'pick',
    why: 'Tracks each theme\u2019s warmth; reads clearly as a rail, stays light.' },
  { key: 'ink32', name: 'ink @ 32%', note: 'heavier alternate',
    paper: 'rgba(29,26,20,0.32)', sepia: 'rgba(58,41,19,0.32)', verdict: 'alt',
    why: 'More present. Opt in if the panel wants extra weight; nears 2:1.' },
];

const ST_PANEL_W = 380;
const ST_FONT = '"Inter", system-ui, -apple-system, sans-serif';
const ST_SERIF = '"Source Serif 4", Georgia, serif';

// ─────────────────────────────────────────────────────
// Faithful SettingsSliderRow (geometry lifted from vreader-panels.jsx)
// ─────────────────────────────────────────────────────
function STLabel({ t, children }) {
  return (
    <div style={{ fontSize: 12, fontWeight: 600, color: t.sub, letterSpacing: 0.8, textTransform: 'uppercase' }}>
      {children}
    </div>
  );
}

function STSliderRow({ t, rail, p, kind, dragging }) {
  const c = t.sub;
  const fillW = `${p * 100}%`;
  const leftIcon = kind === 'size'
    ? <span style={{ fontFamily: 'serif', fontSize: 12, color: c }}>Aa</span>
    : <svg width="16" height="12" viewBox="0 0 16 12"><path d="M0 2h16M0 6h16M0 10h16" stroke={c} strokeWidth="1.5" /></svg>;
  const rightIcon = kind === 'size'
    ? <span style={{ fontFamily: 'serif', fontSize: 22, color: c }}>Aa</span>
    : <svg width="16" height="14" viewBox="0 0 16 14"><path d="M0 1h16M0 7h16M0 13h16" stroke={c} strokeWidth="1.5" /></svg>;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderRadius: 14, marginTop: 8,
      background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
    }}>
      <div style={{ width: 24, display: 'flex', justifyContent: 'center' }}>{leftIcon}</div>
      <div style={{ flex: 1, height: 24, display: 'flex', alignItems: 'center' }}>
        <div style={{ flex: 1, height: 4, borderRadius: 2, background: rail, position: 'relative' }}>
          <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: fillW, background: t.accent, borderRadius: 2 }} />
          <div style={{
            position: 'absolute', left: fillW, top: '50%',
            width: 22, height: 22, borderRadius: 11, background: '#fff',
            transform: `translate(-50%, -50%) scale(${dragging ? 1.1 : 1})`,
            boxShadow: dragging
              ? `0 2px 9px rgba(0,0,0,0.24), 0 0 0 0.5px rgba(0,0,0,0.06), 0 0 0 7px ${stWithAlpha(t.accent, 0.13)}`
              : '0 1px 4px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.06)',
          }} />
        </div>
      </div>
      <div style={{ width: 28, display: 'flex', justifyContent: 'center' }}>{rightIcon}</div>
    </div>
  );
}

// The Display-panel slice the issue points at — grabber, title, two rows.
function STPanel({ themeKey, rail, sizeP = 0.45, spaceP = 0.6, dragging = null }) {
  const t = THEMES[themeKey];
  const railColor = typeof rail === 'string' ? rail : rail[themeKey];
  const sheet = t.isDark ? '#222020' : '#fcf8f0';
  const hair = t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
  return (
    <div style={{
      width: ST_PANEL_W, background: sheet, borderRadius: 22,
      boxShadow: '0 1px 0 rgba(255,255,255,0.4) inset, 0 14px 34px rgba(0,0,0,0.16)',
      overflow: 'hidden', fontFamily: ST_FONT,
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 10 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
      </div>
      <div style={{ textAlign: 'center', padding: '12px 0 11px', borderBottom: `0.5px solid ${hair}`, fontFamily: ST_SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>
        Display
      </div>
      <div style={{ padding: '16px 18px 20px' }}>
        <STLabel t={t}>Size</STLabel>
        <STSliderRow t={t} rail={railColor} p={sizeP} kind="size" dragging={dragging === 'size'} />
        <div style={{ height: 16 }} />
        <STLabel t={t}>Line spacing</STLabel>
        <STSliderRow t={t} rail={railColor} p={spaceP} kind="spacing" dragging={dragging === 'spacing'} />
      </div>
    </div>
  );
}

// Artboard wrapper — panel on its own reader backdrop, like in-app.
function STStage({ themeKey, children, padTop = 26 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: t.bg, display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
      padding: `${padTop}px 24px 26px`,
    }}>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Verdict / annotation chips
// ─────────────────────────────────────────────────────
function STChip({ tone = 'reject', children }) {
  const map = {
    reject: { bg: 'rgba(168,58,58,0.94)', fg: '#fff' },
    pick:   { bg: 'rgba(42,122,68,0.96)', fg: '#fff' },
    alt:    { bg: 'rgba(166,120,40,0.96)', fg: '#fff' },
    info:   { bg: 'rgba(40,36,30,0.85)', fg: '#fff' },
  }[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '3px 9px', borderRadius: 100, background: map.bg, color: map.fg,
      fontSize: 11, fontWeight: 700, letterSpacing: 0.3, fontFamily: ST_FONT,
      boxShadow: '0 3px 9px rgba(0,0,0,0.14)',
    }}>{children}</span>
  );
}

function STRatioTag({ ratio, pass3 }) {
  const ok = ratio >= 3;
  return (
    <span style={{
      fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace',
      fontSize: 12, fontWeight: 600, color: ok ? '#2a7a44' : '#3a352c',
      fontVariantNumeric: 'tabular-nums',
    }}>{ratio.toFixed(2)}:1</span>
  );
}

// Floating annotation pinned over a stage
function STNote({ top, left, right, tone, children }) {
  return (
    <div style={{ position: 'absolute', top, left, right, zIndex: 4 }}>
      <STChip tone={tone}>{children}</STChip>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Candidate comparison card — real rails, measured ratios
// ─────────────────────────────────────────────────────
function STCompareCard({ themeKey }) {
  const t = THEMES[themeKey];
  const rowBg = stRowBg(t);
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: '#fcf8f0', padding: '30px 34px 34px', fontFamily: ST_FONT, color: THEMES.paper.ink,
      overflow: 'hidden',
    }}>
      <div style={{ fontFamily: ST_SERIF, fontSize: 23, fontWeight: 700, marginBottom: 3 }}>
        Candidate rails — {t.name}
      </div>
      <div style={{ fontSize: 13, color: THEMES.paper.sub, marginBottom: 22 }}>
        Each rail composited over the row surface ({`rgb(${rowBg.join(',')})`}). Ratio is the rail vs that surface.
        The accent fill is {stRailRatio(t.accent, t).toFixed(1)}:1 and the white thumb is ~17:1 — those carry state.
      </div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
        {CANDIDATES.map((cand, i) => {
          const rail = cand[themeKey];
          const r = stRailRatio(rail, t);
          return (
            <div key={cand.key} style={{
              display: 'grid', gridTemplateColumns: '136px 230px 1fr', gap: 18, alignItems: 'center',
              padding: '15px 0', borderTop: i === 0 ? 'none' : `0.5px solid ${THEMES.paper.rule}`,
            }}>
              <div>
                <div style={{ fontSize: 15, fontWeight: 700, fontFamily: ST_SERIF }}>{cand.name}</div>
                <div style={{ fontSize: 11.5, color: THEMES.paper.sub, marginTop: 1 }}>{cand.note}</div>
              </div>
              {/* live mini-rail on the true row surface */}
              <div style={{ background: t.isDark ? '#222020' : '#fcf8f0', borderRadius: 10, padding: 6 }}>
                <div style={{
                  background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
                  borderRadius: 9, padding: '11px 12px', display: 'flex', alignItems: 'center',
                }}>
                  <div style={{ flex: 1, height: 4, borderRadius: 2, background: rail, position: 'relative' }}>
                    <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '42%', background: t.accent, borderRadius: 2 }} />
                    <div style={{
                      position: 'absolute', left: '42%', top: '50%', width: 20, height: 20, borderRadius: 10, background: '#fff',
                      transform: 'translate(-50%,-50%)', boxShadow: '0 1px 4px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.06)',
                    }} />
                  </div>
                </div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <STRatioTag ratio={r} />
                <STChip tone={cand.verdict}>
                  {cand.verdict === 'pick' ? 'RECOMMEND' : cand.verdict === 'alt' ? 'ALT' : 'REJECT'}
                </STChip>
                <span style={{ fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.35 }}>{cand.why}</span>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 20, fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.5, borderTop: `0.5px solid ${THEMES.paper.rule}`, paddingTop: 14 }}>
        Clearing the 3:1 graphical-object bar would need ≈ ink @ 60%+ — a heavy slab the issue flags as an invented,
        out-of-character value. Because the fill + thumb already satisfy WCAG 1.4.11 state identification, the rail is
        free to be a quiet ~1.6:1 extent. <b>ink @ 22%</b> is the smallest lift that reliably reads as a rail.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding token contract
// ─────────────────────────────────────────────────────
function STSpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '150px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 13.5, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace', background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: ST_FONT, overflow: 'auto' }}>
      <div style={{ fontFamily: ST_SERIF, fontSize: 25, fontWeight: 700, marginBottom: 4 }}>
        sliderTrack — binding token
      </div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 16 }}>
        Resolves #1273 / the rail sub-symptom of Bug #285. The fixer reads this token; no opacity is invented in code.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Add token</div>
        <div style={valStyle}>
          New <span style={code}>ReaderThemeV2.sliderTrack</span> per theme. Replace the inline
          <span style={code}>t.isDark ? rgba(255,255,255,0.1) : rgba(0,0,0,0.1)</span> in
          <span style={code}>SliderRow</span> with <span style={code}>t.sliderTrack</span>.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Values</div>
        <div style={valStyle}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 2 }}>
            {[['paper', SLIDER_TRACK.paper, 'ink @ 22%'], ['sepia', SLIDER_TRACK.sepia, 'ink @ 22%'], ['dark', SLIDER_TRACK.dark, 'unchanged'], ['oled', SLIDER_TRACK.oled, 'unchanged']].map(([k, v, n]) => (
              <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 52, fontWeight: 600, fontSize: 12.5 }}>{k}</span>
                <span style={{ width: 26, height: 14, borderRadius: 3, background: THEMES[k].isDark ? '#222020' : '#fcf8f0', position: 'relative', boxShadow: '0 0 0 0.5px rgba(0,0,0,0.1)' }}>
                  <span style={{ position: 'absolute', inset: '5px 3px', borderRadius: 2, background: v }} />
                </span>
                <span style={code}>{v}</span>
                <span style={{ fontSize: 11.5, color: t.sub }}>{n}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Derivation</div>
        <div style={valStyle}>
          Light family = each theme\u2019s <span style={code}>ink</span> at <b>22%</b>. One rule, not four magic numbers —
          the rail inherits the theme\u2019s warmth (paper near-black, sepia brown) and stays in-family.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Unchanged</div>
        <div style={valStyle}>
          Accent fill (theme accent, ~7:1), 22pt white thumb, and its <span style={code}>rgba(0,0,0,0.04)</span> shadow ring
          all stay. Dark / OLED rails keep their current weight — the bug is light-family only.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>States</div>
        <div style={valStyle}>
          The token is positional-state-independent — same rail in default, dragging, min (rail fully exposed),
          and max (rail fully covered). Verified in §4.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>WCAG</div>
        <div style={valStyle}>
          1.4.11 is met by the fill + thumb (both ≫ 3:1), which convey the slider value. The rail is decorative extent,
          deliberately tuned below 3:1 for visual weight — an explicit design call, per Rule 51, not an oversight.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Source of truth</div>
        <div style={valStyle}>
          <span style={code}>docs/bugs.md</span> Bug #285. This token closes the rail sub-symptom; the text-legibility
          fix (List chrome → theme tokens) ships separately.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function SliderTrackCanvas() {
  const SW = ST_PANEL_W + 56;   // stage width
  const SH = 312;               // stage height (fits grabber+title+2 rows)
  return (
    <DesignCanvas>

      {/* ─── 1. Decision ─── */}
      <DCSection id="decision"
        title="#1273 — Slider-track contrast · Paper / Sepia"
        subtitle="The Reader Display panel's slider rail dissolves into the cream sheet in the light themes. The fix is a new t.sliderTrack token = each theme's ink @ 22% — warm, in-family, and clearly legible without a heavy slab. Recommended panels below.">
        <DCArtboard id="rec-paper" label="Paper · ink @ 22% (recommended)" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
        <DCArtboard id="rec-sepia" label="Sepia · ink @ 22% (recommended)" width={SW} height={SH}>
          <STStage themeKey="sepia"><STPanel themeKey="sepia" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
        <DCPostIt top={-30} right={34} rotate={2} width={264}>
          One token, derived from each theme's own ink — so the rail is warm cream-grey on Paper and warm brown on Sepia, never a cold smudge. Lifts the rail from 1.25:1 to ~1.6:1.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. The bug ─── */}
      <DCSection id="bug"
        title="The bug · current rail"
        subtitle="Committed value: track = rgba(0,0,0,0.1). Over #fcf8f0 that's ~1.25:1 — and it's cold pure-black, so it reads as no rail at all. This is the exact #285 / #1265 complaint. Before / after, same panel.">
        <DCArtboard id="bug-paper" label="BEFORE · Paper · black @ 10%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <STStage themeKey="paper"><STPanel themeKey="paper" rail={RAIL_CURRENT} /></STStage>
            <STNote top={20} right={20} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {stRailRatio(RAIL_CURRENT.paper, THEMES.paper).toFixed(2)}:1 · reads as no rail
            </STNote>
          </div>
        </DCArtboard>
        <DCArtboard id="bug-sepia" label="BEFORE · Sepia · black @ 10%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <STStage themeKey="sepia"><STPanel themeKey="sepia" rail={RAIL_CURRENT} /></STStage>
            <STNote top={20} right={20} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {stRailRatio(RAIL_CURRENT.sepia, THEMES.sepia).toFixed(2)}:1 · reads as no rail
            </STNote>
          </div>
        </DCArtboard>
        <DCArtboard id="fix-paper" label="AFTER · Paper · ink @ 22%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} /></STStage>
            <STNote top={20} right={20} tone="pick">✓ {stRailRatio(SLIDER_TRACK.paper, THEMES.paper).toFixed(2)}:1 · rail reads</STNote>
          </div>
        </DCArtboard>
      </DCSection>

      {/* ─── 3. Candidates ─── */}
      <DCSection id="candidates"
        title="Candidates · measured"
        subtitle="Four options on the real row surface, with live WCAG ratios. Current and rule-token both stay invisible; ink@22 is the recommended lift; ink@32 is a heavier opt-in. Numbers are computed in-canvas, not asserted.">
        <DCArtboard id="cmp-paper" label="Paper — comparison" width={760} height={430}>
          <STCompareCard themeKey="paper" />
        </DCArtboard>
        <DCArtboard id="cmp-sepia" label="Sepia — comparison" width={760} height={430}>
          <STCompareCard themeKey="sepia" />
        </DCArtboard>
      </DCSection>

      {/* ─── 4. Thumb positions ─── */}
      <DCSection id="positions"
        title="Thumb positions · the explicit ask"
        subtitle="The rail is positional-state-independent: it must read in every thumb position. Default, dragging (active thumb + halo), min (whole track is exposed rail — the worst case), and max (rail almost fully covered). Recommended ink @ 22%, Paper.">
        <DCArtboard id="pos-default" label="default" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} sizeP={0.45} /></STStage>
        </DCArtboard>
        <DCArtboard id="pos-drag" label="dragging · active thumb" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} sizeP={0.62} dragging="size" /></STStage>
        </DCArtboard>
        <DCArtboard id="pos-min" label="min · rail fully exposed" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} sizeP={0} spaceP={0} /></STStage>
        </DCArtboard>
        <DCArtboard id="pos-max" label="max · rail fully covered" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} sizeP={1} spaceP={1} /></STStage>
        </DCArtboard>
        <DCArtboard id="pos-min-sepia" label="min · Sepia" width={SW} height={SH}>
          <STStage themeKey="sepia"><STPanel themeKey="sepia" rail={SLIDER_TRACK} sizeP={0} spaceP={0} /></STStage>
        </DCArtboard>
        <DCPostIt top={-30} right={34} rotate={-2} width={250}>
          Min is the stress test — at the low end the slider is <i>all</i> rail. If the rail reads here, it reads everywhere.
        </DCPostIt>
      </DCSection>

      {/* ─── 5. Across themes ─── */}
      <DCSection id="themes"
        title="Across themes"
        subtitle="Paper and Sepia get the new token. Dark and OLED keep their current rail weight unchanged — the low-contrast bug is light-family only, and the white-on-dark rail already reads fine. Confirmed, not redesigned.">
        <DCArtboard id="th-paper" label="paper · changed" width={SW} height={SH}>
          <STStage themeKey="paper"><STPanel themeKey="paper" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
        <DCArtboard id="th-sepia" label="sepia · changed" width={SW} height={SH}>
          <STStage themeKey="sepia"><STPanel themeKey="sepia" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
        <DCArtboard id="th-dark" label="dark · unchanged" width={SW} height={SH}>
          <STStage themeKey="dark"><STPanel themeKey="dark" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
        <DCArtboard id="th-oled" label="OLED · unchanged" width={SW} height={SH}>
          <STStage themeKey="oled"><STPanel themeKey="oled" rail={SLIDER_TRACK} /></STStage>
        </DCArtboard>
      </DCSection>

      {/* ─── 6. Spec ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what the fixer builds against.">
        <DCArtboard id="spec-card" label="" width={720} height={560}>
          <STSpecCard />
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { SliderTrackCanvas });
