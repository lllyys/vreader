// Issue #1641 — in-reader total reading time (feature #101).
//
// Canonical decision: the bottom-chrome metrics line's TRAILING label is a
// tap target that cycles between the page readout and a time readout that
// carries BOTH durations ("12m read · 6h 40m total"). The always-reachable
// home is a Reading time row in Book details. No new chrome is added.
//
// Components: RTMetricsLine, RTBottomChrome, RTBookDetailsRows.

// One metrics line (the strip under the scrubber). trailingKind drives copy.
//   'pages'   → "414 pages left in book"
//   'time'    → "12m read · 6h 40m total"
//   'first'   → "4m read · first session"
//   'long'    → "18m read · 41h total"
function RTMetricsLine({ t, leading = 'Page 18', trailing, pressed = false, width }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'baseline',
      gap: 12, fontSize: 11, color: t.sub, width,
    }}>
      <span style={{
        overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', minWidth: 0,
      }}>{leading}</span>
      <span style={{
        flexShrink: 0, whiteSpace: 'nowrap',
        padding: pressed ? '1px 6px' : '1px 0',
        margin: pressed ? '-1px -6px' : 0,
        borderRadius: 7,
        background: pressed ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : 'transparent',
      }}>{trailing}</span>
    </div>
  );
}

// Replica of the committed bottom chrome with the trailing readout swappable.
function RTBottomChrome({ t, progress = 0.04, trailing = '414 pages left in book',
                          leading = 'Page 18', pressed = false }) {
  return (
    <div style={{
      position: 'absolute', bottom: 0, left: 0, right: 0,
      paddingBottom: 24, paddingTop: 14, zIndex: 30,
      background: t.chrome, borderTop: `0.5px solid ${t.rule}`,
    }}>
      <div style={{ padding: '0 22px', marginBottom: 12 }}>
        <div style={{ height: 18, display: 'flex', alignItems: 'center' }}>
          <div style={{ flex: 1, height: 3, borderRadius: 2, background: t.rule, position: 'relative' }}>
            <div style={{
              position: 'absolute', left: 0, top: 0, bottom: 0,
              width: `${progress * 100}%`, background: t.accent, borderRadius: 2,
            }}/>
            <div style={{
              position: 'absolute', left: `${progress * 100}%`, top: '50%',
              width: 14, height: 14, borderRadius: 7, background: t.accent,
              transform: 'translate(-50%, -50%)',
              boxShadow: '0 1px 3px rgba(0,0,0,0.3)',
            }}/>
          </div>
        </div>
        <div style={{ marginTop: 4 }}>
          <RTMetricsLine t={t} leading={leading} trailing={trailing} pressed={pressed}/>
        </div>
      </div>
      <div style={{ display: 'flex', justifyContent: 'space-around', padding: '0 12px' }}>
        {[
          { icon: Icons.TOC,         label: 'Contents' },
          { icon: Icons.Highlighter, label: 'Notes' },
          { icon: Icons.Aa,          label: 'Display' },
          { icon: Icons.Sparkle,     label: 'AI', accent: true },
        ].map((b, i) => (
          <div key={i} style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3,
            padding: '4px 12px',
          }}>
            <b.icon size={22} color={b.accent ? t.accent : t.ink} stroke={1.8}/>
            <span style={{
              fontSize: 10, color: b.accent ? t.accent : t.sub, fontWeight: 500,
            }}>{b.label}</span>
          </div>
        ))}
      </div>
    </div>
  );
}

// Book details — the always-reachable home for both durations.
function RTBookDetailsRows({ t }) {
  const Row = ({ label, value, sub, last }) => (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500 }}>{label}</div>
        {sub && <div style={{ fontSize: 11, color: t.sub, marginTop: 2 }}>{sub}</div>}
      </div>
      <div style={{ fontSize: 13, color: t.sub, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
    </div>
  );
  return (
    <div style={{
      borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      border: `0.5px solid ${t.rule}`,
    }}>
      <Row label="Reading time" sub="23 sessions since Mar 2" value="6h 40m total"/>
      <Row label="This session" value="12m"/>
      <Row label="Average session" value="17m" last/>
    </div>
  );
}

Object.assign(window, { RTMetricsLine, RTBottomChrome, RTBookDetailsRows });
