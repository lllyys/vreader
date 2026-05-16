// Main app shell — routes between Library and Reader, owns top-level state

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
  const [openSheet, setOpenSheet] = React.useState(null); // null | 'toc' | 'highlights' | 'reader-settings' | 'settings' | 'ai'
  const [aiMode, setAIMode] = React.useState('summary');
  const [aiContext, setAIContext] = React.useState(null);

  const theme = THEMES[readerSettings.theme];

  const openBook = (book) => {
    setActiveBook(book);
    setPageIdx(0);
    setRoute('reader');
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
          book={activeBook}
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
          onOpenTOC={() => setOpenSheet('toc')}
          onOpenHighlights={() => setOpenSheet('highlights')}
          onOpenSettings={() => setOpenSheet('settings')}
          onOpenReaderSettings={() => setOpenSheet('reader-settings')}
          onOpenSearch={() => setOpenSheet('search')}
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
        <TOCSheet
          theme={theme}
          currentCh={pageIdx < 3 ? 1 : 2}
          onJump={(c) => { setPageIdx(c.ch === 1 ? 0 : 3); }}
          onClose={() => setOpenSheet(null)}
        />
      )}
      {openSheet === 'highlights' && (
        <HighlightsSheet
          theme={theme}
          highlights={highlights.length ? highlights : SAMPLE_HIGHLIGHTS}
          onClose={() => setOpenSheet(null)}
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
    </div>
  );
}

Object.assign(window, { App });
