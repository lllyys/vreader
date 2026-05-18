// Settings profile-header card identity model — issue #862 / feature #67.
//
// The production app has no user account, no user-name concept. The committed design
// (vreader-panels.jsx SettingsSheet) shows "lllyys" + a 48pt gradient avatar with an
// initial; both are wishful. We have to decide what the card shows when there is no
// "user" — and we have to pick something other than the current "drop in your GitHub
// handle" hack.
//
// Three options, with a canonical recommendation.
//
// ─── A. Library-as-identity (CANONICAL) ──────────────────────────────────────────
//   The card represents the LIBRARY, not a person. Header reads "Your library"; the
//   avatar slot becomes the small stack-of-books glyph that already exists in the
//   library nav. Stats below are unchanged ("152 books · 41h this month"). The
//   "Stats" button is unchanged.
//
//   Why this is canonical:
//   • Honest. We don't have a user; pretending otherwise (with a generated initial
//     or "Reader 0247") is uncanny.
//   • Aligns with how this app is used in practice: one library per device, no
//     cross-device user identity. The library IS the user-facing aggregation.
//   • Lossless if we ever add accounts — the avatar slot becomes the user-photo
//     slot, and the "Your library" label becomes the user's display name. Nothing
//     about the layout has to change.
//
// ─── B. User-set display name (alternate) ────────────────────────────────────────
//   Adds a single "Your name" field to Settings → About. If empty, the card falls
//   back to A. If set, the card shows the name + a coloured initial badge. Avatars
//   from the iCloud profile are NOT used (it would require an iCloud sign-in we
//   don't otherwise need).
//
//   Why we'd ship this: power users like to feel like the app knows who's reading.
//   Why we wouldn't: it's an entire new settings flow + a migration path for users
//   who have nothing set, and the value is purely cosmetic. Defer to a feature ask.
//
// ─── C. Stats-as-hero (alternate) ────────────────────────────────────────────────
//   Replace the identity card entirely with a stats hero — the "41h this month"
//   becomes a serif headline + a tiny sparkline, with the Stats button as a small
//   chevron at the right of the row.
//
//   Why we'd ship this: it makes the Settings sheet feel less iOS-default and more
//   "reading is the point". Why we wouldn't: it pushes the actual settings list
//   further down the sheet, and a fresh-install user has 0h, which is a sad hero.
//
// Reading-stats DASHBOARD additions (this issue's part b):
//
//   The committed StatsSheet (vreader-stats.jsx) is missing two things feature #58
//   explicitly calls for:
//     • Time-window aggregation — switchable Today / 7d / 30d / 90d / Year / All
//     • Sortable per-book breakdown — current list is just sorted by time-this-month
//
//   StatsTimeWindowBar and SortablePerBookTable below are drop-ins; both are wired
//   into FullStatsDashboard at the bottom of this file so we can present the
//   whole composed surface in one artboard.

// ────────────────────────────────────────────────────
// A. Library-as-identity card  (CANONICAL)
// ────────────────────────────────────────────────────
function ProfileCardLibrary({ theme, books = 152, hoursMonth = 41, onOpenStats }) {
  const t = theme;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: 14, borderRadius: 14,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
    }}>
      <div style={{
        width: 48, height: 48, borderRadius: 12, flexShrink: 0,
        background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        position: 'relative', overflow: 'hidden',
      }}>
        {/* library glyph — three book spines */}
        <svg width="22" height="26" viewBox="0 0 22 26" fill="none">
          <rect x="0.6" y="3" width="6" height="20" rx="1" fill={t.accent}/>
          <rect x="7.6" y="0.6" width="6" height="22.4" rx="1"
            fill={t.isDark ? 'rgba(216,210,197,0.7)' : 'rgba(29,26,20,0.5)'}/>
          <rect x="14.6" y="5" width="6" height="18" rx="1"
            fill={t.isDark ? '#8c6a4a' : '#5a3a3a'}/>
        </svg>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 16, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>Your library</div>
        <div style={{ fontSize: 12, color: t.sub, marginTop: 2 }}>
          {books} books · {hoursMonth}h read this month
        </div>
      </div>
      <button onClick={onOpenStats} style={{
        padding: '6px 12px', borderRadius: 100, border: 'none',
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(60,40,20,0.08)',
        fontSize: 12, color: t.ink, fontWeight: 600, cursor: 'pointer',
        fontFamily: 'inherit',
      }}>Stats</button>
    </div>
  );
}

// ────────────────────────────────────────────────────
// B. User-set display name (alternate; falls back to A if empty)
// ────────────────────────────────────────────────────
function ProfileCardNamed({ theme, name = '', books = 152, hoursMonth = 41, onOpenStats, onTap }) {
  const t = theme;
  if (!name) return <ProfileCardLibrary theme={t} books={books} hoursMonth={hoursMonth} onOpenStats={onOpenStats}/>;
  const initial = name.trim()[0]?.toUpperCase() || '?';
  const hue = ((initial.charCodeAt(0) * 47) % 360);
  // The card body acts as a button (rename / edit name) but it contains the
  // "Stats" pill — a button-in-button is invalid DOM. Use a div with role +
  // keyboard handlers, and let the inner pill be the real <button>.
  return (
    <div onClick={onTap} role="button" tabIndex={0}
      onKeyDown={(e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); onTap?.(); } }}
      style={{
        display: 'flex', alignItems: 'center', gap: 12, width: '100%',
        padding: 14, borderRadius: 14,
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        cursor: 'pointer', textAlign: 'left', fontFamily: 'inherit',
      }}>
      <div style={{
        width: 48, height: 48, borderRadius: 24, flexShrink: 0,
        background: `linear-gradient(135deg, oklch(0.6 0.12 ${hue}), oklch(0.45 0.14 ${(hue + 30) % 360}))`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 22, fontWeight: 600, fontStyle: 'italic',
      }}>{initial}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 16, fontWeight: 600, color: t.ink,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{name}</div>
        <div style={{ fontSize: 12, color: t.sub, marginTop: 2 }}>
          {books} books · {hoursMonth}h this month
        </div>
      </div>
      <button onClick={(e) => { e.stopPropagation(); onOpenStats?.(); }} style={{
        padding: '6px 12px', borderRadius: 100, border: 'none',
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(60,40,20,0.08)',
        fontSize: 12, color: t.ink, fontWeight: 600, cursor: 'pointer',
        fontFamily: 'inherit',
      }}>Stats</button>
    </div>
  );
}

// ────────────────────────────────────────────────────
// C. Stats-as-hero (alternate)
// ────────────────────────────────────────────────────
function ProfileCardStatsHero({ theme, hoursMonth = 41, minutesMonth = 23,
                                sparkline = [22, 0, 41, 38, 15, 0, 52, 67, 28, 19, 44, 71, 33, 58],
                                onOpenStats }) {
  const t = theme;
  const max = Math.max(...sparkline);
  return (
    <button onClick={onOpenStats} style={{
      width: '100%', display: 'flex', alignItems: 'center', gap: 14,
      padding: 16, borderRadius: 14, border: 'none',
      background: t.isDark ? 'rgba(214,136,90,0.08)' : 'rgba(140,47,47,0.04)',
      cursor: 'pointer', textAlign: 'left', fontFamily: 'inherit',
    }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 11, color: t.sub, fontWeight: 600,
          letterSpacing: 0.8, textTransform: 'uppercase',
        }}>This month</div>
        <div style={{
          display: 'flex', alignItems: 'baseline', gap: 3, marginTop: 4,
        }}>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 32, fontWeight: 600, color: t.ink, lineHeight: 1,
            letterSpacing: -0.8,
          }}>{hoursMonth}</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 14, color: t.sub, fontWeight: 500,
          }}>hr</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 22, fontWeight: 600, color: t.ink, lineHeight: 1, marginLeft: 4,
            letterSpacing: -0.5,
          }}>{minutesMonth}</div>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 12, color: t.sub, fontWeight: 500,
          }}>min</div>
        </div>
        <div style={{ fontSize: 11, color: t.sub, marginTop: 4 }}>
          Tap for reading stats
        </div>
      </div>
      {/* sparkline */}
      <div style={{
        display: 'flex', alignItems: 'flex-end', gap: 2,
        width: 92, height: 38, flexShrink: 0,
      }}>
        {sparkline.map((v, i) => {
          const h = Math.max(2, (v / max) * 100);
          return (
            <div key={i} style={{
              flex: 1, height: `${h}%`,
              background: i === sparkline.length - 1 ? t.accent : t.accent,
              opacity: i === sparkline.length - 1 ? 1 : 0.35 + (v / max) * 0.45,
              borderRadius: 1.5,
            }}/>
          );
        })}
      </div>
    </button>
  );
}

// ────────────────────────────────────────────────────
// Time-window selector — drop-in at the top of the reading stats dashboard
// ────────────────────────────────────────────────────
const TIME_WINDOWS = [
  { k: 'today',   label: 'Today' },
  { k: '7d',      label: '7d' },
  { k: '30d',     label: '30d' },
  { k: '90d',     label: '90d' },
  { k: 'year',    label: 'Year' },
  { k: 'all',     label: 'All' },
  { k: 'custom',  label: 'Custom' },
];

function StatsTimeWindowBar({ theme, value = '30d', onChange }) {
  const t = theme;
  return (
    <div style={{
      display: 'flex', overflowX: 'auto', gap: 4, padding: '4px 18px 4px',
      borderBottom: `0.5px solid ${t.rule}`,
    }} className="hide-scroll">
      {TIME_WINDOWS.map(w => {
        const active = w.k === value;
        return (
          <button key={w.k} onClick={() => onChange?.(w.k)} style={{
            padding: '7px 12px', borderRadius: 100, border: 'none',
            background: active ? t.ink : 'transparent',
            color: active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
            fontFamily: 'inherit', fontSize: 12.5,
            fontWeight: active ? 600 : 500,
            cursor: 'pointer', whiteSpace: 'nowrap',
            display: 'inline-flex', alignItems: 'center', gap: 5,
          }}>
            {w.k === 'custom' && <Icons.Settings size={12} color={active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.sub} stroke={1.8}/>}
            {w.label}
          </button>
        );
      })}
    </div>
  );
}

// ────────────────────────────────────────────────────
// Sortable per-book table — Book / Time / Highlights / Notes, with sort indicator
// ────────────────────────────────────────────────────
const PER_BOOK_FULL = [
  { id: 'pp',   mins: 738, highlights: 47, notes: 18 },
  { id: 'bi',   mins: 587, highlights: 22, notes: 11 },
  { id: 'ddia', mins: 431, highlights: 31, notes: 4 },
  { id: 'prag', mins: 332, highlights: 12, notes: 7 },
  { id: 'med',  mins: 204, highlights: 18, notes: 9 },
  { id: '3b',   mins: 173, highlights: 6,  notes: 2 },
  { id: 'tfs',  mins: 28,  highlights: 0,  notes: 0 },
];

function SortablePerBookTable({ theme, rows = PER_BOOK_FULL }) {
  const t = theme;
  const [sort, setSort] = React.useState({ col: 'mins', dir: 'desc' });
  const sorted = React.useMemo(() => {
    const out = rows.slice().sort((a, b) => (b[sort.col] - a[sort.col]) * (sort.dir === 'desc' ? 1 : -1));
    return out;
  }, [rows, sort]);
  const max = Math.max(...rows.map(r => r.mins), 1);

  const Header = ({ col, label, align = 'right' }) => {
    const active = sort.col === col;
    return (
      <button onClick={() => setSort(s => s.col === col
        ? { col, dir: s.dir === 'desc' ? 'asc' : 'desc' }
        : { col, dir: 'desc' })} style={{
        display: 'inline-flex', alignItems: 'center', gap: 3,
        background: 'none', border: 'none', padding: 0, cursor: 'pointer',
        fontFamily: 'inherit', fontSize: 10.5, fontWeight: 600,
        color: active ? t.ink : t.sub,
        letterSpacing: 0.5, textTransform: 'uppercase',
        justifyContent: align === 'right' ? 'flex-end' : 'flex-start',
      }}>
        <span>{label}</span>
        {active && (
          <svg width="8" height="8" viewBox="0 0 8 8">
            <path d={sort.dir === 'desc' ? 'M1 2l3 4 3-4' : 'M1 6l3-4 3 4'}
              stroke="currentColor" strokeWidth="1.5" fill="none" strokeLinecap="round"/>
          </svg>
        )}
      </button>
    );
  };

  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
    }}>
      {/* header */}
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
      {/* rows */}
      {sorted.map((r, i) => {
        const book = (typeof BOOKS !== 'undefined' && BOOKS.find(b => b.id === r.id)) || { title: r.id, cover: { bg: '#5a3a3a', ink: '#fff' } };
        const hrs = Math.floor(r.mins / 60), m = r.mins % 60;
        return (
          <div key={r.id} style={{
            display: 'grid', gridTemplateColumns: '1fr 70px 38px 38px',
            padding: '10px 14px',
            borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
            alignItems: 'center', columnGap: 8,
          }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 10, minWidth: 0 }}>
              {typeof BookCover !== 'undefined' && book.cover && <BookCover book={book} width={24} height={34} radius={2}/>}
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
              fontSize: 11.5, color: t.sub, fontWeight: 500, letterSpacing: 0.2,
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

// ────────────────────────────────────────────────────
// Full reading-stats dashboard preview (uses the new pieces above + a hero row).
// ────────────────────────────────────────────────────
function FullStatsDashboard({ theme, onClose }) {
  const t = theme;
  const [win, setWin] = React.useState('30d');
  const totals = {
    today:  { h: 0, m: 38, label: '38m' },
    '7d':   { h: 6, m: 12, label: '6h 12m' },
    '30d':  { h: 41, m: 23, label: '41h 23m' },
    '90d':  { h: 124, m: 4, label: '124h 4m' },
    year:   { h: 268, m: 41, label: '268h 41m' },
    all:    { h: 312, m: 8, label: '312h 8m' },
    custom: { h: 41, m: 23, label: '41h 23m' },
  };
  const v = totals[win];

  return (
    <Sheet theme={t} onClose={onClose} height={720} title="Reading"
      trailing={<button onClick={onClose} style={{
        background: 'none', border: 'none', padding: '4px 0',
        color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500, cursor: 'pointer',
      }}>Done</button>}>
      <StatsTimeWindowBar theme={t} value={win} onChange={setWin}/>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 0 32px' }} className="hide-scroll">
        <div style={{ padding: '16px 18px 8px' }}>
          <div style={{
            fontSize: 11, color: t.sub, fontWeight: 600,
            letterSpacing: 0.8, textTransform: 'uppercase',
          }}>Reading time, {TIME_WINDOWS.find(w => w.k === win).label.toLowerCase()}</div>
          <div style={{
            display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4,
          }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 44, fontWeight: 600, color: t.ink,
              letterSpacing: -1, lineHeight: 1,
            }}>{v.h}</div>
            <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 16, color: t.sub, fontWeight: 500 }}>hr</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 30, fontWeight: 600, color: t.ink,
              letterSpacing: -0.5, lineHeight: 1, marginLeft: 6,
            }}>{v.m}</div>
            <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14, color: t.sub, fontWeight: 500 }}>min</div>
            <div style={{ flex: 1 }}/>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 4,
              padding: '4px 10px', borderRadius: 100,
              background: t.isDark ? 'rgba(140,200,140,0.15)' : 'rgba(58,106,90,0.1)',
              fontSize: 11, color: '#3a6a5a', fontWeight: 600,
            }}><span>▲</span><span>22%</span></div>
          </div>
        </div>

        {typeof DailyChart !== 'undefined' && win !== 'today' && (
          <div style={{ padding: '12px 18px 18px' }}>
            <DailyChart theme={t} data={[22, 0, 41, 38, 15, 0, 52, 67, 28, 19, 44, 71, 33, 58]}/>
          </div>
        )}

        {/* tile grid */}
        <div style={{ padding: '0 18px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          {typeof StatTile !== 'undefined' && <>
            <StatTile theme={t} label="Current streak" value="14" unit="days" sub="Best: 28 days"/>
            <StatTile theme={t} label="Pages read" value="1,842" unit="" sub="587 this week"/>
            <StatTile theme={t} label="Books finished" value="2" unit="" sub="9 this year"/>
            <StatTile theme={t} label="Reading speed" value="247" unit="wpm" sub="Avg, last 30d"/>
          </>}
        </div>

        {/* per-book sortable table */}
        <div style={{ padding: '22px 18px 8px' }}>
          <div style={{
            display: 'flex', alignItems: 'baseline', justifyContent: 'space-between', marginBottom: 10,
          }}>
            <SectionLabel theme={t}>By book</SectionLabel>
            <div style={{ fontSize: 11, color: t.sub }}>
              {TIME_WINDOWS.find(w => w.k === win).label}
            </div>
          </div>
          <SortablePerBookTable theme={t}/>
        </div>
      </div>
    </Sheet>
  );
}

Object.assign(window, {
  ProfileCardLibrary, ProfileCardNamed, ProfileCardStatsHero,
  StatsTimeWindowBar, SortablePerBookTable, FullStatsDashboard,
  TIME_WINDOWS, PER_BOOK_FULL,
});
