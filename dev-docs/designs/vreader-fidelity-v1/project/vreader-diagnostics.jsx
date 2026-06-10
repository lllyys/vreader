// Issue #1597 — Settings → Diagnostics entry + in-app log viewer (feature #96).
//
// Components:
//   DiagPulseIcon          — waveform glyph, same stroke vocabulary as Icons.
//   DiagSettingsRow        — colored-tile nav row (SettingsRow replica, local name).
//   DiagSupportGroup       — the new "Support" group in SettingsView.
//   DiagLogViewer          — the pushed Diagnostics screen: nav bar w/ share
//                            trailing, level + category chip rows, log list,
//                            pinned status footer. States: default / loading /
//                            empty / filtered / filtered-empty / share-open.
//   DiagShareMock          — reduced-fidelity system share sheet (system
//                            chrome, NOT designed here — only its trigger is).
//
// Level color coding is functional, not decorative: error = warm red,
// info = cool blue, debug = the theme's sub color. Message text is monospace;
// all chrome stays in Inter per the app vocabulary.

const DIAG_MONO = '"SF Mono", ui-monospace, Menlo, Consolas, monospace';
const DIAG_TILE = '#5b6770';   // steel — diagnostics settings tile
const DIAG_ABOUT_TILE = '#8a8a8e';

function diagLevelColor(t, level) {
  if (level === 'error') return t.isDark ? '#e0826f' : '#b13e36';
  if (level === 'info')  return t.isDark ? '#7fb2d9' : '#3a6f9c';
  return t.sub; // debug
}

// ────────────────────────────────────────────────────
// Pulse icon — adds to the Icons set, same chroma/stroke vocabulary.
// ────────────────────────────────────────────────────
const DiagPulseIcon = ({ size = 17, color = '#fff', stroke = 1.8 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
       stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
    <path d="M3 12h4l2.5-6 5 12 2.5-6h4"/>
  </svg>
);

// ────────────────────────────────────────────────────
// Sample log data — subsystem com.vreader.app. Newest first.
// ────────────────────────────────────────────────────
const DIAG_LOG = [
  { id: 1,  day: 'Today',     ts: '14:32:07.412', level: 'error', cat: 'Persistence', msg: 'Failed to save ReadingSession: CKError 4 (networkUnavailable) — retry queued for next launch' },
  { id: 2,  day: 'Today',     ts: '14:32:06.998', level: 'debug', cat: 'Persistence', msg: 'Flush failed — 3 dirty records re-queued (attempt 2/5)' },
  { id: 3,  day: 'Today',     ts: '14:31:48.221', level: 'info',  cat: 'Sync',        msg: 'WebDAV backup finished — 152 books, 2.1 MB in 8.4 s (Nutstore)' },
  { id: 4,  day: 'Today',     ts: '14:29:12.064', level: 'debug', cat: 'Reader',      msg: 'Pagination cache rebuilt for chapter 12 — 38 pages in 412 ms' },
  { id: 5,  day: 'Today',     ts: '14:29:11.870', level: 'info',  cat: 'Reader',      msg: 'Opened “Pride and Prejudice” at locator 0.418 (chapter 12)' },
  { id: 6,  day: 'Today',     ts: '13:58:40.103', level: 'error', cat: 'AI',          msg: 'Provider request failed: 401 Unauthorized (Claude) — key rejected, check Settings → AI provider' },
  { id: 7,  day: 'Today',     ts: '13:58:39.751', level: 'debug', cat: 'AI',          msg: 'POST /v1/messages — 2,380 tokens estimated, stream=true' },
  { id: 8,  day: 'Today',     ts: '13:14:02.330', level: 'info',  cat: 'Library',     msg: 'Imported “The Beginning of Infinity.epub” — 18 chapters, 1.2 MB in 3.4 s' },
  { id: 9,  day: 'Today',     ts: '13:14:01.118', level: 'debug', cat: 'Library',     msg: 'EPUB manifest parsed — 18 spine items, 214 resources' },
  { id: 10, day: 'Today',     ts: '09:02:55.480', level: 'debug', cat: 'DebugBridge', msg: 'Bridge disabled in Release build — recorder running standalone' },
  { id: 11, day: 'Today',     ts: '09:02:55.214', level: 'info',  cat: 'Library',     msg: 'Library opened — 152 books, index loaded in 96 ms' },
];

const DIAG_LOG_ERRORS = [
  DIAG_LOG[0],
  DIAG_LOG[5],
  { id: 12, day: 'Today',     ts: '11:47:19.207', level: 'error', cat: 'Library',     msg: 'Cover render failed for “Designing Data-Intensive Applications” — image decode error (corrupt JPEG)' },
  { id: 13, day: 'Yesterday', ts: '22:10:33.901', level: 'error', cat: 'Sync',        msg: 'WebDAV upload failed: 507 Insufficient Storage — backup skipped' },
  { id: 14, day: 'Yesterday', ts: '21:03:11.659', level: 'error', cat: 'Persistence', msg: 'Migration warning escalated: duplicate AnnotationRecord ids (2) — deduped' },
];

const DIAG_LOG_PERSISTENCE = [
  DIAG_LOG[0], DIAG_LOG[1],
  { id: 15, day: 'Today',     ts: '12:40:18.092', level: 'debug', cat: 'Persistence', msg: 'Checkpoint: 41 dirty records flushed in 86 ms' },
  { id: 16, day: 'Today',     ts: '09:02:56.101', level: 'debug', cat: 'Persistence', msg: 'Store opened — schema v14, 6,212 records, integrity OK' },
  { id: 14, day: 'Yesterday', ts: '21:03:11.659', level: 'error', cat: 'Persistence', msg: 'Migration warning escalated: duplicate AnnotationRecord ids (2) — deduped' },
];

const DIAG_CATEGORIES = ['All', 'Library', 'Persistence', 'Reader', 'AI', 'Sync', 'DebugBridge'];
const DIAG_COUNTS = { all: 487, error: 12, debug: 203, info: 272 };

// ────────────────────────────────────────────────────
// DiagSettingsRow — colored-tile nav row (replica of shipped SettingsRow).
// ────────────────────────────────────────────────────
function DiagSettingsRow({ theme: t, icon, color, title, detail, value, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0,
        background: color, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{icon}</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, color: t.ink }}>{title}</div>
        {detail && <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>{detail}</div>}
      </div>
      {value && <div style={{ fontSize: 14, color: t.sub, marginRight: 4 }}>{value}</div>}
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </div>
  );
}

// ────────────────────────────────────────────────────
// DiagSupportGroup — the new Support group: Diagnostics row + About row.
// highlight adds a "new" tag (canvas annotation, not shipped chrome).
// errorBadge shows the alternative badged treatment (alt X3 — not canonical).
// ────────────────────────────────────────────────────
function DiagSupportGroup({ theme: t, highlight = false, errorBadge = false }) {
  return (
    <div style={{ position: 'relative' }}>
      <SectionLabel theme={t}>Support</SectionLabel>
      {highlight && (
        <div style={{
          position: 'absolute', right: 0, top: -2,
          fontSize: 9.5, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase',
          color: t.accent, background: `${t.accent}18`, borderRadius: 5, padding: '2px 6px',
        }}>new row</div>
      )}
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <DiagSettingsRow theme={t}
          icon={<DiagPulseIcon size={17} color="#fff" stroke={1.8}/>}
          color={DIAG_TILE}
          title="Diagnostics"
          detail={errorBadge ? 'View and export app logs' : 'View and export app logs'}
          value={errorBadge ? '12 errors' : null}/>
        <DiagSettingsRow theme={t}
          icon={<Icons.Info size={17} color="#fff" stroke={1.8}/>}
          color={DIAG_ABOUT_TILE}
          title="About VReader"
          value="1.8.2" last/>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// DiagNavSheet — pushed screen within the Settings sheet. Same frame as the
// shipped NavSheet (#1380): grabber, ‹ back, centered serif title, trailing.
// ────────────────────────────────────────────────────
function DiagNavSheet({ theme, height = 740, title = 'Diagnostics', backLabel = 'Settings', trailing, children }) {
  const t = theme || THEMES.paper;
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 200,
      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
      background: 'rgba(0,0,0,0.35)',
    }}>
      <div style={{
        background: t.isDark ? '#222020' : '#fcf8f0',
        height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{
            width: 36, height: 5, borderRadius: 3,
            background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
          }}/>
        </div>
        <div style={{
          position: 'relative', display: 'flex', alignItems: 'center',
          padding: '13px 16px 12px',
          borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
        }}>
          <button style={{
            display: 'flex', alignItems: 'center', gap: 1, zIndex: 1,
            background: 'none', border: 'none', padding: 0, cursor: 'pointer',
            color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
            whiteSpace: 'nowrap',
          }}>
            <Icons.ChevronL size={19} color={t.accent} stroke={2.2}/>
            <span>{backLabel}</span>
          </button>
          <div style={{
            position: 'absolute', left: 0, right: 0, textAlign: 'center',
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 17, fontWeight: 600, color: t.ink,
            pointerEvents: 'none',
          }}>{title}</div>
          <div style={{ marginLeft: 'auto', zIndex: 1 }}>{trailing}</div>
        </div>
        {children}
      </div>
    </div>
  );
}

// Share trigger — the nav-bar trailing affordance (canonical home).
function DiagShareButton({ theme: t, emphasized = false }) {
  return (
    <button style={{
      width: 28, height: 28, borderRadius: 14, border: 'none', padding: 0,
      cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
      background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
      boxShadow: emphasized ? `0 0 0 2px ${t.accent}66` : 'none',
    }}>
      <Icons.Share size={15} color={t.accent} stroke={1.9}/>
    </button>
  );
}

// ────────────────────────────────────────────────────
// Filter chips — level row (with counts) + category row (scrollable).
// Active chip = inverted ink pill (HighlightsSheetV2 vocabulary); the Errors
// chip tints to the error color when active so the filtered state is legible
// at a glance.
// ────────────────────────────────────────────────────
function DiagChip({ t, label, count, active, tint }) {
  const bg = active ? (tint || t.ink) : 'transparent';
  const fg = active
    ? (tint ? '#fff' : (t.isDark ? '#1a1815' : '#faf6ea'))
    : t.sub;
  return (
    <button style={{
      display: 'flex', alignItems: 'center', gap: 5, flexShrink: 0,
      padding: '5px 11px', borderRadius: 999, cursor: 'pointer',
      border: active ? '0.5px solid transparent' : `0.5px solid ${t.rule}`,
      background: bg, color: fg,
      fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, whiteSpace: 'nowrap',
    }}>
      {label}
      {count != null && <span style={{ opacity: 0.55, fontWeight: 500 }}>{count}</span>}
    </button>
  );
}

function DiagFilterBar({ theme: t, level = 'all', category = 'All' }) {
  return (
    <div style={{
      padding: '12px 18px 10px', display: 'flex', flexDirection: 'column', gap: 8,
      borderBottom: `0.5px solid ${t.rule}`, flexShrink: 0,
    }}>
      <div style={{ display: 'flex', gap: 7 }}>
        <DiagChip t={t} label="All" count={DIAG_COUNTS.all} active={level === 'all'}/>
        <DiagChip t={t} label="Errors" count={DIAG_COUNTS.error} active={level === 'error'} tint={diagLevelColor(t, 'error')}/>
        <DiagChip t={t} label="Debug" count={DIAG_COUNTS.debug} active={level === 'debug'}/>
        <DiagChip t={t} label="Info" count={DIAG_COUNTS.info} active={level === 'info'}/>
      </div>
      <div className="hide-scroll" style={{ display: 'flex', gap: 7, overflowX: 'auto', margin: '0 -18px', padding: '0 18px' }}>
        {DIAG_CATEGORIES.map(c => (
          <DiagChip key={c} t={t} label={c} active={category === c}/>
        ))}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Log rows — meta line (mono timestamp · colored level · category pill),
// monospace message clamped to 3 lines. Tap expands: full message + Copy.
// ────────────────────────────────────────────────────
function DiagDayHeader({ theme: t, children }) {
  return (
    <div style={{
      padding: '10px 18px 4px',
      fontSize: 10.5, fontWeight: 600, letterSpacing: 0.6,
      textTransform: 'uppercase', color: t.sub,
    }}>{children}</div>
  );
}

function DiagLogRow({ theme: t, entry: e, expanded = false, last = false }) {
  const lc = diagLevelColor(t, e.level);
  return (
    <div style={{
      padding: '9px 18px 10px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
      background: expanded ? (t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.025)') : 'transparent',
    }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 8 }}>
        <span style={{ fontFamily: DIAG_MONO, fontSize: 10.5, color: t.sub }}>{e.ts}</span>
        <span style={{
          fontSize: 10, fontWeight: 700, letterSpacing: 0.8,
          textTransform: 'uppercase', color: lc,
        }}>{e.level}</span>
        <span style={{
          fontFamily: DIAG_MONO, fontSize: 9.5, color: t.sub,
          background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)',
          borderRadius: 4, padding: '1.5px 6px',
        }}>{e.cat}</span>
      </div>
      <div style={{
        fontFamily: DIAG_MONO, fontSize: 12, lineHeight: 1.5, color: t.ink,
        marginTop: 4,
        ...(expanded ? {} : {
          display: '-webkit-box', WebkitLineClamp: 3, WebkitBoxOrient: 'vertical',
          overflow: 'hidden',
        }),
      }}>{e.msg}{expanded && e.msgMore ? '\n' + e.msgMore : ''}</div>
      {expanded && (
        <div style={{ display: 'flex', gap: 8, marginTop: 9 }}>
          <button style={{
            display: 'flex', alignItems: 'center', gap: 5,
            padding: '4px 10px', borderRadius: 999, cursor: 'pointer',
            border: `0.5px solid ${t.rule}`, background: 'transparent',
            color: t.accent, fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600,
          }}>
            <Icons.Copy size={11} color={t.accent} stroke={2}/>Copy entry
          </button>
        </div>
      )}
    </div>
  );
}

function DiagLogList({ theme: t, entries, expandedId }) {
  const out = [];
  let lastDay = null;
  entries.forEach((e, i) => {
    if (e.day !== lastDay) {
      out.push(<DiagDayHeader key={'d' + e.day + i} theme={t}>{e.day === 'Today' ? 'Today · 10 June' : e.day + ' · 9 June'}</DiagDayHeader>);
      lastDay = e.day;
    }
    out.push(<DiagLogRow key={e.id} theme={t} entry={e}
      expanded={expandedId === e.id} last={i === entries.length - 1}/>);
  });
  return <div>{out}</div>;
}

// Pinned status footer — entry count + capture reassurance (no toggle:
// capture is always on in Release; this is a statement, not a control).
function DiagFooter({ theme: t, left = '487 entries · last 24 h', capturing = true }) {
  return (
    <div style={{
      flexShrink: 0, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '10px 18px 14px', borderTop: `0.5px solid ${t.rule}`,
    }}>
      <span style={{ fontFamily: DIAG_MONO, fontSize: 10.5, color: t.sub }}>{left}</span>
      {capturing && (
        <span style={{ display: 'flex', alignItems: 'center', gap: 5, fontSize: 10.5, fontWeight: 600, color: t.sub }}>
          <span style={{ width: 6, height: 6, borderRadius: 3, background: '#4a9a6a' }}></span>
          Capturing
        </span>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// Loading + empty states
// ────────────────────────────────────────────────────
function DiagLoading({ theme: t }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14 }}>
      <style>{'@keyframes diagspin { to { transform: rotate(360deg); } }'}</style>
      <svg width="26" height="26" viewBox="0 0 26 26" style={{ animation: 'diagspin 0.9s linear infinite' }}>
        <circle cx="13" cy="13" r="10" fill="none" stroke={t.rule} strokeWidth="2.5"></circle>
        <path d="M13 3a10 10 0 019.5 6.9" fill="none" stroke={t.accent} strokeWidth="2.5" strokeLinecap="round"></path>
      </svg>
      <div style={{ textAlign: 'center' }}>
        <div style={{ fontSize: 14, fontWeight: 600, color: t.ink }}>Reading log store…</div>
        <div style={{ fontFamily: DIAG_MONO, fontSize: 10.5, color: t.sub, marginTop: 4 }}>OSLogStore · com.vreader.app</div>
      </div>
    </div>
  );
}

function DiagEmpty({ theme: t, filtered = false, filterLabel = '' }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 0, padding: '0 44px', textAlign: 'center' }}>
      <div style={{
        width: 54, height: 54, borderRadius: 14,
        background: filtered ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)') : DIAG_TILE,
        display: 'flex', alignItems: 'center', justifyContent: 'center', marginBottom: 16,
      }}>
        {filtered
          ? <Icons.Filter size={22} color={t.sub} stroke={1.7}/>
          : <DiagPulseIcon size={26} color="#fff" stroke={1.7}/>}
      </div>
      <div style={{ fontSize: 15, fontWeight: 600, color: t.ink }}>
        {filtered ? 'No matching entries' : 'No log entries yet'}
      </div>
      <div style={{ fontSize: 12.5, lineHeight: 1.5, color: t.sub, marginTop: 6 }}>
        {filtered
          ? `Nothing matches ${filterLabel} in the last 24 hours.`
          : 'VReader records errors and key events as you read. Entries appear here automatically — nothing to turn on.'}
      </div>
      {filtered && (
        <button style={{
          marginTop: 14, padding: '6px 14px', borderRadius: 999, cursor: 'pointer',
          border: 'none', background: `${t.accent}18`, color: t.accent,
          fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600,
        }}>Clear filters</button>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// DiagShareMock — the system share sheet, reduced fidelity. System chrome;
// only its TRIGGER is designed (nav trailing). Shown so the export payload
// header (filename + size) has a reviewed reference.
// ────────────────────────────────────────────────────
function DiagShareMock({ theme: t }) {
  const ph = t.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.10)';
  const phSoft = t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)';
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 300, background: 'rgba(0,0,0,0.3)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
      <div style={{
        margin: '0 8px 8px', borderRadius: 18, padding: '10px 16px 18px',
        background: t.isDark ? 'rgba(40,38,35,0.97)' : 'rgba(248,245,238,0.97)',
        boxShadow: '0 -6px 24px rgba(0,0,0,0.3)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingBottom: 10 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: ph }}></div>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 11, paddingBottom: 14, borderBottom: `0.5px solid ${t.rule}` }}>
          <div style={{
            width: 36, height: 36, borderRadius: 8, background: DIAG_TILE,
            display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
          }}>
            <Icons.Note size={18} color="#fff" stroke={1.7}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontFamily: DIAG_MONO, fontSize: 12, color: t.ink }}>vreader-log-2026-06-10.txt</div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: 2 }}>Plain text · 312 KB · last 24 h</div>
          </div>
          <div style={{ width: 26, height: 26, borderRadius: 13, background: phSoft }}></div>
        </div>
        <div style={{ display: 'flex', gap: 18, padding: '14px 4px 12px' }}>
          {[0, 1, 2, 3].map(i => (
            <div key={i} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6 }}>
              <div style={{ width: 46, height: 46, borderRadius: 12, background: ph }}></div>
              <div style={{ width: 38, height: 5, borderRadius: 3, background: phSoft }}></div>
            </div>
          ))}
        </div>
        {[0, 1].map(i => (
          <div key={i} style={{ height: 38, borderRadius: 10, background: phSoft, marginTop: 8 }}></div>
        ))}
        <div style={{
          fontFamily: DIAG_MONO, fontSize: 9.5, color: t.sub,
          textAlign: 'center', marginTop: 12, letterSpacing: 0.3,
        }}>iOS share sheet — system chrome, not designed here</div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// DiagLogViewer — the whole pushed screen, state-driven.
// state: default | loading | empty | filtered-empty | share
// ────────────────────────────────────────────────────
function DiagLogViewer({
  theme, height = 740, state = 'default',
  level = 'all', category = 'All',
  entries = DIAG_LOG, expandedId = null,
  footerLeft, footerVariant = 'export-cta-absent',
  emphasizeShare = false,
}) {
  const t = theme || THEMES.paper;
  const busy = state === 'loading';
  const empty = state === 'empty' || state === 'filtered-empty';
  const filterLabel = level !== 'all' && category !== 'All'
    ? `${category} ${level}s` : (level !== 'all' ? `${level}s` : category);
  return (
    <React.Fragment>
      <DiagNavSheet theme={t} height={height}
        trailing={!busy && state !== 'empty' ? <DiagShareButton theme={t} emphasized={emphasizeShare}/> : null}>
        {!busy && state !== 'empty' && (
          <DiagFilterBar theme={t} level={level} category={category}/>
        )}
        {busy && <DiagLoading theme={t}/>}
        {!busy && empty && (
          <DiagEmpty theme={t} filtered={state === 'filtered-empty'} filterLabel={filterLabel}/>
        )}
        {!busy && !empty && (
          <div className="hide-scroll" style={{ flex: 1, overflow: 'auto', minHeight: 0 }}>
            <DiagLogList theme={t} entries={entries} expandedId={expandedId}/>
          </div>
        )}
        {!busy && state !== 'empty' && (
          <React.Fragment>
            {footerVariant === 'export-cta' && (
              <div style={{ flexShrink: 0, padding: '10px 18px 0', borderTop: `0.5px solid ${t.rule}` }}>
                <button style={{
                  width: '100%', padding: '12px 0', borderRadius: 13, border: 'none',
                  background: t.accent, color: '#fff', cursor: 'pointer',
                  fontFamily: 'inherit', fontSize: 14.5, fontWeight: 600,
                  display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 7,
                }}>
                  <Icons.Share size={15} color="#fff" stroke={2}/>Export log…
                </button>
              </div>
            )}
            <DiagFooter theme={t}
              left={footerLeft || (state === 'filtered-empty' ? '0 of 487 entries' : '487 entries · last 24 h')}/>
          </React.Fragment>
        )}
      </DiagNavSheet>
      {state === 'share' && <DiagShareMock theme={t}/>}
    </React.Fragment>
  );
}

Object.assign(window, {
  DiagPulseIcon, DiagSettingsRow, DiagSupportGroup,
  DiagNavSheet, DiagShareButton, DiagFilterBar, DiagChip,
  DiagLogRow, DiagLogList, DiagFooter, DiagLoading, DiagEmpty,
  DiagShareMock, DiagLogViewer,
  DIAG_LOG, DIAG_LOG_ERRORS, DIAG_LOG_PERSISTENCE, DIAG_MONO, DIAG_TILE,
  diagLevelColor,
});
