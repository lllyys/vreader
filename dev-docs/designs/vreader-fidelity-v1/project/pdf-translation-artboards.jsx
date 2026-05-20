// Canvas artboards for issue #1023 — PDF below-page translation panel.
//
// Three sections:
//   A — Split layout (canonical). Persistent below-page panel. Four content
//       states + collapsed + dark.
//   B — Peek-sheet (alternative). Drawer pinned to bottom, peek vs. expand.
//   C — Panel anatomy detail (true size). Header anatomy + state body
//       comparison so the reviewer can see every variant side-by-side.

const PDF_PHONE_W = 402;
const PDF_PHONE_H = 740;

function PDFPhone({ themeKey = 'paper', children, height = PDF_PHONE_H }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PDF_PHONE_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>{children}</div>
  );
}

// ──────────────────────────────────────────────────────
// A — split layout (canonical)
// ──────────────────────────────────────────────────────
function A_Split({ themeKey, panelState = 'default', collapsed = false, lang = 'Chinese' }) {
  return (
    <PDFPhone themeKey={themeKey}>
      <PDFReaderShell theme={THEMES[themeKey]}
        variant="split"
        panelState={panelState}
        panelCollapsed={collapsed}
        lang={lang}/>
    </PDFPhone>
  );
}

// ──────────────────────────────────────────────────────
// B — peek sheet (alternative)
// ──────────────────────────────────────────────────────
function B_Sheet({ themeKey, panelState = 'default', expanded = false, lang = 'Chinese' }) {
  return (
    <PDFPhone themeKey={themeKey}>
      <PDFReaderShell theme={THEMES[themeKey]}
        variant="sheet"
        panelState={panelState}
        sheetExpanded={expanded}
        lang={lang}/>
    </PDFPhone>
  );
}

// ──────────────────────────────────────────────────────
// C — panel anatomy detail (true size, side-by-side)
// ──────────────────────────────────────────────────────
function C_Anatomy({ themeKey }) {
  const t = THEMES[themeKey];
  const rows = [
    { key: 'default', label: 'Default · translation present',
      note: 'Body inherits the interlinear hierarchy: source font-size × 0.88, line-height 1.55, target-script font, sub colour at 85% opacity. Indented after the first paragraph so the eye sees alternation rhythm.',
      state: 'default' },
    { key: 'loading', label: 'Loading · in flight',
      note: 'Three shimmer bars + a label change in the header (\u201cPage 42 · translating…\u201d). Deliberately less elaborate than the default — this is a 1–3s state, not a destination.',
      state: 'loading' },
    { key: 'offline', label: 'Offline · uncached',
      note: 'Distinguished from loading by a header subhead and an explicit affordance. Retry primary; the AI tab is the single-paragraph escape hatch when the user does’t want to wait for connectivity.',
      state: 'offline' },
    { key: 'empty', label: 'Empty · no extractable text',
      note: 'Image-only page or unOCR’d scan. Distinct copy from \u201coffline\u201d so the user doesn’t bash retry on a page that will never translate. The body is one line tall — there’s nothing to show.',
      state: 'empty' },
  ];
  return (
    <div style={{
      width: 760, padding: '22px 26px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column', gap: 16,
    }}>
      {rows.map(r => (
        <div key={r.key} style={{
          display: 'flex', alignItems: 'stretch', gap: 22,
          paddingBottom: 16, borderBottom: `0.5px dashed ${t.rule}`,
        }}>
          <div style={{ width: 220, flexShrink: 0 }}>
            <div style={{
              fontSize: 11, color: t.sub, letterSpacing: 0.6,
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 6,
            }}>{r.key}</div>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500, marginBottom: 6, lineHeight: 1.3 }}>{r.label}</div>
            <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.5 }}>{r.note}</div>
          </div>
          {/* true-size panel preview */}
          <div style={{
            flex: 1, height: r.state === 'empty' ? 90 : 160,
            background: t.bg,
            borderRadius: 8, overflow: 'hidden',
            border: `0.5px solid ${t.rule}`,
          }}>
            <PDFTranslationPanel theme={t} state={r.state} lang="Chinese" page={42}
              collapsed={false} onToggle={() => {}}/>
          </div>
        </div>
      ))}
    </div>
  );
}

// ──────────────────────────────────────────────────────
// CanvasRoot
// ──────────────────────────────────────────────────────
function CanvasRoot1023() {
  return (
    <DesignCanvas>
      <DCSection id="intro" title="PDF below-page translation panel · #1023"
        subtitle="PDF is fixed-layout. The interlinear renderer can’t reflow glyphs, so when bilingual mode is on the translation sits in a panel BELOW the page. One surface, five states.">
        <DCPostIt top={-30} right={40} rotate={-2} width={300}>
          <b>Pick A1 (split).</b> The panel is part of the reading frame,
          not a modal — that’s the whole point of bilingual mode.
          Collapse handle (A5) gives users who want the page full-bleed an
          exit without leaving bilingual mode entirely.
        </DCPostIt>
      </DCSection>

      <DCSection id="A-split" title="A — Split layout (canonical)"
        subtitle="Persistent below-page panel sharing the reader frame. Page reflows up when collapsed; chrome stays put.">
        <DCArtboard id="A1-default"  label="A1 · Default — paper" width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="paper" panelState="default"/>
        </DCArtboard>
        <DCArtboard id="A2-loading"  label="A2 · Loading"            width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="paper" panelState="loading"/>
        </DCArtboard>
        <DCArtboard id="A3-offline"  label="A3 · Offline + retry"    width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="paper" panelState="offline"/>
        </DCArtboard>
        <DCArtboard id="A4-empty"    label="A4 · Empty — no extractable text" width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="paper" panelState="empty"/>
        </DCArtboard>
        <DCArtboard id="A5-collapsed" label="A5 · Collapsed strip"   width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="paper" panelState="default" collapsed/>
        </DCArtboard>
        <DCArtboard id="A6-dark"     label="A6 · Dark theme"         width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="dark"  panelState="default"/>
        </DCArtboard>
        <DCArtboard id="A7-darkoff"  label="A7 · Dark + offline"     width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="dark"  panelState="offline"/>
        </DCArtboard>
        <DCArtboard id="A8-sepia"    label="A8 · Sepia + Japanese"   width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <A_Split themeKey="sepia" panelState="default" lang="Japanese"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={260}>
          Panel height = ~36% of the body. Tuned so two full source paragraphs
          stay on the page above and the user reads top→bottom without
          shuttling. Independently scrollable when translation overruns.
        </DCPostIt>
      </DCSection>

      <DCSection id="B-sheet" title="B — Peek-sheet (alternative)"
        subtitle="Drawer pinned bottom. Peek shows the first line of translation; tap to expand. Prefer A unless the user has rejected the split feel.">
        <DCArtboard id="B1-peek"     label="B1 · Peek — page full" width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <B_Sheet themeKey="paper" panelState="default" expanded={false}/>
        </DCArtboard>
        <DCArtboard id="B2-expanded" label="B2 · Expanded"             width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <B_Sheet themeKey="paper" panelState="default" expanded/>
        </DCArtboard>
        <DCArtboard id="B3-offline"  label="B3 · Peek · offline (one-liner)" width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <B_Sheet themeKey="paper" panelState="offline" expanded={false}/>
        </DCArtboard>
        <DCArtboard id="B4-dark"     label="B4 · Expanded · dark" width={PDF_PHONE_W} height={PDF_PHONE_H}>
          <B_Sheet themeKey="dark"  panelState="default" expanded/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={280}>
          The peek state preserves PDF page real estate (good for figure-heavy
          books) but hides the very thing bilingual mode promises. Acceptable
          as a setting toggle, not the default.
        </DCPostIt>
      </DCSection>

      <DCSection id="C-anatomy" title="C — Panel anatomy detail"
        subtitle="True-size side-by-side comparison of all four content states. Same header, different bodies.">
        <DCArtboard id="C-paper" label="States — paper" width={760} height={780}>
          <C_Anatomy themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="C-dark"  label="States — dark"  width={760} height={780}>
          <C_Anatomy themeKey="dark"/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot1023 });
