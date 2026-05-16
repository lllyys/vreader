// Main app shell — routes between Library and Reader, owns top-level state

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "themeOverride": "auto",
  "selectedBookId": "pp",
  "fileState": "default",
  "detailsLayout": "stacked",
  "annotationsTab": "all",
  "bilingualLang": "Chinese",
  "aiUnavailable": false
}/*EDITMODE-END*/;

function App() {
  const [route, setRoute] = React.useState('library'); // library | reader
  const [activeBook, setActiveBook] = React.useState(null);
  const [readerSettings, setReaderSettings] = React.useState({
    theme: 'paper',
    fontFamily: 'serif',
    fontSize: 17,
    lineHeight: 1.55,
    margin: 26,
    brightness: 1,
  });
  const [pageIdx, setPageIdx] = React.useState(0);
  const [highlights, setHighlights] = React.useState(SAMPLE_HIGHLIGHTS.map(h => ({
    ...h, pageIdx: h.id === 'h1' ? 0 : h.id === 'h4' ? 0 : -1,
    paraIdx: h.id === 'h1' ? 0 : h.id === 'h4' ? 7 : -1,
  })));

  // Modal/sheet state
  const [openSheet, setOpenSheet] = React.useState(null); // null | 'toc' | 'highlights' | 'reader-settings' | 'settings' | 'ai' | 'book-details' | 'bilingual-setup'
  const [aiMode, setAIMode] = React.useState('summary');
  const [aiContext, setAIContext] = React.useState(null);
  const [tocInitialTab, setTocInitialTab] = React.useState('contents');
  const [hlInitialFilter, setHlInitialFilter] = React.useState('all');

  // Bilingual state — when bilingual is on, the reader renders interlinear translations.
  const [bilingualOn, setBilingualOn] = React.useState(false);
  const [bilingualConfig, setBilingualConfig] = React.useState({ lang: 'Chinese', granularity: 'paragraph' });
  const [bilingualSetupSeen, setBilingualSetupSeen] = React.useState(false);

  // Tweaks — exposed via the toolbar's Tweaks toggle.
  const [tw, setTweak] = useTweaks(TWEAK_DEFAULTS);

  const themeKey = tw.themeOverride && tw.themeOverride !== 'auto' ? tw.themeOverride : readerSettings.theme;
  const theme = THEMES[themeKey] || THEMES.paper;

  // Resolve which book the reader is using based on tweaks (file-state simulation).
  const baseBook = (BOOKS.find(b => b.id === tw.selectedBookId) || BOOKS[0]);
  const fakeBook = React.useMemo(() => {
    if (tw.fileState === 'longTitle') return {
      ...baseBook,
      title: 'The Strange Case of the Astonishingly Long Title and Its Even Longer Subtitle About Everything',
      author: 'Aurelius Theophilus Hartwell-Worthington III, with foreword by Cornelius P. Featherstonehaugh',
    };
    if (tw.fileState === 'missingCover') return { ...baseBook, cover: { ...baseBook.cover, _missing: true } };
    if (tw.fileState === 'remoteOnly')   return { ...baseBook, _remoteOnly: true };
    return baseBook;
  }, [baseBook, tw.fileState]);

  const openBook = (book) => {
    setActiveBook(book);
    setPageIdx(0);
    setRoute('reader');
  };

  const handleMoreAction = (action) => {
    if (action === 'details')        setOpenSheet('book-details');
    else if (action === 'configure-ai') setOpenSheet('settings');
  };

  const toggleBilingual = () => {
    if (!bilingualOn && !bilingualSetupSeen) {
      setOpenSheet('bilingual-setup');
    } else {
      setBilingualOn(b => !b);
    }
  };

  const closeBook = () => {
    setRoute('library');
  };

  const openAI = (mode, context = null) => {
    const m = typeof mode === 'string' ? mode : 'summary';
    setAIMode(m);
    setAIContext(typeof context === 'string' ? context : null);
    setOpenSheet('ai');
  };

  const addHighlight = ({ text, color, paraIdx, pageIdx }) => {
    setHighlights(hs => [...hs, {
      id: `h${Date.now()}`, text, color, paraIdx, pageIdx,
      chapter: 'Chapter 1', page: activeBook.currentPage + pageIdx,
      note: '', date: 'Just now',
    }]);
  };

  const updateHighlight = (id, patch) => {
    setHighlights(hs => hs.map(h => h.id === id ? { ...h, ...patch } : h));
  };

  const deleteHighlight = (id) => {
    setHighlights(hs => hs.filter(h => h.id !== id));
  };

  const statusBarDark = route === 'reader' && theme.isDark;

  return (
    <div style={{
      position: 'absolute', inset: 0, overflow: 'hidden',
      background: route === 'reader' ? theme.bg : '#f7f4ee',
    }}>
      {/* Status bar (rendered above everything, reacts to theme) */}
      <div style={{ position: 'absolute', top: 0, left: 0, right: 0, zIndex: 500, pointerEvents: 'none' }}>
        <IOSStatusBar dark={statusBarDark}/>
      </div>

      {/* Routes — kept mounted so state persists; current one visible */}
      <div style={{
        position: 'absolute', inset: 0,
        visibility: route === 'library' ? 'visible' : 'hidden',
      }}>
        <LibraryScreen
          onOpenBook={openBook}
          onOpenSettings={() => setOpenSheet('settings')}
        />
      </div>

      {route === 'reader' && activeBook && (
        <ReaderScreen
          book={fakeBook && activeBook.id === fakeBook.id ? fakeBook : activeBook}
          theme={theme}
          fontFamily={readerSettings.fontFamily}
          fontSize={readerSettings.fontSize}
          lineHeight={readerSettings.lineHeight}
          margin={readerSettings.margin}
          brightness={readerSettings.brightness}
          pageIdx={pageIdx}
          onPageChange={setPageIdx}
          highlights={highlights}
          onAddHighlight={addHighlight}
          onUpdateHighlight={updateHighlight}
          onDeleteHighlight={deleteHighlight}
          onClose={closeBook}
          onOpenAI={openAI}
          onOpenTOC={() => { setTocInitialTab('contents'); setOpenSheet('toc'); }}
          onOpenHighlights={() => { setHlInitialFilter(tw.annotationsTab || 'all'); setOpenSheet('highlights'); }}
          onOpenSettings={() => setOpenSheet('settings')}
          onOpenReaderSettings={() => setOpenSheet('reader-settings')}
          onOpenSearch={() => setOpenSheet('search')}
          onMoreAction={handleMoreAction}
          onToggleBilingual={toggleBilingual}
          bilingualOn={bilingualOn}
          bilingualLang={bilingualConfig.lang}
          aiUnavailable={tw.aiUnavailable}
        />
      )}

      {/* Sheets */}
      {openSheet === 'reader-settings' && (
        <ReaderSettingsSheet
          theme={theme}
          settings={readerSettings}
          onChange={setReaderSettings}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'toc' && (
        <TOCSheetV2
          theme={theme}
          book={activeBook || fakeBook}
          currentCh={pageIdx < 3 ? 1 : 2}
          tab={tocInitialTab}
          onJump={(c) => { setPageIdx(c.ch === 1 ? 0 : 3); }}
          onOpenSearch={() => setOpenSheet('search')}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'highlights' && (
        <HighlightsSheetV2
          theme={theme}
          highlights={highlights.length ? highlights : SAMPLE_HIGHLIGHTS}
          filter={hlInitialFilter}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'book-details' && (
        <BookDetailsSheet
          theme={theme}
          book={fakeBook}
          layout={tw.detailsLayout}
          state={tw.fileState}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'bilingual-setup' && (
        <BilingualSetupSheet
          theme={theme}
          value={bilingualConfig}
          onChange={setBilingualConfig}
          onClose={() => {
            setBilingualSetupSeen(true);
            setBilingualOn(true);
            setOpenSheet(null);
          }}
          aiConfigured={!tw.aiUnavailable}
        />
      )}
      {openSheet === 'ai' && (
        <AISheet
          theme={theme}
          mode={aiMode}
          context={aiContext}
          book={activeBook}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'settings' && (
        <SettingsSheet
          theme={route === 'reader' ? theme : THEMES.paper}
          onClose={() => setOpenSheet(null)}
          onOpenStats={() => setOpenSheet('stats')}
        />
      )}
      {openSheet === 'search' && (
        <SearchSheet
          theme={route === 'reader' ? theme : THEMES.paper}
          book={activeBook}
          onClose={() => setOpenSheet(null)}
          onJump={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'stats' && (
        <StatsSheet
          theme={route === 'reader' ? theme : THEMES.paper}
          onClose={() => setOpenSheet(null)}
        />
      )}

      {/* Tweaks panel (toolbar toggle wakes it) */}
      <AppTweaksPanel tw={tw} setTweak={setTweak}
        onOpenBookDetails={() => setOpenSheet('book-details')}
        onOpenBilingualSetup={() => setOpenSheet('bilingual-setup')}
      />
    </div>
  );
}

Object.assign(window, { App });
