// Issue #1800 / Feature #110 (Android Phase-3) — reading-stats surfaces.
//
// iOS shows cumulative + per-session reading time (#101) and per-book stats;
// the Android tracking layer is backend, but the display UI was design-gated
// (rule 51). Built in VReader's vocabulary — reader THEMES for the in-reader
// HUD, the shared form tokens for the dashboard. States: no-data, populated.
//
// Two surfaces:
//   A. In-reader reading-time — a glassy session pill that auto-fades, and the
//      reading-time detail card (session · total · time-left · pace) reached
//      from the progress area.
//   B. The stats dashboard — a time-window chip bar, an hour hero, a 14-day
//      daily-reading column chart, and a sortable per-book table.

const ST_SERIF = '"Source Serif 4", Georgia, serif';
const ST_SANS = "'Inter', -apple-system, system-ui, sans-serif";

const DAILY = [22, 34, 0, 41, 58, 30, 12, 47, 63, 38, 0, 25, 54, 72]; // minutes/day
const PERBOOK = [
  { t: 'Pride and Prejudice', time: '12h 18m', mins: 738, hl: 47, nt: 18 },
  { t: 'The Beginning of Infinity', time: '9h 47m', mins: 587, hl: 22, nt: 11 },
  { t: 'Designing Data-Intensive Apps', time: '7h 11m', mins: 431, hl: 31, nt: 4 },
  { t: 'The Pragmatic Programmer', time: '4h 02m', mins: 242, hl: 9, nt: 2 },
];

// ── A · in-reader reading time ───────────────────────────────
function InReaderTime({ themeKey = 'paper', variant = 'pill', height = 880 }) {
  const t = window.THEMES[themeKey];
  const glass = t.isDark ? 'rgba(28,26,23,0.82)' : 'rgba(252,248,240,0.88)';
  return (
    <window.TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <window.StatusStrip t={t} />
        <window.ReaderChrome t={t} />
        <div style={{ flex: 1, position: 'relative', padding: '6px 26px 0', overflow: 'hidden' }}>
          <div style={{ fontFamily: ST_SERIF, fontSize: 18.5, lineHeight: 1.62, color: t.ink, textWrap: 'pretty' }}>
            <p style={{ margin: '0 0 17px' }}>Elizabeth's astonishment was beyond expression. She stared, coloured, doubted, and was silent. This he considered sufficient encouragement.</p>
            <p style={{ margin: '0 0 17px' }}>The avowal of all that he felt, and had long felt for her, immediately followed. He spoke well; but there were feelings besides those of the heart to be detailed.</p>
            <p style={{ margin: 0, color: t.sub }}>He was not more eloquent on the subject of tenderness than of pride.</p>
          </div>

          {variant === 'pill' && (
            <div style={{
              position: 'absolute', top: 14, right: 18, display: 'inline-flex', alignItems: 'center', gap: 7,
              background: glass, backdropFilter: 'blur(16px)', WebkitBackdropFilter: 'blur(16px)',
              borderRadius: 100, padding: '7px 13px', boxShadow: '0 4px 16px rgba(0,0,0,0.14)',
              border: `0.5px solid ${t.rule}`,
            }}>
              <window.Icons.Timer size={15} color={t.accent} />
              <span style={{ fontFamily: ST_SANS, fontSize: 12.5, fontWeight: 600, color: t.ink, fontVariantNumeric: 'tabular-nums' }}>24:08</span>
              <span style={{ fontFamily: ST_SANS, fontSize: 12, color: t.sub }}>this session</span>
            </div>
          )}
        </div>

        {/* progress footer — the time detail card sits above it */}
        {variant === 'detail' && (
          <div style={{
            margin: '0 14px 14px', background: glass, backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
            borderRadius: 16, border: `0.5px solid ${t.rule}`, padding: '15px 17px', boxShadow: '0 8px 28px rgba(0,0,0,0.18)',
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 13 }}>
              <span style={{ fontFamily: ST_SERIF, fontStyle: 'italic', fontSize: 16, color: t.ink }}>Pride and Prejudice</span>
              <span style={{ fontFamily: ST_SANS, fontSize: 12, color: t.sub }}>42% · Ch. 34</span>
            </div>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '13px 10px' }}>
              {[['This session', '24m'], ['Total in book', '12h 18m'], ['Left in chapter', '~6m'], ['Left in book', '~9h 40m']].map(([k, v]) => (
                <div key={k}>
                  <div style={{ fontFamily: ST_SANS, fontSize: 11.5, color: t.sub }}>{k}</div>
                  <div style={{ fontFamily: ST_SERIF, fontSize: 20, fontWeight: 700, color: t.ink, marginTop: 1, fontVariantNumeric: 'tabular-nums' }}>{v}</div>
                </div>
              ))}
            </div>
            <div style={{ marginTop: 14, display: 'flex', alignItems: 'center', gap: 8, fontFamily: ST_SANS, fontSize: 11.5, color: t.sub }}>
              <span style={{ width: 8, height: 8, borderRadius: 4, background: t.accent }} />
              Reading pace 248 wpm · faster than your average
            </div>
          </div>
        )}
      </div>
    </window.TtsFrame>
  );
}

// ── B · stats dashboard ──────────────────────────────────────
function TimeWindowBar({ ui, active = '30d' }) {
  const w = ['Today', '7d', '30d', '90d', 'Year', 'All'];
  return (
    <div className="hide-scroll" style={{ display: 'flex', gap: 7, overflowX: 'auto', padding: '2px 0 2px' }}>
      {w.map((k) => {
        const on = k === active;
        return (
          <span key={k} style={{
            flexShrink: 0, fontFamily: ST_SANS, fontSize: 13, fontWeight: on ? 700 : 500,
            color: on ? ui.bg : ui.ink, background: on ? ui.ink : (ui.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)'),
            borderRadius: 100, padding: '7px 14px',
          }}>{k}</span>
        );
      })}
    </div>
  );
}

function DailyChart({ ui, empty }) {
  const max = Math.max(...DAILY);
  return (
    <Card ui={ui} style={{ padding: '14px 15px 12px', marginTop: 12 }}>
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'baseline', marginBottom: 12 }}>
        <span style={{ fontFamily: ST_SANS, fontSize: 13, fontWeight: 600, color: ui.ink }}>Daily reading</span>
        <span style={{ fontFamily: ST_SANS, fontSize: 11.5, color: ui.sec }}>last 14 days</span>
      </div>
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 5, height: 88 }}>
        {DAILY.map((m, i) => (
          <div key={i} style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', height: '100%' }}>
            <div style={{
              height: empty ? 2 : `${Math.max(4, (m / max) * 100)}%`,
              background: empty ? ui.sep : (i === DAILY.length - 1 ? ui.tint : (ui.isDark ? 'rgba(214,136,90,0.45)' : 'rgba(140,47,47,0.32)')),
              borderRadius: 3,
            }} />
          </div>
        ))}
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 8, fontFamily: ST_SANS, fontSize: 10.5, color: ui.ter }}>
        <span>2 wks ago</span><span>Today</span>
      </div>
    </Card>
  );
}

function PerBookTable({ ui, empty }) {
  const Th = ({ children, active, right }) => (
    <div style={{ display: 'flex', alignItems: 'center', gap: 3, justifyContent: right ? 'flex-end' : 'flex-start', color: active ? ui.tint : ui.sec, fontFamily: ST_SANS, fontSize: 11.5, fontWeight: 600 }}>
      {children}{active && <svg width="9" height="9" viewBox="0 0 12 12" fill="none" stroke={ui.tint} strokeWidth="2" strokeLinecap="round"><path d="M3 5l3 3 3-3"/></svg>}
    </div>
  );
  return (
    <Card ui={ui} style={{ padding: '13px 15px 6px', marginTop: 12 }}>
      <div style={{ display: 'grid', gridTemplateColumns: '1fr 70px 34px 34px', gap: 8, paddingBottom: 9, borderBottom: `0.5px solid ${ui.sep}` }}>
        <Th>Book</Th><Th right active>Time</Th><Th right>Hl</Th><Th right>Nt</Th>
      </div>
      {(empty ? [] : PERBOOK).map((b, i) => {
        const maxM = PERBOOK[0].mins;
        return (
          <div key={i} style={{ padding: '11px 0 10px', borderBottom: i < PERBOOK.length - 1 ? `0.5px solid ${ui.sep}` : 'none' }}>
            <div style={{ display: 'grid', gridTemplateColumns: '1fr 70px 34px 34px', gap: 8, alignItems: 'center' }}>
              <div style={{ fontFamily: ST_SERIF, fontSize: 14, color: ui.ink, lineHeight: 1.2, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{b.t}</div>
              <div style={{ textAlign: 'right', fontFamily: ST_SANS, fontSize: 13, fontWeight: 600, color: ui.ink, fontVariantNumeric: 'tabular-nums' }}>{b.time}</div>
              <div style={{ textAlign: 'right', fontFamily: ST_SANS, fontSize: 13, color: ui.sec, fontVariantNumeric: 'tabular-nums' }}>{b.hl}</div>
              <div style={{ textAlign: 'right', fontFamily: ST_SANS, fontSize: 13, color: ui.sec, fontVariantNumeric: 'tabular-nums' }}>{b.nt}</div>
            </div>
            <div style={{ height: 3, borderRadius: 2, background: ui.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(29,26,20,0.06)', marginTop: 8 }}>
              <div style={{ height: '100%', width: `${(b.mins / maxM) * 100}%`, background: ui.tint, borderRadius: 2, opacity: 0.7 }} />
            </div>
          </div>
        );
      })}
      {empty && <div style={{ padding: '24px 0', textAlign: 'center', fontFamily: ST_SANS, fontSize: 13.5, color: ui.ter }}>No books opened yet</div>}
    </Card>
  );
}

function StatsDashboard({ ui, state = 'populated', height = 880 }) {
  const empty = state === 'nodata';
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title="Reading Stats"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: ST_SANS, fontSize: 15, color: ui.sec }}>Close</button>}
        trailing={<window.Icons.Share size={20} color={ui.tint} />}
        height={height - 36}>
        <div style={{ padding: '14px 16px 32px' }}>
          <TimeWindowBar ui={ui} active="30d" />

          {/* hero */}
          <Card ui={ui} style={{ padding: '18px 17px', marginTop: 12 }}>
            <div style={{ fontFamily: ST_SANS, fontSize: 12, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', color: ui.sec }}>This month</div>
            <div style={{ fontFamily: ST_SERIF, fontSize: 44, fontWeight: 700, color: ui.ink, lineHeight: 1, margin: '6px 0 2px', fontVariantNumeric: 'tabular-nums' }}>
              {empty ? '0m' : '41h 12m'}
            </div>
            {empty ? (
              <div style={{ fontFamily: ST_SANS, fontSize: 13.5, color: ui.sec, marginTop: 6, lineHeight: 1.5 }}>Open a book to start tracking. Your reading time, streak, and per-book breakdown will show up here.</div>
            ) : (
              <div style={{ display: 'flex', gap: 18, marginTop: 14 }}>
                {[['Streak', '9 days'], ['Daily avg', '1h 22m'], ['Finished', '3 books']].map(([k, v]) => (
                  <div key={k}>
                    <div style={{ fontFamily: ST_SERIF, fontSize: 18, fontWeight: 700, color: ui.ink, fontVariantNumeric: 'tabular-nums' }}>{v}</div>
                    <div style={{ fontFamily: ST_SANS, fontSize: 11, color: ui.sec, marginTop: 1 }}>{k}</div>
                  </div>
                ))}
              </div>
            )}
          </Card>

          <DailyChart ui={ui} empty={empty} />

          <div style={{ fontFamily: ST_SANS, fontSize: 12, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: ui.sec, margin: '20px 2px 0' }}>By book</div>
          <PerBookTable ui={ui} empty={empty} />
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

Object.assign(window, { InReaderTime, StatsDashboard, TimeWindowBar, DailyChart, PerBookTable });
