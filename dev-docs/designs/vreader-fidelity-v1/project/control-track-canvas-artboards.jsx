// Canvas artboards for issue #1329 —
// Paper / Sepia CONTROL-TRACK contrast for the Reader Display panel.
//
// Third facet of Bug #298 (docs/bugs.md), sibling to #1273 (slider rail,
// shipped, ink @ 22%) and #1292 (secondary text, sub → ink @ 68%). This one
// is the NATIVE CONTROL TRACKS — the surfaces SwiftUI's `.tint(accent)` never
// touches:
//   • the "Custom Background" UISwitch in its OFF state — track is a pale
//     system gray that vanishes on the cream sheet (#fcf8f0).
//   • the "Scroll | Paged" UISegmentedControl — the trough (unselected
//     surface) and the pale selected pill both wash out over cream.
//
// `.tint(accentColor)` (ReaderSettingsPanel.swift:170) only colors the ON
// toggle track and the SELECTED segment fill — it leaves the OFF track and
// the trough as system defaults. Over #fcf8f0 those defaults compute to
// ~1.19:1 — you can't tell, at a glance, that the control is even there.
//
// Decision (Rule 51 — the fixer needs a token, not a hand-picked tint):
// introduce a per-theme `controlTrack` token. Light family = each theme's
// ink @ 30%.
//   • Same derivation family as #1273's rail (ink-derived, in-theme warmth),
//     but a touch heavier: a rail is reinforced by a high-contrast fill +
//     thumb on the SAME element; a control track stands alone as the OFF /
//     inactive surface, so it carries its own visible weight (~1.9:1).
//   • Lifts the OFF switch + the segmented trough from invisible to clearly
//     present, and gives the elevated selected pill a darker trough to read
//     against. State stays carried by the knob position, the accent ON-track,
//     and the selected pill's elevation + bold label — never by track color
//     alone, so WCAG 1.4.11 identification holds.
//   • Dark / OLED keep their current track weight — the bug is light-family.
//
// Sections:
//   1. Decision       — recommended Paper / Sepia panels (toggle + segmented)
//   2. The bug        — current OFF track + trough, measured, annotated
//   3. Candidates     — current · ink@22 (rail) · ink@30 · ink@40, measured
//   4. Control states — off / on toggle · scroll|paged selected either side
//   5. Across themes  — paper/sepia changed · dark/OLED confirmed unchanged
//   6. Spec card      — binding token contract

// ─────────────────────────────────────────────────────
// Colour / contrast helpers (sRGB · WCAG 2.x). ct-prefixed.
// ─────────────────────────────────────────────────────
function ctParse(c) {
  if (c[0] === '#') {
    let h = c.slice(1);
    if (h.length === 3) h = h.split('').map(x => x + x).join('');
    return { r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16), a: 1 };
  }
  const m = c.match(/rgba?\(([^)]+)\)/);
  const p = m[1].split(',').map(s => parseFloat(s.trim()));
  return { r: p[0], g: p[1], b: p[2], a: p[3] === undefined ? 1 : p[3] };
}
function ctOver(fg, a, bg) { return [0, 1, 2].map(i => Math.round(bg[i] * (1 - a) + fg[i] * a)); }
function ctLum([r, g, b]) {
  const f = c => { c /= 255; return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4); };
  return 0.2126 * f(r) + 0.7152 * f(g) + 0.0722 * f(b);
}
function ctRatio(a, b) {
  const L1 = ctLum(a), L2 = ctLum(b);
  const hi = Math.max(L1, L2), lo = Math.min(L1, L2);
  return (hi + 0.05) / (lo + 0.05);
}
function ctSolid(str, bg) { const c = ctParse(str); return ctOver([c.r, c.g, c.b], c.a, bg); }

// The Display panel / sheet surface — cream #fcf8f0 in the light family,
// #222020 in dark (Sheet hardcodes these), regardless of reader page color.
function ctSheetRGB(t) { return t.isDark ? [34, 32, 32] : [252, 248, 240]; }

// Each theme's ink, so we can derive controlTrack = ink @ alpha.
const CT_INK = {
  paper: [29, 26, 20],
  sepia: [58, 41, 19],
  dark:  [216, 210, 197],
  oled:  [185, 182, 176],
};
function ctInkAt(themeKey, a) { const [r, g, b] = CT_INK[themeKey]; return `rgba(${r},${g},${b},${a})`; }

// Contrast of a track colour against the panel sheet (does the control read?).
function ctTrackRatio(trackStr, t) {
  const bg = ctSheetRGB(t);
  return ctRatio(ctSolid(trackStr, bg), bg);
}
// Contrast of the selected pill against the trough it floats on.
function ctPillRatio(pillStr, trackStr, t) {
  const bg = ctSheetRGB(t);
  const trough = ctSolid(trackStr, bg);
  return ctRatio(ctSolid(pillStr, trough), trough);
}

// ─────────────────────────────────────────────────────
// The recommended token, the current state, and candidates
// ─────────────────────────────────────────────────────
const CONTROL_TRACK = {                  // proposed t.controlTrack
  paper: ctInkAt('paper', 0.30),         // ink @ 30%
  sepia: ctInkAt('sepia', 0.30),         // ink @ 30%
  dark:  'rgba(255,255,255,0.16)',       // unchanged (bug is light-family)
  oled:  'rgba(255,255,255,0.16)',       // unchanged
};
// Current: SwiftUI default off-track / unselected trough — iOS .systemFill,
// a cold pale gray, identical across the light themes (no theme warmth).
const CURRENT_TRACK = {
  paper: 'rgba(120,120,128,0.16)', sepia: 'rgba(120,120,128,0.16)',
  dark:  'rgba(255,255,255,0.16)', oled:  'rgba(255,255,255,0.16)',
};
// The elevated selected-segment pill (unchanged by this token — kept light/raised).
const PILL = { paperLight: '#fffdf7', dark: '#3a3530' };
function ctPill(t) { return t.isDark ? PILL.dark : PILL.paperLight; }

const CT_CANDIDATES = [
  { key: 'cur', name: 'Current', note: 'iOS .systemFill · committed', verdict: 'reject',
    paper: 'rgba(120,120,128,0.16)', sepia: 'rgba(120,120,128,0.16)',
    why: 'Cold pale gray, no theme warmth — dissolves into cream. The bug.' },
  { key: 'rail', name: 'ink @ 22%', note: 'reuse the rail token', verdict: 'alt',
    paper: ctInkAt('paper', 0.22), sepia: ctInkAt('sepia', 0.22),
    why: 'Warm and in-family, but a rail leans on its fill + thumb; a bare control track wants a touch more.' },
  { key: 'c30', name: 'ink @ 30%', note: 'control-track · derived', verdict: 'pick',
    paper: ctInkAt('paper', 0.30), sepia: ctInkAt('sepia', 0.30),
    why: 'Reads clearly as an inactive control, gives the selected pill a darker trough, stays quiet.' },
  { key: 'c40', name: 'ink @ 40%', note: 'heavier alternate', verdict: 'alt',
    paper: ctInkAt('paper', 0.40), sepia: ctInkAt('sepia', 0.40),
    why: 'More present, but it starts competing with the accent ON-track — off no longer reads obviously "off".' },
];

const CT_PANEL_W = 392;
const CT_FONT = '"Inter", system-ui, -apple-system, sans-serif';
const CT_SERIF = '"Source Serif 4", Georgia, serif';

// ─────────────────────────────────────────────────────
// Faithful native controls, driven by the track token
// ─────────────────────────────────────────────────────

// UISwitch — 51×31 track, 27 knob. `on` swaps to accent track + knob right.
function CTSwitch({ t, track, on }) {
  const trackColor = on ? t.accent : track;
  return (
    <div style={{
      width: 51, height: 31, borderRadius: 16, background: trackColor,
      position: 'relative', flexShrink: 0, transition: 'background 0.18s',
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 22 : 2,
        width: 27, height: 27, borderRadius: 14, background: '#fff',
        boxShadow: '0 3px 8px rgba(0,0,0,0.18), 0 1px 1px rgba(0,0,0,0.12), 0 0 0 0.5px rgba(0,0,0,0.04)',
        transition: 'left 0.18s',
      }} />
    </div>
  );
}

// A grouped-list row carrying a primary title + trailing switch.
function CTToggleRow({ t, track, on, title, sub }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '13px 16px' }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15.5, color: t.ink }}>{title}</div>
        {sub && <div style={{ fontSize: 12.5, color: t.sub, marginTop: 2 }}>{sub}</div>}
      </div>
      <CTSwitch t={t} track={track} on={on} />
    </div>
  );
}

// UISegmentedControl — trough = track token, selected = elevated pill.
function CTSegmented({ t, track, selected = 'paged' }) {
  const opts = [
    { k: 'scroll', label: 'Scroll', icon: 'scroll' },
    { k: 'paged',  label: 'Paged',  icon: 'paged' },
  ];
  const pill = ctPill(t);
  return (
    <div style={{
      display: 'flex', borderRadius: 12, background: track, padding: 3, gap: 0,
      transition: 'background 0.18s',
    }}>
      {opts.map(o => {
        const sel = o.k === selected;
        return (
          <div key={o.k} style={{
            flex: 1, padding: '9px 0', borderRadius: 9,
            background: sel ? pill : 'transparent',
            boxShadow: sel
              ? '0 1px 3px rgba(0,0,0,0.16), 0 0 0 0.5px rgba(0,0,0,0.06)'
              : 'none',
            color: t.ink, fontSize: 14, fontWeight: sel ? 600 : 500,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 7,
          }}>
            <CTLayoutGlyph mode={o.icon} color={t.ink} />
            {o.label}
          </div>
        );
      })}
    </div>
  );
}

// Paged = two-page spread, scroll = continuous page (lifted from the panel).
function CTLayoutGlyph({ mode, color }) {
  const c = color || '#000';
  if (mode === 'paged') {
    return (
      <svg width="16" height="14" viewBox="0 0 16 14" fill="none">
        <rect x="0.5" y="1.5" width="6.5" height="11" rx="0.5" stroke={c} strokeWidth="1.2"/>
        <rect x="9" y="1.5" width="6.5" height="11" rx="0.5" stroke={c} strokeWidth="1.2"/>
        <path d="M2 5h4M2 7.5h4M2 10h3M10.5 5h4M10.5 7.5h4M10.5 10h3" stroke={c} strokeWidth="0.8" opacity="0.55"/>
      </svg>
    );
  }
  return (
    <svg width="16" height="14" viewBox="0 0 16 14" fill="none">
      <rect x="2.5" y="0.5" width="11" height="13" rx="1" stroke={c} strokeWidth="1.2"/>
      <path d="M5 3h6M5 5.5h6M5 8h6M5 10.5h4" stroke={c} strokeWidth="0.9"/>
      <path d="M0.7 4l1.6 1.6M0.7 10l1.6-1.6" stroke={c} strokeWidth="1" strokeLinecap="round" opacity="0.45"/>
      <path d="M15.3 4l-1.6 1.6M15.3 10l-1.6-1.6" stroke={c} strokeWidth="1" strokeLinecap="round" opacity="0.45"/>
    </svg>
  );
}

function CTHeader({ sub, children }) {
  return (
    <div style={{ fontSize: 12, fontWeight: 600, color: sub, letterSpacing: 0.7, textTransform: 'uppercase', padding: '0 6px 7px' }}>
      {children}
    </div>
  );
}
function CTCard({ t, children }) {
  return (
    <div style={{
      borderRadius: 14,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fffdf7',
      boxShadow: t.isDark ? 'none' : '0 0.5px 0 rgba(0,0,0,0.04), inset 0 0 0 0.5px rgba(0,0,0,0.05)',
      overflow: 'hidden',
    }}>{children}</div>
  );
}

// The Display-panel slice the issue points at: a Custom Background toggle
// row and the Layout (Scroll | Paged) segmented control.
function CTDisplayPanel({ themeKey, track, toggleOn = false, selected = 'paged' }) {
  const t = THEMES[themeKey];
  const trackColor = typeof track === 'string' ? track : track[themeKey];
  const sheet = t.isDark ? '#222020' : '#fcf8f0';
  const hair = t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)';
  return (
    <div style={{
      width: CT_PANEL_W, background: sheet, borderRadius: 22,
      boxShadow: '0 1px 0 rgba(255,255,255,0.4) inset, 0 14px 34px rgba(0,0,0,0.16)',
      overflow: 'hidden', fontFamily: CT_FONT,
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 10 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
      </div>
      <div style={{ textAlign: 'center', padding: '12px 0 11px', borderBottom: `0.5px solid ${hair}`, fontFamily: CT_SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>
        Display
      </div>

      <div style={{ padding: '18px 18px 22px' }}>
        <CTHeader sub={t.sub}>Background</CTHeader>
        <CTCard t={t}>
          <CTToggleRow t={t} track={trackColor} on={toggleOn} title="Custom Background" />
        </CTCard>

        <div style={{ height: 22 }} />

        <CTHeader sub={t.sub}>Layout</CTHeader>
        <CTSegmented t={t} track={trackColor} selected={selected} />
      </div>
    </div>
  );
}

// Reader backdrop behind the panel — like in-app.
function CTStage({ themeKey, children, padTop = 26 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: t.bg, display: 'flex', justifyContent: 'center', alignItems: 'flex-start',
      padding: `${padTop}px 22px 26px`,
    }}>
      {children}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Verdict / annotation chips (shared vocabulary w/ #1273 · #1292)
// ─────────────────────────────────────────────────────
function CTChip({ tone = 'reject', children }) {
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
      fontSize: 11, fontWeight: 700, letterSpacing: 0.3, fontFamily: CT_FONT,
      boxShadow: '0 3px 9px rgba(0,0,0,0.14)',
    }}>{children}</span>
  );
}
function CTRatioTag({ ratio, bar = 3 }) {
  const ok = ratio >= bar;
  return (
    <span style={{
      fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace',
      fontSize: 12.5, fontWeight: 600, color: ok ? '#2a7a44' : '#3a352c',
      fontVariantNumeric: 'tabular-nums',
    }}>{ratio.toFixed(2)}:1</span>
  );
}
function CTNote({ top, left, right, tone, children }) {
  return (
    <div style={{ position: 'absolute', top, left, right, zIndex: 4 }}>
      <CTChip tone={tone}>{children}</CTChip>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Candidate comparison card — live controls, measured ratios
// ─────────────────────────────────────────────────────
function CTCompareCard({ themeKey }) {
  const t = THEMES[themeKey];
  const sheet = ctSheetRGB(t);
  const accentRatio = ctTrackRatio(t.accent, t);
  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      background: '#fcf8f0', padding: '30px 34px 30px', fontFamily: CT_FONT, color: THEMES.paper.ink,
      overflow: 'hidden',
    }}>
      <div style={{ fontFamily: CT_SERIF, fontSize: 23, fontWeight: 700, marginBottom: 3 }}>
        Control-track candidates — {t.name}
      </div>
      <div style={{ fontSize: 13, color: THEMES.paper.sub, marginBottom: 18, lineHeight: 1.45 }}>
        Each track over the panel sheet (<code style={{ fontFamily: '"SF Mono", Menlo, monospace', fontSize: 12 }}>{`rgb(${sheet.join(',')})`}</code>).
        The first ratio is the OFF track vs the sheet (is the control visible?); the accent ON-track sits at {accentRatio.toFixed(1)}:1 and carries the ON state.
      </div>
      <div style={{ display: 'flex', flexDirection: 'column' }}>
        {CT_CANDIDATES.map((cand, i) => {
          const track = cand[themeKey];
          const trackR = ctTrackRatio(track, t);
          return (
            <div key={cand.key} style={{
              display: 'grid', gridTemplateColumns: '128px 188px 1fr', gap: 16, alignItems: 'center',
              padding: '13px 0', borderTop: i === 0 ? 'none' : `0.5px solid ${THEMES.paper.rule}`,
            }}>
              <div>
                <div style={{ fontSize: 15, fontWeight: 700, fontFamily: CT_SERIF }}>{cand.name}</div>
                <div style={{ fontSize: 11.5, color: THEMES.paper.sub, marginTop: 1 }}>{cand.note}</div>
              </div>
              {/* live OFF switch + segmented on the true sheet */}
              <div style={{ background: t.isDark ? '#222020' : '#fcf8f0', borderRadius: 10, padding: 9, display: 'flex', flexDirection: 'column', gap: 8, boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.08)' }}>
                <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                  <CTSwitch t={t} track={track} on={false} />
                </div>
                <CTSegmented t={t} track={track} selected="paged" />
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 11 }}>
                <span style={{ minWidth: 58 }}><CTRatioTag ratio={trackR} /></span>
                <CTChip tone={cand.verdict}>
                  {cand.verdict === 'pick' ? 'RECOMMEND' : cand.verdict === 'alt' ? 'ALT' : 'REJECT'}
                </CTChip>
                <span style={{ fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.35 }}>{cand.why}</span>
              </div>
            </div>
          );
        })}
      </div>
      <div style={{ marginTop: 16, fontSize: 12, color: THEMES.paper.sub, lineHeight: 1.5, borderTop: `0.5px solid ${THEMES.paper.rule}`, paddingTop: 13 }}>
        A pure 3:1 boundary would need ≈ ink @ 48%+ — a heavy mid-gray slab that reads like a disabled control and crowds
        the accent ON-track. Because state is carried by the knob position, the accent track, and the selected pill's
        elevation + bold label (WCAG 1.4.11), the track is free to be a quiet ~1.9:1 surface. <b>ink @ 30%</b> is the
        smallest weight that reliably reads as an inactive control without competing with "on".
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding token contract
// ─────────────────────────────────────────────────────
function CTSpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '150px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 13.5, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace', background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: CT_FONT, overflow: 'auto' }}>
      <div style={{ fontFamily: CT_SERIF, fontSize: 25, fontWeight: 700, marginBottom: 4 }}>
        controlTrack — binding token
      </div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 16 }}>
        Resolves #1329 / the control-track facet of Bug #298. Third sibling to #1273 (rail, shipped) and #1292 (sub text, designed).
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Add token</div>
        <div style={valStyle}>
          New <span style={code}>ReaderThemeV2.controlTrack</span> per theme. Add a
          <span style={code}>UISwitch.appearance().offTrackColor</span>-equivalent override (no native API — use a custom
          toggle style or a background capsule) and set the <span style={code}>UISegmentedControl</span> trough /
          unselected segment to <span style={code}>t.controlTrack</span>. <span style={code}>.tint(accent)</span> stays for ON / selected.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Values</div>
        <div style={valStyle}>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 6, marginTop: 2 }}>
            {[['paper', CONTROL_TRACK.paper, 'ink @ 30%'], ['sepia', CONTROL_TRACK.sepia, 'ink @ 30%'], ['dark', CONTROL_TRACK.dark, 'unchanged'], ['oled', CONTROL_TRACK.oled, 'unchanged']].map(([k, v, n]) => (
              <div key={k} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <span style={{ width: 48, fontWeight: 600, fontSize: 12.5 }}>{k}</span>
                <span style={{ width: 40, height: 24, borderRadius: 13, background: THEMES[k].isDark ? '#222020' : '#fcf8f0', position: 'relative', boxShadow: '0 0 0 0.5px rgba(0,0,0,0.1)' }}>
                  <span style={{ position: 'absolute', inset: 3, borderRadius: 11, background: v }} />
                </span>
                <span style={code}>{v}</span>
                <span style={{ fontSize: 11.5, color: t.sub }}>{n}</span>
                {!THEMES[k].isDark && <CTRatioTag ratio={ctTrackRatio(v, THEMES[k])} bar={1.6} />}
              </div>
            ))}
          </div>
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Derivation</div>
        <div style={valStyle}>
          Light family = each theme's <span style={code}>ink</span> at <b>30%</b> — same ink-derived family as #1273's
          rail (22%) and #1292's sub text (68%), so the control track inherits the theme's warmth (Paper near-black,
          Sepia brown) rather than a cold system gray. One rule, not four magic numbers.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Why 30% (not 22%)</div>
        <div style={valStyle}>
          The rail (22%) leans on a high-contrast fill + thumb on the same element. A control track stands alone as the
          OFF / inactive surface, so it carries its own weight: 22% → ~1.6:1 reads as a faint hairline; 30% → ~1.9:1
          reads unmistakably as a control. Above ~40% it starts rivalling the accent ON-track and "off" stops reading as off.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Selected pill</div>
        <div style={valStyle}>
          Unchanged token-wise: the selected segment stays the elevated light pill (<span style={code}>{PILL.paperLight}</span> /
          dark <span style={code}>{PILL.dark}</span>) with its shadow + 0.5px hairline + 600-weight label. It now reads
          because it floats on the darker <span style={code}>controlTrack</span> trough
          (~{ctPillRatio(PILL.paperLight, CONTROL_TRACK.paper, THEMES.paper).toFixed(2)}:1 lighter), not because the trough was invisible.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>WCAG 1.4.11</div>
        <div style={valStyle}>
          State identification is met without the track clearing 3:1: the toggle's white knob position (~17:1) +
          accent ON-track distinguish on/off; the segmented selection is the pill's elevation + bold label. The track is
          a visible-extent surface, deliberately tuned below 3:1 for visual weight — an explicit design call (Rule 51), mirroring the rail.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Unchanged</div>
        <div style={valStyle}>
          Accent ON-track + selected fill (<span style={code}>.tint(accent)</span>), the 27pt white knob, and Dark / OLED
          tracks (white @ 16%) all stay. The bug is light-family only.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Tests</div>
        <div style={valStyle}>
          Add <span style={code}>controlTrack</span> assertions to <span style={code}>ReaderSettingsPanelContrastTests</span> —
          OFF track vs sheet ≥ 1.8:1 (light), and OFF-track ≠ accent ON-track (Δ ≥ 2.5:1) so on/off stay distinguishable.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Source of truth</div>
        <div style={valStyle}>
          <span style={code}>docs/bugs.md</span> Bug #298. This closes the control-track facet; the rail shipped via #1273, the secondary text via #1292.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function ControlTrackCanvas() {
  const SW = CT_PANEL_W + 50;   // stage width
  const SH = 376;               // stage height (grabber + title + toggle + segmented)
  return (
    <DesignCanvas>

      {/* ─── 1. Decision ─── */}
      <DCSection id="decision"
        title="#1329 — Control-track contrast · Paper / Sepia"
        subtitle="The OFF 'Custom Background' switch and the 'Scroll | Paged' segmented trough are native control surfaces that .tint(accent) never colors — over the cream sheet they read at ~1.19:1, near-invisible. The fix is a new t.controlTrack token = each theme's ink @ 30%: warm, in-family, clearly a control. Recommended panels below.">
        <DCArtboard id="rec-paper" label="Paper · ink @ 30% (recommended)" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
        <DCArtboard id="rec-sepia" label="Sepia · ink @ 30% (recommended)" width={SW} height={SH}>
          <CTStage themeKey="sepia"><CTDisplayPanel themeKey="sepia" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
        <DCPostIt top={-32} right={34} rotate={2} width={268}>
          The OFF switch track and the segmented trough are now a warm cream-grey you can actually see — and the selected "Paged" pill reads because it floats on that darker trough, not on invisible.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. The bug ─── */}
      <DCSection id="bug"
        title="The bug · current tracks"
        subtitle="SwiftUI's defaults: the OFF UISwitch track and the UISegmentedControl trough are iOS .systemFill — a cold pale gray at ~1.19:1 over #fcf8f0. You can't tell the switch is off (or there), and the white selected pill washes into the trough. Before / after, same panel.">
        <DCArtboard id="bug-paper" label="BEFORE · Paper · systemFill" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CURRENT_TRACK} /></CTStage>
            <CTNote top={20} right={18} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {ctTrackRatio(CURRENT_TRACK.paper, THEMES.paper).toFixed(2)}:1 · invisible
            </CTNote>
          </div>
        </DCArtboard>
        <DCArtboard id="bug-sepia" label="BEFORE · Sepia · systemFill" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <CTStage themeKey="sepia"><CTDisplayPanel themeKey="sepia" track={CURRENT_TRACK} /></CTStage>
            <CTNote top={20} right={18} tone="reject">
              <span style={{ width: 13, height: 13, borderRadius: 7, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 800 }}>×</span>
              {ctTrackRatio(CURRENT_TRACK.sepia, THEMES.sepia).toFixed(2)}:1 · invisible
            </CTNote>
          </div>
        </DCArtboard>
        <DCArtboard id="fix-paper" label="AFTER · Paper · ink @ 30%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} /></CTStage>
            <CTNote top={20} right={18} tone="pick">✓ {ctTrackRatio(CONTROL_TRACK.paper, THEMES.paper).toFixed(2)}:1 · reads</CTNote>
          </div>
        </DCArtboard>
        <DCArtboard id="fix-sepia" label="AFTER · Sepia · ink @ 30%" width={SW} height={SH}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <CTStage themeKey="sepia"><CTDisplayPanel themeKey="sepia" track={CONTROL_TRACK} /></CTStage>
            <CTNote top={20} right={18} tone="pick">✓ {ctTrackRatio(CONTROL_TRACK.sepia, THEMES.sepia).toFixed(2)}:1 · reads</CTNote>
          </div>
        </DCArtboard>
      </DCSection>

      {/* ─── 3. Candidates ─── */}
      <DCSection id="candidates"
        title="Candidates · measured"
        subtitle="Four tracks on the real cream sheet, with live ratios and live controls. systemFill stays invisible; the rail token (22%) helps but reads faint on a bare control; ink@30% is the recommended lift; ink@40% starts competing with the accent ON-track. Numbers are computed in-canvas, not asserted.">
        <DCArtboard id="cmp-paper" label="Paper — comparison" width={800} height={452}>
          <CTCompareCard themeKey="paper" />
        </DCArtboard>
        <DCArtboard id="cmp-sepia" label="Sepia — comparison" width={800} height={452}>
          <CTCompareCard themeKey="sepia" />
        </DCArtboard>
      </DCSection>

      {/* ─── 4. Control states ─── */}
      <DCSection id="states"
        title="Control states · the explicit ask"
        subtitle="The token must read in every state. Toggle OFF (the bug) and ON (accent carries it); segmented with Scroll selected and with Paged selected — the elevated pill reads against the new trough either side. Recommended ink @ 30%, Paper.">
        <DCArtboard id="st-off" label="toggle · OFF" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} toggleOn={false} selected="paged" /></CTStage>
        </DCArtboard>
        <DCArtboard id="st-on" label="toggle · ON (accent)" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} toggleOn={true} selected="paged" /></CTStage>
        </DCArtboard>
        <DCArtboard id="st-scroll" label="segmented · Scroll selected" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} selected="scroll" /></CTStage>
        </DCArtboard>
        <DCArtboard id="st-paged" label="segmented · Paged selected" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} selected="paged" /></CTStage>
        </DCArtboard>
        <DCArtboard id="st-on-sepia" label="toggle · ON · Sepia" width={SW} height={SH}>
          <CTStage themeKey="sepia"><CTDisplayPanel themeKey="sepia" track={CONTROL_TRACK} toggleOn={true} selected="scroll" /></CTStage>
        </DCArtboard>
        <DCPostIt top={-32} right={34} rotate={-2} width={252}>
          OFF vs ON is the stress test: off is a quiet warm-grey track, on is the accent. They must never be mistaken for each other — that's why the track stays below the accent's weight.
        </DCPostIt>
      </DCSection>

      {/* ─── 5. Across themes ─── */}
      <DCSection id="themes"
        title="Across themes"
        subtitle="Paper and Sepia get the new token. Dark and OLED keep their current track weight (white @ 16%) — the low-contrast bug is light-family only, and white-on-dark tracks already read fine. Confirmed, not redesigned.">
        <DCArtboard id="th-paper" label="paper · changed" width={SW} height={SH}>
          <CTStage themeKey="paper"><CTDisplayPanel themeKey="paper" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
        <DCArtboard id="th-sepia" label="sepia · changed" width={SW} height={SH}>
          <CTStage themeKey="sepia"><CTDisplayPanel themeKey="sepia" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
        <DCArtboard id="th-dark" label="dark · unchanged" width={SW} height={SH}>
          <CTStage themeKey="dark"><CTDisplayPanel themeKey="dark" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
        <DCArtboard id="th-oled" label="OLED · unchanged" width={SW} height={SH}>
          <CTStage themeKey="oled"><CTDisplayPanel themeKey="oled" track={CONTROL_TRACK} /></CTStage>
        </DCArtboard>
      </DCSection>

      {/* ─── 6. Spec ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what the fixer builds against.">
        <DCArtboard id="spec-card" label="" width={760} height={620}>
          <CTSpecCard />
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { ControlTrackCanvas });
