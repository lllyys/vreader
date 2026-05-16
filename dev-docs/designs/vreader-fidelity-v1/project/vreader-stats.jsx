// Reading-time dashboard — per-book stats, streaks, sessions

const STATS_DATA = {
  totalMonth: { hours: 41, minutes: 23 },
  totalAllTime: { hours: 312, minutes: 8 },
  streak: 14,
  longestStreak: 28,
  booksFinished: { month: 2, year: 9 },
  pagesRead: { month: 1842, week: 587 },
  avgWPM: 247,
  // 14 days of session minutes (oldest → today)
  daily: [22, 0, 41, 38, 15, 0, 52, 67, 28, 19, 44, 71, 33, 58],
  // hour-of-day distribution (24 buckets)
  hourly: [0, 0, 0, 0, 0, 0, 3, 8, 12, 4, 2, 1, 1, 2, 3, 5, 8, 12, 18, 24, 32, 28, 18, 6],
  // recent sessions
  sessions: [
    { book: 'Pride and Prejudice', start: 'Today, 8:14 PM', mins: 38, pages: 12 },
    { book: 'The Beginning of Infinity', start: 'Yesterday, 11:02 PM', mins: 24, pages: 6 },
    { book: 'Pride and Prejudice', start: 'Yesterday, 7:38 AM', mins: 19, pages: 7 },
    { book: 'Designing Data-Intensive Applications', start: '2 days ago, 10:14 AM', mins: 67, pages: 18 },
    { book: 'The Three-Body Problem', start: '2 days ago, 11:45 PM', mins: 18, pages: 8 },
  ],
  // per-book breakdown (month)
  perBook: [
    { id: 'pp',  hours: 12, mins: 18 },
    { id: 'bi',  hours: 9,  mins: 47 },
    { id: 'ddia',hours: 7,  mins: 11 },
    { id: 'prag',hours: 5,  mins: 32 },
    { id: 'med', hours: 3,  mins: 24 },
    { id: '3b',  hours: 2,  mins: 53 },
    { id: 'tfs', hours: 0,  mins: 28 },
  ],
};

function StatsSheet({ theme, onClose }) {
  const t = theme;
  const [range, setRange] = React.useState('30d');

  return (
    <Sheet theme={t} onClose={onClose} height={720} title="Reading"
      trailing={<button onClick={onClose} style={{
        background: 'none', border: 'none', padding: '4px 0',
        color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500, cursor: 'pointer',
      }}>Done</button>}>
      <div style={{ flex: 1, overflow: 'auto', padding: '4px 0 32px' }} className="hide-scroll">
        {/* Hero stat */}
        <div style={{ padding: '14px 18px 8px' }}>
          <div style={{ fontSize: 12, color: t.sub, fontWeight: 500, letterSpacing: 0.3 }}>
            Reading time, last 30 days
          </div>
          <div style={{
            display: 'flex', alignItems: 'baseline', gap: 4,
            marginTop: 4,
          }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 44, fontWeight: 600, color: t.ink,
              letterSpacing: -1, lineHeight: 1,
            }}>{STATS_DATA.totalMonth.hours}</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 16, color: t.sub, fontWeight: 500,
            }}>hr</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 30, fontWeight: 600, color: t.ink,
              letterSpacing: -0.5, lineHeight: 1, marginLeft: 6,
            }}>{STATS_DATA.totalMonth.minutes}</div>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 14, color: t.sub, fontWeight: 500,
            }}>min</div>
            <div style={{ flex: 1 }}/>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 4,
              padding: '4px 10px', borderRadius: 100,
              background: t.isDark ? 'rgba(140,200,140,0.15)' : 'rgba(58,106,90,0.1)',
              fontSize: 11, color: '#3a6a5a', fontWeight: 600,
            }}>
              <span>▲</span>
              <span>22%</span>
            </div>
          </div>
          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 6 }}>
            vs previous 30 days (33h 56m)
          </div>
        </div>

        {/* Daily chart */}
        <div style={{ padding: '12px 18px 18px' }}>
          <DailyChart theme={t} data={STATS_DATA.daily}/>
          <div style={{
            display: 'flex', justifyContent: 'space-between',
            fontSize: 10, color: t.sub, marginTop: 6, letterSpacing: 0.3,
          }}>
            <span>2 wk ago</span>
            <span>1 wk ago</span>
            <span>Today</span>
          </div>
        </div>

        {/* Stat tiles */}
        <div style={{ padding: '0 18px', display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
          <StatTile theme={t} label="Current streak" value={STATS_DATA.streak} unit="days"
            sub={`Best: ${STATS_DATA.longestStreak} days`}/>
          <StatTile theme={t} label="Pages read" value={STATS_DATA.pagesRead.month.toLocaleString()} unit=""
            sub={`${STATS_DATA.pagesRead.week} this week`}/>
          <StatTile theme={t} label="Books finished" value={STATS_DATA.booksFinished.month} unit=""
            sub={`${STATS_DATA.booksFinished.year} this year`}/>
          <StatTile theme={t} label="Reading speed" value={STATS_DATA.avgWPM} unit="wpm"
            sub="Avg, last 30 days"/>
        </div>

        {/* Hour-of-day */}
        <div style={{ padding: '24px 18px 8px' }}>
          <SectionLabel theme={t}>When you read</SectionLabel>
          <div style={{ marginTop: 12 }}>
            <HourChart theme={t} data={STATS_DATA.hourly}/>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontSize: 10, color: t.sub, marginTop: 4, letterSpacing: 0.3,
            }}>
              <span>12a</span><span>6a</span><span>12p</span><span>6p</span><span>12a</span>
            </div>
          </div>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 6, marginTop: 12,
            padding: '10px 12px', borderRadius: 10,
            background: t.isDark ? 'rgba(214,136,90,0.08)' : 'rgba(140,47,47,0.04)',
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 13, color: t.ink, lineHeight: 1.4,
          }}>
            <Icons.Sparkle size={13} color={t.accent} stroke={2} style={{ flexShrink: 0 }}/>
            <span>You read most between <strong>8&thinsp;PM and 10&thinsp;PM</strong>, averaging 32 minutes per evening session.</span>
          </div>
        </div>

        {/* Per-book breakdown */}
        <div style={{ padding: '24px 18px 8px' }}>
          <div style={{
            display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
            marginBottom: 12,
          }}>
            <div style={{ fontSize: 12, color: t.sub, fontWeight: 600, letterSpacing: 0.8, textTransform: 'uppercase' }}>
              By book
            </div>
            <div style={{ fontSize: 11, color: t.sub }}>Last 30 days</div>
          </div>
          <div style={{
            borderRadius: 14, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)',
          }}>
            {STATS_DATA.perBook.map((pb, i) => {
              const book = BOOKS.find(b => b.id === pb.id);
              if (!book) return null;
              const totalMins = pb.hours * 60 + pb.mins;
              const maxMins = STATS_DATA.perBook[0].hours * 60 + STATS_DATA.perBook[0].mins;
              return (
                <div key={pb.id} style={{
                  display: 'flex', alignItems: 'center', gap: 12,
                  padding: '10px 12px',
                  borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
                }}>
                  <BookCover book={book} width={28} height={40} radius={2}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{
                      fontFamily: '"Source Serif 4", Georgia, serif',
                      fontSize: 13.5, fontWeight: 600, color: t.ink,
                      overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                    }}>{book.title}</div>
                    <div style={{
                      marginTop: 4, height: 4, borderRadius: 2,
                      background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
                      position: 'relative',
                    }}>
                      <div style={{
                        position: 'absolute', left: 0, top: 0, bottom: 0,
                        width: `${(totalMins / maxMins) * 100}%`,
                        background: t.accent, borderRadius: 2,
                      }}/>
                    </div>
                  </div>
                  <div style={{
                    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                    fontSize: 11.5, color: t.sub, fontWeight: 500,
                    width: 50, textAlign: 'right', letterSpacing: 0.2,
                  }}>{pb.hours}h {String(pb.mins).padStart(2, '0')}m</div>
                </div>
              );
            })}
          </div>
        </div>

        {/* Recent sessions */}
        <div style={{ padding: '24px 18px 8px' }}>
          <SectionLabel theme={t}>Recent sessions</SectionLabel>
          <div style={{ marginTop: 10 }}>
            {STATS_DATA.sessions.map((s, i) => (
              <div key={i} style={{
                display: 'flex', alignItems: 'center', gap: 10,
                padding: '10px 0', borderBottom: i < STATS_DATA.sessions.length - 1 ? `0.5px solid ${t.rule}` : 'none',
              }}>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontFamily: '"Source Serif 4", Georgia, serif',
                    fontSize: 14, color: t.ink, fontWeight: 500,
                    overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                  }}>{s.book}</div>
                  <div style={{ fontSize: 11, color: t.sub, marginTop: 2 }}>{s.start}</div>
                </div>
                <div style={{ textAlign: 'right' }}>
                  <div style={{
                    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
                    fontSize: 13, fontWeight: 600, color: t.ink, letterSpacing: 0.2,
                  }}>{s.mins} min</div>
                  <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{s.pages} pages</div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* All time summary */}
        <div style={{ padding: '22px 18px 0' }}>
          <div style={{
            padding: '14px 16px', borderRadius: 14,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          }}>
            <div>
              <div style={{ fontSize: 11, color: t.sub, fontWeight: 500, letterSpacing: 0.3 }}>
                Lifetime reading
              </div>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 22, fontWeight: 600, color: t.ink,
                marginTop: 2, letterSpacing: -0.4,
              }}>{STATS_DATA.totalAllTime.hours}h {STATS_DATA.totalAllTime.minutes}m</div>
            </div>
            <div style={{ textAlign: 'right' }}>
              <div style={{ fontSize: 11, color: t.sub, fontWeight: 500, letterSpacing: 0.3 }}>
                Tracking since
              </div>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 14, color: t.ink, marginTop: 2,
              }}>Mar 12, 2023</div>
            </div>
          </div>
        </div>
      </div>
    </Sheet>
  );
}

function StatTile({ theme, label, value, unit, sub }) {
  const t = theme;
  return (
    <div style={{
      padding: '12px 14px', borderRadius: 14,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)',
    }}>
      <div style={{ fontSize: 11, color: t.sub, fontWeight: 500, letterSpacing: 0.2 }}>{label}</div>
      <div style={{
        display: 'flex', alignItems: 'baseline', gap: 4, marginTop: 4,
      }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 24, fontWeight: 600, color: t.ink, lineHeight: 1,
          letterSpacing: -0.5,
        }}>{value}</div>
        {unit && (
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 12, color: t.sub, fontWeight: 500,
          }}>{unit}</div>
        )}
      </div>
      <div style={{ fontSize: 10.5, color: t.sub, marginTop: 6 }}>{sub}</div>
    </div>
  );
}

function DailyChart({ theme, data }) {
  const t = theme;
  const max = Math.max(...data, 1);
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-end', gap: 4,
      height: 80, padding: '0 0',
    }}>
      {data.map((v, i) => {
        const h = (v / max) * 100;
        const isToday = i === data.length - 1;
        const isZero = v === 0;
        return (
          <div key={i} style={{
            flex: 1, position: 'relative',
            height: '100%', display: 'flex', alignItems: 'flex-end',
          }}>
            {isZero ? (
              <div style={{
                width: '100%', height: 4, borderRadius: 2,
                background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
              }}/>
            ) : (
              <div style={{
                width: '100%', minHeight: 4, height: `${h}%`,
                background: isToday ? t.accent : (t.isDark ? 'rgba(216,210,197,0.5)' : 'rgba(29,26,20,0.45)'),
                borderRadius: 3,
              }}/>
            )}
          </div>
        );
      })}
    </div>
  );
}

function HourChart({ theme, data }) {
  const t = theme;
  const max = Math.max(...data, 1);
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-end', gap: 2,
      height: 56,
    }}>
      {data.map((v, i) => {
        const h = (v / max) * 100;
        return (
          <div key={i} style={{
            flex: 1, position: 'relative', height: '100%',
            display: 'flex', alignItems: 'flex-end',
          }}>
            <div style={{
              width: '100%', height: v === 0 ? 0 : `${Math.max(h, 6)}%`,
              background: t.accent,
              opacity: 0.3 + (v / max) * 0.7,
              borderRadius: 2,
            }}/>
          </div>
        );
      })}
    </div>
  );
}

Object.assign(window, { StatsSheet });
