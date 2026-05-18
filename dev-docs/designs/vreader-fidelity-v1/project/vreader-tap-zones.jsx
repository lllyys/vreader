// Tap-zone overlays — for #842 / #812 reader navigation.
//
// Two related visuals:
//   1. TapZoneHint     — first-open discoverability overlay; left + right zones get
//                        a labeled chevron, center gets a "toggle controls" dot.
//                        Fades in after ~220ms, lives ~2.5s, fades out over 400ms.
//                        pointer-events: none, so it never steals taps.
//   2. TapZoneDebug    — designer-only opaque-tinted regions for the 30/40/30 split.
//                        Surfaced via a tweak.

function TapZoneHint({ theme, visible, onDone }) {
  const t = theme;
  const [stage, setStage] = React.useState('hidden'); // hidden | enter | hold | exit
  React.useEffect(() => {
    if (!visible) { setStage('hidden'); return; }
    setStage('enter');
    const t1 = setTimeout(() => setStage('hold'), 220);
    const t2 = setTimeout(() => setStage('exit'), 220 + 2500);
    const t3 = setTimeout(() => { setStage('hidden'); onDone?.(); }, 220 + 2500 + 400);
    return () => { clearTimeout(t1); clearTimeout(t2); clearTimeout(t3); };
  }, [visible]);
  if (stage === 'hidden') return null;
  const opacity = stage === 'enter' || stage === 'hold' ? 1 : 0;
  const transition = stage === 'enter' ? 'opacity 0.22s ease-out' : 'opacity 0.4s ease-in';

  const baseTint = t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)';
  const accentTint = t.isDark ? `${t.accent}28` : `${t.accent}18`;

  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 25,
      pointerEvents: 'none', opacity, transition,
      display: 'flex',
    }}>
      <HintZone t={t} side="left"   label="Tap to go back"        glyph={<Icons.ChevronL size={26} color={t.accent} stroke={2.2}/>} tint={accentTint} flex={3}/>
      <HintZone t={t} side="center" label="Tap to toggle controls" glyph={<Icons.Dot size={10} color={t.sub} stroke={0}/>}          tint={baseTint}   flex={4}/>
      <HintZone t={t} side="right"  label="Tap to advance"         glyph={<Icons.Chevron size={26} color={t.accent} stroke={2.2}/>} tint={accentTint} flex={3}/>
    </div>
  );
}

function HintZone({ t, side, label, glyph, tint, flex }) {
  return (
    <div style={{
      flex, position: 'relative', background: tint,
      borderRight: side === 'left'   ? `0.5px dashed ${t.rule}` : 'none',
      borderLeft:  side === 'right'  ? `0.5px dashed ${t.rule}` : 'none',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', gap: 14,
    }}>
      <div style={{
        width: 56, height: 56, borderRadius: 28,
        background: t.isDark ? 'rgba(0,0,0,0.45)' : 'rgba(255,255,255,0.65)',
        backdropFilter: 'blur(4px)', boxShadow: '0 4px 14px rgba(0,0,0,0.18)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</div>
      <div style={{
        fontFamily: '"Inter", system-ui',
        fontSize: 11.5, fontWeight: 600, letterSpacing: 0.4,
        color: t.ink, textAlign: 'center', padding: '0 8px',
        textTransform: 'uppercase',
        textShadow: t.isDark ? '0 1px 2px rgba(0,0,0,0.45)' : '0 1px 2px rgba(255,255,255,0.65)',
      }}>{label}</div>
    </div>
  );
}

// Debug — designer-only, tinted regions
function TapZoneDebug({ theme }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 22, pointerEvents: 'none',
      display: 'flex', opacity: 0.92,
    }}>
      <div style={{
        flex: 3, background: 'rgba(245, 132, 132, 0.18)',
        borderRight: `1px dashed rgba(245, 132, 132, 0.55)`,
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
        padding: 12, fontSize: 10, color: '#a73a3a', fontWeight: 700, letterSpacing: 0.5,
      }}>PREV · 30%</div>
      <div style={{
        flex: 4, background: 'rgba(155, 155, 245, 0.16)',
        borderRight: `1px dashed rgba(155, 155, 245, 0.55)`,
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
        padding: 12, fontSize: 10, color: '#3a4aa7', fontWeight: 700, letterSpacing: 0.5,
      }}>TOGGLE · 40%</div>
      <div style={{
        flex: 3, background: 'rgba(132, 200, 132, 0.18)',
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
        padding: 12, fontSize: 10, color: '#2a6a3a', fontWeight: 700, letterSpacing: 0.5,
        alignItems: 'flex-end',
      }}>NEXT · 30%</div>
    </div>
  );
}

Object.assign(window, { TapZoneHint, TapZoneDebug });
