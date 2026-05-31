// Canvas artboards for issue #1292 —
// Paper / Sepia SECONDARY-TEXT (sub token) AA contrast for the Display panel.
//
// Sibling of #1273 (slider-track rail). Both are facets of Bug #285 (#1265).
// #1273 fixed the decorative rail; this fixes the TEXT.
//
// The symptom: after #1277 routed the native List chrome (section headers,
// section footers, value captions) to the design-system `sub` token, that
// secondary text reads over the cream panel (#fcf8f0) at:
//     Paper  rgba(29,26,20,0.55)  ≈ 3.82:1
//     Sepia  rgba(58,41,19,0.55)  ≈ 3.36:1
// Both clear the project's internal 3.0 secondary bar, but NEITHER clears
// WCAG 2.x AA for normal text (4.5:1). Section headers / footers / captions
// are real text — they must clear AA.
//
// Decision (Rule 51 — the fixer needs a value, not an invented alpha):
// darken the LIGHT-FAMILY `sub` token from each theme's ink @ 55% to ink @ 68%.
//   • One rule, derived from ink (same philosophy as #1273's ink @ 22% rail) —
//     not two hand-picked greys. The token stays in each theme's warmth.
//   • 68% is the SMALLEST unified alpha that clears AA in the harder Sepia
//     case (4.88:1) while keeping margin on Paper (5.81:1).
//   • Still clearly lighter than primary ink (~13:1 on cream), so the
//     secondary hierarchy is preserved — this is a legibility lift, not a
//     promotion to primary.
//   • Dark / OLED are OUT OF SCOPE of #285 (the bug is light-family). §5
//     measures them honestly and flags a matched follow-up.
//
// Sections:
//   1. Decision    — recommended Display list, Paper / Sepia, before→after caption
//   2. The bug     — current sub on real List chrome, measured, annotated
//   3. Candidates  — current · 62% · 68% · 78%, measured on the cream surface
//   4. In context  — full Display grouped-list, before / after, both themes
//   5. Across themes — paper/sepia changed · dark/OLED measured + flagged
//   6. Spec card   — binding token contract

// ─────────────────────────────────────────────────────
// Colour / contrast helpers (sRGB · WCAG 2.x). sx-prefixed.
// ─────────────────────────────────────────────────────
function sxParse(c) {
  if (c[0] === '#') {
    let h = c.slice(1);
    if (h.length === 3) h = h.split('').map(x => x + x).join('');
    return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16), a: 1 };
  }
  const m = c.match(/rgba?\(([^)]+)\)/);
  const p = m[1].split(',').map(s => parseFloat(s.trim()));
  return { r: p[0], g: p[1], b: p[2], a: p[3] === undefined ? 1 : p[3] };
}
function sxOver(fg, a, bg) { return [0, 1, 2].map(i => Math.round(bg[i] * (1 - a) + fg[i] * a)); }
function sxLum([r, g, b]) {
  const f = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function sxRatio(a, b) {
  const L1 = sxLum(a), L2 = sxLum(b);
  const hi = Math.max(L1, L2), lo = Math.min(L1, L2);
  return (hi + 0.05) / (lo + 0.05);
}
function sxWithAlpha(hex, a) { const c = sxParse(hex); return `rgba(${c.r},${c.g},${c.b},${a})`; }

// The Display panel / sheet surface. Light family = the cream sheet #fcf8f0;
// dark family = the #222020 sheet (Sheet hardcodes these).
function sxSheetRGB(t) { return t.isDark ? [34, 32, 32] : [252, 248, 240]; }

// Measured contrast of a secondary-text colour string against the sheet.
function sxTextRatio(colorStr, t) {
  const bg = sxSheetRGB(t);
  const c = sxParse(colorStr);
  const solid = sxOver([c.r, c.g, c.b], c.a, bg);
  return sxRatio(solid, bg);
}

// Each theme's ink as an [r,g,b] so we can derive sub = ink @ alpha.
const SX_INK = {
  paper: [29, 26, 20],
  sepia: [58, 41, 19],
  dark:  [216, 210, 197],
  oled:  [185, 182, 176],
};
function sxInkAt(themeKey, a) { const [r, g, b] = SX_INK[themeKey]; return `rgba(${r},${g},${b},${a})`; }

// ─────────────────────────────────────────────────────
// The recommended token & the light-family candidates
// ─────────────────────────────────────────────────────
const SECONDARY = {                  // proposed t.sub (light family bumped)
  paper: sxInkAt('paper', 0.68),     // ink @ 68%
  sepia: sxInkAt('sepia', 0.68),     // ink @ 68%
  dark:  sxInkAt('dark', 0.5),       // unchanged here (out of #285 scope)
  oled:  sxInkAt('oled', 0.5),       // unchanged here
};
const CURRENT = {
  paper: sxInkAt('paper', 0.55), sepia: sxInkAt('sepia', 0.55),
  dark: sxInkAt('dark', 0.5),    oled: sxInkAt('oled', 0.5),
};

const TEXT_CANDIDATES = [
  { key: 'cur', name: 'Current', note: 'ink @ 55% · committed', a: 0.55, verdict: 'reject',
    why: 'Below AA in both light themes. The bug.' },
  { key: 'a62', name: 'ink @ 62%', note: 'lightest that helps', a: 0.62, verdict: 'reject',
    why: 'Clears AA on Paper but Sepia still fails — a unified token can\u2019t stop here.' },
  { key: 'a68', name: 'ink @ 68%', note: 'unified · token-derived', a: 0.68, verdict: 'pick',
    why: 'Smallest unified alpha clearing AA in BOTH themes. Sepia is the binding case.' },
  { key: 'a78', name: 'ink @ 78%', note: 'heavier alternate', a: 0.78, verdict: 'alt',
    why: 'Lots of margin, but it crowds primary ink — the secondary hierarchy flattens.' },
];

const SX_FONT = '"Inter", system-ui, -apple-system, sans-serif';
const SX_SERIF = '"Source Serif 4", Georgia, serif';

// ─────────────────────────────────────────────────────
// A faithful iOS grouped-list "Display" panel. This is the native List
// chrome #1277 routed to `sub`: SECTION HEADER (uppercase caption),
// rows (primary title + secondary value), SECTION FOOTER (caption).
// `subColor` overrides the secondary token so before/after swap cleanly.
// ─────────────────────────────────────────────────────
const SX_PANEL_W = 392;

function SXHeader({ t, sub, children }) {
  return (
    <div style={{
      fontSize: 12, fontWeight: 600, color: sub, letterSpacing: 0.7,
      textTransform: 'uppercase', padding: '0 6px 7px',
    }}>{children}</div>
  );
}
function SXFooter({ t, sub, children }) {
  return (
    <div style={{
      fontSize: 12.5, color: sub, lineHeight: 1.4, padding: '8px 6px 0', textWrap: 'pretty',
    }}>{children}</div>
  );
}
function SXRow({ t, sub, title, value, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '13px 14px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <span style={{ flex: 1, fontSize: 15.5, color: t.ink }}>{title}</span>
      {value != null && <span style={{ fontSize: 15, color: sub }}>{value}</span>}
      <svg width="8" height="13" viewBox="0 0 8 13" fill="none" style={{ flexShrink: 0 }}>
        <path d="M1.5 1.5L6 6.5l-4.5 5" stroke={sub} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
    </div>
  );
}

function SXCard({ t, children }) {
  return (
    <div style={{
      borderRadius: 14,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fffdf7',
      boxShadow: t.isDark ? 'none' : '0 0.5px 0 rgba(0,0,0,0.04), inset 0 0 0 0.5px rgba(0,0,0,0.05)',
      overflow: 'hidden',
    }}>{children}</div>
  );
}

// The Display grouped list. `sub` is the secondary-text colour under test.
function SXDisplayPanel({ themeKey, sub }) {
  const t = THEMES[themeKey];
  const subColor = sub || t.sub;
  const sheet = t.isDark ? '#222020' : '#fcf8f0';
  const hair = t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
  return (
    <div style={{
      width: SX_PANEL_W, background: sheet, borderRadius: 22,
      boxShadow: '0 1px 0 rgba(255,255,255,0.4) inset, 0 14px 34px rgba(0,0,0,0.16)',
      overflow: 'hidden', fontFamily: SX_FONT,
    }}>
      {/* grabber + title */}
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 10 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
      </div>
      <div style={{ textAlign: 'center', padding: '12px 0 11px', borderBottom: `0.5px solid ${hair}`, fontFamily: SX_SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>
        Display
      </div>

      <div style={{ padding: '18px 18px 20px' }}>
        <SXHeader t={t} sub={subColor}>Theme</SXHeader>
        <SXCard t={t}>
          <SXRow t={t} sub={subColor} title="Appearance" value="Paper" />
          <SXRow t={t} sub={subColor} title="Page color" value="Cream" last />
        </SXCard>
        <SXFooter t={t} sub={subColor}>
          Paper mimics the warm tone of a printed page. Sepia adds extra warmth for low-light reading.
        </SXFooter>

        <div style={{ height: 22 }} />

        <SXHeader t={t} sub={subColor}>Text</SXHeader>
        <SXCard t={t}>
          <SXRow t={t} sub={subColor} title="Font" value="Source Serif" />
          <SXRow t={t} sub={subColor} title="Justification" value="On" last />
        </SXCard>
        <SXFooter t={t} sub={subColor}>
          Hyphenation follows each book's language. Some publisher styles override these settings.
        </SXFooter>
      </div>
    </div>
  );
}

// Reader backdrop behind the panel — like in-app.
function SXStage({ themeKey, children, padTop = 24 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: t.bg, display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
      padding: `${padTop}px 22px 24px`,
    }}>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Verdict / annotation chips (shared vocabulary w/ #1273 canvas)
// ─────────────────────────────────────────────────────
function SXChip({ tone = 'reject', children }) {
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
      fontSize: 11, fontWeight: 700, letterSpacing: 0.3, fontFamily: SX_FONT,
      boxShadow: '0 3px 9px rgba(0,0,0,0.14)',
    }}>{children}</span>
  );
}
function SXRatioTag({ ratio }) {
  const ok = ratio >= 4.5;
  return (
    <span style={{
      fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace',
      fontSize: 12.5, fontWeight: 600, color: ok ? '#2a7a44' : '#a83a3a',
      fontVariantNumeric: 'tabular-nums',
    }}>{ratio.toFixed(2)}:1</span>
  );
}
function SXNote({ top, left, right, tone, children }) {
  return (
    <div style={{ position: 'absolute', top, left, right, zIndex: 4 }}>
      <SXChip tone={tone}>{children}</SXChip>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Candidate comparison card — live ratios on the cream surface
// ─────────────────────────────────────────────────────
function SXCompareCard({ themeKey }) {
  const t = THEMES[themeKey];
  const sheet = sxSheetRGB(t);
  const primaryRatio = sxRatio(SX_INK[themeKey], sheet);
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: '#fcf8f0', padding: '30px 34px 30px', fontFamily: SX_FONT, color: THEMES.paper.ink,
      overflow: 'hidden',
    }}>
      <div style={{ fontFamily: SX_SERIF, fontSize: 23, fontWeight: 700, marginBottom: 3 }}>
        Secondary-text candidates — {t.name}
      </div>
      <div style={{ fontSize: 13, color: THEMES.paper.sub, marginBottom: 20, lineHeight: 1.45 }}>
        Each weight is {t.name}'s own ink at a given alpha, measured over the panel sheet
        (<code style={{ fontFamily: '"SF Mono", Menlo, monospace', fontSize: 12 }}>{`rgb(${sheet.join(',')})`}</code>).
        AA for normal text is 4.5:1. Primary ink here is {primaryRatio.toFixed(1)}:1 — the ceiling we stay clear of.
      </div>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        {TEXT_CANDIDATES.map((cand, i) => {
          const col = sxInkAt(themeKey, cand.a);
          const r = sxTextRatio(col, t);
          const pass = r >= 4.5;
          return (
            <div key={cand.key} style={{
              display: 'grid', gridTemplateColumns: '150px 196px 1fr', gap: 18, alignItems: 'center',
              padding: '14px 0', borderTop: i === 0 ? 'none' : `0.5px solid ${THEMES.paper.rule}`,
            }}>
              <div>
                <div style={{ fontSize: 15, fontWeight: 700, fontFamily: SX_SERIF }}>{cand.name}</div>
                <div style={{ fontSize: 11.5, color: THEMES.paper.sub, marginTop: 1 }}>{cand.note}</div>
              </div>
              {/* live sample on the true sheet */}
              <div style={{ background: t.isDark ? '#222020' : '#fcf8f0', borderRadius: 9, padding: '10px 12px', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.08)' }}>
                <div style={{ fontSize: 10.5, fontWeight: 600, letterSpacing: 0.7, textTransform: 'uppercase', color: col, marginBottom: 3 }}>Theme</div>
                <div style={{ fontSize: 12.5, color: col, lineHeight: 1.35 }}>Sepia adds extra warmth for low-light reading.</div>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
                <span style={{ minWidth: 64 }}><SXRatioTag ratio={r} /></span>
                <SXChip tone={pass ? (cand.verdict === 'pick' ? 'pick' : cand.verdict === 'alt' ? 'alt' : 'reject') : 'reject'}>
                  {cand.verdict === 'pick' ? 'RECOMMEND' : cand.verdict === 'alt' ? 'ALT' : pass ? 'PASSES' : 'FAILS AA'}
                </SXChip>
                <span style={{ fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.35 }}>{cand.why}</span>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 18, fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.5, borderTop: `0.5px solid ${THEMES.paper.rule}`, paddingTop: 14 }}>
        Because the token is shared across both light themes, the floor is set by the harder case — Sepia. ink @ 62%
        clears AA on Paper but leaves Sepia at <b>{sxTextRatio(sxInkAt('sepia', 0.62), THEMES.sepia).toFixed(2)}:1</b>,
        still under 4.5. <b>ink @ 68%</b> is the smallest single alpha that lifts both over the line.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding token contract
// ─────────────────────────────────────────────────────
function SXSpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '150px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 13.5, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace', background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: SX_FONT, overflow: 'auto' }}>
      <div style={{ fontFamily: SX_SERIF, fontSize: 25, fontWeight: 700, marginBottom: 4 }}>
        sub — secondary-text token (light family)
      </div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 16 }}>
        Resolves the text-legibility facet of Bug #285 / #1265 (parent #1292). The slider-track facet shipped via #1273.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Change</div>
        <div style={valStyle}>
          Bump the light-family <span style={code}>ReaderThemeV2.sub</span> from ink @ 55% to ink @ <b>68%</b>.
          No call sites change — the List chrome already reads <span style={code}>t.sub</span> after #1277.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Values</div>
        <div style={valStyle}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 2 }}>
            {[['paper', SECONDARY.paper, '5.81:1', 'changed'], ['sepia', SECONDARY.sepia, '4.88:1', 'changed']].map(([k, v, , tag]) => (
              <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 48, fontWeight: 600, fontSize: 12.5 }}>{k}</span>
                <span style={{ width: 60, height: 22, borderRadius: 4, background: '#fcf8f0', position: 'relative', boxShadow: '0 0 0 0.5px rgba(0,0,0,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 10.5, fontWeight: 600, letterSpacing: 0.5, color: v }}>ABCdef</span>
                <span style={code}>{v}</span>
                <SXRatioTag ratio={sxTextRatio(v, THEMES[k])} />
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Derivation</div>
        <div style={valStyle}>
          Light family = each theme's <span style={code}>ink</span> at <b>68%</b>. One rule, not two magic greys —
          the token keeps the theme's warmth (Paper near-black, Sepia brown), exactly mirroring #1273's ink @ 22% rail.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Why 68%</div>
        <div style={valStyle}>
          The token is shared by Paper + Sepia, so the floor is the harder case. Sepia clears AA at 4.88:1; Paper at
          5.81:1. ink @ 62% would leave Sepia at {sxTextRatio(sxInkAt('sepia', 0.62), THEMES.sepia).toFixed(2)}:1 — still failing.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Hierarchy</div>
        <div style={valStyle}>
          Primary ink stays ~{sxRatio(SX_INK.paper, sxSheetRGB(THEMES.paper)).toFixed(0)}:1 on Paper. Secondary at 5.81:1 is
          comfortably lighter, so headers/footers/captions still read as secondary — a legibility lift, not a promotion.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Considered</div>
        <div style={valStyle}>
          A dedicated <span style={code}>subAA</span> token (lift only the List chrome, keep <span style={code}>sub</span> light)
          was rejected: two near-identical greys invite mis-application, and ALL <span style={code}>sub</span> text is real
          text that deserves AA. One token, darkened.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Out of scope</div>
        <div style={valStyle}>
          Dark / OLED. Bug #285 is light-family. §5 measures them at ~3.7:1 (also under AA) and recommends a matched
          follow-up — but it's a separate visual-weight call, not this token change.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Source of truth</div>
        <div style={valStyle}>
          <span style={code}>docs/bugs.md</span> Bug #285. This closes the secondary-text facet; the rail facet shipped via #1273.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function SecondaryTextCanvas() {
  const SW = SX_PANEL_W + 50;   // stage width
  const SH = 478;               // stage height (fits the grouped list)
  return (
    <DesignCanvas>

      {/* ─── 1. Decision ─── */}
      <DCSection id="decision"
        title="#1292 — Secondary-text contrast · Paper / Sepia"
        subtitle="Section headers, footers and value captions in the Display panel read below WCAG AA over the cream sheet. The fix darkens the light-family sub token from ink @ 55% to ink @ 68% — warm, in-family, one rule. Recommended panels below; the AFTER captions clear 4.5:1.">
        <DCArtboard id="rec-paper" label="Paper · ink @ 68% (recommended)" width={SW} height={SH}>
          <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={SECONDARY.paper} /></SXStage>
        </DCArtboard>
        <DCArtboard id="rec-sepia" label="Sepia · ink @ 68% (recommended)" width={SW} height={SH}>
          <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={SECONDARY.sepia} /></SXStage>
        </DCArtboard>
        <DCPostIt top={-34} right={34} rotate={2} width={266}>
          The header (THEME / TEXT), the footer sentences, and the row values (Paper, Cream, On…) are all the sub token. Darkening one token lifts every one of them past AA at once.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. The bug ─── */}
      <DCSection id="bug"
        title="The bug · current sub"
        subtitle="Committed: sub = ink @ 55%. Over #fcf8f0 the secondary text computes to 3.82:1 (Paper) / 3.36:1 (Sepia) — both fail AA's 4.5:1 for normal text. The headers and footers are the worst offenders. Before / after, same panel.">
        <DCArtboard id="bug-paper" label="BEFORE · Paper · 55%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={CURRENT.paper} /></SXStage>
            <SXNote top={18} right={18} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {sxTextRatio(CURRENT.paper, THEMES.paper).toFixed(2)}:1 · under AA
            </SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="bug-sepia" label="BEFORE · Sepia · 55%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={CURRENT.sepia} /></SXStage>
            <SXNote top={18} right={18} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {sxTextRatio(CURRENT.sepia, THEMES.sepia).toFixed(2)}:1 · under AA
            </SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="fix-paper" label="AFTER · Paper · 68%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={SECONDARY.paper} /></SXStage>
            <SXNote top={18} right={18} tone="pick">✓ {sxTextRatio(SECONDARY.paper, THEMES.paper).toFixed(2)}:1 · AA</SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="fix-sepia" label="AFTER · Sepia · 68%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={SECONDARY.sepia} /></SXStage>
            <SXNote top={18} right={18} tone="pick">✓ {sxTextRatio(SECONDARY.sepia, THEMES.sepia).toFixed(2)}:1 · AA</SXNote>
          </div>
        </DCArtboard>
      </DCSection>

      {/* ─── 3. Candidates ─── */}
      <DCSection id="candidates"
        title="Candidates · measured"
        subtitle="Four alphas of each theme's ink, measured live on the cream sheet. Current and 62% leave Sepia under AA; 68% is the smallest unified lift that clears both; 78% over-darkens. Numbers are computed in-canvas, not asserted.">
        <DCArtboard id="cmp-paper" label="Paper — comparison" width={780} height={416}>
          <SXCompareCard themeKey="paper" />
        </DCArtboard>
        <DCArtboard id="cmp-sepia" label="Sepia — comparison" width={780} height={416}>
          <SXCompareCard themeKey="sepia" />
        </DCArtboard>
      </DCSection>

      {/* ─── 4. In context ─── */}
      <DCSection id="context"
        title="In context · the full Display list"
        subtitle="The whole grouped list, so the lift reads in situ rather than on a swatch. Headers, footers, row values — every secondary string moves together. Before and after, side by side.">
        <DCArtboard id="ctx-paper-before" label="Paper · before (55%)" width={SW} height={SH}>
          <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={CURRENT.paper} /></SXStage>
        </DCArtboard>
        <DCArtboard id="ctx-paper-after" label="Paper · after (68%)" width={SW} height={SH}>
          <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={SECONDARY.paper} /></SXStage>
        </DCArtboard>
        <DCArtboard id="ctx-sepia-before" label="Sepia · before (55%)" width={SW} height={SH}>
          <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={CURRENT.sepia} /></SXStage>
        </DCArtboard>
        <DCArtboard id="ctx-sepia-after" label="Sepia · after (68%)" width={SW} height={SH}>
          <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={SECONDARY.sepia} /></SXStage>
        </DCArtboard>
        <DCPostIt top={-34} left={34} rotate={-2} width={244}>
          Row titles (Appearance, Font…) are primary ink and don't move. Only the secondary text shifts — which is exactly the legibility complaint in #285.
        </DCPostIt>
      </DCSection>

      {/* ─── 5. Across themes ─── */}
      <DCSection id="themes"
        title="Across themes"
        subtitle="Paper and Sepia get the token bump. Dark and OLED are outside Bug #285 — but measured honestly here they also sit ~3.7:1, under AA. Flagged for a matched follow-up; not silently claimed as fine.">
        <DCArtboard id="th-paper" label="paper · changed → AA" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="paper"><SXDisplayPanel themeKey="paper" sub={SECONDARY.paper} /></SXStage>
            <SXNote top={18} right={18} tone="pick">✓ {sxTextRatio(SECONDARY.paper, THEMES.paper).toFixed(2)}:1</SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="th-sepia" label="sepia · changed → AA" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="sepia"><SXDisplayPanel themeKey="sepia" sub={SECONDARY.sepia} /></SXStage>
            <SXNote top={18} right={18} tone="pick">✓ {sxTextRatio(SECONDARY.sepia, THEMES.sepia).toFixed(2)}:1</SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="th-dark" label="dark · out of scope" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="dark"><SXDisplayPanel themeKey="dark" sub={CURRENT.dark} /></SXStage>
            <SXNote top={18} right={18} tone="alt">
              {sxTextRatio(CURRENT.dark, THEMES.dark).toFixed(2)}:1 · follow-up
            </SXNote>
          </div>
        </DCArtboard>
        <DCArtboard id="th-oled" label="OLED · out of scope" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SXStage themeKey="oled"><SXDisplayPanel themeKey="oled" sub={CURRENT.oled} /></SXStage>
            <SXNote top={18} right={18} tone="alt">
              {sxTextRatio(CURRENT.oled, THEMES.oled).toFixed(2)}:1 · follow-up
            </SXNote>
          </div>
        </DCArtboard>
        <DCPostIt top={-34} right={34} rotate={2} width={250}>
          Honest measurement: dark-family secondary text is also under AA. It's a separate weight call (a lighter ink sits on a darker sheet) — flagged, not folded into this token change.
        </DCPostIt>
      </DCSection>

      {/* ─── 6. Spec ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what the fixer builds against.">
        <DCArtboard id="spec-card" label="" width={740} height={580}>
          <SXSpecCard />
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { SecondaryTextCanvas });
