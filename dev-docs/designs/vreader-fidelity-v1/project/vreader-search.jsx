// Search sheet — in-book (FTS5) + library-wide

const SEARCH_RESULTS = {
  // Pride and Prejudice — sample in-book FTS results for "bingley"
  bingley: [
    { chapter: 'Chapter 1', page: 1, snippet: 'have you heard that Netherfield Park is let at last? […] Mrs. Long has just been here, and she told me all about it.' },
    { chapter: 'Chapter 1', page: 2, snippet: 'Netherfield is taken by a young man of large fortune from the north of England; that he came down on Monday in a chaise and four', match: 'Bingley' },
    { chapter: 'Chapter 3', page: 18, snippet: 'Mr. **Bingley** had soon made himself acquainted with all the principal people in the room; he was lively and unreserved, danced every dance.' },
    { chapter: 'Chapter 4', page: 27, snippet: 'When Jane and Elizabeth were alone, the former, who had been cautious in her praise of Mr. **Bingley** before, expressed to her sister' },
    { chapter: 'Chapter 6', page: 43, snippet: 'as **Bingley** had now been gone a week and nothing more was heard of his return.' },
    { chapter: 'Chapter 11', page: 92, snippet: '**Bingley** then addressed himself to Miss Bennet, and the conversation was renewed.' },
    { chapter: 'Chapter 13', page: 108, snippet: 'Mr. **Bingley** and Jane were standing together, a little detached from the rest, and talked only to each other.' },
  ],
  // Library-wide for "consciousness"
  consciousness: [
    { bookId: 'bi', chapter: 'Chapter 8: The Universal Constructor', page: 184, snippet: 'human **consciousness** is a kind of universal explainer — an entity capable of representing any explicable phenomenon.' },
    { bookId: 'bi', chapter: 'Chapter 4: Creation', page: 87, snippet: 'the appearance of **consciousness** in evolutionary history requires the same kind of universality argument' },
    { bookId: 'sap', chapter: 'Part 1: The Cognitive Revolution', page: 41, snippet: 'A startling feature of Homo sapiens **consciousness** is its capacity to hold beliefs about purely fictional realities.' },
    { bookId: 'tfs', chapter: 'Part I: Two Systems', page: 24, snippet: 'System 2 operations are often associated with the subjective experience of agency, choice, and concentration — what we typically call **consciousness**.' },
  ],
};

function SearchSheet({ theme, book, onClose, onJump }) {
  const t = theme;
  const [query, setQuery] = React.useState('');
  const [scope, setScope] = React.useState('book'); // book | library
  const inputRef = React.useRef(null);

  React.useEffect(() => {
    const id = setTimeout(() => inputRef.current?.focus(), 100);
    return () => clearTimeout(id);
  }, []);

  const results = (() => {
    if (!query) return [];
    const key = query.toLowerCase();
    if (scope === 'book') {
      // try matching keys
      for (const k in SEARCH_RESULTS) if (key.includes(k.slice(0, 4)) || k.includes(key)) return SEARCH_RESULTS[k];
      // fake "no results"
      return [];
    } else {
      for (const k in SEARCH_RESULTS) if (key.includes(k.slice(0, 4)) || k.includes(key)) return SEARCH_RESULTS[k];
      return [];
    }
  })();

  const recent = ['Mr. Darcy', 'Pemberley', 'consciousness', 'Bayesian'];
  const inBook = scope === 'book';

  return (
    <Sheet theme={t} onClose={onClose} height={720} title={null}>
      {/* Search bar */}
      <div style={{ padding: '12px 16px 8px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8,
          padding: '10px 14px', borderRadius: 12,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
        }}>
          <Icons.Search size={17} color={t.sub} stroke={1.7}/>
          <input ref={inputRef} value={query} onChange={e => setQuery(e.target.value)}
            placeholder={inBook ? `Search ${book?.title || 'this book'}` : 'Search across all books'}
            style={{
              flex: 1, border: 'none', outline: 'none', background: 'transparent',
              fontFamily: 'inherit', fontSize: 15, color: t.ink,
            }}/>
          {query && (
            <button onClick={() => setQuery('')} style={{
              background: 'none', border: 'none', padding: 2, cursor: 'pointer',
            }}>
              <Icons.Close size={14} color={t.sub} stroke={2}/>
            </button>
          )}
          <button onClick={onClose} style={{
            background: 'none', border: 'none', padding: '0 0 0 6px',
            color: t.accent, fontFamily: 'inherit', fontSize: 14, fontWeight: 500,
            cursor: 'pointer', whiteSpace: 'nowrap',
          }}>Cancel</button>
        </div>
      </div>

      {/* Scope toggle */}
      <div style={{ padding: '0 16px 4px' }}>
        <div style={{
          display: 'flex', borderRadius: 10, padding: 3,
          background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
        }}>
          {[
            { k: 'book', label: 'This book' },
            { k: 'library', label: 'All books' },
          ].map(o => (
            <button key={o.k} onClick={() => setScope(o.k)} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, border: 'none',
              background: scope === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: scope === o.k ? t.ink : t.sub,
              fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500, cursor: 'pointer',
              boxShadow: scope === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{o.label}</button>
          ))}
        </div>
      </div>

      {/* Body */}
      <div style={{ flex: 1, overflow: 'auto', padding: '8px 0 24px' }} className="hide-scroll">
        {!query && (
          <SearchEmptyState theme={t} recent={recent} onPick={setQuery}/>
        )}
        {query && results.length === 0 && (
          <NoResults theme={t} query={query}/>
        )}
        {query && results.length > 0 && (
          <SearchResultsList theme={t} results={results} query={query}
                             scope={scope} onJump={(r) => { onJump?.(r); onClose(); }}/>
        )}
      </div>
    </Sheet>
  );
}

function SearchEmptyState({ theme, recent, onPick }) {
  const t = theme;
  return (
    <div style={{ padding: '16px 18px' }}>
      <SectionLabel theme={t}>Recent</SectionLabel>
      <div style={{
        marginTop: 10, display: 'flex', flexDirection: 'column',
        gap: 2,
      }}>
        {recent.map((r, i) => (
          <button key={i} onClick={() => onPick(r)} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '10px 4px', background: 'none', border: 'none',
            cursor: 'pointer', textAlign: 'left', borderRadius: 6,
            borderBottom: i < recent.length - 1 ? `0.5px solid ${t.rule}` : 'none',
          }}>
            <Icons.Search size={14} color={t.sub} stroke={1.7}/>
            <span style={{ flex: 1, fontSize: 14, color: t.ink }}>{r}</span>
            <span style={{ fontSize: 11, color: t.sub }}>Tap to repeat</span>
          </button>
        ))}
      </div>

      <div style={{ marginTop: 28 }}>
        <SectionLabel theme={t}>Try searching</SectionLabel>
        <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginTop: 10 }}>
          {['"exact phrase"', 'darcy AND elizabeth', 'chapter:1', 'highlighted:yellow', 'note:'].map((s, i) => (
            <span key={i} style={{
              padding: '5px 10px', borderRadius: 8,
              background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: t.sub,
            }}>{s}</span>
          ))}
        </div>
        <div style={{
          marginTop: 14, fontSize: 11.5, color: t.sub, lineHeight: 1.5,
        }}>
          Full-text search uses SQLite FTS5 with CJK tokenization. Quoted phrases match exactly; lowercase boolean operators combine terms.
        </div>
      </div>
    </div>
  );
}

function NoResults({ theme, query }) {
  const t = theme;
  return (
    <div style={{
      padding: '60px 24px', textAlign: 'center',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
    }}>
      <div style={{
        width: 40, height: 40, borderRadius: 20,
        background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Search size={18} color={t.sub} stroke={1.7}/>
      </div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 16, fontWeight: 500, color: t.ink, marginTop: 4,
      }}>No matches for "{query}"</div>
      <div style={{ fontSize: 12, color: t.sub, lineHeight: 1.5, maxWidth: 240 }}>
        Try a different spelling, a partial word, or switch the scope to all books.
      </div>
    </div>
  );
}

function SearchResultsList({ theme, results, query, scope, onJump }) {
  const t = theme;
  // Group by chapter (in-book) or by book (library)
  const grouped = {};
  results.forEach(r => {
    const k = scope === 'book' ? r.chapter : (BOOKS.find(b => b.id === r.bookId)?.title || 'Unknown');
    if (!grouped[k]) grouped[k] = [];
    grouped[k].push(r);
  });

  return (
    <div style={{ padding: '0 16px' }}>
      <div style={{
        padding: '6px 4px 12px', fontSize: 12, color: t.sub,
      }}>
        {results.length} matches in {Object.keys(grouped).length} {scope === 'book' ? 'chapters' : 'books'}
      </div>
      {Object.entries(grouped).map(([groupName, rs], gi) => (
        <div key={gi} style={{ marginBottom: 18 }}>
          <div style={{
            display: 'flex', alignItems: 'baseline',
            justifyContent: 'space-between', padding: '4px 4px 8px',
          }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 13, fontWeight: 600, color: t.ink,
              letterSpacing: 0.1,
            }}>{groupName}</div>
            <div style={{ fontSize: 11, color: t.sub }}>{rs.length} match{rs.length === 1 ? '' : 'es'}</div>
          </div>
          <div style={{
            borderRadius: 12, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
          }}>
            {rs.map((r, i) => (
              <button key={i} onClick={() => onJump(r)} style={{
                display: 'flex', alignItems: 'flex-start', gap: 10,
                padding: '12px 12px', width: '100%', background: 'none', border: 'none',
                borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
                cursor: 'pointer', textAlign: 'left',
              }}>
                <div style={{
                  fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                  fontSize: 10.5, color: t.accent, fontWeight: 600,
                  width: 30, flexShrink: 0, paddingTop: 2, letterSpacing: 0.3,
                }}>p.{r.page}</div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <SnippetText snippet={r.snippet} query={query} theme={t}/>
                </div>
                <Icons.Chevron size={13} color={t.sub} stroke={2} style={{ marginTop: 4, flexShrink: 0 }}/>
              </button>
            ))}
          </div>
        </div>
      ))}
    </div>
  );
}

function SnippetText({ snippet, query, theme }) {
  const t = theme;
  // Render bolded **match** segments + highlight query term
  const parts = snippet.split(/(\*\*[^*]+\*\*)/);
  return (
    <div style={{
      fontFamily: '"Source Serif 4", Georgia, serif',
      fontSize: 13.5, lineHeight: 1.45, color: t.ink,
    }}>
      {parts.map((part, i) => {
        if (part.startsWith('**') && part.endsWith('**')) {
          return <mark key={i} style={{
            background: t.isDark ? 'rgba(214,136,90,0.3)' : 'rgba(140,47,47,0.18)',
            color: t.accent, fontWeight: 600, padding: '0 2px',
            borderRadius: 2,
          }}>{part.slice(2, -2)}</mark>;
        }
        return <span key={i}>{part}</span>;
      })}
    </div>
  );
}

Object.assign(window, { SearchSheet });
