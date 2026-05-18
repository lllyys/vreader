// Continuous-scroll reader — for #812 (scroll-mode chapter nav).
//
// Renders multiple chapters in one scrollable column, separated by ChapterDivider.
// Chapter boundaries are visual (divider + uppercase heading), not navigational.
//
// State variants:
//   - default          → fully loaded, mid-chapter
//   - boundaryVisible  → chapter divider centered in viewport
//   - midRender        → skeleton-pulse at the bottom (next chapter loading)

const SCROLL_DEMO_CHAPTERS = [
  { num: 1, title: 'Chapter 1', paragraphs: PP_PAGES[0].paragraphs.concat(PP_PAGES[1].paragraphs) },
  { num: 2, title: 'Chapter 2', paragraphs: PP_PAGES[3].paragraphs.concat([
    'It was not till the afternoon, when he joined them at tea, that Mr. Bennet ventured to say—',
    '"I hope, my dear, that you have ordered a good dinner today, because I have reason to expect an addition to our family party."',
    '"Who do you mean, my dear? I know of nobody that is coming, I am sure, unless Charlotte Lucas should happen to call in,—and I hope my dinners are good enough for her. I do not believe she often sees such at home."',
  ]) },
];

function ChapterDivider({ theme, chapter }) {
  const t = theme;
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 14,
      margin: '36px 0 28px',
    }}>
      <div style={{ flex: 1, height: 0.5, background: t.rule }}/>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 11, fontWeight: 600, color: t.sub,
        letterSpacing: 2.5, textTransform: 'uppercase',
        whiteSpace: 'nowrap',
      }}>{chapter}</div>
      <div style={{ flex: 1, height: 0.5, background: t.rule }}/>
    </div>
  );
}

function ScrollSkeleton({ theme }) {
  const t = theme;
  const widths = ['100%', '94%', '88%', '40%'];
  return (
    <div style={{ marginTop: 32, opacity: 0.7 }}>
      {widths.map((w, i) => (
        <div key={i} style={{
          height: 12, width: w, marginBottom: 10, borderRadius: 4,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)',
          backgroundImage: `linear-gradient(90deg, transparent, ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.04)'}, transparent)`,
          backgroundSize: '200% 100%',
          animation: 'scrollSkeletonPulse 1.6s ease-in-out infinite',
        }}/>
      ))}
    </div>
  );
}

function ScrollModeContent({ theme, fontFamily, fontSize, lineHeight, margin,
                            chapters, scrollY = 0, showSkeleton = false }) {
  const t = theme;
  const ff = fontFamily === 'serif'
    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
    : '"Inter", -apple-system, system-ui, sans-serif';
  const scrollRef = React.useRef(null);

  React.useEffect(() => {
    if (scrollRef.current && scrollY > 0) {
      scrollRef.current.scrollTop = scrollY;
    }
  }, [scrollY]);

  return (
    <>
      <style>{`
        @keyframes scrollSkeletonPulse {
          0%, 100% { background-position: 200% 0; }
          50% { background-position: -100% 0; }
        }
      `}</style>
      <div ref={scrollRef} className="hide-scroll" style={{
        position: 'absolute', top: 90, bottom: 0, left: 0, right: 0,
        overflowY: 'auto', padding: `0 ${margin}px 120px`,
      }}>
        {chapters.map((ch, ci) => (
          <React.Fragment key={ci}>
            {ci > 0 && <ChapterDivider theme={t} chapter={ch.title}/>}
            {ci === 0 && (
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 13, color: t.sub, letterSpacing: 2,
                textTransform: 'uppercase', textAlign: 'center',
                marginTop: 8, marginBottom: 18, fontWeight: 500,
              }}>{ch.title}</div>
            )}
            {ch.paragraphs.map((p, pi) => (
              <p key={pi} style={{
                fontFamily: ff, fontSize, lineHeight, color: t.ink,
                margin: 0, marginBottom: lineHeight * fontSize * 0.4,
                textIndent: pi === 0 ? 0 : `${fontSize * 1.4}px`,
                textAlign: 'justify', hyphens: 'auto',
              }}>
                {ci === 0 && pi === 0 && (
                  <span style={{
                    fontFamily: '"Source Serif 4", Georgia, serif',
                    fontSize: fontSize * 2.6, lineHeight: 0.85,
                    float: 'left', marginRight: 6, marginTop: 4,
                    color: t.accent, fontWeight: 600,
                  }}>{p[0]}</span>
                )}
                {ci === 0 && pi === 0 ? p.slice(1) : p}
              </p>
            ))}
          </React.Fragment>
        ))}
        {showSkeleton && <ScrollSkeleton theme={t}/>}
      </div>
    </>
  );
}

Object.assign(window, {
  ScrollModeContent, ChapterDivider, ScrollSkeleton,
  SCROLL_DEMO_CHAPTERS,
});
