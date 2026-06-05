// Canvas artboards for #1478 — Bilingual control on the Summarize tab. Feature #90.
//
// The Summarize tab already has a scope row (Section · Chapter · Book so far). Bilingual
// mode (feature #60) is a reading-surface setting. #1478 brings that choice INTO the
// Summarize tab so a summary can be produced in the reader's own language, the target
// language, or BOTH stacked interlinear — without leaving the AI sheet.
//
// CANONICAL: a second control row under the scope chips — a language control on the left
// (current target + globe, tap → language popover) and a single↔dual segmented toggle on
// the right. Two rows, not one crowded row: scope answers "how much", language answers
// "in what language", and mixing them reads as noise.
//
// Output:
//   single  → summary in ONE language (reader picks source or target)
//   dual    → interlinear: target paragraph under each source paragraph, muted + smaller,
//             matching the BilingualReader treatment so the two surfaces feel like one mode.

const PW = 402;

const LANGS = [
  { k: 'Chinese',  glyph: '中', script: 'cjk' },
  { k: 'Japanese', glyph: '日', script: 'cjk' },
  { k: 'Korean',   glyph: '한', script: 'cjk' },
  { k: 'Spanish',  glyph: 'Es', script: 'latin' },
  { k: 'French',   glyph: 'Fr', script: 'latin' },
  { k: 'German',   glyph: 'De', script: 'latin' },
  { k: 'Italian',  glyph: 'It', script: 'latin' },
  { k: 'Arabic',   glyph: 'ع',  script: 'rtl' },
  { k: 'Russian',  glyph: 'Ru', script: 'cyrillic' },
];
const cjkFont = '"Songti SC", "Source Han Serif", "Noto Serif SC", serif';

const SUMMARY_EN = 'The novel opens with its famous ironic claim that a wealthy single man must want a wife. When Mr. Bingley rents nearby Netherfield Park, Mrs. Bennet is desperate to introduce her five daughters; Mr. Bennet teases her but quietly visits anyway.';
const SUMMARY_ZH = '小说以那句著名的反讽开篇：凡有钱的单身男子，必定想娶妻。当宾利先生租下附近的尼日斐庄园时，班纳特太太急于把五个女儿介绍给他；班纳特先生表面上取笑妻子，却悄悄登门拜访。';

// ════════════════════════════════════════════════════
// Scope chips (existing) + language row (new)
// ════════════════════════════════════════════════════
function ScopeChips({ t, active = 'Chapter' }) {
  return (
    <div style={{ display: 'flex', gap: 6 }}>
      {['Section', 'Chapter', 'Book so far'].map(s => (
        <span key={s} style={{ padding: '6px 12px', borderRadius: 100, fontSize: 12, fontWeight: 500,
          background: s === active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
          color: s === active ? '#fff' : t.ink, whiteSpace: 'nowrap' }}>{s}</span>
      ))}
    </div>
  );
}

// Language control + single/dual segmented toggle
function LangRow({ t, lang = 'Chinese', layout = 'single', popoverOpen = false }) {
  const L = LANGS.find(l => l.k === lang);
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
      {/* language control */}
      <button style={{ display: 'inline-flex', alignItems: 'center', gap: 7, padding: '6px 10px 6px 7px',
        borderRadius: 100, border: `0.5px solid ${t.rule}`,
        background: popoverOpen ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)') : 'transparent',
        cursor: 'pointer', fontFamily: 'inherit' }}>
        <span style={{ width: 22, height: 22, borderRadius: 6, flexShrink: 0, background: t.accent, color: '#fff',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontWeight: 700,
          fontFamily: L.script === 'cjk' || L.script === 'rtl' ? cjkFont : 'inherit', fontSize: L.script === 'cjk' ? 13 : 11 }}>{L.glyph}</span>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>{lang}</span>
        <Icons.ChevronD size={13} color={t.sub} stroke={2.2} style={{ transform: popoverOpen ? 'rotate(180deg)' : 'none', transition: 'transform .15s' }}/>
      </button>

      {/* single / dual segmented */}
      <div style={{ display: 'flex', borderRadius: 9, padding: 2,
        background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
        {[['single', 'Single'], ['dual', 'Bilingual']].map(([k, label]) => (
          <span key={k} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 11px', borderRadius: 7,
            background: k === layout ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
            color: k === layout ? t.ink : t.sub, fontSize: 11.5, fontWeight: 600,
            boxShadow: k === layout ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>
            {k === 'dual' ? <StackGlyph size={12} color={k === layout ? t.accent : t.sub}/> : <LineGlyph size={12} color={k === layout ? t.accent : t.sub}/>}
            {label}
          </span>
        ))}
      </div>
    </div>
  );
}

function LineGlyph({ size = 12, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 6h10M3 10h7"/>
    </svg>
  );
}
function StackGlyph({ size = 12, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="none" stroke={color} strokeWidth="1.6" strokeLinecap="round">
      <path d="M3 4h10M3 7h7"/><path d="M3 11h10M3 13.5h7" opacity="0.55"/>
    </svg>
  );
}

// ════════════════════════════════════════════════════
// Summary card — single / dual / loading / error
// ════════════════════════════════════════════════════
function SummaryCard({ t, mode = 'single', lang = 'Chinese' }) {
  const L = LANGS.find(l => l.k === lang);
  const useCjk = L.script === 'cjk';
  return (
    <div style={{ padding: 16, borderRadius: 14, marginTop: 14,
      background: t.isDark ? 'rgba(214,136,90,0.08)' : 'rgba(140,47,47,0.04)',
      border: `0.5px solid ${t.rule}` }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 12 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 11, color: t.sub, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase' }}>
          <Icons.Sparkle size={11} color={t.accent} stroke={2}/>
          <span>Chapter 1 — Summary</span>
        </div>
        <button style={{ border: 'none', background: 'none', cursor: 'pointer', padding: 4, display: 'flex' }}>
          <Icons.Copy size={14} color={t.sub} stroke={2}/>
        </button>
      </div>

      {mode === 'loading' && <SummarySkeleton t={t} dual/>}
      {mode === 'error' && <SummaryError t={t} lang={lang}/>}

      {mode === 'single' && (
        <p style={{ margin: 0, fontFamily: SERIF, fontSize: 15, lineHeight: 1.55, color: t.ink }}>{SUMMARY_EN}</p>
      )}

      {mode === 'single-target' && (
        <p style={{ margin: 0, fontFamily: useCjk ? cjkFont : SERIF, fontSize: 15.5, lineHeight: 1.7, color: t.ink }}>{SUMMARY_ZH}</p>
      )}

      {mode === 'dual' && (
        <div>
          <p style={{ margin: '0 0 7px', fontFamily: SERIF, fontSize: 15, lineHeight: 1.55, color: t.ink }}>{SUMMARY_EN}</p>
          <p style={{ margin: 0, paddingTop: 8, borderTop: `0.5px dashed ${t.rule}`,
            fontFamily: useCjk ? cjkFont : SERIF, fontSize: 14, lineHeight: 1.65, color: t.sub }}>{SUMMARY_ZH}</p>
        </div>
      )}
    </div>
  );
}

function SummarySkeleton({ t, dual = false }) {
  const bar = (w, muted) => (
    <div style={{ height: 9, width: `${w * 100}%`, borderRadius: 5, marginBottom: 8,
      background: t.isDark ? `rgba(255,255,255,${muted ? 0.04 : 0.07})` : `rgba(0,0,0,${muted ? 0.035 : 0.06})` }}/>
  );
  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
        <CSpinner size={13} color={t.accent} stroke={2}/>
        <span style={{ fontSize: 12.5, color: t.sub }}>Summarizing & translating…</span>
      </div>
      {bar(1)}{bar(0.95)}{bar(0.55)}
      {dual && <div style={{ marginTop: 6, paddingTop: 8, borderTop: `0.5px dashed ${t.rule}` }}>{bar(0.9, true)}{bar(0.5, true)}</div>}
    </div>
  );
}

function SummaryError({ t, lang }) {
  return (
    <div style={{ display: 'flex', gap: 10 }}>
      <span style={{ width: 26, height: 26, borderRadius: 13, flexShrink: 0, background: 'rgba(192,68,58,0.12)',
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <Icons.Alert size={14} color="#c0443a" stroke={2}/>
      </span>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 13.5, fontWeight: 600, color: t.ink }}>Couldn’t translate to {lang}</div>
        <div style={{ fontSize: 12.5, color: t.sub, marginTop: 2, lineHeight: 1.4 }}>The summary was generated, but the translation step failed. Show it in English, or try the translation again.</div>
        <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
          <button style={{ padding: '7px 13px', borderRadius: 100, border: 'none', background: t.accent, color: '#fff',
            fontSize: 12.5, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit', whiteSpace: 'nowrap' }}>Retry translation</button>
          <button style={{ padding: '7px 13px', borderRadius: 100, border: `0.5px solid ${t.rule}`, background: 'transparent',
            color: t.ink, fontSize: 12.5, fontWeight: 600, cursor: 'pointer', fontFamily: 'inherit', whiteSpace: 'nowrap' }}>Keep English</button>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Language popover
// ════════════════════════════════════════════════════
function LangPopover({ t, lang = 'Chinese' }) {
  return (
    <div style={{ position: 'absolute', left: 18, top: 150, width: 290, zIndex: 8 }}>
      <Popover t={t}>
        <PopHeader t={t} title="Summary language" hint="The summary is written in this language."/>
        <div style={{ padding: 10, display: 'grid', gridTemplateColumns: 'repeat(2, 1fr)', gap: 7 }}>
          {LANGS.map(l => {
            const active = l.k === lang;
            return (
              <div key={l.k} style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '8px 9px', borderRadius: 10,
                background: active ? (t.isDark ? `${t.accent}26` : `${t.accent}14`) : (t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.02)'),
                boxShadow: active ? `inset 0 0 0 1.5px ${t.accent}` : `inset 0 0 0 0.5px ${t.rule}` }}>
                <span style={{ width: 20, height: 20, borderRadius: 5, flexShrink: 0,
                  background: active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'),
                  color: active ? '#fff' : t.ink, display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
                  fontWeight: 700, fontFamily: l.script === 'cjk' || l.script === 'rtl' ? cjkFont : 'inherit', fontSize: l.script === 'cjk' ? 12 : 10 }}>{l.glyph}</span>
                <span style={{ fontSize: 12.5, fontWeight: active ? 600 : 500, color: t.ink }}>{l.k}</span>
              </div>
            );
          })}
        </div>
        <PopFooter t={t} icon="Globe" text="Translation uses your configured AI provider. Long summaries may take a few seconds."/>
      </Popover>
      <Notch t={t} left={40} />
    </div>
  );
}

// ════════════════════════════════════════════════════
// Full Summarize screen
// ════════════════════════════════════════════════════
function SummarizeScreen({ themeKey = 'paper', mode = 'single', layout = 'single', lang = 'Chinese', popover = false }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="summary">
        <div style={{ padding: '14px 18px 8px', borderBottom: `0.5px solid ${t.rule}`, display: 'flex', flexDirection: 'column', gap: 11 }}>
          <ScopeChips t={t} active="Chapter"/>
          <LangRow t={t} lang={lang} layout={layout} popoverOpen={popover}/>
        </div>
        <div style={{ flex: 1, overflow: 'hidden', padding: '4px 18px 16px' }} className="hide-scroll">
          <SummaryCard t={t} mode={mode} lang={lang}/>
        </div>
        {popover && <LangPopover t={t} lang={lang}/>}
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// Rejected — language folded into the scope row
// ════════════════════════════════════════════════════
function CrowdedRowScreen({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="summary">
        <div style={{ padding: '14px 18px 12px', borderBottom: `0.5px solid ${t.rule}` }}>
          <div style={{ display: 'flex', gap: 6, alignItems: 'center', overflow: 'hidden' }}>
            <span style={{ padding: '6px 11px', borderRadius: 100, fontSize: 11.5, fontWeight: 500, background: t.accent, color: '#fff', whiteSpace: 'nowrap' }}>Chapter</span>
            <span style={{ padding: '6px 11px', borderRadius: 100, fontSize: 11.5, fontWeight: 500, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', color: t.ink, whiteSpace: 'nowrap' }}>Book</span>
            <span style={{ width: 1, height: 18, background: t.rule, flexShrink: 0 }}/>
            <span style={{ padding: '6px 11px', borderRadius: 100, fontSize: 11.5, fontWeight: 600, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', color: t.ink, whiteSpace: 'nowrap', display: 'inline-flex', gap: 4, alignItems: 'center' }}>中 ZH</span>
            <span style={{ padding: '6px 11px', borderRadius: 100, fontSize: 11.5, fontWeight: 600, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', color: t.ink, whiteSpace: 'nowrap' }}>Dual</span>
          </div>
        </div>
        <div style={{ flex: 1, padding: '4px 18px 16px' }}><SummaryCard t={t} mode="dual" lang="Chinese"/></div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// CANVAS
// ════════════════════════════════════════════════════
function BilingualSummarizeCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>
      <DCSection id="intro" title="Bilingual control · Summarize tab · #1478"
        subtitle="Feature #90. Brings the bilingual reading choice (feature #60) into the Summarize tab so a summary can be produced in the reader’s language, the target language, or both stacked interlinear. A second control row under the scope chips: language picker on the left, single↔bilingual toggle on the right.">
        <DCPostIt top={-36} right={26} rotate={-2} width={336}>
          <b>Two rows, not one.</b> Scope answers “how much” (Section/Chapter/Book); language
          answers “in what language”. Folding both into one chip strip reads as noise and
          overflows on narrow phones — so language gets its own row.
        </DCPostIt>
      </DCSection>

      {/* A — canonical */}
      <DCSection id="A" title="A — Control row + output modes (canonical)"
        subtitle="The new row sits under the scope chips. “Bilingual” stacks the target paragraph under the source in the muted, smaller style used by the bilingual reader, so summary and reading surface feel like one mode.">
        <DCArtboard id="A-single-en" label="Single · English source" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="single" layout="single" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="A-single-zh" label="Single · target language" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="single-target" layout="single" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="A-dual" label="Bilingual · interlinear" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="dual" layout="dual" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="A-pop" label="Language popover" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="dual" layout="dual" lang="Chinese" popover/>
        </DCArtboard>
      </DCSection>

      {/* States */}
      <DCSection id="S" title="S — Loading · error"
        subtitle="Bilingual generation runs two steps (summarize, then translate). Loading shows a dual skeleton so the layout doesn’t jump. If translation fails after the summary lands, the card offers Retry translation or Keep English — the work isn’t lost.">
        <DCArtboard id="S-loading" label="Generating · dual skeleton" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="loading" layout="dual" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="S-error" label="Translation failed" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="error" layout="dual" lang="Chinese"/>
        </DCArtboard>
      </DCSection>

      {/* Other languages + dark */}
      <DCSection id="L" title="L — Other languages · themes"
        subtitle="Latin-script and dark-theme coverage. The target paragraph adopts the script’s font; CJK gets a serif CJK stack and looser line-height.">
        <DCArtboard id="L-fr" label="French · bilingual" width={PW} height={760}>
          <SummarizeScreen themeKey="paper" mode="dual" layout="dual" lang="French"/>
        </DCArtboard>
        <DCArtboard id="L-dark" label="Chinese · bilingual · dark" width={PW} height={760}>
          <SummarizeScreen themeKey="dark" mode="dual" layout="dual" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="L-dark-pop" label="Popover · dark" width={PW} height={760}>
          <SummarizeScreen themeKey="dark" mode="single" layout="single" lang="Japanese" popover/>
        </DCArtboard>
      </DCSection>

      {/* Anatomy */}
      <DCSection id="D" title="D — Control row · true size"
        subtitle="Scope chips + language row at 1:1.">
        <DCArtboard id="D-row" label="Two-row control block" width={PW} height={120}>
          <AnatomyWrap pad={16}>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 11 }}>
              <ScopeChips t={THEMES.paper} active="Chapter"/>
              <LangRow t={THEMES.paper} lang="Chinese" layout="dual"/>
            </div>
          </AnatomyWrap>
        </DCArtboard>
      </DCSection>

      {/* Rejected */}
      <DCSection id="B" title="B — Language folded into scope row (rejected)"
        subtitle="Language + layout chips appended to the scope strip behind a divider. One row is tidier in the mock, but four-plus chips overflow on small phones and the two different kinds of choice blur together.">
        <DCArtboard id="B-crowded" label="One crowded row" width={PW} height={760}>
          <CrowdedRowScreen themeKey="paper"/>
        </DCArtboard>
        <DCPostIt bottom={-28} left={22} rotate={2} width={300}>
          Rejected: the strip scrolls horizontally the moment a language name is long
          (“Book so far”, “Portuguese”), hiding the layout toggle. Separate rows keep both
          controls always visible.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { BilingualSummarizeCanvas });
