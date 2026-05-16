// Book Details sheet — feature #60 follow-up (#789)
//
// Two layouts: "stacked" (cover-on-top, canonical) and "split" (cover-left, dense alternate).
// Four states: default, long-title, missing-cover, remote-only.
// Cover-swap affordance: inline pencil overlay on the cover, plus a row in Actions.

function BookDetailsSheet({ theme, book, layout = 'stacked', state = 'default', onClose }) {
  const t = theme;
  // synthesize the variant-specific book + flags
  const remote = state === 'remoteOnly';
  const missingCover = state === 'missingCover';
  const longTitle = state === 'longTitle';

  const displayBook = longTitle ? {
    ...book,
    title: 'The Strange Case of the Astonishingly Long Title and Its Even Longer Subtitle About Everything',
    author: 'Aurelius Theophilus Hartwell-Worthington III, with foreword by Cornelius P. Featherstonehaugh',
  } : book;

  const fingerprint = `${(displayBook.format || 'epub').toLowerCase()}:8a4f2e91b7c3d56f9e1a4b2c…2c1b`;
  const location = remote ? null : `Documents/Books/${displayBook.format}/${displayBook.title.slice(0, 22)}…`;
  const size = remote ? '—' : displayBook.size;

  return (
    <Sheet theme={t} onClose={onClose} height={layout === 'split' ? 580 : 660} title="Book details"
      trailing={
        <button style={iconBtnSheet(t)} aria-label="Share">
          <Icons.Share size={18} color={t.ink} stroke={1.7}/>
        </button>
      }>
      {layout === 'stacked'
        ? <DetailsStacked t={t} book={displayBook} remote={remote} missingCover={missingCover}
            fingerprint={fingerprint} location={location} size={size}/>
        : <DetailsSplit t={t} book={displayBook} remote={remote} missingCover={missingCover}
            fingerprint={fingerprint} location={location} size={size}/>}
    </Sheet>
  );
}

function DetailsStacked({ t, book, remote, missingCover, fingerprint, location, size }) {
  return (
    <div style={{ padding: '20px 22px 32px' }}>
      <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 16 }}>
        <CoverWithSwap t={t} book={book} missingCover={missingCover} width={120} height={180}/>
        <div style={{ textAlign: 'center', width: '100%' }}>
          {remote && <RemoteChip t={t}/>}
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 22, fontStyle: 'italic', fontWeight: 600,
            color: t.ink, lineHeight: 1.1, textWrap: 'pretty',
            margin: '6px 0 6px',
          }}>{book.title}</div>
          <div style={{
            fontFamily: '"Inter", system-ui', fontSize: 13,
            color: t.sub, lineHeight: 1.35,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
          }}>{book.author} · {book.year}</div>
        </div>
        {book.tags && (
          <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', justifyContent: 'center' }}>
            {book.tags.map(tag => <Tag key={tag} t={t}>{tag}</Tag>)}
          </div>
        )}
      </div>

      <MetaList t={t} book={book} fingerprint={fingerprint} location={location} size={size} remote={remote}/>
      <ActionList t={t} missingCover={missingCover}/>
    </div>
  );
}

function DetailsSplit({ t, book, remote, missingCover, fingerprint, location, size }) {
  return (
    <div style={{ padding: '18px 20px 30px' }}>
      <div style={{ display: 'flex', gap: 16, alignItems: 'flex-start' }}>
        <CoverWithSwap t={t} book={book} missingCover={missingCover} width={92} height={138}/>
        <div style={{ flex: 1, minWidth: 0 }}>
          {remote && <RemoteChip t={t}/>}
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 18, fontStyle: 'italic', fontWeight: 600,
            color: t.ink, lineHeight: 1.15, textWrap: 'pretty', marginBottom: 4,
          }}>{book.title}</div>
          <div style={{
            fontFamily: '"Inter", system-ui', fontSize: 12.5,
            color: t.sub, lineHeight: 1.35, marginBottom: 10,
            display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
            overflow: 'hidden',
          }}>{book.author} · {book.year}</div>
          {book.tags && (
            <div style={{ display: 'flex', gap: 5, flexWrap: 'wrap' }}>
              {book.tags.slice(0, 3).map(tag => <Tag key={tag} t={t} small>{tag}</Tag>)}
            </div>
          )}
        </div>
      </div>
      <MetaList t={t} book={book} fingerprint={fingerprint} location={location} size={size} remote={remote}/>
      <ActionList t={t} missingCover={missingCover}/>
    </div>
  );
}

function CoverWithSwap({ t, book, missingCover, width, height }) {
  return (
    <div style={{ position: 'relative', width, height, flexShrink: 0 }}>
      {missingCover ? (
        <div style={{
          width, height, borderRadius: 4,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
          border: `1.5px dashed ${t.accent}66`,
          display: 'flex', flexDirection: 'column', alignItems: 'center',
          justifyContent: 'center', gap: 6,
        }}>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: width * 0.45, fontStyle: 'italic', fontWeight: 600,
            color: t.accent, opacity: 0.7, lineHeight: 1, marginBottom: 2,
          }}>V</div>
          <div style={{
            fontFamily: '"Inter", system-ui', fontSize: 10,
            color: t.sub, letterSpacing: 0.5, textAlign: 'center', padding: '0 8px',
          }}>Tap to add cover</div>
        </div>
      ) : (
        <BookCover book={book} width={width} height={height} radius={4}/>
      )}
      {/* pencil overlay */}
      <button aria-label="Replace cover" style={{
        position: 'absolute', bottom: 6, right: 6,
        width: 28, height: 28, borderRadius: 14, border: 'none', cursor: 'pointer',
        background: t.accent, boxShadow: '0 2px 8px rgba(0,0,0,0.25), 0 0 0 1.5px rgba(255,255,255,0.6)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        padding: 0,
      }}>
        <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
          <path d="M14 4l6 6-11 11H3v-6z" stroke="#fff" strokeWidth="1.8" strokeLinejoin="round" fill="none"/>
        </svg>
      </button>
    </div>
  );
}

function MetaList({ t, book, fingerprint, location, size, remote }) {
  const rows = [
    { label: 'Format', value: book.format, mono: true },
    { label: 'Size',   value: size, mono: true, muted: remote },
    { label: 'Pages',  value: `${book.pages}`, mono: true },
    { label: 'Fingerprint', value: fingerprint, mono: true, action: 'copy' },
    remote
      ? { label: 'Location', value: 'Not downloaded', muted: true, action: 'download' }
      : { label: 'Location', value: location, mono: true, action: 'reveal' },
  ];
  return (
    <div style={{ marginTop: 22 }}>
      <SectionLabel theme={t}>Metadata</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        {rows.map((r, i) => (
          <div key={r.label} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '11px 14px',
            borderBottom: i === rows.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
          }}>
            <div style={{
              width: 96, fontSize: 12, color: t.sub, flexShrink: 0,
              fontFamily: '"Inter", system-ui', fontWeight: 500,
            }}>{r.label}</div>
            <div style={{
              flex: 1, minWidth: 0,
              fontSize: 13.5, color: r.muted ? t.sub : t.ink,
              fontFamily: r.mono ? '"SF Mono", Menlo, monospace' : 'inherit',
              fontStyle: r.muted ? 'italic' : 'normal',
              overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
            }}>{r.value}</div>
            {r.action === 'copy' && (
              <button style={miniBtn(t)} aria-label="Copy fingerprint">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
                  <rect x="8" y="4" width="12" height="14" rx="2" stroke={t.sub} strokeWidth="1.6"/>
                  <path d="M4 8v10a2 2 0 002 2h10" stroke={t.sub} strokeWidth="1.6"/>
                </svg>
              </button>
            )}
            {r.action === 'reveal' && (
              <button style={miniBtn(t)} aria-label="Reveal in Files">
                <svg width="13" height="13" viewBox="0 0 24 24" fill="none">
                  <path d="M7 17L17 7M9 7h8v8" stroke={t.sub} strokeWidth="1.8" strokeLinecap="round"/>
                </svg>
              </button>
            )}
            {r.action === 'download' && (
              <button style={{
                padding: '5px 10px', borderRadius: 100, border: 'none',
                background: t.accent, color: '#fff',
                fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 4,
              }}>
                <Icons.Download size={11} color="#fff" stroke={2}/>
                Download
              </button>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

function ActionList({ t, missingCover }) {
  const actions = [
    { icon: Icons.Translate, label: missingCover ? 'Add cover…' : 'Replace cover…' },
    { icon: Icons.Share,    label: 'Share book…' },
    { icon: Icons.Download, label: 'Export annotations…', sub: 'Markdown · JSON · VReader JSON' },
  ];
  // First action is Cover; swap icon to a pencil
  actions[0].icon = (p) => (
    <svg width={p.size} height={p.size} viewBox="0 0 24 24" fill="none">
      <path d="M14 4l6 6-11 11H3v-6z" stroke={p.color} strokeWidth={p.stroke || 1.7} strokeLinejoin="round"/>
    </svg>
  );

  return (
    <div style={{ marginTop: 22 }}>
      <SectionLabel theme={t}>Actions</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        {actions.map((a, i) => {
          const Ico = a.icon;
          return (
            <button key={a.label} style={{
              display: 'flex', alignItems: 'center', gap: 12, width: '100%',
              padding: '12px 14px', border: 'none', background: 'transparent',
              borderBottom: i === actions.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
              cursor: 'pointer', textAlign: 'left',
            }}>
              <div style={{
                width: 28, height: 28, borderRadius: 8,
                background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                flexShrink: 0,
              }}>
                <Ico size={14} color={t.ink} stroke={1.7}/>
              </div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14.5, color: t.ink, fontWeight: 500, lineHeight: 1.2 }}>{a.label}</div>
                {a.sub && <div style={{ fontSize: 11, color: t.sub, marginTop: 2 }}>{a.sub}</div>}
              </div>
              <Icons.Chevron size={13} color={t.sub} stroke={2}/>
            </button>
          );
        })}
      </div>
    </div>
  );
}

function RemoteChip({ t }) {
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '3px 8px', borderRadius: 100, marginBottom: 4,
      background: `${t.accent}1a`, color: t.accent,
      fontFamily: '"Inter", system-ui', fontSize: 10.5, fontWeight: 600,
      letterSpacing: 0.5, textTransform: 'uppercase',
    }}>
      <Icons.Cloud size={10} color={t.accent} stroke={2}/>
      Remote
    </div>
  );
}

function Tag({ t, small, children }) {
  return (
    <span style={{
      padding: small ? '2px 8px' : '3px 10px',
      borderRadius: 100,
      background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
      color: t.ink, fontSize: small ? 10 : 11, fontWeight: 500,
      fontFamily: '"Inter", system-ui',
    }}>{children}</span>
  );
}

function miniBtn(t) {
  return {
    width: 26, height: 26, borderRadius: 8, padding: 0,
    background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
    border: 'none', cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
    flexShrink: 0,
  };
}

function iconBtnSheet(t) {
  return {
    background: 'rgba(0,0,0,0.06)', border: 'none',
    width: 28, height: 28, borderRadius: 14, padding: 0, cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  };
}

Object.assign(window, { BookDetailsSheet });
