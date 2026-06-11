// Canvas artboards — bilingual follow-up suite:
//   #1650 heading translation · #1646 sentence granularity ·
//   #1640 settings re-entry · #1641 total reading time.

const BST_W = 402;
const BST_H = 740;

// ────────────────────────────────────────────────────
// Phone shell
// ────────────────────────────────────────────────────
function BST_Phone({ themeKey, children, height = BST_H, lang = 'Chinese',
                     pill = true, pillPressed = false, bottom = true }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: BST_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <BST_TopChrome t={t} lang={lang} pill={pill} pillPressed={pillPressed}/>
      {children}
      {bottom && (
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 10, color: t.sub, opacity: 0.65, letterSpacing: 0.5,
        }}>3 / 432</div>
      )}
    </div>
  );
}

function BST_TopChrome({ t, lang, pill, pillPressed }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      paddingTop: 36, paddingBottom: 8, zIndex: 30,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 14px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 2, color: t.accent, fontSize: 14, fontWeight: 500 }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor"
            strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
          <span>Library</span>
        </div>
        <div style={{
          flex: 1, textAlign: 'center', padding: '0 8px',
          overflow: 'hidden', whiteSpace: 'nowrap',
          fontFamily: BS_SERIF, fontSize: 13.5, fontWeight: 600,
          color: t.ink, fontStyle: 'italic',
        }}>
          <span>Pride and Prejudice</span>
          {pill && <BSBilingualPill t={t} lang={lang} pressed={pillPressed}/>}
        </div>
        <div style={{ display: 'flex', gap: 0, color: t.ink }}>
          <div style={{ width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></svg>
          </div>
          <div style={{ width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <svg width="17" height="17" viewBox="0 0 24 24" fill="currentColor"><circle cx="5" cy="12" r="1.3"/><circle cx="12" cy="12" r="1.3"/><circle cx="19" cy="12" r="1.3"/></svg>
          </div>
        </div>
      </div>
    </div>
  );
}

// Faded page behind popovers / sheets
function BST_Faded({ t }) {
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '92px 26px 40px', opacity: 0.5 }}>
      <BSHeadingPair t={t} en="Chapter 1" tr="第一章"/>
      {BS_PARAS.slice(0, 2).map((p, i) => (
        <BSParagraphPara key={i} t={t} sentences={p.sentences} first={i === 0} fontSize={15}/>
      ))}
    </div>
  );
}

// Plain (non-bilingual) page body — for #1641 artboards.
function BST_PlainPage({ t, fontSize = 16, margin = 22, bottomInset = 132 }) {
  const paras = [
    BS_PARAS[0].sentences[0].en,
    BS_PARAS[1].sentences[0].en,
    BS_PARAS[2].sentences.map(s => s.en).join(' '),
    BS_PARAS[3].sentences.map(s => s.en).join(' '),
  ];
  return (
    <div style={{
      position: 'absolute', top: 92, bottom: bottomInset, left: margin, right: margin,
      overflow: 'hidden',
    }}>
      <div style={{
        fontFamily: BS_SERIF, fontSize: 13, color: t.sub, letterSpacing: 2,
        textTransform: 'uppercase', textAlign: 'center',
        marginBottom: 18, marginTop: 8, fontWeight: 500,
      }}>Chapter 1</div>
      {paras.map((p, i) => (
        <p key={i} style={{
          fontFamily: BS_SERIF, fontSize, lineHeight: 1.62, color: t.ink,
          margin: `0 0 ${fontSize * 0.55}px`,
          textIndent: i === 0 ? 0 : `${fontSize * 1.4}px`,
          textAlign: 'justify', hyphens: 'auto',
        }}>
          {i === 0 && (
            <span style={{
              fontFamily: BS_SERIF, fontSize: fontSize * 2.6, lineHeight: 0.85,
              float: 'left', marginRight: 6, marginTop: 4,
              color: t.accent, fontWeight: 600,
            }}>{p[0]}</span>
          )}
          {i === 0 ? p.slice(1) : p}
        </p>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────
// Detail cards
// ────────────────────────────────────────────────────
function HeadingAnatomy({ themeKey }) {
  const t = THEMES[themeKey];
  const rows = [
    { key: 'H-A', label: 'Centered echo (canonical)',
      note: 'Heading vocabulary, not paragraph vocabulary: centered, no border. Target serif at 15.5px with wide tracking so the CJK line reads as a title, one step quieter than the source strip.',
      el: <BSHeadingPair t={t} en="Chapter 1" tr="第一章" marginBottom={0}/> },
    { key: 'H-A', label: 'Numbered heading — numerals translate',
      note: '"Chapter 12" becomes 第十二章, not 章 12. The translator owns numeral handling; the row never mixes scripts.',
      el: <BSHeadingPair t={t} en="Chapter 12" tr="第十二章" marginBottom={0}/> },
    { key: 'H-A', label: 'Front matter / very short',
      note: 'Single-glyph-pair results stay legible because tracking carries the width.',
      el: <BSHeadingPair t={t} en="Preface" tr="序言" marginBottom={0}/> },
    { key: 'H-A', label: 'Long descriptive heading',
      note: 'Wraps centered; tracking drops via the same rule the source strip uses.',
      el: <BSHeadingPair t={t} en="On the Method of Reading Old Books" tr="论读旧书之法" marginBottom={0}/> },
    { key: 'H-A', label: 'Loading — not yet translated',
      note: 'A single centered shimmer bar in the row\u2019s slot. Same loading vocabulary as paragraph rows (#1024), centered like the heading.',
      el: <BSHeadingPair t={t} en="Chapter 1" tr="" state="loading" marginBottom={0}/> },
    { key: 'H-B', label: 'Inline dot-joined (alt, short headings only)',
      note: 'One line: "CHAPTER 1 · 第一章". Tightest; breaks down the moment a heading wraps, so it is an optimization, not the base treatment.',
      el: <BSHeadingPair t={t} en="Chapter 1" tr="第一章" variant="inline" marginBottom={0}/> },
    { key: 'H-C', label: 'Paragraph-row vocabulary (rejected)',
      note: 'The left-border row under a centered heading mixes two alignment systems — the border reads as a pull-quote, not a title.',
      el: <BSHeadingPair t={t} en="Chapter 1" tr="第一章" variant="border" marginBottom={0}/> },
  ];
  return (
    <div style={{
      width: 700, padding: '24px 28px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column', gap: 18,
    }}>
      {rows.map((r, i) => (
        <div key={i} style={{
          display: 'flex', alignItems: 'center', gap: 22, paddingBottom: 18,
          borderBottom: i === rows.length - 1 ? 'none' : `0.5px dashed ${t.rule}`,
        }}>
          <div style={{ width: 250, flexShrink: 0 }}>
            <div style={{
              fontSize: 11, color: t.sub, letterSpacing: 0.6,
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 5,
            }}>{r.key}</div>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500, marginBottom: 5, lineHeight: 1.3 }}>{r.label}</div>
            <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.5 }}>{r.note}</div>
          </div>
          <div style={{ flex: 1 }}>{r.el}</div>
        </div>
      ))}
    </div>
  );
}

function SentenceAnatomy({ themeKey }) {
  const t = THEMES[themeKey];
  const pair = BS_PARAS[2];
  return (
    <div style={{
      width: 740, padding: '24px 28px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', gap: 28,
    }}>
      {[
        { label: 'Paragraph mode (committed)',
          note: 'One row per ¶ · 0.88× size · border ' + '55-alpha · 6px gap above the row.',
          el: <BSParagraphPara t={t} sentences={pair.sentences} first fontSize={16}/> },
        { label: 'Sentence mode (this issue)',
          note: 'One row per sentence · 0.85× size · border 40-alpha · 4px gap. One step lighter so doubling the row count does not double the page weight. 7px between sentence pairs keeps the ¶ reading as one block.',
          el: <BSSentencePara t={t} sentences={pair.sentences} first fontSize={16}/> },
      ].map((c, i) => (
        <div key={i} style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 11, color: t.sub, letterSpacing: 0.6,
            textTransform: 'uppercase', fontWeight: 600, marginBottom: 4,
          }}>{c.label}</div>
          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.5, marginBottom: 14, minHeight: 68 }}>{c.note}</div>
          {c.el}
        </div>
      ))}
    </div>
  );
}

// #1646 alternative — the Sentence option as a DISABLED control state
function GranularityDisabledCard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 380, padding: '22px 24px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
    }}>
      <BSuiteLabel t={t}>Granularity</BSuiteLabel>
      <div style={{
        display: 'flex', marginTop: 10, borderRadius: 12, padding: 3,
        background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
      }}>
        <div style={{
          flex: 1, padding: '10px 10px', borderRadius: 10, textAlign: 'center',
          background: t.isDark ? '#3a3530' : '#fff',
          boxShadow: '0 1px 2px rgba(0,0,0,0.08)',
        }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: t.ink }}>Paragraph</div>
          <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>Translate after each ¶</div>
        </div>
        <div style={{ flex: 1, padding: '10px 10px', borderRadius: 10, textAlign: 'center', opacity: 0.45 }}>
          <div style={{ fontSize: 13, fontWeight: 600, color: t.ink }}>Sentence</div>
          <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>Translate after each sentence</div>
        </div>
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7, marginTop: 9 }}>
        <Icons.Info size={12} color={t.sub} stroke={2}/>
        <span style={{ fontSize: 10.5, color: t.sub, lineHeight: 1.45 }}>
          Sentence mode isn&rsquo;t available for this book&rsquo;s format yet.
        </span>
      </div>
    </div>
  );
}

// #1641 — metrics-line variants, true size
function MetricsLineAnatomy({ themeKey }) {
  const t = THEMES[themeKey];
  const rows = [
    { label: 'Page readout (default · ships today)',
      note: 'Leading and trailing as committed.',
      el: <RTMetricsLine t={t} leading="Page 18" trailing="414 pages left in book"/> },
    { label: 'Time readout — tap the trailing label',
      note: 'Session first, then total. Both durations in one glance; choice persists per book.',
      el: <RTMetricsLine t={t} leading="Page 18" trailing="12m read · 6h 40m total"/> },
    { label: 'Pressed — mid-tap highlight',
      note: 'The label is the hit target (44px tall incl. padding). No extra chrome.',
      el: <RTMetricsLine t={t} leading="Page 18" trailing="12m read · 6h 40m total" pressed/> },
    { label: 'First-ever session',
      note: 'total == session, so a "total" would be noise — the suffix names the situation instead.',
      el: <RTMetricsLine t={t} leading="Page 4" trailing="4m read · first session"/> },
    { label: 'Long totals',
      note: 'Above 10h the total drops minutes — "41h", never "41h 23m".',
      el: <RTMetricsLine t={t} leading="Page 812" trailing="18m read · 41h total"/> },
    { label: 'Narrow width + long chapter leading',
      note: 'Leading truncates with an ellipsis; the trailing label never shrinks or wraps (flex-shrink 0).',
      el: <div style={{ width: 240 }}>
        <RTMetricsLine t={t} leading="Ch. 19 — Travelling in Company with a Saint" trailing="12m · 6h 40m total"/>
      </div> },
  ];
  return (
    <div style={{
      width: 620, padding: '24px 28px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column', gap: 16,
    }}>
      {rows.map((r, i) => (
        <div key={i} style={{
          paddingBottom: 16,
          borderBottom: i === rows.length - 1 ? 'none' : `0.5px dashed ${t.rule}`,
        }}>
          <div style={{ fontSize: 13, color: t.ink, fontWeight: 500, marginBottom: 2 }}>{r.label}</div>
          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, marginBottom: 10 }}>{r.note}</div>
          <div style={{
            padding: '10px 14px', borderRadius: 10,
            background: t.chrome, border: `0.5px solid ${t.rule}`,
            maxWidth: 360,
          }}>{r.el}</div>
        </div>
      ))}
    </div>
  );
}

function BookDetailsTimeCard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 380, padding: '22px 24px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
    }}>
      <BSuiteLabel t={t}>Book details · after Progress</BSuiteLabel>
      <div style={{ marginTop: 10 }}>
        <RTBookDetailsRows t={t}/>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Canvas root
// ────────────────────────────────────────────────────
function CanvasRootSuite() {
  const sheetShell = (themeKey, children) => {
    const t = THEMES[themeKey];
    return (
      <div style={{
        width: BST_W, height: 720, position: 'relative', overflow: 'hidden',
        background: t.bg, borderRadius: 18,
        boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
      }}>
        <BST_Faded t={t}/>
        {children}
      </div>
    );
  };

  return (
    <DesignCanvas>
      <DCSection id="H" title="#1650 — Heading translation · bilingual mode"
        subtitle="Feature #100. Chapter headings join the interlinear contract. Canonical: a centered echo row — heading vocabulary (centered, tracked, no border), one step quieter than the source strip.">
        <DCArtboard id="H1" label="H1 · Canonical — heading echo over paragraph rows" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper">
            <BSReadingPage t={THEMES.paper} mode="paragraph"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="H2" label="H2 · Heading still loading" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper">
            <BSReadingPage t={THEMES.paper} mode="paragraph" headingState="loading"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="H3" label="H3 · Dark theme" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="dark">
            <BSReadingPage t={THEMES.dark} mode="paragraph"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="H4" label="H4 · Variants & edge cases · true size" width={700} height={990}>
          <HeadingAnatomy themeKey="paper"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={290}>
          <b>Why centered, not bordered:</b> the heading is the one block whose
          typography is symmetric. Putting the paragraph-row border under it
          would left-anchor a centered element. The echo keeps the 1:1
          block↔segment contract — one heading, one row — and the drop-cap
          paragraph below is untouched.
        </DCPostIt>
      </DCSection>

      <DCSection id="S" title="#1646 — Sentence granularity · interlinear rows"
        subtitle="Bug #344. The Sentence option finally gets a reading treatment: a translation row after each sentence, one step lighter than the paragraph row, with the paragraph still reading as one block.">
        <DCArtboard id="S1" label="S1 · Sentence mode — dialogue run" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper">
            <BSReadingPage t={THEMES.paper} mode="sentence"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="S2" label="S2 · Paragraph mode — same page, for comparison" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper">
            <BSReadingPage t={THEMES.paper} mode="paragraph"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="S3" label="S3 · Partial — cached + loading + pending" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper">
            <BSReadingPage t={THEMES.paper} mode="sentence"
              paraStates={[['cached'], ['cached'], ['loading', 'pending'], ['pending', 'pending']]}/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="S4" label="S4 · Dark theme" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="dark">
            <BSReadingPage t={THEMES.dark} mode="sentence"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="S5" label="S5 · Row anatomy — paragraph vs sentence · true size" width={740} height={560}>
          <SentenceAnatomy themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="S6" label="S6 · Alternative — Sentence disabled (per-format fallback)" width={380} height={220}>
          <GranularityDisabledCard themeKey="paper"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={300}>
          <b>Pick the rows, keep the fallback.</b> Per-sentence rows are the
          option&rsquo;s plain meaning — S1 is the target. S6 is the designed
          DISABLED state for pipelines that can&rsquo;t hold the 1:1 contract
          at sentence level yet (Gate-4): the control dims rather than lying.
          Drop cap, justification and short sentences all hold in S1.
        </DCPostIt>
      </DCSection>

      <DCSection id="E" title="#1640 — Translation settings · re-entry after setup"
        subtitle="Feature #99. Canonical: a Translation settings row inside the More menu&rsquo;s bilingual cluster. Secondary: tapping the EN↔中 pill. Both reopen the setup sheet, edit-framed and pre-filled.">
        <DCArtboard id="E1" label="E1 · More menu — bilingual cluster + settings row" width={BST_W} height={620}>
          <BST_Phone themeKey="paper" height={620} bottom={false}>
            <BST_Faded t={THEMES.paper}/>
            <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.08)' }}/>
            <BSMorePopover t={THEMES.paper}/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="E2" label="E2 · Sheet, edit-framed — no changes yet" width={BST_W} height={720}>
          {sheetShell('paper', <BSSettingsSheet t={THEMES.paper} selLang="Chinese" dirty="none"/>)}
        </DCArtboard>
        <DCArtboard id="E3" label="E3 · New language picked — cost surfaced" width={BST_W} height={720}>
          {sheetShell('paper', <BSSettingsSheet t={THEMES.paper} selLang="Japanese" dirty="new-lang"/>)}
        </DCArtboard>
        <DCArtboard id="E4" label="E4 · Cached language picked — instant switch" width={BST_W} height={720}>
          {sheetShell('paper', <BSSettingsSheet t={THEMES.paper} selLang="French" dirty="cached-lang"/>)}
        </DCArtboard>
        <DCArtboard id="E5" label="E5 · Confirmed — re-translating, pill flips to 日" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper" lang="Japanese">
            <BSReadingPage t={THEMES.paper} mode="paragraph" lang="Japanese"
              heading={{ en: 'Chapter 1', tr: '第一章' }}
              paraStates={['cached', 'pending', 'pending', 'pending']}/>
            <BSRetranslateBanner t={THEMES.paper}/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="E6" label="E6 · Secondary — pill is tappable" width={BST_W} height={300}>
          <BST_Phone themeKey="paper" height={300} pillPressed bottom={false}>
            <BST_Faded t={THEMES.paper}/>
            <div style={{
              position: 'absolute', top: 96, left: 0, right: 0,
              display: 'flex', justifyContent: 'center',
            }}>
              <div style={{
                padding: '7px 13px', borderRadius: 10,
                background: THEMES.paper.isDark ? '#2a2724' : '#fcf8f0',
                boxShadow: '0 6px 18px rgba(0,0,0,0.18), 0 0 0 0.5px rgba(0,0,0,0.08)',
                fontSize: 11.5, color: THEMES.paper.ink, fontWeight: 500,
              }}>Tap pill → Translation settings</div>
            </div>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="E7" label="E7 · Dark — new language" width={BST_W} height={720}>
          {sheetShell('dark', <BSSettingsSheet t={THEMES.dark} selLang="Japanese" dirty="new-lang"/>)}
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={300}>
          <b>One sheet, two doors.</b> The cluster row is the discoverable
          path (sub-line doubles as a status readout: language · granularity ·
          engine). The pill is the fast path for people who already know.
          Cache badges on language tiles make the cost story visible BEFORE
          the strip says it: green tick = paid for, instant.
        </DCPostIt>
      </DCSection>

      <DCSection id="T" title="#1641 — Total reading time · in-reader"
        subtitle="Feature #101. Canonical: the trailing metrics label is a tap target cycling page ↔ time readouts; the time readout carries session AND total. Book details is the always-on home.">
        <DCArtboard id="T1" label="T1 · Reader — time readout active" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper" pill={false} bottom={false}>
            <BST_PlainPage t={THEMES.paper}/>
            <RTBottomChrome t={THEMES.paper} trailing="12m read · 6h 40m total"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="T2" label="T2 · Reader — default page readout (unchanged)" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="paper" pill={false} bottom={false}>
            <BST_PlainPage t={THEMES.paper}/>
            <RTBottomChrome t={THEMES.paper} trailing="414 pages left in book"/>
          </BST_Phone>
        </DCArtboard>
        <DCArtboard id="T3" label="T3 · Label variants & widths · true size" width={620} height={760}>
          <MetricsLineAnatomy themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="T4" label="T4 · Book details — Reading time rows" width={380} height={260}>
          <BookDetailsTimeCard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="T5" label="T5 · Dark" width={BST_W} height={BST_H}>
          <BST_Phone themeKey="dark" pill={false} bottom={false}>
            <BST_PlainPage t={THEMES.dark}/>
            <RTBottomChrome t={THEMES.dark} trailing="18m read · 41h total"/>
          </BST_Phone>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={280}>
          <b>No new chrome.</b> The slot already exists; we make it earn more.
          Tap cycles, the choice persists per book, and Book details carries
          the full breakdown for anyone who never discovers the tap. First
          session says &ldquo;first session&rdquo; instead of repeating the
          same number twice.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRootSuite });
