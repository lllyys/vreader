// Android backup & WebDAV restore UI — issue #1767 (feature #110).
//
// iOS has a full subsystem (Views/Settings/WebDAV*, Views/Backup,
// BackupViewModel). Android needs the equivalent USER-FACING surfaces.
// The backend (backup-format model, WebDAV client, restore pipeline) is
// implemented + emulator-verified separately and is NOT design-gated.
//
// Three surfaces, every state (idle / loading / empty / error / in-progress
// / success / partial), rendered in VReader's own vocabulary — the paper /
// dark tokens, Source-Serif titles, #8c2f2f accent, rounded-14 cards and
// SectionLabel rows shared with the AI-provider editor. Primitives (UI, Card,
// Row, GroupHeader, GroupFooter, Tag, Sep, PhoneFrame, AppSheet, APP_FONT,
// SERIF, MONO) are reused from vreader-ai-provider-fields.jsx.
//
//   1. NavScreen / TopBar     — pushed settings screen scaffold
//   2. Toggle, StatusDot, ConnBadge, AppAlert — shared bits
//   3. WebDAVServerList       — saved servers (empty / populated / error)
//   4. ServerEditSheet        — add / edit a server (+ test-connection states)
//   5. BackupRestoreScreen    — back-up-now + available-backups list (states)
//   6. RestoreProgress        — in-progress + success / partial / failed
//   7. SelectiveRestoreSheet  — per-book restore picker w/ lazy download

// ── shared bits ─────────────────────────────────────────────
function Toggle({ ui, on }) {
  return (
    <div style={{
      width: 44, height: 27, borderRadius: 14, flexShrink: 0,
      background: on ? ui.tint : (ui.isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.16)'),
      position: 'relative', transition: 'background .18s',
    }}>
      <div style={{
        position: 'absolute', top: 2.5, left: on ? 20 : 2.5,
        width: 22, height: 22, borderRadius: 11, background: '#fff',
        boxShadow: '0 1px 3px rgba(0,0,0,0.3)', transition: 'left .18s',
      }}/>
    </div>
  );
}

function StatusDot({ color, pulse }) {
  return <span style={{
    width: 8, height: 8, borderRadius: 4, background: color, flexShrink: 0,
    boxShadow: pulse ? `0 0 0 3px ${color}33` : 'none',
  }}/>;
}

// Top app bar — back chevron + serif title, optional trailing action.
function TopBar({ ui, title, trailing, large = false }) {
  return (
    <div style={{
      position: 'relative', zIndex: 10, background: ui.bg,
      paddingTop: 38, borderBottom: large ? 'none' : `0.5px solid ${ui.sep}`,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', padding: '6px 8px 10px', minHeight: 44 }}>
        <button style={{
          display: 'flex', alignItems: 'center', gap: 1, padding: '6px 6px',
          background: 'none', border: 'none', cursor: 'pointer', color: ui.tint,
          fontFamily: APP_FONT, fontSize: 15, fontWeight: 500,
        }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M15 6l-6 6 6 6"/></svg>
          <span>Settings</span>
        </button>
        <div style={{ flex: 1 }}/>
        {trailing}
      </div>
      {large && (
        <div style={{ padding: '0 20px 14px' }}>
          <div style={{ fontFamily: SERIF, fontSize: 28, fontWeight: 700, color: ui.ink, letterSpacing: -0.4 }}>{title}</div>
        </div>
      )}
      {!large && (
        <div style={{
          position: 'absolute', top: 38, left: 0, right: 0, height: 50,
          display: 'flex', alignItems: 'center', justifyContent: 'center', pointerEvents: 'none',
        }}>
          <span style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: ui.ink }}>{title}</span>
        </div>
      )}
    </div>
  );
}

function NavScreen({ ui, title, trailing, large, height = 880, children }) {
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column', background: ui.bg }}>
        <TopBar ui={ui} title={title} trailing={trailing} large={large}/>
        <div className="hide-scroll" style={{ flex: 1, overflow: 'auto' }}>{children}</div>
      </div>
    </PhoneFrame>
  );
}

// centered iOS-style alert
function AppAlert({ ui, title, children, buttons }) {
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 300, background: 'rgba(0,0,0,0.4)', display: 'flex', alignItems: 'center', justifyContent: 'center', padding: 28 }}>
      <div style={{
        width: '100%', maxWidth: 300, background: ui.isDark ? '#2a2724' : '#fbf7ef',
        borderRadius: 18, overflow: 'hidden', boxShadow: '0 18px 50px rgba(0,0,0,0.4)',
      }}>
        <div style={{ padding: '20px 20px 16px', textAlign: 'center' }}>
          <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 700, color: ui.ink, marginBottom: 8 }}>{title}</div>
          <div style={{ fontFamily: APP_FONT, fontSize: 13, color: ui.sec, lineHeight: 1.5 }}>{children}</div>
        </div>
        <div style={{ display: 'flex', borderTop: `0.5px solid ${ui.sep}` }}>
          {buttons.map((b, i) => (
            <React.Fragment key={i}>
              {i > 0 && <div style={{ width: 0.5, background: ui.sep }}/>}
              <div style={{
                flex: 1, textAlign: 'center', padding: '13px 8px',
                fontFamily: APP_FONT, fontSize: 15.5,
                fontWeight: b.bold ? 700 : 500,
                color: b.danger ? ui.red : ui.tint,
              }}>{b.label}</div>
            </React.Fragment>
          ))}
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// 3. WebDAVServerList
// ════════════════════════════════════════════════════
const SERVERS = [
  { id: 'nas', name: 'Home NAS', url: 'nas.local/dav/vreader', user: 'leon', status: 'ok', detail: 'Connected · last sync 9:14 AM', wifiOnly: true },
  { id: 'fm', name: 'Fastmail Files', url: 'myfiles.fastmail.com/dav', user: 'leon@fastmail.com', status: 'error', detail: '401 — authentication failed', wifiOnly: false },
];

function ServerRow({ ui, server, last }) {
  const color = server.status === 'ok' ? ui.green : server.status === 'error' ? ui.red : ui.sec;
  return (
    <div style={{ display: 'flex', alignItems: 'center', minHeight: 64, padding: '10px 14px', position: 'relative' }}>
      <div style={{
        width: 38, height: 38, borderRadius: 10, flexShrink: 0, marginRight: 12,
        background: ui.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={ui.sec} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>
        </svg>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: APP_FONT, fontSize: 15.5, fontWeight: 600, color: ui.ink, marginBottom: 3 }}>{server.name}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
          <StatusDot color={color}/>
          <span style={{ fontFamily: APP_FONT, fontSize: 12, color: server.status === 'error' ? ui.red : ui.sec, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{server.detail}</span>
        </div>
      </div>
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={ui.ter} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0 }}><path d="M9 6l6 6-6 6"/></svg>
      {!last && <div style={{ position: 'absolute', left: 64, right: 0, bottom: 0, height: 0.5, background: ui.sep }}/>}
    </div>
  );
}

function WebDAVServerList({ ui, empty = false, height = 880 }) {
  const addBtn = (
    <button style={{ background: 'none', border: 'none', padding: '6px 6px', cursor: 'pointer', color: ui.tint, display: 'flex', alignItems: 'center' }}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>
    </button>
  );
  return (
    <NavScreen ui={ui} title="WebDAV Servers" trailing={addBtn} large height={height}>
      <div style={{ padding: '4px 18px 32px' }}>
        {empty ? (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '64px 24px 0' }}>
            <div style={{
              width: 72, height: 72, borderRadius: 36, marginBottom: 20,
              background: ui.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
                <rect x="3" y="4" width="18" height="7" rx="1.5"/><rect x="3" y="13" width="18" height="7" rx="1.5"/><path d="M7 7.5h.01M7 16.5h.01"/>
              </svg>
            </div>
            <div style={{ fontFamily: SERIF, fontSize: 19, fontWeight: 600, color: ui.ink, marginBottom: 8, lineHeight: 1.25 }}>No servers yet</div>
            <div style={{ fontFamily: APP_FONT, fontSize: 13.5, color: ui.sec, lineHeight: 1.55, maxWidth: 280, marginBottom: 22 }}>
              Add a WebDAV server to back up your library and sync reading progress across devices. Works with Nextcloud, Fastmail, Synology, and any standard WebDAV host.
            </div>
            <button style={{
              height: 46, padding: '0 22px', borderRadius: 100, border: 'none',
              background: ui.tint, color: '#fff', fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, cursor: 'pointer',
              display: 'inline-flex', alignItems: 'center', gap: 7,
            }}>
              <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>
              Add Server
            </button>
          </div>
        ) : (
          <>
            <GroupHeader ui={ui}>Saved Servers</GroupHeader>
            <Card ui={ui}>
              {SERVERS.map((s, i) => <ServerRow key={s.id} ui={ui} server={s} last={i === SERVERS.length - 1}/>)}
            </Card>
            <GroupFooter ui={ui}>Tap a server to edit its details or test the connection. The active server is used for automatic backups.</GroupFooter>

            <div style={{ height: 22 }}/>
            <Card ui={ui}>
              <div style={{ display: 'flex', alignItems: 'center', minHeight: 50, padding: '0 14px', color: ui.tint, fontFamily: APP_FONT, fontSize: 15, fontWeight: 500, gap: 8 }}>
                <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round"><path d="M12 5v14M5 12h14"/></svg>
                Add Server
              </div>
            </Card>
          </>
        )}
      </div>
    </NavScreen>
  );
}

// ════════════════════════════════════════════════════
// 4. ServerEditSheet — add / edit. test: idle|testing|ok|fail
// ════════════════════════════════════════════════════
function FieldRow({ ui, label, value, placeholder, mono, last, focused, secure }) {
  const empty = !value;
  return (
    <Row ui={ui} label={label} last={last} focused={focused}>
      <span style={{
        fontFamily: mono ? MONO : APP_FONT, fontSize: mono ? 13.5 : 15,
        color: empty ? ui.placeholder : ui.ink,
        whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
        letterSpacing: secure ? 2 : 0,
      }}>{empty ? placeholder : value}</span>
    </Row>
  );
}

function ServerEditSheet({ ui, mode = 'add', test = 'idle', height = 880 }) {
  const editMode = mode === 'edit';
  const name = editMode ? 'Home NAS' : '';
  const url = editMode ? 'https://nas.local/dav/vreader' : '';
  const user = editMode ? 'leon' : '';
  const pass = editMode ? '••••••••••' : '';
  const testResult = test === 'ok' || test === 'fail';
  const canTest = editMode || true;

  const Cancel = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 15, color: ui.sec, cursor: 'pointer' }}>Cancel</button>;
  const Save = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, color: editMode ? ui.tint : ui.ter, cursor: 'pointer' }}>Save</button>;

  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }}/>
      <AppSheet ui={ui} title={editMode ? 'Edit Server' : 'Add Server'} leading={Cancel} trailing={Save} height={height - 36}>
        <div style={{ padding: '16px 18px 32px' }}>
          <GroupHeader ui={ui}>Server</GroupHeader>
          <Card ui={ui}>
            <FieldRow ui={ui} label="Name" value={name} placeholder="Home NAS"/>
            <FieldRow ui={ui} label="Base URL" value={url} placeholder="https://host/dav" mono focused={!editMode}/>
            <FieldRow ui={ui} label="Username" value={user} placeholder="Required" last/>
          </Card>
          <GroupFooter ui={ui}>The full WebDAV collection URL — the app stores backups in a <Code ui={ui}>/vreader</Code> folder there.</GroupFooter>

          <div style={{ height: 20 }}/>
          <GroupHeader ui={ui}>Authentication</GroupHeader>
          <Card ui={ui}>
            <FieldRow ui={ui} label="Password" value={pass} placeholder="Required" secure last/>
          </Card>
          <GroupFooter ui={ui}>Stored in the Android Keystore. Use an app password if your host offers one.</GroupFooter>

          <div style={{ height: 20 }}/>
          <GroupHeader ui={ui}>Sync</GroupHeader>
          <Card ui={ui}>
            <div style={{ display: 'flex', alignItems: 'center', minHeight: 50, padding: '0 14px' }}>
              <span style={{ fontFamily: APP_FONT, fontSize: 15, color: ui.ink }}>Back up on Wi-Fi only</span>
              <span style={{ flex: 1 }}/>
              <Toggle ui={ui} on/>
            </div>
          </Card>
          <GroupFooter ui={ui}>When off, backups may run over cellular data.</GroupFooter>

          <div style={{ height: 20 }}/>
          <GroupHeader ui={ui}>Connection</GroupHeader>
          <Card ui={ui}>
            <Row ui={ui} last={!testResult}>
              <div style={{ display: 'flex', width: '100%', justifyContent: 'flex-start' }}>
                <span style={{
                  display: 'inline-flex', alignItems: 'center', gap: 7,
                  fontFamily: APP_FONT, fontSize: 14, fontWeight: 600,
                  color: canTest ? ui.tint : ui.ter,
                  background: canTest ? ui.chipBg : 'transparent',
                  boxShadow: canTest ? 'none' : `inset 0 0 0 1px ${ui.sep}`,
                  borderRadius: 100, padding: '8px 15px',
                }}>
                  {test === 'testing' ? (
                    <svg className="apf-spin" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
                  ) : (
                    <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12a7 7 0 0112-5l2 2M19 12a7 7 0 01-12 5l-2-2M17 4v3h-3M7 20v-3h3"/></svg>
                  )}
                  {test === 'testing' ? 'Testing…' : 'Test Connection'}
                </span>
              </div>
            </Row>
            {testResult && (
              <Row ui={ui} last>
                <div style={{ display: 'flex', alignItems: 'flex-start', gap: 7, width: '100%', justifyContent: 'flex-start', padding: '4px 0' }}>
                  {test === 'ok' ? (
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" style={{ flexShrink: 0, marginTop: 1 }}><circle cx="12" cy="12" r="10" fill={ui.green}/><path d="M7.5 12.3l3 3 6-6.5" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" fill="none"/></svg>
                  ) : (
                    <svg width="16" height="16" viewBox="0 0 24 24" fill="none" style={{ flexShrink: 0, marginTop: 1 }}><circle cx="12" cy="12" r="10" fill={ui.red}/><path d="M8 8l8 8M16 8l-8 8" stroke="#fff" strokeWidth="2" strokeLinecap="round"/></svg>
                  )}
                  <span style={{ fontFamily: APP_FONT, fontSize: 13, color: test === 'ok' ? ui.green : ui.red, lineHeight: 1.45 }}>
                    {test === 'ok' ? 'Connected — found an existing /vreader folder with 3 backups.' : 'Failed: 401 Unauthorized — check the username and password.'}
                  </span>
                </div>
              </Row>
            )}
          </Card>

          {editMode && (
            <>
              <div style={{ height: 28 }}/>
              <Card ui={ui}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', minHeight: 50, color: ui.red, fontFamily: APP_FONT, fontSize: 15, fontWeight: 500 }}>
                  Remove Server
                </div>
              </Card>
            </>
          )}
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// 5. BackupRestoreScreen — back-up-now + available backups
//    state: 'idle' | 'loading' | 'empty' | 'error'
//    err:   '401' | '404' | 'offline' | 'timeout'
// ════════════════════════════════════════════════════
const BACKUPS = [
  { id: 'b1', when: 'Today, 9:14 AM', size: '4.2 MB', device: 'Pixel 8 · this device', books: 12, latest: true },
  { id: 'b2', when: 'Yesterday, 10:01 PM', size: '4.1 MB', device: 'Pixel 8', books: 12 },
  { id: 'b3', when: 'Jun 16, 8:30 AM', size: '3.9 MB', device: 'iPad Air', books: 11 },
  { id: 'b4', when: 'Jun 9, 7:42 PM', size: '3.6 MB', device: 'iPhone 15', books: 10 },
];

function BackupHeaderCard({ ui, syncing }) {
  return (
    <Card ui={ui}>
      <div style={{ padding: '14px 14px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 8 }}>
          <StatusDot color={ui.green}/>
          <span style={{ fontFamily: APP_FONT, fontSize: 12, fontWeight: 600, color: ui.sec, letterSpacing: 0.4, textTransform: 'uppercase', lineHeight: 1 }}>Active server</span>
        </div>
        <div style={{ fontFamily: APP_FONT, fontSize: 16, fontWeight: 600, color: ui.ink, lineHeight: 1.2 }}>Home NAS</div>
        <div style={{ fontFamily: MONO, fontSize: 12, color: ui.sec, marginTop: 2 }}>nas.local/dav/vreader</div>
        <button style={{
          marginTop: 14, width: '100%', height: 46, borderRadius: 12, border: 'none', cursor: 'pointer',
          background: syncing ? (ui.isDark ? 'rgba(214,136,90,0.16)' : 'rgba(140,47,47,0.1)') : ui.tint,
          color: syncing ? ui.tint : '#fff',
          fontFamily: APP_FONT, fontSize: 15, fontWeight: 600,
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          {syncing ? (
            <><svg className="apf-spin" width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>Backing up… 8 / 12</>
          ) : (
            <><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"><path d="M12 16V4M7 9l5-5 5 5M5 20h14"/></svg>Back Up Now</>
          )}
        </button>
      </div>
    </Card>
  );
}

function BackupItemRow({ ui, b, last }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', minHeight: 60, padding: '10px 14px', position: 'relative' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 3 }}>
          <span style={{ fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, color: ui.ink }}>{b.when}</span>
          {b.latest && <Tag ui={ui}>Latest</Tag>}
        </div>
        <div style={{ fontFamily: APP_FONT, fontSize: 12, color: ui.sec }}>
          {b.books} books · {b.size} · {b.device}
        </div>
      </div>
      <button style={{
        flexShrink: 0, height: 32, padding: '0 14px', borderRadius: 100, cursor: 'pointer',
        background: 'transparent', border: `1px solid ${ui.isDark ? 'rgba(214,136,90,0.4)' : 'rgba(140,47,47,0.3)'}`,
        color: ui.tint, fontFamily: APP_FONT, fontSize: 13, fontWeight: 600,
      }}>Restore</button>
      {!last && <div style={{ position: 'absolute', left: 14, right: 0, bottom: 0, height: 0.5, background: ui.sep }}/>}
    </div>
  );
}

function BackupErrorBlock({ ui, err }) {
  const map = {
    '401': { t: 'Authentication failed', d: 'The server rejected your credentials (401). Re-enter the password in the server settings.', cta: 'Open Server Settings' },
    '404': { t: 'No backup folder found', d: 'The /vreader folder doesn’t exist on this server yet (404). Run your first backup to create it.', cta: 'Back Up Now' },
    'offline': { t: 'You’re offline', d: 'Connect to the internet to reach Home NAS, then pull to refresh.', cta: 'Retry' },
    'timeout': { t: 'Server didn’t respond', d: 'The request to nas.local timed out. Check the server is reachable on your network.', cta: 'Retry' },
  };
  const e = map[err] || map.offline;
  const glyph = err === 'offline'
    ? <><path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18"/><path d="M3 3l18 18"/></>
    : err === '401'
      ? <><rect x="5" y="11" width="14" height="9" rx="2"/><path d="M8 11V8a4 4 0 018 0v3"/></>
      : <><path d="M12 8v5M12 16v.01"/><circle cx="12" cy="12" r="9"/></>;
  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '40px 24px 0' }}>
      <div style={{
        width: 64, height: 64, borderRadius: 32, marginBottom: 18,
        background: ui.isDark ? 'rgba(224,119,90,0.14)' : 'rgba(168,64,47,0.08)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <svg width="28" height="28" viewBox="0 0 24 24" fill="none" stroke={ui.red} strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round">{glyph}</svg>
      </div>
      <div style={{ fontFamily: SERIF, fontSize: 18, fontWeight: 600, color: ui.ink, marginBottom: 8, lineHeight: 1.25 }}>{e.t}</div>
      <div style={{ fontFamily: APP_FONT, fontSize: 13.5, color: ui.sec, lineHeight: 1.55, maxWidth: 280, marginBottom: 20 }}>{e.d}</div>
      <button style={{
        height: 44, padding: '0 20px', borderRadius: 100, border: 'none', cursor: 'pointer',
        background: ui.tint, color: '#fff', fontFamily: APP_FONT, fontSize: 14.5, fontWeight: 600,
      }}>{e.cta}</button>
    </div>
  );
}

function BackupRestoreScreen({ ui, state = 'idle', err = 'offline', syncing = false, height = 880 }) {
  return (
    <NavScreen ui={ui} title="Backup & Restore" large height={height}>
      <div style={{ padding: '4px 18px 32px' }}>
        <BackupHeaderCard ui={ui} syncing={syncing}/>

        <div style={{ height: 22 }}/>
        <div style={{ display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', padding: '0 2px' }}>
          <GroupHeader ui={ui}>Available Backups</GroupHeader>
          {state === 'idle' && <span style={{ fontFamily: APP_FONT, fontSize: 12, color: ui.sec }}>Home NAS</span>}
        </div>

        {state === 'loading' && (
          <Card ui={ui}>
            {[0, 1, 2].map(i => (
              <div key={i} style={{ display: 'flex', alignItems: 'center', minHeight: 60, padding: '10px 14px', position: 'relative', gap: 12 }}>
                <div style={{ flex: 1 }}>
                  <div style={{ height: 11, width: '46%', borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)', marginBottom: 7 }}/>
                  <div style={{ height: 9, width: '66%', borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)' }}/>
                </div>
                {i < 2 && <div style={{ position: 'absolute', left: 14, right: 0, bottom: 0, height: 0.5, background: ui.sep }}/>}
              </div>
            ))}
            <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8, padding: '12px', color: ui.sec, fontFamily: APP_FONT, fontSize: 12.5 }}>
              <svg className="apf-spin" width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={ui.sec} strokeWidth="2.4" strokeLinecap="round"><path d="M12 3a9 9 0 1 0 9 9"/></svg>
              Reading backups from server…
            </div>
          </Card>
        )}

        {state === 'idle' && (
          <>
            <Card ui={ui}>
              {BACKUPS.map((b, i) => <BackupItemRow key={b.id} ui={ui} b={b} last={i === BACKUPS.length - 1}/>)}
            </Card>
            <GroupFooter ui={ui}>Restoring merges a backup into your current library — nothing is deleted. Use selective restore to pick individual books.</GroupFooter>
          </>
        )}

        {state === 'empty' && (
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', textAlign: 'center', padding: '36px 24px 0' }}>
            <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke={ui.ter} strokeWidth="1.4" strokeLinecap="round" strokeLinejoin="round" style={{ marginBottom: 14 }}>
              <path d="M3 7a2 2 0 012-2h4l2 2h8a2 2 0 012 2v8a2 2 0 01-2 2H5a2 2 0 01-2-2z"/>
            </svg>
            <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: ui.ink, marginBottom: 6, lineHeight: 1.25 }}>No backups yet</div>
            <div style={{ fontFamily: APP_FONT, fontSize: 13, color: ui.sec, lineHeight: 1.5, maxWidth: 260 }}>
              This server has no VReader backups. Tap <b style={{ color: ui.ink }}>Back Up Now</b> to create your first one.
            </div>
          </div>
        )}

        {state === 'error' && <BackupErrorBlock ui={ui} err={err}/>}
      </div>
    </NavScreen>
  );
}

// ════════════════════════════════════════════════════
// 6. RestoreProgress — in-progress + result (success / partial / failed)
// ════════════════════════════════════════════════════
function RestoreProgress({ ui, mode = 'progress', height = 880 }) {
  // mode: 'progress' | 'success' | 'partial' | 'failed'
  const done = 7, total = 12;
  const pct = mode === 'progress' ? done / total : 1;
  const result = mode !== 'progress';

  const resMeta = {
    success: { color: ui.green, title: 'Restore complete', sub: `${total} of ${total} books restored from Today, 9:14 AM.` },
    partial: { color: '#c79a2e', title: 'Restored with issues', sub: `9 of ${total} books restored. 3 couldn’t be downloaded — retry them below.` },
    failed: { color: ui.red, title: 'Restore failed', sub: 'The connection dropped before any books were restored. Your library is unchanged.' },
  }[mode];

  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg, display: 'flex', flexDirection: 'column' }}>
        <TopBar ui={ui} title="Restore" large={false}/>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0 32px', textAlign: 'center' }}>

          {/* progress ring / result mark */}
          <div style={{ position: 'relative', width: 96, height: 96, marginBottom: 24 }}>
            <svg width="96" height="96" viewBox="0 0 96 96" style={{ transform: 'rotate(-90deg)' }}>
              <circle cx="48" cy="48" r="42" fill="none" stroke={ui.sep} strokeWidth="6"/>
              <circle cx="48" cy="48" r="42" fill="none"
                stroke={result ? resMeta.color : ui.tint} strokeWidth="6" strokeLinecap="round"
                strokeDasharray={2 * Math.PI * 42}
                strokeDashoffset={2 * Math.PI * 42 * (1 - pct)}
                style={{ transition: 'stroke-dashoffset .4s' }}/>
            </svg>
            <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              {mode === 'progress' && <span style={{ fontFamily: APP_FONT, fontSize: 22, fontWeight: 700, color: ui.ink, fontVariantNumeric: 'tabular-nums' }}>{Math.round(pct * 100)}%</span>}
              {mode === 'success' && <svg width="40" height="40" viewBox="0 0 24 24" fill="none" stroke={ui.green} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l5 5 9-10"/></svg>}
              {mode === 'partial' && <svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#c79a2e" strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M12 8v5M12 16.5v.01"/></svg>}
              {mode === 'failed' && <svg width="34" height="34" viewBox="0 0 24 24" fill="none" stroke={ui.red} strokeWidth="2.4" strokeLinecap="round"><path d="M7 7l10 10M17 7L7 17"/></svg>}
            </div>
          </div>

          <div style={{ fontFamily: SERIF, fontSize: 20, fontWeight: 700, color: ui.ink, marginBottom: 8, lineHeight: 1.2 }}>
            {result ? resMeta.title : 'Restoring your library'}
          </div>
          <div style={{ fontFamily: APP_FONT, fontSize: 13.5, color: ui.sec, lineHeight: 1.55, maxWidth: 270 }}>
            {result ? resMeta.sub : `Downloading book ${done} of ${total} · The Pragmatic Programmer`}
          </div>

          {mode === 'progress' && (
            <div style={{ width: '100%', maxWidth: 280, marginTop: 22 }}>
              <div style={{ height: 5, borderRadius: 3, background: ui.sep, overflow: 'hidden' }}>
                <div style={{ width: `${pct * 100}%`, height: '100%', background: ui.tint, borderRadius: 3, transition: 'width .4s' }}/>
              </div>
              <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontFamily: APP_FONT, fontSize: 11.5, color: ui.sec }}>
                <span>{done} / {total} books</span>
                <span>~40s left</span>
              </div>
            </div>
          )}
        </div>

        {/* footer action */}
        <div style={{ padding: '0 24px 30px' }}>
          {mode === 'progress' && (
            <button style={{ width: '100%', height: 46, borderRadius: 12, background: 'transparent', border: `1px solid ${ui.sep}`, color: ui.ink, fontFamily: APP_FONT, fontSize: 15, fontWeight: 500, cursor: 'pointer' }}>Cancel</button>
          )}
          {(mode === 'success') && (
            <button style={{ width: '100%', height: 46, borderRadius: 12, background: ui.tint, border: 'none', color: '#fff', fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>Done</button>
          )}
          {mode === 'partial' && (
            <div style={{ display: 'flex', gap: 10 }}>
              <button style={{ flex: 1, height: 46, borderRadius: 12, background: 'transparent', border: `1px solid ${ui.sep}`, color: ui.ink, fontFamily: APP_FONT, fontSize: 15, fontWeight: 500, cursor: 'pointer' }}>Done</button>
              <button style={{ flex: 1, height: 46, borderRadius: 12, background: ui.tint, border: 'none', color: '#fff', fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>Retry 3 Books</button>
            </div>
          )}
          {mode === 'failed' && (
            <div style={{ display: 'flex', gap: 10 }}>
              <button style={{ flex: 1, height: 46, borderRadius: 12, background: 'transparent', border: `1px solid ${ui.sep}`, color: ui.ink, fontFamily: APP_FONT, fontSize: 15, fontWeight: 500, cursor: 'pointer' }}>Back</button>
              <button style={{ flex: 1, height: 46, borderRadius: 12, background: ui.tint, border: 'none', color: '#fff', fontFamily: APP_FONT, fontSize: 15, fontWeight: 600, cursor: 'pointer' }}>Try Again</button>
            </div>
          )}
        </div>
      </div>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// 7. SelectiveRestoreSheet — per-book picker w/ lazy download
//    book.state: 'local' | 'remote' | 'downloading' | 'failed'
// ════════════════════════════════════════════════════
const MANIFEST = [
  { id: 'm1', title: 'Pride and Prejudice', author: 'Jane Austen', size: '432 KB', state: 'local', sel: true },
  { id: 'm2', title: 'The Beginning of Infinity', author: 'David Deutsch', size: '1.8 MB', state: 'remote', sel: true },
  { id: 'm3', title: 'Designing Data-Intensive Applications', author: 'Martin Kleppmann', size: '8.4 MB', state: 'downloading', sel: true, progress: 0.46 },
  { id: 'm4', title: 'Sapiens', author: 'Yuval Noah Harari', size: '2.1 MB', state: 'remote', sel: false },
  { id: 'm5', title: 'Meditations', author: 'Marcus Aurelius', size: '298 KB', state: 'failed', sel: true },
  { id: 'm6', title: 'The Three-Body Problem', author: '刘慈欣', size: '1.2 MB', state: 'remote', sel: true },
];

function BookCover({ size = 38 }) {
  return (
    <div style={{
      width: size, height: size * 1.32, borderRadius: 3, flexShrink: 0,
      background: 'linear-gradient(135deg, #5a3a3a, #3a2424)',
      boxShadow: '0 1px 3px rgba(0,0,0,0.25)', position: 'relative', overflow: 'hidden',
    }}>
      <div style={{ position: 'absolute', left: 4, top: 6, right: 4, height: 2, background: 'rgba(199,164,90,0.7)', borderRadius: 1 }}/>
      <div style={{ position: 'absolute', left: 4, top: 11, right: 8, height: 1.5, background: 'rgba(244,233,212,0.4)', borderRadius: 1 }}/>
    </div>
  );
}

function ManifestRow({ ui, b, last }) {
  const stateMeta = {
    local: { label: 'On this device', color: ui.green, icon: <path d="M5 12.5l4 4 8-9" stroke={ui.green} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/> },
    remote: { label: `Download · ${b.size}`, color: ui.sec, icon: <><path d="M12 4v10M8 11l4 4 4-4" stroke={ui.tint} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/></> },
    downloading: { label: `Downloading… ${Math.round((b.progress || 0) * 100)}%`, color: ui.tint, icon: null },
    failed: { label: 'Download failed — tap to retry', color: ui.red, icon: <><path d="M5 8a7 7 0 0112-3M19 12a7 7 0 01-12 5" stroke={ui.red} strokeWidth="2" fill="none" strokeLinecap="round"/><path d="M5 4v4h4M19 20v-4h-4" stroke={ui.red} strokeWidth="2" fill="none" strokeLinecap="round" strokeLinejoin="round"/></> },
  }[b.state];

  return (
    <div style={{ display: 'flex', alignItems: 'center', minHeight: 64, padding: '10px 14px', position: 'relative', gap: 12, opacity: b.sel ? 1 : 0.55 }}>
      {/* checkbox */}
      <div style={{
        width: 22, height: 22, borderRadius: 11, flexShrink: 0,
        background: b.sel ? ui.tint : 'transparent',
        boxShadow: b.sel ? 'none' : `inset 0 0 0 1.5px ${ui.isDark ? 'rgba(255,255,255,0.25)' : 'rgba(0,0,0,0.22)'}`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        {b.sel && <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12.5l4 4 9-10"/></svg>}
      </div>
      <BookCover/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: SERIF, fontSize: 14.5, fontWeight: 600, color: ui.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.title}</div>
        <div style={{ fontFamily: APP_FONT, fontSize: 11.5, color: ui.sec, marginBottom: b.state === 'downloading' ? 5 : 0, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.author}</div>
        {b.state === 'downloading' ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 7, marginTop: 1 }}>
            <div style={{ flex: 1, maxWidth: 120, height: 3, borderRadius: 2, background: ui.sep, overflow: 'hidden' }}>
              <div style={{ width: `${(b.progress || 0) * 100}%`, height: '100%', background: ui.tint }}/>
            </div>
            <span style={{ fontFamily: APP_FONT, fontSize: 11, color: ui.tint, fontWeight: 600 }}>{Math.round((b.progress || 0) * 100)}%</span>
          </div>
        ) : (
          <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 2 }}>
            {b.state === 'local' && <StatusDot color={ui.green}/>}
            <span style={{ fontFamily: APP_FONT, fontSize: 11.5, color: stateMeta.color, fontWeight: b.state === 'remote' ? 500 : 600, whiteSpace: 'nowrap' }}>{stateMeta.label}</span>
          </div>
        )}
      </div>
      {/* trailing affordance */}
      {b.state === 'downloading' ? (
        <svg className="apf-spin" width="18" height="18" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.4" strokeLinecap="round" style={{ flexShrink: 0 }}><path d="M12 3a9 9 0 1 0 9 9"/></svg>
      ) : (
        <div style={{ width: 30, height: 30, borderRadius: 15, flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', background: b.state === 'remote' ? ui.chipBg : 'transparent' }}>
          <svg width="18" height="18" viewBox="0 0 24 24" fill="none">{stateMeta.icon}</svg>
        </div>
      )}
      {!last && <div style={{ position: 'absolute', left: 48, right: 0, bottom: 0, height: 0.5, background: ui.sep }}/>}
    </div>
  );
}

function SelectiveRestoreSheet({ ui, height = 880 }) {
  const selCount = MANIFEST.filter(b => b.sel).length;
  const Cancel = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 15, color: ui.sec, cursor: 'pointer' }}>Cancel</button>;
  const SelectAll = <button style={{ background: 'none', border: 'none', padding: 0, fontFamily: APP_FONT, fontSize: 14, fontWeight: 500, color: ui.tint, cursor: 'pointer' }}>Deselect all</button>;
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }}/>
      <AppSheet ui={ui} title="Choose Books" leading={Cancel} trailing={SelectAll} height={height - 36}>
        <div style={{ padding: '12px 18px 8px' }}>
          <div style={{ fontFamily: APP_FONT, fontSize: 12.5, color: ui.sec, lineHeight: 1.5, padding: '0 2px 12px' }}>
            From <span style={{ color: ui.ink, fontWeight: 600 }}>Today, 9:14 AM</span> · 12 books in this backup. Remote-only books download from the server as you restore.
          </div>
          <Card ui={ui}>
            {MANIFEST.map((b, i) => <ManifestRow key={b.id} ui={ui} b={b} last={i === MANIFEST.length - 1}/>)}
          </Card>
        </div>
      </AppSheet>
      {/* pinned restore CTA */}
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: 0, zIndex: 250,
        padding: '12px 18px 26px', background: ui.sheetBg,
        borderTop: `0.5px solid ${ui.sep}`,
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontFamily: APP_FONT, fontSize: 14, fontWeight: 600, color: ui.ink }}>{selCount} books selected</div>
          <div style={{ fontFamily: APP_FONT, fontSize: 11.5, color: ui.sec }}>3 already local · 2 will download</div>
        </div>
        <button style={{
          height: 46, padding: '0 24px', borderRadius: 12, border: 'none', cursor: 'pointer',
          background: ui.tint, color: '#fff', fontFamily: APP_FONT, fontSize: 15, fontWeight: 600,
        }}>Restore</button>
      </div>
    </PhoneFrame>
  );
}

Object.assign(window, {
  Toggle, StatusDot, TopBar, NavScreen, AppAlert,
  SERVERS, ServerRow, WebDAVServerList,
  ServerEditSheet,
  BACKUPS, BackupRestoreScreen, RestoreProgress,
  MANIFEST, SelectiveRestoreSheet,
});
