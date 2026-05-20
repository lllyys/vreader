// Canvas artboards for the two stats-dashboard follow-up issues:
//
//   #1058 — Custom date-range picker for the StatsTimeWindowBar
//   #1059 — `Last read` 5th sortable column for SortablePerBookTable
//
// Both surfaces hang off the FullStatsDashboard committed in vreader-profile-stats.jsx.
// We do not redraw the dashboard hero or daily-chart; those are linked-in via PhoneFrame.

const PHONE_W = 402;
const FB = (typeof BOOKS !== 'undefined' && BOOKS.find(b => b.id === 'pp')) || null;

// ────────────────────────────────────────────────────
// Local PhoneFrame (each babel script has its own scope; redeclaring is safe)
// ────────────────────────────────────────────────────
function StatsPhoneFrame({ themeKey = 'paper', height = 720, children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>{children}</div>
  );
}

// Status-bar mock for atop sheets
function FauxStatusBar({ t }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, height: 44,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 22px', fontSize: 14, fontWeight: 600, color: t.ink, zIndex: 5,
      pointerEvents: 'none',
    }}>
      <span>9:41</span>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 4, opacity: 0.85 }}>
        <Icons.Wifi size={14} color={t.ink} stroke={1.8}/>
        <span style={{ width: 22, height: 11, borderRadius: 2, border: `1px solid ${t.ink}`, opacity: 0.6, position: 'relative', display: 'inline-block' }}>
          <span style={{ position: 'absolute', inset: 1.5, right: 6, background: t.ink, borderRadius: 1 }}/>
        </span>
      </span>
    </div>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// Section A — #1058 Custom date-range picker
//
// Canonical = paper sub-sheet that slides up over the dashboard sheet. The
// month grid is the load-bearing element; quick-presets are a thin rail at the
// top so the canonical 7-day/14-day cases stay 1-tap.
//
// The TIME_WINDOWS array (from vreader-profile-stats.jsx) is extended so the
// 'custom' pill knows its applied range and renders an inline summary.
// ════════════════════════════════════════════════════════════════════════════

// ---- Calendar primitives ---------------------------------------------------

// Local 'today' baseline that matches the design's sample data
const TODAY = { y: 2026, m: 4 /* May, 0-indexed */, d: 20 };
const MONTH_NAMES = ['January', 'February', 'March', 'April', 'May', 'June',
                     'July', 'August', 'September', 'October', 'November', 'December'];
const DOW = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

function daysIn(y, m) { return new Date(y, m + 1, 0).getDate(); }
function dowOf(y, m, d) { // Monday=0…Sunday=6
  return (new Date(y, m, d).getDay() + 6) % 7;
}
function ymdKey(y, m, d) { return `${y}-${String(m).padStart(2,'0')}-${String(d).padStart(2,'0')}`; }
function cmp(a, b) {
  if (a.y !== b.y) return a.y - b.y;
  if (a.m !== b.m) return a.m - b.m;
  return a.d - b.d;
}
function fmtShort(d, opts = {}) {
  if (!d) return '—';
  return `${MONTH_NAMES[d.m].slice(0,3)} ${d.d}${opts.year ? `, ${d.y}` : ''}`;
}

// Read-activity heatmap density per day — drives the "has sessions" dot under
// dates. Deterministic from ymdKey so the same dates render identically across
// artboards.
function readDensity(y, m, d) {
  const h = (y * 31 + (m + 1) * 17 + d * 7) % 11;
  if (h < 3) return 0;     // no sessions
  if (h < 7) return 1;     // light
  if (h < 10) return 2;    // medium
  return 3;                // heavy
}

function MonthGrid({ theme, year, month, start, end, hover, error,
                     onPick, onHover }) {
  const t = theme;
  const dim = daysIn(year, month);
  const offset = dowOf(year, month, 1);
  const cells = [];
  for (let i = 0; i < offset; i++) cells.push(null);
  for (let d = 1; d <= dim; d++) cells.push(d);
  while (cells.length % 7) cells.push(null);

  // Range membership: range is [start, end OR hover]
  const rangeEnd = end || (start && hover && cmp(hover, start) > 0 ? hover : null);
  const inRange = (d) => {
    if (!d || !start) return false;
    const here = { y: year, m: month, d };
    const a = cmp(here, start);
    const b = rangeEnd ? cmp(here, rangeEnd) : null;
    if (!rangeEnd) return a === 0;
    return a >= 0 && b <= 0;
  };
  const isStart = (d) => d && start && start.y === year && start.m === month && start.d === d;
  const isEnd   = (d) => d && end   && end.y   === year && end.m   === month && end.d   === d;
  const isToday = (d) => d && TODAY.y === year && TODAY.m === month && TODAY.d === d;
  const isFuture = (d) => d && cmp({ y: year, m: month, d }, TODAY) > 0;

  return (
    <div>
      {/* DoW row */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)',
        padding: '0 4px 4px', columnGap: 0,
      }}>
        {DOW.map((c, i) => (
          <div key={i} style={{
            textAlign: 'center', fontSize: 10, color: t.sub, fontWeight: 600,
            letterSpacing: 0.5, textTransform: 'uppercase',
          }}>{c}</div>
        ))}
      </div>
      {/* Day grid */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(7, 1fr)', columnGap: 0, rowGap: 2,
        padding: '0 4px',
      }}>
        {cells.map((d, i) => {
          if (!d) return <div key={i}/>;
          const future = isFuture(d);
          const inR    = inRange(d);
          const s      = isStart(d);
          const e      = isEnd(d);
          const today  = isToday(d);
          const dens   = readDensity(year, month, d);
          // Range "rail" continuity: don't round the inside edges so the run
          // looks like a continuous bar.
          const isLeftEnd  = s || (inR && (i % 7 === 0 || cells[i - 1] === null));
          const isRightEnd = e || (inR && (i % 7 === 6 || cells[i + 1] === null));
          return (
            <button key={i} disabled={future}
              onMouseEnter={() => onHover?.({ y: year, m: month, d })}
              onClick={() => onPick?.({ y: year, m: month, d })}
              style={{
                position: 'relative', height: 36, padding: 0, border: 'none',
                background: inR && !s && !e
                  ? (t.isDark ? `${t.accent}25` : `${t.accent}1c`)
                  : 'transparent',
                borderTopLeftRadius:    isLeftEnd  ? 18 : 0,
                borderBottomLeftRadius: isLeftEnd  ? 18 : 0,
                borderTopRightRadius:   isRightEnd ? 18 : 0,
                borderBottomRightRadius:isRightEnd ? 18 : 0,
                cursor: future ? 'not-allowed' : 'pointer',
                fontFamily: 'inherit',
                opacity: future ? 0.32 : 1,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
              {/* selected endpoint dot */}
              {(s || e) && (
                <div style={{
                  position: 'absolute', inset: 1,
                  borderRadius: 18,
                  background: error ? '#c44' : t.accent,
                }}/>
              )}
              <span style={{
                position: 'relative', zIndex: 1,
                fontSize: 13.5,
                fontFeatureSettings: '"tnum" 1',
                fontVariantNumeric: 'tabular-nums',
                fontWeight: s || e ? 600 : (today ? 600 : 500),
                color: s || e
                  ? (t.isDark ? '#1a1815' : '#fcf8f0')
                  : (today ? t.accent : t.ink),
              }}>{d}</span>
              {/* read-density dot */}
              {dens > 0 && !s && !e && (
                <span style={{
                  position: 'absolute', bottom: 4, left: '50%',
                  transform: 'translateX(-50%)',
                  width: 4, height: 4, borderRadius: 2,
                  background: t.accent,
                  opacity: future ? 0 : (dens === 3 ? 0.9 : dens === 2 ? 0.55 : 0.28),
                }}/>
              )}
            </button>
          );
        })}
      </div>
    </div>
  );
}

// ---- Date chip (Start / End) ----------------------------------------------
function DateChip({ theme, label, value, active, error, placeholder = 'Select', onClick }) {
  const t = theme;
  const filled = !!value;
  return (
    <button onClick={onClick} style={{
      flex: 1, textAlign: 'left',
      padding: '10px 14px',
      borderRadius: 12,
      background: active
        ? (t.isDark ? 'rgba(214,136,90,0.12)' : `${t.accent}10`)
        : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
      border: 'none',
      boxShadow: active
        ? `inset 0 0 0 1.5px ${error ? '#c44' : t.accent}`
        : `inset 0 0 0 0.5px ${t.rule}`,
      cursor: 'pointer', fontFamily: 'inherit',
    }}>
      <div style={{
        fontSize: 10, color: active ? (error ? '#c44' : t.accent) : t.sub,
        fontWeight: 600, letterSpacing: 0.6, textTransform: 'uppercase',
      }}>{label}</div>
      <div style={{
        marginTop: 3,
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 18, fontWeight: 600,
        color: filled ? t.ink : t.sub,
        letterSpacing: -0.2,
        fontVariantNumeric: 'tabular-nums',
      }}>{filled ? fmtShort(value, { year: true }) : placeholder}</div>
    </button>
  );
}

// ---- Quick-preset rail ----------------------------------------------------
const QUICK_PRESETS = [
  'Last 7 days',
  'Last 14 days',
  'This month',
  'Last month',
  'This year',
  'All time',
];

function QuickPresetRail({ theme, value, onChange }) {
  const t = theme;
  return (
    <div className="hide-scroll" style={{
      display: 'flex', gap: 6, overflowX: 'auto',
      padding: '0 18px 4px',
    }}>
      {QUICK_PRESETS.map(p => {
        const on = p === value;
        return (
          <button key={p} onClick={() => onChange?.(p)} style={{
            padding: '6px 12px', borderRadius: 100,
            border: 'none', whiteSpace: 'nowrap',
            background: on
              ? (t.isDark ? 'rgba(214,136,90,0.18)' : `${t.accent}14`)
              : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
            color: on ? t.accent : t.ink,
            fontFamily: 'inherit', fontSize: 12.5, fontWeight: on ? 600 : 500,
            cursor: 'pointer',
          }}>{p}</button>
        );
      })}
    </div>
  );
}

// ---- The picker sheet (canonical) -----------------------------------------
function CustomRangePickerSheet({ theme, state = 'empty', onClose,
                                  start: pStart, end: pEnd,
                                  hover: pHover, viewMonth = 4, viewYear = 2026,
                                  error = null, sessions = null }) {
  const t = theme;
  const start = pStart === undefined ? null : pStart;
  const end   = pEnd   === undefined ? null : pEnd;

  // Bottom summary text depends on state
  let summary = null;
  if (state === 'empty') summary = (
    <span style={{ color: t.sub }}>Pick a start date to begin.</span>
  );
  else if (state === 'picking-end') summary = (
    <span style={{ color: t.sub }}>Pick an end date.</span>
  );
  else if (state === 'error') summary = (
    <span style={{ color: '#c44' }}>{error}</span>
  );
  else if (state === 'no-results') summary = (
    <span style={{ color: t.sub }}>
      No reading sessions in this range. {sessions != null && `· 0h 0m`}
    </span>
  );
  else if (state === 'applied') summary = (
    <span style={{ color: t.ink, fontWeight: 500 }}>
      <span style={{ color: t.sub }}>This range · </span>
      {sessions?.days ?? 14} days · {sessions?.label ?? '11h 23m'} read
    </span>
  );

  const canApply = !!(start && end) && state !== 'error';

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      borderTopLeftRadius: 22, borderTopRightRadius: 22,
      background: t.isDark ? '#222020' : '#fcf8f0',
      boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
      maxHeight: '92%', display: 'flex', flexDirection: 'column',
      overflow: 'hidden',
    }}>
      {/* grabber */}
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
        <div style={{
          width: 36, height: 5, borderRadius: 3,
          background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
        }}/>
      </div>
      {/* title bar */}
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '12px 16px 14px',
        borderBottom: `0.5px solid ${t.rule}`,
      }}>
        <button onClick={onClose} style={{
          background: 'none', border: 'none', padding: 0, cursor: 'pointer',
          color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
        }}>Cancel</button>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 17, fontWeight: 600, color: t.ink,
        }}>Custom range</div>
        <button disabled={!canApply} style={{
          background: 'none', border: 'none', padding: 0,
          cursor: canApply ? 'pointer' : 'default',
          color: canApply ? t.accent : t.sub,
          fontFamily: 'inherit', fontSize: 15, fontWeight: 600,
        }}>Apply</button>
      </div>
      {/* Date chips */}
      <div style={{ display: 'flex', gap: 8, padding: '14px 18px 10px' }}>
        <DateChip theme={t} label="Start" value={start}
          active={state === 'empty' || state === 'picking-start'} error={state === 'error'}/>
        <div style={{ display: 'flex', alignItems: 'center', color: t.sub, fontSize: 16, padding: '0 2px' }}>→</div>
        <DateChip theme={t} label="End" value={end}
          active={state === 'picking-end' || state === 'error'} error={state === 'error'}
          placeholder={start ? 'Pick end' : '—'}/>
      </div>
      {/* preset rail */}
      <QuickPresetRail theme={t} value={state === 'applied' && sessions?.preset}/>
      {/* Month header + grid */}
      <div style={{ padding: '12px 18px 4px' }}>
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          marginBottom: 8,
        }}>
          <button style={{
            width: 32, height: 32, borderRadius: 16, border: 'none',
            background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.ChevronL size={15} color={t.ink} stroke={2}/>
          </button>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 16, fontWeight: 600, color: t.ink, fontStyle: 'italic',
          }}>{MONTH_NAMES[viewMonth]} {viewYear}</div>
          <button style={{
            width: 32, height: 32, borderRadius: 16, border: 'none',
            background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
            cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Chevron size={15} color={t.ink} stroke={2}/>
          </button>
        </div>
        <MonthGrid theme={t} year={viewYear} month={viewMonth}
          start={start} end={end} hover={pHover} error={state === 'error'}/>
      </div>
      {/* summary bar */}
      <div style={{
        marginTop: 'auto',
        padding: '14px 18px 22px',
        borderTop: `0.5px solid ${t.rule}`,
        fontSize: 12.5,
        display: 'flex', alignItems: 'center', gap: 8,
      }}>
        {state === 'error' && (
          <div style={{
            width: 18, height: 18, borderRadius: 9, background: '#c44',
            color: '#fff', fontSize: 11, fontWeight: 700,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>!</div>
        )}
        {state === 'applied' && (
          <div style={{
            width: 16, height: 16, borderRadius: 8, background: t.accent,
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Check size={11} color={t.isDark ? '#1a1815' : '#fcf8f0'} stroke={3}/>
          </div>
        )}
        {summary}
      </div>
    </div>
  );
}

// ---- Mini dashboard underlay (so the picker has a paper sheet behind it) --
function MiniDashboardUnderlay({ theme, customLabel }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', inset: 0,
      background: t.isDark ? '#222020' : '#fcf8f0',
      borderTopLeftRadius: 22, borderTopRightRadius: 22,
      overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
        <div style={{
          width: 36, height: 5, borderRadius: 3,
          background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
        }}/>
      </div>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '14px 18px 12px',
        borderBottom: `0.5px solid ${t.rule}`,
      }}>
        <span style={{ width: 40 }}/>
        <span style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 17, fontWeight: 600, color: t.ink,
        }}>Reading</span>
        <span style={{ color: t.accent, fontSize: 15, fontWeight: 500 }}>Done</span>
      </div>
      <ExtendedTimeWindowBar theme={t} value="custom" customLabel={customLabel}/>
      <div style={{ padding: '18px 18px 10px' }}>
        <div style={{
          fontSize: 11, color: t.sub, fontWeight: 600,
          letterSpacing: 0.8, textTransform: 'uppercase',
        }}>Reading time, {customLabel ? customLabel.toLowerCase() : 'custom range'}</div>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 40, fontWeight: 600, color: t.ink,
          letterSpacing: -1, lineHeight: 1, marginTop: 4,
        }}>11h <span style={{ color: t.sub, fontSize: 16 }}>· </span>23min</div>
      </div>
    </div>
  );
}

// Extended bar that supports the long Custom-with-range pill
function ExtendedTimeWindowBar({ theme, value, customLabel }) {
  const t = theme;
  return (
    <div className="hide-scroll" style={{
      display: 'flex', overflowX: 'auto', gap: 4,
      padding: '4px 18px',
      borderBottom: `0.5px solid ${t.rule}`,
    }}>
      {['Today','7d','30d','90d','Year','All'].map(k => (
        <button key={k} style={{
          padding: '7px 12px', borderRadius: 100, border: 'none',
          background: 'transparent', color: t.ink,
          fontFamily: 'inherit', fontSize: 12.5, fontWeight: 500,
          cursor: 'pointer', whiteSpace: 'nowrap',
        }}>{k}</button>
      ))}
      {/* extended Custom pill */}
      <button style={{
        padding: '7px 12px', borderRadius: 100, border: 'none',
        background: value === 'custom' ? t.ink : 'transparent',
        color: value === 'custom' ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
        fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600,
        cursor: 'pointer', whiteSpace: 'nowrap',
        display: 'inline-flex', alignItems: 'center', gap: 6,
      }}>
        <Icons.Settings size={12}
          color={value === 'custom' ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.sub}
          stroke={1.8}/>
        {customLabel ? (
          <>
            <span>Custom</span>
            <span style={{ opacity: 0.55, fontWeight: 500 }}>·</span>
            <span style={{ fontWeight: 500, fontVariantNumeric: 'tabular-nums' }}>{customLabel}</span>
          </>
        ) : 'Custom'}
      </button>
    </div>
  );
}

// ---- Picker artboard wrapper ----------------------------------------------
function RangePickerArtboard({ themeKey = 'paper', state = 'empty',
                               start, end, hover, error,
                               viewYear = 2026, viewMonth = 4,
                               customLabel = null, sessions }) {
  const t = THEMES[themeKey];
  return (
    <StatsPhoneFrame themeKey={themeKey} height={780}>
      <MiniDashboardUnderlay theme={t} customLabel={customLabel}/>
      <FauxStatusBar t={t}/>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.18)' }}/>
      <CustomRangePickerSheet theme={t}
        state={state} start={start} end={end} hover={hover} error={error}
        viewYear={viewYear} viewMonth={viewMonth} sessions={sessions}/>
    </StatsPhoneFrame>
  );
}

// ---- Applied artboard — picker dismissed, pill reflects range -------------
function AppliedDashboardArtboard({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <StatsPhoneFrame themeKey={themeKey} height={780}>
      <div style={{ position: 'absolute', inset: 0, background: t.isDark ? '#222020' : '#fcf8f0' }}/>
      <FauxStatusBar t={t}/>
      <Sheet theme={t} onClose={() => {}} height={736} title="Reading"
        trailing={<button style={{
          background: 'none', border: 'none', padding: '4px 0',
          color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
          cursor: 'pointer',
        }}>Done</button>}>
        <ExtendedTimeWindowBar theme={t} value="custom" customLabel="May 1 – May 15"/>
        <div style={{ flex: 1, overflow: 'auto', padding: '4px 0 32px' }} className="hide-scroll">
          <div style={{ padding: '16px 18px 8px' }}>
            <div style={{
              fontSize: 11, color: t.sub, fontWeight: 600,
              letterSpacing: 0.8, textTransform: 'uppercase',
            }}>Reading time · May 1 – May 15</div>
            <div style={{ display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4 }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 44, fontWeight: 600, color: t.ink,
                letterSpacing: -1, lineHeight: 1,
              }}>11</div>
              <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 16, color: t.sub, fontWeight: 500 }}>hr</div>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 30, fontWeight: 600, color: t.ink,
                letterSpacing: -0.5, lineHeight: 1, marginLeft: 6,
              }}>23</div>
              <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14, color: t.sub, fontWeight: 500 }}>min</div>
              <div style={{ flex: 1 }}/>
              <div style={{
                fontSize: 11, color: t.sub, fontWeight: 500,
              }}>14 reading days</div>
            </div>
          </div>
          {typeof DailyChart !== 'undefined' && (
            <div style={{ padding: '12px 18px 18px' }}>
              <DailyChart theme={t} data={[22, 0, 41, 38, 15, 0, 52, 67, 28, 19, 44, 71, 33, 58, 0]}/>
            </div>
          )}
          <div style={{ padding: '0 18px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            {typeof StatTile !== 'undefined' && <>
              <StatTile theme={t} label="Reading days" value="14" unit="of 15"   sub="93% of range"/>
              <StatTile theme={t} label="Daily average" value="45" unit="min"     sub="Range avg"/>
            </>}
          </div>
        </div>
      </Sheet>
    </StatsPhoneFrame>
  );
}

// Popover variant — anchored to the Custom pill in the bar, lighter weight.
// Used for narrow custom ranges (≤ 1 month). Falls back to full sheet on overflow.
function RangePickerPopoverArtboard({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <StatsPhoneFrame themeKey={themeKey} height={620}>
      <MiniDashboardUnderlay theme={t} customLabel={null}/>
      <FauxStatusBar t={t}/>
      {/* dim only above the pill bar */}
      <div style={{ position: 'absolute', top: 130, left: 0, right: 0, bottom: 0, background: 'rgba(0,0,0,0.18)' }}/>
      {/* popover */}
      <div style={{
        position: 'absolute', top: 118, right: 18, width: 312,
        borderRadius: 18, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 16px 50px rgba(0,0,0,0.32), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        zIndex: 10,
      }}>
        {/* tail */}
        <div style={{
          position: 'absolute', top: -6, right: 26,
          width: 12, height: 12, transform: 'rotate(45deg)',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}/>
        <div style={{ padding: '12px 14px 4px' }}>
          <div style={{ display: 'flex', gap: 6 }}>
            <DateChip theme={t} label="Start" value={{ y: 2026, m: 4, d: 5 }}/>
            <DateChip theme={t} label="End" value={{ y: 2026, m: 4, d: 15 }} active/>
          </div>
        </div>
        <div style={{ padding: '8px 0 4px' }}>
          <QuickPresetRail theme={t}/>
        </div>
        <div style={{ padding: '4px 6px 10px' }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '0 10px 6px',
          }}>
            <button style={{
              width: 26, height: 26, borderRadius: 13, border: 'none',
              background: 'transparent', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icons.ChevronL size={13} color={t.ink} stroke={2}/>
            </button>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14, fontWeight: 600, color: t.ink, fontStyle: 'italic',
            }}>May 2026</div>
            <button style={{
              width: 26, height: 26, borderRadius: 13, border: 'none',
              background: 'transparent', cursor: 'pointer',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icons.Chevron size={13} color={t.ink} stroke={2}/>
            </button>
          </div>
          <MonthGrid theme={t} year={2026} month={4}
            start={{ y: 2026, m: 4, d: 5 }} end={{ y: 2026, m: 4, d: 15 }}/>
        </div>
        <div style={{
          borderTop: `0.5px solid ${t.rule}`,
          display: 'flex', justifyContent: 'flex-end', gap: 8,
          padding: '10px 14px',
        }}>
          <button style={{
            padding: '6px 14px', borderRadius: 100, border: 'none',
            background: 'transparent', color: t.sub,
            fontFamily: 'inherit', fontSize: 13, fontWeight: 500, cursor: 'pointer',
          }}>Cancel</button>
          <button style={{
            padding: '6px 14px', borderRadius: 100, border: 'none',
            background: t.accent, color: t.isDark ? '#1a1815' : '#fcf8f0',
            fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer',
          }}>Apply</button>
        </div>
      </div>
    </StatsPhoneFrame>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// Section B — #1059 `Last read` 5th column for SortablePerBookTable
//
// Canonical: keep four visible columns. Add `Last read` to the SORT-BY menu.
// When `Last read` is the active sort, the per-row time-bar (which is most
// useful when sorted by time) is swapped for the `Last read` value inline.
// This keeps the iPhone-narrow layout legible without horizontal scroll, and
// makes the new column feel discoverable rather than crammed.
//
// Three variants for compare:
//   1. Canonical (sort-driven swap; 4 columns visible)
//   2. Always-5-columns (compact text)
//   3. Column chooser (popover; swap any one slot)
// ════════════════════════════════════════════════════════════════════════════

const ROWS_WITH_LASTREAD = [
  { id: 'pp',   mins: 738, highlights: 47, notes: 18, lastReadAt: '2h' },
  { id: 'bi',   mins: 587, highlights: 22, notes: 11, lastReadAt: '1d' },
  { id: 'ddia', mins: 431, highlights: 31, notes: 4,  lastReadAt: '3d' },
  { id: 'prag', mins: 332, highlights: 12, notes: 7,  lastReadAt: '6d' },
  { id: 'med',  mins: 204, highlights: 18, notes: 9,  lastReadAt: '12d' },
  { id: '3b',   mins: 173, highlights: 6,  notes: 2,  lastReadAt: '5w' },
  { id: 'tfs',  mins: 28,  highlights: 0,  notes: 0,  lastReadAt: null },
];

function bookFor(id) {
  return (typeof BOOKS !== 'undefined' && BOOKS.find(b => b.id === id))
    || { id, title: id, cover: { bg: '#5a3a3a', ink: '#fff' } };
}

// ---- Sort menu popover (canonical) ----------------------------------------
const SORT_OPTIONS = [
  { k: 'title',      label: 'Title' },
  { k: 'mins',       label: 'Reading time' },
  { k: 'highlights', label: 'Highlights' },
  { k: 'notes',      label: 'Notes' },
  { k: 'lastRead',   label: 'Last read', new: true },
];

function SortMenu({ theme, value = 'mins', dir = 'desc', open = true, x = 12, y = 36 }) {
  const t = theme;
  if (!open) return null;
  return (
    <div style={{
      position: 'absolute', right: x, top: y, width: 220,
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? '#2a2724' : '#fcf8f0',
      boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      zIndex: 30, padding: '4px 0',
      animation: 'popIn 0.18s cubic-bezier(.32,.72,0,1)',
    }}>
      {/* tail */}
      <div style={{
        position: 'absolute', top: -6, right: 18,
        width: 12, height: 12, transform: 'rotate(45deg)',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      }}/>
      <div style={{
        padding: '8px 14px 4px',
        fontSize: 10, color: t.sub, fontWeight: 600,
        letterSpacing: 0.6, textTransform: 'uppercase',
      }}>Sort by</div>
      {SORT_OPTIONS.map(o => {
        const on = o.k === value;
        return (
          <div key={o.k} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '10px 14px',
            background: on ? (t.isDark ? `${t.accent}1a` : `${t.accent}0e`) : 'transparent',
          }}>
            <div style={{ width: 14, display: 'flex', justifyContent: 'center' }}>
              {on && <Icons.Check size={13} color={t.accent} stroke={2.4}/>}
            </div>
            <div style={{ flex: 1, fontSize: 14, color: on ? t.accent : t.ink, fontWeight: on ? 600 : 500 }}>
              {o.label}
            </div>
            {o.new && !on && (
              <div style={{
                fontSize: 9, fontWeight: 700, padding: '2px 6px', borderRadius: 100,
                background: t.isDark ? 'rgba(214,136,90,0.18)' : `${t.accent}14`,
                color: t.accent, letterSpacing: 0.5,
              }}>NEW</div>
            )}
            {on && (
              <div style={{
                fontSize: 10, color: t.sub, fontWeight: 600,
                letterSpacing: 0.5, textTransform: 'uppercase',
              }}>{dir}</div>
            )}
          </div>
        );
      })}
    </div>
  );
}

// ---- Canonical table — Last-read shown when it's active sort --------------
function PerBookTableV2({ theme, rows = ROWS_WITH_LASTREAD, sortCol = 'mins', dir = 'desc' }) {
  const t = theme;
  const sorted = [...rows].sort((a, b) => {
    if (sortCol === 'lastRead') {
      // null sorts to bottom regardless of dir
      if (a.lastReadAt === null && b.lastReadAt !== null) return 1;
      if (b.lastReadAt === null && a.lastReadAt !== null) return -1;
      if (a.lastReadAt === null && b.lastReadAt === null) return 0;
      const order = ['2h', '1d', '3d', '6d', '12d', '5w'];
      return (order.indexOf(a.lastReadAt) - order.indexOf(b.lastReadAt)) * (dir === 'desc' ? 1 : -1);
    }
    return (b[sortCol] - a[sortCol]) * (dir === 'desc' ? 1 : -1);
  });
  const max = Math.max(...rows.map(r => r.mins), 1);
  const showLastReadInline = sortCol === 'lastRead';

  const Header = ({ col, label, align = 'right' }) => {
    const active = col === sortCol;
    return (
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 3,
        fontSize: 10.5, fontWeight: 600,
        color: active ? t.ink : t.sub,
        letterSpacing: 0.5, textTransform: 'uppercase',
        justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      }}>
        <span>{label}</span>
        {active && (
          <svg width="8" height="8" viewBox="0 0 8 8">
            <path d={dir === 'desc' ? 'M1 2l3 4 3-4' : 'M1 6l3-4 3 4'}
              stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
          </svg>
        )}
      </div>
    );
  };

  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
    }}>
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 70px 38px 38px',
        padding: '10px 14px',
        borderBottom: `0.5px solid ${t.rule}`,
        alignItems: 'center', columnGap: 8,
      }}>
        <Header col="title" label="Book" align="left"/>
        <Header col="mins" label="Time"/>
        <Header col="highlights" label="Hl"/>
        <Header col="notes" label="Nt"/>
      </div>
      {sorted.map((r, i) => {
        const book = bookFor(r.id);
        const hrs = Math.floor(r.mins / 60), m = r.mins % 60;
        const isNullLR = r.lastReadAt === null;
        return (
          <div key={r.id} style={{
            display: 'grid', gridTemplateColumns: '1fr 70px 38px 38px',
            padding: '10px 14px',
            borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
            alignItems: 'center', columnGap: 8,
            opacity: isNullLR && showLastReadInline ? 0.55 : 1,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              {typeof BookCover !== 'undefined' && book.cover &&
                <BookCover book={book} width={24} height={34} radius={2}/>}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 13, fontWeight: 600, color: t.ink,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>{book.title}</div>
                {showLastReadInline ? (
                  <div style={{
                    marginTop: 3,
                    display: 'inline-flex', alignItems: 'center', gap: 5,
                    fontSize: 10.5, color: isNullLR ? t.sub : t.accent, fontWeight: 600,
                    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                    letterSpacing: 0.3,
                  }}>
                    <span style={{
                      width: 4, height: 4, borderRadius: 2,
                      background: isNullLR ? t.sub : t.accent, opacity: isNullLR ? 0.4 : 1,
                    }}/>
                    {r.lastReadAt ? `Last read · ${r.lastReadAt} ago` : 'No sessions recorded'}
                  </div>
                ) : (
                  <div style={{
                    marginTop: 3, height: 3, borderRadius: 2,
                    background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
                    position: 'relative',
                  }}>
                    <div style={{
                      position: 'absolute', left: 0, top: 0, bottom: 0,
                      width: `${(r.mins / max) * 100}%`, background: t.accent,
                      borderRadius: 2,
                    }}/>
                  </div>
                )}
              </div>
            </div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: t.sub, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{hrs > 0 ? `${hrs}h ${String(m).padStart(2, '0')}` : `${m}m`}</div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: r.highlights ? t.ink : t.sub, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{r.highlights || '—'}</div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: r.notes ? t.ink : t.sub, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{r.notes || '—'}</div>
          </div>
        );
      })}
    </div>
  );
}

// ---- Alt 1 — always-5-columns, compact text -------------------------------
function PerBookTableAllFive({ theme, rows = ROWS_WITH_LASTREAD, sortCol = 'lastRead', dir = 'desc' }) {
  const t = theme;
  const sorted = [...rows].sort((a, b) => {
    if (sortCol === 'lastRead') {
      if (a.lastReadAt === null) return 1;
      if (b.lastReadAt === null) return -1;
      const order = ['2h', '1d', '3d', '6d', '12d', '5w'];
      return order.indexOf(a.lastReadAt) - order.indexOf(b.lastReadAt);
    }
    return (b[sortCol] - a[sortCol]) * (dir === 'desc' ? 1 : -1);
  });
  const max = Math.max(...rows.map(r => r.mins), 1);
  const cols = '1fr 54px 30px 30px 44px';

  const Header = ({ col, label, align = 'right' }) => {
    const active = col === sortCol;
    return (
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 3,
        fontSize: 9.5, fontWeight: 600,
        color: active ? t.ink : t.sub,
        letterSpacing: 0.5, textTransform: 'uppercase',
        justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      }}>
        <span>{label}</span>
        {active && (
          <svg width="7" height="7" viewBox="0 0 8 8">
            <path d={dir === 'desc' ? 'M1 2l3 4 3-4' : 'M1 6l3-4 3 4'}
              stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
          </svg>
        )}
      </div>
    );
  };

  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
    }}>
      <div style={{
        display: 'grid', gridTemplateColumns: cols,
        padding: '10px 12px',
        borderBottom: `0.5px solid ${t.rule}`,
        alignItems: 'center', columnGap: 6,
      }}>
        <Header col="title" label="Book" align="left"/>
        <Header col="mins" label="Time"/>
        <Header col="highlights" label="Hl"/>
        <Header col="notes" label="Nt"/>
        <Header col="lastRead" label="Read"/>
      </div>
      {sorted.map((r, i) => {
        const book = bookFor(r.id);
        const hrs = Math.floor(r.mins / 60), m = r.mins % 60;
        const timeStr = hrs > 0 ? `${hrs}h${String(m).padStart(2, '0')}` : `${m}m`;
        return (
          <div key={r.id} style={{
            display: 'grid', gridTemplateColumns: cols,
            padding: '10px 12px',
            borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
            alignItems: 'center', columnGap: 6,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
              {typeof BookCover !== 'undefined' && book.cover &&
                <BookCover book={book} width={20} height={28} radius={2}/>}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 12, fontWeight: 600, color: t.ink,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>{book.title}</div>
                <div style={{
                  marginTop: 3, height: 2.5, borderRadius: 2,
                  background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
                  position: 'relative',
                }}>
                  <div style={{
                    position: 'absolute', left: 0, top: 0, bottom: 0,
                    width: `${(r.mins / max) * 100}%`, background: t.accent,
                    borderRadius: 2,
                  }}/>
                </div>
              </div>
            </div>
            {[timeStr, r.highlights || '—', r.notes || '—',
              r.lastReadAt ? `${r.lastReadAt}` : '—'].map((v, j) => (
              <div key={j} style={{
                textAlign: 'right',
                fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                fontSize: 11, color: (j > 0 && v === '—') ? t.sub : t.ink, fontWeight: 500,
                fontVariantNumeric: 'tabular-nums',
              }}>{v}</div>
            ))}
          </div>
        );
      })}
    </div>
  );
}

// ---- Alt 2 — column chooser (per-slot swap) -------------------------------
function PerBookTableColumnChooser({ theme, slotColumn = 'lastRead', rows = ROWS_WITH_LASTREAD, sortCol = 'mins', dir = 'desc' }) {
  const t = theme;
  const sorted = [...rows].sort((a, b) => {
    if (sortCol === 'lastRead') {
      if (a.lastReadAt === null) return 1;
      if (b.lastReadAt === null) return -1;
      const order = ['2h', '1d', '3d', '6d', '12d', '5w'];
      return order.indexOf(a.lastReadAt) - order.indexOf(b.lastReadAt);
    }
    return (b[sortCol] - a[sortCol]) * (dir === 'desc' ? 1 : -1);
  });
  const max = Math.max(...rows.map(r => r.mins), 1);

  // Slot label/value resolver
  const slotLabel = { highlights: 'Hl', notes: 'Nt', lastRead: 'Last', mins: 'Time' }[slotColumn];
  const slotVal = (r) => {
    if (slotColumn === 'highlights') return r.highlights || '—';
    if (slotColumn === 'notes')      return r.notes      || '—';
    if (slotColumn === 'mins') {
      const h = Math.floor(r.mins/60), mm = r.mins%60;
      return h > 0 ? `${h}h${String(mm).padStart(2,'0')}` : `${mm}m`;
    }
    return r.lastReadAt ? r.lastReadAt : '—';
  };

  const Header = ({ col, label, slot = false, align = 'right' }) => {
    const active = col === sortCol;
    return (
      <div style={{
        display: 'inline-flex', alignItems: 'center', gap: 3,
        fontSize: 10.5, fontWeight: 600,
        color: active ? t.ink : t.sub,
        letterSpacing: 0.5, textTransform: 'uppercase',
        justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      }}>
        <span>{label}</span>
        {slot && <Icons.ChevronD size={9} color={t.sub} stroke={2}/>}
        {active && !slot && (
          <svg width="8" height="8" viewBox="0 0 8 8">
            <path d={dir === 'desc' ? 'M1 2l3 4 3-4' : 'M1 6l3-4 3 4'}
              stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
          </svg>
        )}
      </div>
    );
  };

  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
    }}>
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 70px 38px 50px',
        padding: '10px 14px',
        borderBottom: `0.5px solid ${t.rule}`,
        alignItems: 'center', columnGap: 8,
      }}>
        <Header col="title" label="Book" align="left"/>
        <Header col="mins" label="Time"/>
        <Header col="notes" label="Nt"/>
        <Header col={slotColumn} label={slotLabel} slot/>
      </div>
      {sorted.map((r, i) => {
        const book = bookFor(r.id);
        const hrs = Math.floor(r.mins / 60), m = r.mins % 60;
        return (
          <div key={r.id} style={{
            display: 'grid', gridTemplateColumns: '1fr 70px 38px 50px',
            padding: '10px 14px',
            borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
            alignItems: 'center', columnGap: 8,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              {typeof BookCover !== 'undefined' && book.cover &&
                <BookCover book={book} width={24} height={34} radius={2}/>}
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 13, fontWeight: 600, color: t.ink,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>{book.title}</div>
                <div style={{
                  marginTop: 3, height: 3, borderRadius: 2,
                  background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
                  position: 'relative',
                }}>
                  <div style={{
                    position: 'absolute', left: 0, top: 0, bottom: 0,
                    width: `${(r.mins / max) * 100}%`, background: t.accent,
                    borderRadius: 2,
                  }}/>
                </div>
              </div>
            </div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: t.sub, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{hrs > 0 ? `${hrs}h ${String(m).padStart(2, '0')}` : `${m}m`}</div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5, color: r.notes ? t.ink : t.sub, fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{r.notes || '—'}</div>
            <div style={{
              textAlign: 'right',
              fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
              fontSize: 11.5,
              color: slotColumn === 'lastRead' && r.lastReadAt === null ? t.sub
                   : (slotVal(r) === '—' ? t.sub : t.ink),
              fontWeight: 500,
              fontVariantNumeric: 'tabular-nums',
            }}>{slotVal(r)}</div>
          </div>
        );
      })}
    </div>
  );
}

// ---- Column chooser popover -----------------------------------------------
function SlotColumnChooserPopover({ theme, current = 'lastRead' }) {
  const t = theme;
  const options = [
    { k: 'lastRead',   label: 'Last read', sub: 'May 17, 3d ago, …' },
    { k: 'highlights', label: 'Highlights', sub: 'Count of highlights' },
    { k: 'notes',      label: 'Notes', sub: 'Count of notes' },
  ];
  return (
    <div style={{
      position: 'absolute', top: 42, right: 14, width: 240, zIndex: 30,
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? '#2a2724' : '#fcf8f0',
      boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      padding: '4px 0',
    }}>
      <div style={{
        position: 'absolute', top: -6, right: 22,
        width: 12, height: 12, transform: 'rotate(45deg)',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      }}/>
      <div style={{
        padding: '8px 14px 4px', fontSize: 10, color: t.sub, fontWeight: 600,
        letterSpacing: 0.6, textTransform: 'uppercase',
      }}>Show in 4th column</div>
      {options.map(o => {
        const on = o.k === current;
        return (
          <div key={o.k} style={{
            display: 'flex', alignItems: 'center', gap: 10,
            padding: '10px 14px',
            background: on ? (t.isDark ? `${t.accent}1a` : `${t.accent}0e`) : 'transparent',
          }}>
            <div style={{ width: 14, display: 'flex', justifyContent: 'center' }}>
              {on && <Icons.Check size={13} color={t.accent} stroke={2.4}/>}
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13.5, color: on ? t.accent : t.ink, fontWeight: on ? 600 : 500 }}>{o.label}</div>
              <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>{o.sub}</div>
            </div>
          </div>
        );
      })}
    </div>
  );
}

// ---- Stats dashboard frame for table artboards ----------------------------
function TableArtboardShell({ theme, title = 'By book', subtitle = '30d', children, menuOpen = false, sortValue, dir = 'desc', chooser = null }) {
  const t = theme;
  return (
    <div style={{ padding: '18px 18px 8px', position: 'relative' }}>
      <div style={{
        display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10,
      }}>
        <div style={{
          fontSize: 11, color: t.sub, fontWeight: 600,
          letterSpacing: 0.8, textTransform: 'uppercase',
        }}>{title}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <span style={{ fontSize: 11, color: t.sub }}>{subtitle}</span>
          <button style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '4px 10px', borderRadius: 100,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            border: 'none', cursor: 'pointer',
            fontFamily: 'inherit', fontSize: 11, fontWeight: 600, color: t.ink,
          }}>
            <Icons.Sort size={11} color={t.ink} stroke={2}/>
            Sort
          </button>
        </div>
      </div>
      {children}
      {menuOpen && <SortMenu theme={t} value={sortValue} dir={dir} x={14} y={36}/>}
      {chooser}
    </div>
  );
}

function TableArtboard({ themeKey, variant = 'canonical', sortValue = 'mins', menuOpen = false, slotColumn = 'lastRead', chooserOpen = false }) {
  const t = THEMES[themeKey];
  let table;
  if (variant === 'all-five') {
    table = <PerBookTableAllFive theme={t} sortCol={sortValue}/>;
  } else if (variant === 'chooser') {
    table = <PerBookTableColumnChooser theme={t} slotColumn={slotColumn} sortCol={sortValue}/>;
  } else {
    table = <PerBookTableV2 theme={t} sortCol={sortValue}/>;
  }
  return (
    <StatsPhoneFrame themeKey={themeKey} height={520}>
      <div style={{ position: 'absolute', inset: 0, background: t.isDark ? '#222020' : '#fcf8f0' }}/>
      <TableArtboardShell theme={t}
        title="By book" subtitle="30d"
        menuOpen={menuOpen}
        sortValue={sortValue}
        dir={sortValue === 'lastRead' ? 'desc' : 'desc'}
        chooser={chooserOpen ? <SlotColumnChooserPopover theme={t} current={slotColumn}/> : null}>
        {table}
      </TableArtboardShell>
    </StatsPhoneFrame>
  );
}

// ════════════════════════════════════════════════════════════════════════════
// CanvasRoot
// ════════════════════════════════════════════════════════════════════════════
function CanvasRoot() {
  return (
    <DesignCanvas>
      {/* ───── #1058 Custom range picker ───── */}
      <DCSection id="i1058" title="#1058 — Custom date-range picker"
        subtitle="Tap the Custom pill in the time-window bar → range picker sheet. Sessions density shown as dots under each date.">
        <DCArtboard id="empty" label="Empty · just opened" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="empty"/>
        </DCArtboard>
        <DCArtboard id="picking-end" label="Picking end (range preview)" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="picking-end"
            start={{ y: 2026, m: 4, d: 2 }} hover={{ y: 2026, m: 4, d: 11 }}/>
        </DCArtboard>
        <DCArtboard id="range-set" label="Range chosen · ready to apply" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="ready"
            start={{ y: 2026, m: 4, d: 1 }} end={{ y: 2026, m: 4, d: 15 }}
            sessions={{ days: 14, label: '11h 23m' }}/>
        </DCArtboard>
        <DCArtboard id="applied-summary" label="Applied · summary footer" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="applied"
            start={{ y: 2026, m: 4, d: 1 }} end={{ y: 2026, m: 4, d: 15 }}
            sessions={{ days: 14, label: '11h 23m', preset: 'Last 14 days' }}/>
        </DCArtboard>
        <DCArtboard id="error" label="Error · start after end" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="error"
            start={{ y: 2026, m: 4, d: 15 }} end={{ y: 2026, m: 4, d: 3 }}
            error="End date must be on or after the start date."/>
        </DCArtboard>
        <DCArtboard id="no-results" label="No sessions in range" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="paper" state="no-results"
            start={{ y: 2026, m: 3, d: 6 }} end={{ y: 2026, m: 3, d: 9 }}
            viewMonth={3} viewYear={2026}
            sessions={{ days: 0, label: '0h 0m' }}/>
        </DCArtboard>
        <DCArtboard id="picker-dark" label="Dark · ready" width={PHONE_W} height={780}>
          <RangePickerArtboard themeKey="dark" state="ready"
            start={{ y: 2026, m: 4, d: 1 }} end={{ y: 2026, m: 4, d: 15 }}
            sessions={{ days: 14, label: '11h 23m' }}/>
        </DCArtboard>
        <DCArtboard id="popover" label="Alt · popover from Custom pill" width={PHONE_W} height={620}>
          <RangePickerPopoverArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="applied-dashboard" label="Dashboard · range applied" width={PHONE_W} height={780}>
          <AppliedDashboardArtboard themeKey="paper"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={260}>
          Canonical = sheet, not popover — Custom is the only time-window that needs two values, and the popover form runs out of vertical room once the preset rail + 2 chips + month grid are stacked. The popover variant is kept as a tablet-class fallback.
        </DCPostIt>
        <DCPostIt top={-30} left={420} rotate={-2} width={240}>
          The Custom pill DOES update when applied — `Custom · May 1 – May 15`. That's how the user knows the range survived; the pill is the persistent label until they pick a different window.
        </DCPostIt>
      </DCSection>

      {/* ───── #1059 Last-read column ───── */}
      <DCSection id="i1059" title="#1059 — Last read 5th sort column"
        subtitle="Canonical: keep 4 columns visible; Last read joins the Sort menu and swaps the time-bar inline when active.">
        <DCArtboard id="sort-menu" label="Sort menu · Last read offered" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="canonical" sortValue="mins" menuOpen/>
        </DCArtboard>
        <DCArtboard id="canonical-active" label="Canonical · sorted by Last read" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="canonical" sortValue="lastRead"/>
        </DCArtboard>
        <DCArtboard id="canonical-default" label="Canonical · default sort (Time)" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="canonical" sortValue="mins"/>
        </DCArtboard>
        <DCArtboard id="all-five" label="Alt 1 · always-5 columns (compact)" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="all-five" sortValue="lastRead"/>
        </DCArtboard>
        <DCArtboard id="chooser-closed" label="Alt 2 · column chooser (swappable slot)" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="chooser" sortValue="lastRead" slotColumn="lastRead"/>
        </DCArtboard>
        <DCArtboard id="chooser-open" label="Alt 2 · chooser open" width={PHONE_W} height={520}>
          <TableArtboard themeKey="paper" variant="chooser" sortValue="mins" slotColumn="lastRead" chooserOpen/>
        </DCArtboard>
        <DCArtboard id="dark-active" label="Canonical · dark, Last read active" width={PHONE_W} height={520}>
          <TableArtboard themeKey="dark" variant="canonical" sortValue="lastRead"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={-2} width={280}>
          Canonical wins because Last read is rarely a header you scan — you sort once, glance, sort back. Hiding it from the always-visible column set and surfacing it via the swap keeps the 4-col layout that already works at iPhone-SE width. Nil rows sort to the bottom and read as "No sessions recorded".
        </DCPostIt>
        <DCPostIt top={-30} left={420} rotate={2} width={240}>
          Alt 1 ships if/when iPad becomes a target. At 402px it's borderline (Read column compresses to "3d", "5w"); below 360 it breaks.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, {
  CanvasRoot,
  CustomRangePickerSheet, MonthGrid, DateChip, QuickPresetRail,
  ExtendedTimeWindowBar, AppliedDashboardArtboard,
  PerBookTableV2, PerBookTableAllFive, PerBookTableColumnChooser,
  SortMenu, SlotColumnChooserPopover,
  ROWS_WITH_LASTREAD,
});
