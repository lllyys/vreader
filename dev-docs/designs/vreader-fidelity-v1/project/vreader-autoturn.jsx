// Auto-page-turn indicator — 1px sweeping ribbon at the bottom of the page.
// When `running` is true, ribbon fills left→right over `interval` seconds, then resets.
//
// pointer-events: none, sits *under* chrome but *over* content.

function AutoTurnRibbon({ theme, running, interval = 30, paused = false }) {
  const t = theme;
  const [progress, setProgress] = React.useState(0);
  const startRef = React.useRef(null);
  const rafRef = React.useRef(null);

  React.useEffect(() => {
    if (!running || paused) {
      cancelAnimationFrame(rafRef.current);
      return;
    }
    startRef.current = performance.now();
    const tick = (now) => {
      const elapsed = (now - startRef.current) / 1000;
      const p = (elapsed % interval) / interval;
      setProgress(p);
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(rafRef.current);
  }, [running, paused, interval]);

  if (!running) return null;

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height: 1.5,
      pointerEvents: 'none', zIndex: 28,
      background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)',
    }}>
      <div style={{
        height: '100%',
        width: `${progress * 100}%`,
        background: t.accent,
        opacity: t.isDark ? 0.85 : 0.7,
        boxShadow: `0 0 6px ${t.accent}55`,
        transition: 'width 0.05s linear',
      }}/>
    </div>
  );
}

Object.assign(window, { AutoTurnRibbon });
