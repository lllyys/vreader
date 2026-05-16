// Canvas — every state of every surface for Feature #60 follow-ups.
// Sections: Book Details (#789) · Bilingual (#790) · Annotations split (#793).

const BOOK_DEFAULT = BOOKS.find(b => b.id === 'pp');
const BOOK_REMOTE  = { ...BOOKS.find(b => b.id === '3b') };
const BOOK_NO_COVER = BOOKS.find(b => b.id === 'sg');

// ────────────────────────────────────────────────────
// Sheet artboard — renders a single sheet over a faded reader page background
// at a fixed phone-width (402) so each surface reads as a finished screen.
// ────────────────────────────────────────────────────
function SheetFrame({ themeKey = 'paper', height = 720, children, dim = true, page = true }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      {page && <FakeReaderPage t={t}/>}
      {dim && <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.35)' }}/>}
      {children}
    </div>
  );
}

function PhoneTopFrame({ themeKey = 'paper', height = 460, children }) {
  // Smaller frame for popover/menu artboards — shows just the top chrome region.
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      <FakeReaderPage t={t}/>
      <FakeTopChrome t={t}/>
      {children}
    </div>
  );
}

function FakeReaderPage({ t }) {
  // A muted, blurred-looking version of the reader content so the sheet pops.
  const ink = t.ink;
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '70px 26px 60px', opacity: 0.55 }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11,
        color: t.sub, letterSpacing: 2, textTransform: 'uppercase',
        textAlign: 'center', marginBottom: 16,
      }}>Chapter 1</div>
      {[
        'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
        'However little known the feelings or views of such a man may be on his first entering a neighbourhood…',
        'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
      ].map((p, i) => (
        <p key={i} style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, lineHeight: 1.55, color: ink,
          margin: '0 0 12px', textIndent: i === 0 ? 0 : 18,
          textAlign: 'justify',
        }}>{p}</p>
      ))}
    </div>
  );
}

function FakeTopChrome({ t, popoverOpen }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 90,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
      display: 'flex', alignItems: 'flex-end', padding: '0 14px 12px',
      justifyContent: 'space-between',
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 4,
        color: t.accent, fontSize: 15, fontWeight: 500,
      }}>
        <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library
      </div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14, fontStyle: 'italic', fontWeight: 600, color: t.ink,
      }}>Pride and Prejudice</div>
      <div style={{ display: 'flex', gap: 0 }}>
        <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icons.Search size={18} color={t.ink} stroke={1.7}/>
        </div>
        <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icons.Bookmark size={18} color={t.ink} stroke={1.7}/>
        </div>
        <div style={{
          width: 36, height: 36, borderRadius: 18, display: 'flex',
          alignItems: 'center', justifyContent: 'center',
          background: popoverOpen ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : 'transparent',
        }}>
          <Icons.More size={20} color={t.ink} stroke={1.7}/>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Bilingual reader artboard — paragraph-interlinear preview, full phone surface
// ────────────────────────────────────────────────────
function BilingualReaderFrame({ themeKey = 'paper', lang = 'Chinese' }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 402, height: 720, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      {/* fake top chrome */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0,
        background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
        padding: '38px 14px 12px',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 4,
          color: t.accent, fontSize: 15, fontWeight: 500,
        }}><Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library</div>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, fontStyle: 'italic', fontWeight: 600, color: t.ink,
          display: 'inline-flex', alignItems: 'center',
        }}>
          Pride and Prejudice
          <BilingualPill theme={t} lang={lang}/>
        </div>
        <div style={{ display: 'flex' }}>
          <Icons.Search size={18} color={t.ink} stroke={1.7} style={{ margin: 9 }}/>
          <Icons.More size={20} color={t.ink} stroke={1.7} style={{ margin: 8 }}/>
        </div>
      </div>
      <BilingualPageContent
        page={PP_PAGES[0]} theme={t} fontFamily="serif"
        fontSize={16} lineHeight={1.55} margin={26}
        pageDir={0} animating={false} pageIdx={0} lang={lang}
      />
      {/* fake footer */}
      <div style={{
        position: 'absolute', bottom: 14, left: 26, right: 26,
        display: 'flex', justifyContent: 'space-between',
        fontSize: 11, color: t.sub,
      }}>
        <span>34%</span><span>147 / 432</span>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// More-menu row state artboard (#790)
// ────────────────────────────────────────────────────
function MoreRowArtboard({ themeKey = 'paper', state }) {
  const t = THEMES[themeKey];
  const moreState = state === 'off'
    ? { autoTurn: false, bilingual: false, bilingualLang: 'Chinese', ttsPlaying: false, aiUnavailable: false }
    : state === 'on'
    ? { autoTurn: false, bilingual: true, bilingualLang: 'Chinese', ttsPlaying: false, aiUnavailable: false }
    : { autoTurn: false, bilingual: false, bilingualLang: 'Chinese', ttsPlaying: false, aiUnavailable: true };

  return (
    <PhoneTopFrame themeKey={themeKey} height={460}>
      <MorePopover theme={t} state={moreState}
        onToggle={() => {}} onAction={() => {}} onClose={() => {}}/>
    </PhoneTopFrame>
  );
}

// ────────────────────────────────────────────────────
// Section helpers — small label/title
// ────────────────────────────────────────────────────

function CanvasRoot() {
  return (
    <DesignCanvas style={{ background: '#0f0d0c' }}>
      {/* ─── BOOK DETAILS (#789) ─── */}
      <DCSection id="bd-themes" title="① Book Details · canonical layout across themes"
        subtitle="Cover-on-top stacked layout. Default state. The canonical surface for the More-menu 'Book details' destination.">
        {['paper','sepia','dark','oled','image'].map(k => (
          <DCArtboard key={k} id={`bd-default-${k}`} label={`Default · ${THEMES[k].name}`} width={402} height={720}>
            <SheetFrame themeKey={k}>
              <BookDetailsSheet theme={THEMES[k]} book={BOOK_DEFAULT} layout="stacked" state="default" onClose={() => {}}/>
            </SheetFrame>
          </DCArtboard>
        ))}
      </DCSection>

      <DCSection id="bd-states" title="② Book Details · four required states"
        subtitle="Per #789 — default · long title/author · missing cover · remote-only. Paper theme.">
        {[
          { k: 'default',      label: 'Default',      book: BOOK_DEFAULT },
          { k: 'longTitle',    label: 'Long title',   book: BOOK_DEFAULT },
          { k: 'missingCover', label: 'Missing cover', book: BOOK_NO_COVER },
          { k: 'remoteOnly',   label: 'Remote-only',  book: BOOK_REMOTE },
        ].map(s => (
          <DCArtboard key={s.k} id={`bd-state-${s.k}`} label={s.label} width={402} height={720}>
            <SheetFrame themeKey="paper">
              <BookDetailsSheet theme={THEMES.paper} book={s.book} layout="stacked" state={s.k} onClose={() => {}}/>
            </SheetFrame>
          </DCArtboard>
        ))}
      </DCSection>

      <DCSection id="bd-alt" title="③ Book Details · alternate compact layout"
        subtitle="Cover-left, metadata-right. Shipping as a Tweak for review, not canon. Dark + Paper to show theme range.">
        {['paper','dark'].map(k => (
          <DCArtboard key={k} id={`bd-split-${k}`} label={`Compact · ${THEMES[k].name}`} width={402} height={660}>
            <SheetFrame themeKey={k} height={660}>
              <BookDetailsSheet theme={THEMES[k]} book={BOOK_DEFAULT} layout="split" state="default" onClose={() => {}}/>
            </SheetFrame>
          </DCArtboard>
        ))}
      </DCSection>

      {/* ─── BILINGUAL (#790) ─── */}
      <DCSection id="bi-reader" title="④ Bilingual mode · the backing feature"
        subtitle="Paragraph-interlinear rendering. Source paragraph followed by translation in muted style. The reader's top-chrome shows an EN↔target pill.">
        <DCArtboard id="bi-reader-paper-zh" label="Paper · Chinese" width={402} height={720}>
          <BilingualReaderFrame themeKey="paper" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="bi-reader-dark-zh" label="Dark · Chinese" width={402} height={720}>
          <BilingualReaderFrame themeKey="dark" lang="Chinese"/>
        </DCArtboard>
        <DCArtboard id="bi-reader-sepia-es" label="Sepia · Spanish" width={402} height={720}>
          <BilingualReaderFrame themeKey="sepia" lang="Spanish"/>
        </DCArtboard>
        <DCArtboard id="bi-reader-oled-ja" label="OLED · Japanese" width={402} height={720}>
          <BilingualReaderFrame themeKey="oled" lang="Japanese"/>
        </DCArtboard>
        <DCArtboard id="bi-reader-photo-ar" label="Photo · Arabic" width={402} height={720}>
          <BilingualReaderFrame themeKey="image" lang="Arabic"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="bi-setup" title="⑤ Bilingual mode · setup sheet"
        subtitle="Shown the first time the toggle flips on. Subsequent toggles flip immediately; sub-detail row 'Tap to change' returns here.">
        {['paper','sepia','dark'].map(k => (
          <DCArtboard key={k} id={`bi-setup-${k}`} label={`Setup · ${THEMES[k].name}`} width={402} height={720}>
            <SheetFrame themeKey={k}>
              <BilingualSetupSheet theme={THEMES[k]}
                value={{ lang: 'Chinese', granularity: 'paragraph' }}
                onChange={() => {}} onClose={() => {}} aiConfigured/>
            </SheetFrame>
          </DCArtboard>
        ))}
        <DCArtboard id="bi-setup-no-ai" label="Setup · AI not configured" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <BilingualSetupSheet theme={THEMES.paper}
              value={{ lang: 'Chinese', granularity: 'paragraph' }}
              onChange={() => {}} onClose={() => {}} aiConfigured={false}/>
          </SheetFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="bi-row" title="⑥ Bilingual · More-menu row · 3 states"
        subtitle="Row 3 of the More popover. Off / On (with active sub-detail) / Unavailable (when no AI provider configured).">
        {[
          { k: 'off',  label: 'Off · default' },
          { k: 'on',   label: 'On · English ↔ Chinese' },
          { k: 'unavailable', label: 'Unavailable · no AI provider' },
        ].map(s => (
          <DCArtboard key={s.k} id={`bi-row-${s.k}`} label={s.label} width={402} height={460}>
            <MoreRowArtboard themeKey="paper" state={s.k}/>
          </DCArtboard>
        ))}
        <DCArtboard id="bi-row-dark-on" label="On · Dark" width={402} height={460}>
          <MoreRowArtboard themeKey="dark" state="on"/>
        </DCArtboard>
      </DCSection>

      {/* ─── ANNOTATIONS SPLIT (#793) ─── */}
      <DCSection id="ann-toc" title="⑦ TOCSheet · Contents + Bookmarks"
        subtitle="Decision: split. TOCSheet is the navigation surface — opened from the Contents button. Title is the book name.">
        <DCArtboard id="toc-contents-filled" label="Contents · filled" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <TOCSheetV2 theme={THEMES.paper} book={BOOK_DEFAULT} currentCh={1} tab="contents" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="toc-contents-empty" label="Contents · empty (rare, no-TOC EPUB)" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <TOCSheetV2 theme={THEMES.paper} book={BOOK_DEFAULT} currentCh={1} tab="contents" toc={[]} onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="toc-bookmarks-filled" label="Bookmarks · filled" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <TOCSheetV2 theme={THEMES.paper} book={BOOK_DEFAULT} currentCh={1} tab="bookmarks" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="toc-bookmarks-empty" label="Bookmarks · empty" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <TOCSheetV2 theme={THEMES.paper} book={BOOK_DEFAULT} currentCh={1} tab="bookmarks" bookmarks={[]} onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="ann-toc-themes" title="⑧ TOCSheet · theme range">
        {['sepia','dark','oled','image'].map(k => (
          <DCArtboard key={k} id={`toc-theme-${k}`} label={`Contents · ${THEMES[k].name}`} width={402} height={720}>
            <SheetFrame themeKey={k}>
              <TOCSheetV2 theme={THEMES[k]} book={BOOK_DEFAULT} currentCh={1} tab="contents" onClose={() => {}}/>
            </SheetFrame>
          </DCArtboard>
        ))}
      </DCSection>

      <DCSection id="ann-hl" title="⑨ HighlightsSheet · All / Highlights / Notes / Bookmarks"
        subtitle="The review surface — opened from the Notes button. Title is 'Annotations'. Trailing share button.">
        <DCArtboard id="hl-all-filled" label="All · filled" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <HighlightsSheetV2 theme={THEMES.paper} highlights={SAMPLE_HIGHLIGHTS} filter="all" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="hl-notes-filled" label="Notes filter · only items with notes" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <HighlightsSheetV2 theme={THEMES.paper} highlights={SAMPLE_HIGHLIGHTS} filter="notes" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="hl-all-empty" label="All · empty (new book)" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <HighlightsSheetV2 theme={THEMES.paper} highlights={[]} filter="all" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
        <DCArtboard id="hl-bookmarks-empty" label="Bookmarks filter · empty (in-sheet)" width={402} height={720}>
          <SheetFrame themeKey="paper">
            <HighlightsSheetV2 theme={THEMES.paper} highlights={SAMPLE_HIGHLIGHTS} filter="bookmarks" onClose={() => {}}/>
          </SheetFrame>
        </DCArtboard>
      </DCSection>

      <DCSection id="ann-hl-themes" title="⑩ HighlightsSheet · theme range">
        {['sepia','dark','oled','image'].map(k => (
          <DCArtboard key={k} id={`hl-theme-${k}`} label={`Annotations · ${THEMES[k].name}`} width={402} height={720}>
            <SheetFrame themeKey={k}>
              <HighlightsSheetV2 theme={THEMES[k]} highlights={SAMPLE_HIGHLIGHTS} filter="all" onClose={() => {}}/>
            </SheetFrame>
          </DCArtboard>
        ))}
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot });
