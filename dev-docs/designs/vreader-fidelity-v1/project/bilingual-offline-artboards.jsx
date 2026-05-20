// Canvas artboards for issue #1024 — bilingual offline / translation-unavailable inline state.
//
// Sections:
//   A — Ghost placeholder (canonical). Per-paragraph ghost shell + page banner.
//   B — Inline italic copy (alternative). Per-paragraph explicit text.
//   C — Source-only collapse (rejected option, shown for comparison).
//   L — Loading state, side-by-side with offline so the distinction is concrete.
//   M — Mixed / partial cache state.
//   D — State anatomy detail — true-size, every slot variant.

const I1024_PHONE_W = 402;
const I1024_PHONE_H = 740;

// Sample source + translations (subset of vreader-data PP_PAGES, hand-paired).
const I1024_SOURCE = [
  'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
  'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.',
  '"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"',
  'Mr. Bennet replied that he had not. "But it is," returned she; "for Mrs. Long has just been here, and she told me all about it."',
];
const I1024_TR_CN = [
  '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
  '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何，见解如何，可是，既然这样的一条真理早已在人们心目中根深蒂固，因此人们总是把他看作自己某一个女儿理所应得的一笔财产。',
  '有一天，班纳特太太对她丈夫说："我的好老爷，尼日斐花园终于租出去了，你听说过没有？"',
  '班纳特先生回答道，没有听说过。"的确租出去了，"她说，"朗格太太刚刚上这儿来过，她把这件事的底细，一五一十地告诉了我。"',
];


// Reader phone shell — top chrome (with bilingual pill), the page body
// from BilingualPageContent_OfflineDemo, and a thin bottom strip with page
// indicator. Lightweight, self-contained — doesn't pull in ReaderScreen.
function I1024_Phone({ themeKey, children, height = I1024_PHONE_H, lang = 'Chinese' }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: I1024_PHONE_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <I1024_TopChrome theme={t} lang={lang}/>
      {children}
      <I1024_BottomStrip theme={t}/>
    </div>
  );
}

function I1024_TopChrome({ theme: t, lang }) {
  const glyph = lang === 'Chinese' ? '中'
              : lang === 'Japanese' ? '日'
              : lang === 'Korean' ? '한'
              : lang === 'Arabic' ? 'ع' : 'Es';
  const ff = lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean'
    ? '"Songti SC", "Source Han Serif", serif' : '"Inter", system-ui';
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
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>
          <span>Pride and Prejudice</span>
          {/* bilingual pill */}
          <span style={{
            display: 'inline-flex', alignItems: 'center', gap: 3,
            padding: '2px 7px 2px 3px', borderRadius: 100, marginLeft: 6,
            background: `${t.accent}1a`, color: t.accent,
            fontStyle: 'normal', fontFamily: '"Inter", system-ui',
            fontSize: 9.5, fontWeight: 600, verticalAlign: 'middle',
          }}>
            <span style={{
              width: 14, height: 14, borderRadius: 7, background: t.accent,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              color: '#fff', fontSize: 8, fontWeight: 700,
            }}>EN</span>
            <span style={{ opacity: 0.7, fontSize: 8 }}>↔</span>
            <span style={{ fontFamily: ff, fontWeight: 700, fontSize: 11 }}>{glyph}</span>
          </span>
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

function I1024_BottomStrip({ theme: t }) {
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0,
      height: 30, display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: '"Inter", system-ui', fontSize: 10,
      color: t.sub, opacity: 0.65, letterSpacing: 0.5,
    }}>
      <span>3 / 432</span>
    </div>
  );
}


// Build the paragraph spec for a given offline pattern.
//   pattern: 'all-offline' | 'all-cached' | 'partial' | 'all-loading' | 'mixed'
function makeParas(pattern) {
  switch (pattern) {
    case 'all-cached':  return I1024_SOURCE.map(t => ({ text: t, state: 'cached' }));
    case 'all-offline': return I1024_SOURCE.map(t => ({ text: t, state: 'offline' }));
    case 'all-loading': return I1024_SOURCE.map(t => ({ text: t, state: 'loading' }));
    case 'partial':     return [
      { text: I1024_SOURCE[0], state: 'cached' },
      { text: I1024_SOURCE[1], state: 'cached' },
      { text: I1024_SOURCE[2], state: 'offline' },
      { text: I1024_SOURCE[3], state: 'offline' },
    ];
    case 'mixed':       return [
      { text: I1024_SOURCE[0], state: 'cached' },
      { text: I1024_SOURCE[1], state: 'loading' },
      { text: I1024_SOURCE[2], state: 'offline' },
      { text: I1024_SOURCE[3], state: 'offline' },
    ];
    default: return I1024_SOURCE.map(t => ({ text: t, state: 'cached' }));
  }
}


// Approach-A artboard
function A_Ghost({ themeKey, pattern = 'all-offline', pageStatus = 'offline', lang = 'Chinese' }) {
  const t = THEMES[themeKey];
  const paras = makeParas(pattern);
  const cached = paras.filter(p => p.state === 'cached').length;
  return (
    <I1024_Phone themeKey={themeKey} lang={lang}>
      <BilingualPageContent_OfflineDemo
        theme={t} lang={lang}
        fontSize={16} margin={22}
        paragraphs={paras}
        translations={lang === 'Chinese' ? I1024_TR_CN : undefined}
        approach="A"
        pageStatus={pageStatus}
        cachedCount={cached} totalCount={paras.length}
        chapter="Chapter 1"/>
    </I1024_Phone>
  );
}

// Approach-B artboard
function B_InlineCopy({ themeKey, pattern = 'all-offline', pageStatus = 'none' }) {
  const t = THEMES[themeKey];
  const paras = makeParas(pattern);
  return (
    <I1024_Phone themeKey={themeKey}>
      <BilingualPageContent_OfflineDemo
        theme={t} lang="Chinese"
        fontSize={16} margin={22}
        paragraphs={paras}
        translations={I1024_TR_CN}
        approach="B"
        pageStatus={pageStatus}
        chapter="Chapter 1"/>
    </I1024_Phone>
  );
}

// Approach-C artboard (rejected option — source-only collapse + banner only)
function C_Collapse({ themeKey, pattern = 'all-offline', pageStatus = 'offline' }) {
  const t = THEMES[themeKey];
  const paras = makeParas(pattern);
  return (
    <I1024_Phone themeKey={themeKey}>
      <BilingualPageContent_OfflineDemo
        theme={t} lang="Chinese"
        fontSize={16} margin={22}
        paragraphs={paras}
        translations={I1024_TR_CN}
        approach="C"
        pageStatus={pageStatus}
        chapter="Chapter 1"/>
    </I1024_Phone>
  );
}

// Side-by-side detail card. True-size slot variants stacked, so the
// reviewer can see the rhythm difference at-a-glance.
function StateAnatomy({ themeKey }) {
  const t = THEMES[themeKey];
  const fontSize = 16;
  const SourcePara = ({ children }) => (
    <p style={{
      margin: 0,
      fontFamily: '"Source Serif 4", Georgia, serif',
      fontSize, lineHeight: 1.55, color: t.ink, textAlign: 'justify',
    }}>{children}</p>
  );
  const rows = [
    { key: 'cached',  label: 'Cached translation (baseline)',
      note: 'Source paragraph followed by translation block with left-accent border. Every other state inherits this shell.',
      slot: <BilingualCachedSlot theme={t} fontSize={fontSize} text={I1024_TR_CN[0]}/> },
    { key: 'loading', label: 'Loading · in flight',
      note: 'Shimmer bars in the same shell. Animation distinguishes it from offline — users learn the difference after seeing both once.',
      slot: <BilingualLoadingSlot theme={t} fontSize={fontSize}/> },
    { key: 'ghost-first', label: 'A · Ghost — first on page (with glyph)',
      note: 'Dim border + cloud-off glyph + dashed bar. The glyph appears once per page so the user has a visual anchor without repetition.',
      slot: <BilingualGhostSlot theme={t} fontSize={fontSize} withGlyph/> },
    { key: 'ghost-bare', label: 'A · Ghost — subsequent (bare)',
      note: 'No glyph. The accent border (dimmed to 33% alpha) is enough to maintain the rhythm.',
      slot: <BilingualGhostSlot theme={t} fontSize={fontSize}/> },
    { key: 'inline',  label: 'B · Inline italic copy',
      note: 'One italic muted line per paragraph. More explicit; noisier when 8+ paragraphs are offline on one page.',
      slot: <BilingualInlineCopySlot theme={t} fontSize={fontSize}/> },
    { key: 'collapse', label: 'C · Source-only collapse',
      note: 'Translation slot omitted entirely. Cleanest visually — but page looks identical to non-bilingual mode, which reads as "feature failed" right after toggling on.',
      slot: null },
  ];
  return (
    <div style={{
      width: 760, padding: '24px 28px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column', gap: 18,
    }}>
      {rows.map((r, i) => (
        <div key={r.key} style={{
          display: 'flex', alignItems: 'flex-start', gap: 22,
          paddingBottom: 18,
          borderBottom: i === rows.length - 1 ? 'none' : `0.5px dashed ${t.rule}`,
        }}>
          <div style={{ width: 220, flexShrink: 0 }}>
            <div style={{
              fontSize: 11, color: t.sub, letterSpacing: 0.6,
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 6,
            }}>{r.key}</div>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500, marginBottom: 6, lineHeight: 1.3 }}>{r.label}</div>
            <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.5 }}>{r.note}</div>
          </div>
          <div style={{ flex: 1, padding: '0 8px' }}>
            <SourcePara>{I1024_SOURCE[0]}</SourcePara>
            {r.slot}
          </div>
        </div>
      ))}
    </div>
  );
}

// Banner-only zoomed comparison.
function BannerDetail({ themeKey }) {
  const t = THEMES[themeKey];
  const rows = [
    { status: 'offline', label: 'Offline · uncached', note: 'Default state during an offline reading session. Sub-color tray; no CTA — there\u2019s nothing the user can do until they reconnect.' },
    { status: 'partial', label: 'Partial cache', note: 'When some paragraphs are cached but others aren\u2019t. Banner counts the ratio so the user understands gaps below are expected.' },
    { status: 'online',  label: 'Back online · retry', note: 'Reachability has returned; explicit Retry CTA. Accent-tinted tray so it reads as actionable, not informational.' },
  ];
  return (
    <div style={{
      width: 520, padding: '22px 24px', background: t.bg,
      borderRadius: 12, border: `0.5px solid ${t.rule}`,
      display: 'flex', flexDirection: 'column', gap: 14,
    }}>
      {rows.map(r => (
        <div key={r.status}>
          <div style={{
            fontSize: 11, color: t.sub, letterSpacing: 0.6,
            textTransform: 'uppercase', fontWeight: 600, marginBottom: 8,
          }}>{r.label}</div>
          <BilingualPageBanner theme={t} status={r.status}
            cached={3} total={9} onRetry={() => {}}/>
          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.5, marginTop: 4 }}>{r.note}</div>
        </div>
      ))}
    </div>
  );
}


function CanvasRoot1024() {
  return (
    <DesignCanvas>
      <DCSection id="intro" title="Bilingual offline · inline state · #1024"
        subtitle="Inline within the paragraph-interlinear flow. Preserves the source/translation rhythm. Distinct from loading. Three approaches across themes + the partial / loading / online-retry states.">
        <DCPostIt top={-30} right={40} rotate={-2} width={300}>
          <b>Pick A (Ghost).</b> The shell-preserving placeholder + one
          page-level banner is the right weight: the user understands once
          (banner), then sees the missing-slot rhythm continue without
          eight repetitions of the same copy.
        </DCPostIt>
      </DCSection>

      <DCSection id="A" title="A — Ghost placeholder (canonical)"
        subtitle="Same shell as the cached translation; content is a dim dashed bar. Page banner explains once. Glyph appears on the FIRST ghost only, as a visual anchor.">
        <DCArtboard id="A1-offline" label="A1 · All offline + banner" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="all-offline" pageStatus="offline"/>
        </DCArtboard>
        <DCArtboard id="A2-online-retry" label="A2 · Back online + retry CTA" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="all-offline" pageStatus="online"/>
        </DCArtboard>
        <DCArtboard id="A3-no-banner" label="A3 · No banner — ghost-only" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="all-offline" pageStatus="none"/>
        </DCArtboard>
        <DCArtboard id="A4-dark" label="A4 · Dark theme" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="dark" pattern="all-offline" pageStatus="offline"/>
        </DCArtboard>
        <DCArtboard id="A5-sepia-jp" label="A5 · Sepia + Japanese" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="sepia" pattern="all-offline" pageStatus="offline" lang="Japanese"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={260}>
          The accent border dims to 33% alpha on ghost slots — same vocabulary
          as the cached state, but visibly lower-stakes. The page banner is
          the SINGLE place that carries copy; per-paragraph repetition is the
          thing this approach exists to avoid.
        </DCPostIt>
      </DCSection>

      <DCSection id="B" title="B — Inline italic copy (alternative)"
        subtitle="Per-paragraph italic muted text inside the translation slot. More explicit; redundant when many paragraphs are offline.">
        <DCArtboard id="B1-paper" label="B1 · All offline · paper" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <B_InlineCopy themeKey="paper" pattern="all-offline"/>
        </DCArtboard>
        <DCArtboard id="B2-with-banner" label="B2 · Inline copy + banner (belt + braces)" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <B_InlineCopy themeKey="paper" pattern="all-offline" pageStatus="offline"/>
        </DCArtboard>
        <DCArtboard id="B3-dark" label="B3 · Dark" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <B_InlineCopy themeKey="dark" pattern="all-offline"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="C" title="C — Source-only collapse (rejected, for comparison)"
        subtitle="Translation slot omitted entirely. Visually cleanest but the page looks identical to non-bilingual mode — reads as &ldquo;feature failed&rdquo; right after the user toggles bilingual on.">
        <DCArtboard id="C1-banner-only" label="C1 · Banner-only · source unchanged" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <C_Collapse themeKey="paper" pattern="all-offline" pageStatus="offline"/>
        </DCArtboard>
        <DCArtboard id="C2-no-banner" label="C2 · No banner (silent — current shipped)" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <C_Collapse themeKey="paper" pattern="all-offline" pageStatus="none"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={240}>
          C2 is what ships today (silent fallback per the issue). The whole
          point of #1024 is that this state needs a visible affordance.
        </DCPostIt>
      </DCSection>

      <DCSection id="L-loading" title="L — Loading state — distinct from offline"
        subtitle="Shimmer bars in the same shell. Side-by-side so the difference (animated vs static, full bars vs dashed line) is unmistakable.">
        <DCArtboard id="L1-loading-all" label="L1 · All loading" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="all-loading" pageStatus="none"/>
        </DCArtboard>
        <DCArtboard id="L2-mixed" label="L2 · Mixed — cached + loading + offline" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="mixed" pageStatus="partial"/>
        </DCArtboard>
        <DCArtboard id="L3-dark" label="L3 · Mixed · dark" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="dark" pattern="mixed" pageStatus="partial"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="M-partial" title="M — Partial / mixed cache"
        subtitle="When SOME paragraphs are cached and others aren&rsquo;t. Cached slots render normally; uncached use the ghost. Banner counts the ratio.">
        <DCArtboard id="M1-partial" label="M1 · 2 of 4 cached" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="paper" pattern="partial" pageStatus="partial"/>
        </DCArtboard>
        <DCArtboard id="M2-partial-dark" label="M2 · Partial · dark" width={I1024_PHONE_W} height={I1024_PHONE_H}>
          <A_Ghost themeKey="dark" pattern="partial" pageStatus="partial"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="D-detail" title="D — Slot anatomy · true size"
        subtitle="All six slot variants stacked over the same source paragraph so rhythm + weight are directly comparable.">
        <DCArtboard id="D1-paper" label="States · paper" width={760} height={920}>
          <StateAnatomy themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="D2-dark" label="States · dark" width={760} height={920}>
          <StateAnatomy themeKey="dark"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="D-banner" title="D — Banner variants · true size"
        subtitle="The three banner states zoomed.">
        <DCArtboard id="DB1-paper" label="Banners · paper" width={520} height={420}>
          <BannerDetail themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="DB2-dark" label="Banners · dark" width={520} height={420}>
          <BannerDetail themeKey="dark"/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot1024 });
