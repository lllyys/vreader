// Issue #1799 / Feature #110 (Android Phase-3) — OPDS catalog UI.
//
// The OPDS backend (feed parser + HTTP client + acquisition→import) ships
// design-free; the browse/add/download UI was design-gated (rule 51). Built in
// VReader's vocabulary, reusing the AI-provider / backup form primitives (UI,
// Card, Row, GroupHeader/Footer, PhoneFrame, AppSheet) so catalogs feel like
// one system with the rest of Settings.
//
// Surfaces:
//   A. Source list — saved catalogs with a live status dot; empty onboards.
//   B. Add / edit a source — Name · URL · optional auth; test inline.
//   C. Browse a feed — navigation rows (folders) + acquisition entries
//      (cover/title/author/format + download). loading / empty / downloading.
//   D. Errors — offline / 401 auth / 404 not-found, each one cause + one CTA.

const OP_SERIF = '"Source Serif 4", Georgia, serif';
const OP_SANS = "'Inter', -apple-system, system-ui, sans-serif";

const OP_SOURCES = [
  { name: 'Standard Ebooks', host: 'standardebooks.org/opds', status: 'ok' },
  { name: 'Project Gutenberg', host: 'm.gutenberg.org/ebooks', status: 'ok' },
  { name: 'Home Calibre server', host: '192.168.1.20:8080/opds', status: 'auth' },
];

const OP_ENTRIES = [
  { t: 'Middlemarch', a: 'George Eliot', bg: '#3a4a5c', size: '2.1 MB', state: 'get' },
  { t: 'The Picture of Dorian Gray', a: 'Oscar Wilde', bg: '#5c2f3a', size: '1.4 MB', state: 'downloading' },
  { t: 'Walden', a: 'Henry David Thoreau', bg: '#2f4630', size: '1.1 MB', state: 'library' },
  { t: 'Frankenstein', a: 'Mary Shelley', bg: '#3a3550', size: '1.3 MB', state: 'get' },
];

// pushed-screen frame with a nav bar (back + title + trailing)
function OpdsScreen({ ui, title, sub, trailing, back = true, height = 880, children }) {
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg, display: 'flex', flexDirection: 'column' }}>
        <div style={{ height: 30 }} />
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '6px 14px 12px', borderBottom: `0.5px solid ${ui.sep}` }}>
          {back && <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>}
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: OP_SERIF, fontSize: 18, fontWeight: 600, color: ui.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</div>
            {sub && <div style={{ fontFamily: OP_SANS, fontSize: 11.5, color: ui.sec, marginTop: 1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{sub}</div>}
          </div>
          {trailing}
        </div>
        <div className="hide-scroll" style={{ flex: 1, overflow: 'auto' }}>{children}</div>
      </div>
    </PhoneFrame>
  );
}

function StatusDot({ ui, status }) {
  const map = { ok: ui.green, auth: '#caa23a', off: ui.red };
  return <span style={{ width: 8, height: 8, borderRadius: 4, background: map[status] || ui.ter, flexShrink: 0 }} />;
}

// ── A · source list ──────────────────────────────────────────
function OpdsSourceList({ ui, empty, height = 880 }) {
  return (
    <OpdsScreen ui={ui} title="Catalogs" back={false}
      trailing={<window.Icons.Plus size={24} color={ui.tint} />} height={height}>
      <div style={{ padding: '14px 16px 32px' }}>
        {empty ? (
          <>
            <div style={{ textAlign: 'center', padding: '40px 26px 8px' }}>
              <div style={{ width: 62, height: 62, borderRadius: 31, background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
                <window.Icons.Globe size={30} color={ui.ter} />
              </div>
              <div style={{ fontFamily: OP_SERIF, fontSize: 20, color: ui.ink, marginBottom: 8 }}>Add a catalog</div>
              <div style={{ fontFamily: OP_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.5 }}>
                Browse and download books from any OPDS catalog — public libraries or your own Calibre server.
              </div>
            </div>
            <GroupHeader ui={ui}>Try one of these</GroupHeader>
            <Card ui={ui}>
              {['Standard Ebooks', 'Project Gutenberg', 'Feedbooks'].map((n, i) => (
                <div key={n} style={{ display: 'flex', alignItems: 'center', minHeight: 50, padding: '0 14px', position: 'relative' }}>
                  <window.Icons.Globe size={19} color={ui.tint} />
                  <span style={{ flex: 1, fontFamily: OP_SANS, fontSize: 15, color: ui.ink, marginLeft: 11 }}>{n}</span>
                  <window.Icons.Plus size={19} color={ui.tint} />
                  {i < 2 && <div style={{ position: 'absolute', left: 44, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
                </div>
              ))}
            </Card>
          </>
        ) : (
          <>
            <GroupHeader ui={ui}>Your catalogs</GroupHeader>
            <Card ui={ui}>
              {OP_SOURCES.map((s, i) => (
                <div key={s.name} style={{ display: 'flex', alignItems: 'center', minHeight: 58, padding: '0 14px', position: 'relative' }}>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontFamily: OP_SANS, fontSize: 15.5, fontWeight: 500, color: ui.ink }}>{s.name}</div>
                    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 3 }}>
                      <StatusDot ui={ui} status={s.status} />
                      <span style={{ fontFamily: window.MONO, fontSize: 11.5, color: s.status === 'auth' ? ui.red : ui.sec }}>
                        {s.status === 'auth' ? '401 — sign-in required' : s.host}
                      </span>
                    </div>
                  </div>
                  <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />
                  {i < OP_SOURCES.length - 1 && <div style={{ position: 'absolute', left: 14, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
                </div>
              ))}
            </Card>
            <GroupFooter ui={ui}>Tap a catalog to browse it. The status dot reflects the last connection.</GroupFooter>
          </>
        )}
      </div>
    </OpdsScreen>
  );
}

// ── B · add / edit source ────────────────────────────────────
function OpdsAddSheet({ ui, mode = 'add', auth = false, test = 'idle', height = 880 }) {
  const testResult = test === 'ok' || test === 'fail';
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title={mode === 'edit' ? 'Edit Catalog' : 'Add Catalog'}
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: OP_SANS, fontSize: 15, color: ui.sec }}>Cancel</button>}
        trailing={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: OP_SANS, fontSize: 15, fontWeight: 600, color: ui.tint }}>Save</button>}
        height={height - 36}>
        <div style={{ padding: '16px 18px 32px' }}>
          <GroupHeader ui={ui}>Catalog</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} label="Name"><ValueText ui={ui} text={mode === 'edit' ? 'Home Calibre server' : 'Standard Ebooks'} /></Row>
            <Row ui={ui} label="URL" last><ValueText ui={ui} text={mode === 'edit' ? 'http://192.168.1.20:8080/opds' : 'https://standardebooks.org/opds'} /></Row>
          </Card>
          <GroupFooter ui={ui}>Paste the catalog's OPDS feed URL. VReader follows navigation links from there.</GroupFooter>

          <div style={{ height: 18 }} />
          <GroupHeader ui={ui}>Authentication</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} label="Requires sign-in" last={!auth}>
              <div style={{ width: 46, height: 28, borderRadius: 14, background: auth ? ui.tint : ui.sep, position: 'relative', transition: 'background .15s' }}>
                <div style={{ position: 'absolute', top: 2, left: auth ? 20 : 2, width: 24, height: 24, borderRadius: 12, background: '#fff', boxShadow: '0 1px 3px rgba(0,0,0,0.25)', transition: 'left .15s' }} />
              </div>
            </Row>
            {auth && <>
              <Row ui={ui} label="Username"><ValueText ui={ui} text="reader" /></Row>
              <Row ui={ui} label="Password" last><span style={{ fontFamily: OP_SANS, fontSize: 16, letterSpacing: 2, color: ui.ink }}>{'•'.repeat(10)}</span></Row>
            </>}
          </Card>

          <div style={{ height: 18 }} />
          <GroupHeader ui={ui}>Connection</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} last={!testResult}>
              <div style={{ display: 'flex', width: '100%', justifyContent: 'flex-start' }}>
                <span style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontFamily: OP_SANS, fontSize: 14, fontWeight: 600, color: ui.tint, background: ui.chipBg, borderRadius: 100, padding: '8px 15px' }}>
                  {test === 'testing'
                    ? <svg className="apf-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
                    : <window.Icons.Globe size={14} color={ui.tint} />}
                  {test === 'testing' ? 'Testing…' : 'Test Connection'}
                </span>
              </div>
            </Row>
            {testResult && (
              <Row ui={ui} last>
                <div style={{ display: 'flex', alignItems: 'center', gap: 7, width: '100%', justifyContent: 'flex-start' }}>
                  {test === 'ok'
                    ? <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill={ui.green}/><path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>
                    : <svg width="16" height="16" viewBox="0 0 24 24" fill="none"><circle cx="12" cy="12" r="10" fill={ui.red}/><path d="M8 8l8 8M16 8l-8 8" stroke="#fff" strokeWidth="2" strokeLinecap="round"/></svg>}
                  <span style={{ fontFamily: OP_SANS, fontSize: 13.5, color: test === 'ok' ? ui.green : ui.red }}>
                    {test === 'ok' ? 'Connected — found 3 navigation links.' : 'Failed: 401 Unauthorized — check sign-in.'}
                  </span>
                </div>
              </Row>
            )}
          </Card>
          {mode === 'edit' && (
            <>
              <div style={{ height: 18 }} />
              <Card ui={ui}>
                <Row ui={ui} last><span style={{ fontFamily: OP_SANS, fontSize: 15, color: ui.red }}>Remove Catalog</span></Row>
              </Card>
            </>
          )}
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

// ── C · browse a feed ────────────────────────────────────────
function MiniCover({ bg, w = 52 }) {
  return <div style={{ width: w, height: Math.round(w * 1.5), borderRadius: 5, background: bg, flexShrink: 0, boxShadow: '0 1px 4px rgba(0,0,0,0.2), inset 2px 0 0 rgba(255,255,255,0.14)' }} />;
}

function AcquisitionEntry({ ui, e, last }) {
  return (
    <div style={{ display: 'flex', gap: 13, padding: '13px 16px', position: 'relative', alignItems: 'center' }}>
      <MiniCover bg={e.bg} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: OP_SERIF, fontSize: 15.5, fontWeight: 600, color: ui.ink, lineHeight: 1.25 }}>{e.t}</div>
        <div style={{ fontFamily: OP_SANS, fontSize: 12.5, color: ui.sec, marginTop: 2 }}>{e.a}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 8 }}>
          <span style={{ fontFamily: OP_SANS, fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4, color: ui.sec, background: ui.codeBg, borderRadius: 5, padding: '2px 6px' }}>EPUB</span>
          {e.state === 'get' && <span style={{ fontFamily: OP_SANS, fontSize: 11.5, color: ui.ter }}>{e.size}</span>}
        </div>
      </div>
      <div style={{ flexShrink: 0 }}>
        {e.state === 'get' && (
          <button style={{ display: 'inline-flex', alignItems: 'center', gap: 6, border: 'none', cursor: 'pointer', background: ui.chipBg, color: ui.tint, borderRadius: 100, padding: '8px 14px', fontFamily: OP_SANS, fontSize: 13, fontWeight: 600 }}>
            <window.Icons.Download size={15} color={ui.tint} /> Get
          </button>
        )}
        {e.state === 'downloading' && (
          <div style={{ width: 64, textAlign: 'center' }}>
            <svg width="34" height="34" viewBox="0 0 36 36" style={{ transform: 'rotate(-90deg)' }}>
              <circle cx="18" cy="18" r="15" fill="none" stroke={ui.sep} strokeWidth="3"/>
              <circle cx="18" cy="18" r="15" fill="none" stroke={ui.tint} strokeWidth="3" strokeLinecap="round" strokeDasharray={`${0.48 * 94} 94`}/>
            </svg>
            <div style={{ fontFamily: OP_SANS, fontSize: 10.5, color: ui.sec, marginTop: 1, fontVariantNumeric: 'tabular-nums' }}>48%</div>
          </div>
        )}
        {e.state === 'library' && (
          <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: OP_SANS, fontSize: 12.5, fontWeight: 600, color: ui.green }}>
            <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={ui.green} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5L20 7"/></svg>
            In Library
          </span>
        )}
      </div>
      {!last && <div style={{ position: 'absolute', left: 81, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />}
    </div>
  );
}

function OpdsBrowse({ ui, state = 'feed', height = 880 }) {
  return (
    <OpdsScreen ui={ui} title="Standard Ebooks" sub="standardebooks.org/opds" height={height}
      trailing={<window.Icons.Search size={20} color={ui.tint} />}>
      {state === 'loading' && (
        <div style={{ padding: '8px 0' }}>
          {[0, 1, 2, 3].map((i) => (
            <div key={i} style={{ display: 'flex', gap: 13, padding: '13px 16px', alignItems: 'center' }}>
              <div style={{ width: 52, height: 78, borderRadius: 5, background: ui.sep, opacity: 0.6 }} />
              <div style={{ flex: 1 }}>
                <div style={{ height: 13, width: '70%', borderRadius: 4, background: ui.sep, opacity: 0.6 }} />
                <div style={{ height: 11, width: '40%', borderRadius: 4, background: ui.sep, opacity: 0.4, marginTop: 8 }} />
              </div>
            </div>
          ))}
          <div style={{ textAlign: 'center', padding: '14px', fontFamily: OP_SANS, fontSize: 13, color: ui.sec }}>Loading feed…</div>
        </div>
      )}

      {state === 'empty' && (
        <div style={{ textAlign: 'center', padding: '80px 30px' }}>
          <div style={{ width: 60, height: 60, borderRadius: 30, background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(29,26,20,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
            <window.Icons.Folder size={28} color={ui.ter} />
          </div>
          <div style={{ fontFamily: OP_SERIF, fontSize: 19, color: ui.ink, marginBottom: 8 }}>This shelf is empty</div>
          <div style={{ fontFamily: OP_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.5 }}>The catalog returned no entries for this feed. Try another section.</div>
        </div>
      )}

      {(state === 'feed' || state === 'downloading') && (
        <>
          {/* navigation feed */}
          <div style={{ padding: '8px 0 2px' }}>
            {[['Newest releases', '50'], ['By author', '1,074'], ['Subjects', '38']].map(([n, c], i) => (
              <div key={n} style={{ display: 'flex', alignItems: 'center', minHeight: 50, padding: '0 16px', position: 'relative' }}>
                <window.Icons.Folder size={19} color={ui.tint} />
                <span style={{ flex: 1, fontFamily: OP_SANS, fontSize: 15, color: ui.ink, marginLeft: 11 }}>{n}</span>
                <span style={{ fontFamily: OP_SANS, fontSize: 12.5, color: ui.ter, marginRight: 8, fontVariantNumeric: 'tabular-nums' }}>{c}</span>
                <window.Icons.ChevronD size={18} color={ui.ter} style={{ transform: 'rotate(-90deg)' }} />
                <div style={{ position: 'absolute', left: 46, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />
              </div>
            ))}
          </div>
          {/* acquisition feed */}
          <div style={{ padding: '12px 16px 4px' }}>
            <GroupHeader ui={ui}>Newest releases</GroupHeader>
          </div>
          <div>
            {OP_ENTRIES.map((e, i) => <AcquisitionEntry key={i} ui={ui} e={e} last={i === OP_ENTRIES.length - 1} />)}
          </div>
        </>
      )}

      {(state === 'offline' || state === 'auth' || state === 'notfound') && (
        <OpdsError ui={ui} kind={state} />
      )}
    </OpdsScreen>
  );
}

function OpdsError({ ui, kind }) {
  const map = {
    offline: { icon: 'Wifi', title: 'You’re offline', body: 'VReader can’t reach this catalog. Check your connection and try again.', cta: 'Retry' },
    auth: { icon: 'Globe', title: '401 — sign-in required', body: 'This catalog needs a username and password. Add them to the source to browse it.', cta: 'Edit sign-in' },
    notfound: { icon: 'Alert', title: '404 — feed not found', body: 'The catalog URL didn’t return a feed. Double-check the OPDS address.', cta: 'Edit URL' },
  };
  const e = map[kind];
  const I = window.Icons[e.icon];
  return (
    <div style={{ textAlign: 'center', padding: '74px 30px' }}>
      <div style={{ width: 62, height: 62, borderRadius: 31, background: ui.isDark ? 'rgba(224,119,90,0.14)' : 'rgba(168,64,47,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center', margin: '0 auto 18px' }}>
        <I size={30} color={ui.red} />
      </div>
      <div style={{ fontFamily: OP_SERIF, fontSize: 19, color: ui.ink, marginBottom: 8 }}>{e.title}</div>
      <div style={{ fontFamily: OP_SANS, fontSize: 14, color: ui.sec, lineHeight: 1.5, marginBottom: 20 }}>{e.body}</div>
      <button style={{ border: 'none', cursor: 'pointer', background: ui.tint, color: '#fff', borderRadius: 11, padding: '11px 22px', fontFamily: OP_SANS, fontSize: 14.5, fontWeight: 600 }}>{e.cta}</button>
    </div>
  );
}

Object.assign(window, {
  OP_SOURCES, OP_ENTRIES, OpdsScreen, OpdsSourceList, OpdsAddSheet, OpdsBrowse, OpdsError, AcquisitionEntry,
});
