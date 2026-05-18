// Canvas artboards for #812 (EPUB chapter nav) and #842 (MD paged-mode).
// Sections:
//   ① Paged · hybrid · tap behavior at chapter boundaries
//   ② Scroll · continuous · chapter dividers + mid-render skeleton
//   ③ MD paged-mode · chrome inset (#842 §1) — before/after
//   ④ Auto-page-turn ribbon — frozen at three progresses
//   ⑤ Tap-zone discoverability — hint + debug overlay
//   ⑥ Cross-theme matrix

// ─────────────────────────────────────────
// A re-usable phone "frame" — paints chrome + page text, no real reader needed.
// Variants set what overlays/states sit on top.
// ─────────────────────────────────────────
function NavFrame({
  themeKey = 'paper',
  height = 720,
  showTopChrome = true,
  showBottomChrome = true,
  chapterEnd = false,
  endOfBook = false,
  margin = 26,
  fontSize = 17, lineHeight = 1.55,
  children,
}) {
  const t = THEMES[themeKey];
  const ff = '"Source Serif 4", Georgia, serif';
  const paragraphs = chapterEnd ? [
    'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.',
    'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
    'Mr. Bennet replied that he had not.',
    'But it is, returned she; for Mrs. Long has just been here, and she told me all about it.',
    '. . .',
  ] : [
    'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.',
    'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
  ];

  const bottomInset = showBottomChrome ? 136 : 56;

  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: t.bg, color: t.ink, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      {/* status bar fake */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 44, zIndex: 10,
        background: showTopChrome ? t.chrome : 'transparent',
        display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 24px 6px',
        fontSize: 13, fontWeight: 600, color: t.ink,
      }}>
        <span>9:41</span>
        <span style={{ display: 'inline-flex', gap: 4, alignItems: 'center' }}>
          <svg width="14" height="10" viewBox="0 0 14 10"><circle cx="2" cy="9" r="1" fill={t.ink}/><circle cx="6" cy="7" r="1" fill={t.ink}/><circle cx="10" cy="5" r="1" fill={t.ink}/><circle cx="14" cy="3" r="1" fill={t.ink}/></svg>
          <span style={{ fontSize: 10 }}>100%</span>
        </span>
      </div>

      {/* top chrome */}
      {showTopChrome && (
        <div style={{
          position: 'absolute', top: 44, left: 0, right: 0,
          paddingTop: 6, paddingBottom: 12, zIndex: 10,
          background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
        }}>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '0 14px',
          }}>
            <div style={{
              display: 'flex', alignItems: 'center', gap: 4,
              color: t.accent, fontSize: 15, fontWeight: 500,
            }}><Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library</div>
            <div style={{
              fontFamily: ff, fontSize: 14, fontStyle: 'italic',
              fontWeight: 600, color: t.ink,
            }}>Pride and Prejudice</div>
            <div style={{ display: 'flex' }}>
              <Icons.Search size={18} color={t.ink} stroke={1.7} style={{ margin: 9 }}/>
              <Icons.Bookmark size={18} color={t.ink} stroke={1.7} style={{ margin: 9 }}/>
              <Icons.More size={20} color={t.ink} stroke={1.7} style={{ margin: 8 }}/>
            </div>
          </div>
        </div>
      )}

      {/* page content */}
      <div style={{
        position: 'absolute', top: showTopChrome ? 88 : 60, bottom: bottomInset,
        left: margin, right: margin,
        overflow: 'hidden',
      }}>
        <div style={{
          fontFamily: ff, fontSize: 13, color: t.sub,
          letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center',
          marginBottom: 18, marginTop: 8, fontWeight: 500,
        }}>Chapter {chapterEnd && !endOfBook ? '12' : '1'}</div>
        {paragraphs.map((p, i) => (
          <p key={i} style={{
            fontFamily: ff, fontSize, lineHeight, color: t.ink,
            margin: 0, marginBottom: lineHeight * fontSize * 0.4,
            textIndent: i === 0 ? 0 : 24,
            textAlign: 'justify', hyphens: 'auto',
          }}>
            {i === 0 && (
              <span style={{
                fontFamily: ff, fontSize: fontSize * 2.6, lineHeight: 0.85,
                float: 'left', marginRight: 6, marginTop: 4,
                color: t.accent, fontWeight: 600,
              }}>{p[0]}</span>
            )}
            {i === 0 ? p.slice(1) : p}
          </p>
        ))}
      </div>

      {/* bottom-content page indicator (#842) when chrome hidden */}
      {!showBottomChrome && (
        <div style={{
          position: 'absolute', bottom: 18, left: 0, right: 0,
          textAlign: 'center', fontSize: 11, color: t.sub, opacity: 0.65,
          letterSpacing: 0.5, zIndex: 6, pointerEvents: 'none',
        }}>147 / 432</div>
      )}

      {/* bottom chrome */}
      {showBottomChrome && (
        <div style={{
          position: 'absolute', bottom: 0, left: 0, right: 0,
          paddingBottom: 28, paddingTop: 14, zIndex: 10,
          background: t.chrome, borderTop: `0.5px solid ${t.rule}`,
        }}>
          <div style={{ padding: '0 22px', marginBottom: 14 }}>
            <div style={{
              height: 3, borderRadius: 2,
              background: t.rule, position: 'relative',
            }}>
              <div style={{
                position: 'absolute', left: 0, top: 0, bottom: 0, width: '34%',
                background: t.accent, borderRadius: 2,
              }}/>
              <div style={{
                position: 'absolute', left: '34%', top: '50%',
                width: 14, height: 14, borderRadius: 7, background: t.accent,
                transform: 'translate(-50%, -50%)',
              }}/>
            </div>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontSize: 11, color: t.sub, marginTop: 4,
            }}>
              <span>Page 147</span>
              <span>285 pages left in book</span>
            </div>
          </div>
          <div style={{
            display: 'flex', justifyContent: 'space-around', padding: '0 12px',
          }}>
            {[
              { ico: Icons.TOC, l: 'Contents' },
              { ico: Icons.Highlighter, l: 'Notes' },
              { ico: Icons.Aa, l: 'Display' },
              { ico: Icons.Sparkle, l: 'AI', accent: true },
            ].map((b, i) => (
              <div key={i} style={{
                display: 'flex', flexDirection: 'column',
                alignItems: 'center', gap: 3, padding: '4px 12px',
              }}>
                <b.ico size={22} color={b.accent ? t.accent : t.ink} stroke={1.8}/>
                <span style={{ fontSize: 10, color: b.accent ? t.accent : t.sub, fontWeight: 500 }}>{b.l}</span>
              </div>
            ))}
          </div>
        </div>
      )}

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 100, zIndex: 12,
        background: t.isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.32)',
      }}/>

      {children}
    </div>
  );
}

// Bounce hint — small arrow with "End of book" caption, shown when user taps right
// on the last page of the last chapter.
function BounceHintOverlay({ theme, side = 'right' }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute',
      [side]: 12, top: '50%', transform: 'translateY(-50%)',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 8,
      zIndex: 22, pointerEvents: 'none',
    }}>
      <div style={{
        width: 50, height: 50, borderRadius: 25,
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        animation: 'navBounce 1.2s ease-in-out infinite',
      }}>
        <Icons.Chevron size={22} color={t.sub} stroke={2.4}/>
      </div>
      <div style={{
        fontSize: 11, color: t.sub, fontWeight: 600, letterSpacing: 0.6,
        textTransform: 'uppercase',
      }}>End of book</div>
      <style>{`
        @keyframes navBounce {
          0%, 100% { transform: translateX(0); }
          50% { transform: translateX(-6px); }
        }
      `}</style>
    </div>
  );
}

// Chapter-advance arrow — points right, with "Next: Chapter 13" caption.
function ChapterAdvanceHint({ theme, chapter = 13 }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', right: 18, top: '52%', transform: 'translateY(-50%)',
      display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 6,
      pointerEvents: 'none', zIndex: 22,
    }}>
      <div style={{
        padding: '7px 11px', borderRadius: 100,
        background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(255,255,255,0.92)',
        boxShadow: '0 4px 12px rgba(0,0,0,0.18)',
        display: 'flex', alignItems: 'center', gap: 6,
      }}>
        <span style={{
          fontSize: 10.5, fontWeight: 700, letterSpacing: 0.5,
          color: t.accent, textTransform: 'uppercase',
        }}>Next · Ch 13</span>
        <Icons.Chevron size={13} color={t.accent} stroke={2.4}/>
      </div>
    </div>
  );
}

// A frozen auto-turn ribbon at a specific progress (for canvas display).
function FrozenRibbon({ theme, progress }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height: 1.5,
      background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.06)',
      zIndex: 28,
    }}>
      <div style={{
        height: '100%', width: `${progress * 100}%`,
        background: t.accent, opacity: t.isDark ? 0.85 : 0.7,
        boxShadow: `0 0 6px ${t.accent}55`,
      }}/>
    </div>
  );
}

// Scroll-mode frame (used to render the scroll variants).
function ScrollFrame({ themeKey = 'paper', variant = 'default' }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 402, height: 720, position: 'relative', overflow: 'hidden',
      background: t.bg, color: t.ink, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      {/* simplified top chrome */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 88, zIndex: 10,
        background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
        display: 'flex', alignItems: 'flex-end', padding: '0 14px 12px',
        justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: t.accent, fontSize: 15, fontWeight: 500 }}>
          <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library
        </div>
        <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14, fontStyle: 'italic', fontWeight: 600, color: t.ink }}>
          Pride and Prejudice
        </div>
        <Icons.More size={20} color={t.ink} stroke={1.7}/>
      </div>

      <ScrollModeContent
        theme={t} fontFamily="serif" fontSize={16} lineHeight={1.55} margin={26}
        chapters={
          variant === 'boundary' ? SCROLL_DEMO_CHAPTERS
          : variant === 'midRender' ? [SCROLL_DEMO_CHAPTERS[0]]
          : [SCROLL_DEMO_CHAPTERS[0]]
        }
        scrollY={variant === 'boundary' ? 540 : 0}
        showSkeleton={variant === 'midRender'}
      />

      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: '50%', transform: 'translateX(-50%)',
        width: 134, height: 5, borderRadius: 100, zIndex: 12,
        background: t.isDark ? 'rgba(255,255,255,0.45)' : 'rgba(0,0,0,0.32)',
      }}/>
    </div>
  );
}

function NavCanvasRoot() {
  return (
    <DesignCanvas style={{ background: '#0f0d0c' }}>
      {/* ── ① EPUB chapter nav · paged hybrid ── */}
      <DCSection id="epub-paged"
        title="① EPUB chapter nav · paged · hybrid model (#812)"
        subtitle="Side-tap zones extend across chapter boundaries. Next on last page → Ch+1 page 1. Next on last page of book → bounce.">
        <DCArtboard id="epub-paged-mid" label="Mid-chapter · default" width={402} height={720}>
          <NavFrame themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="epub-paged-boundary" label="At chapter boundary · next tap advances Ch12 → Ch13" width={402} height={720}>
          <NavFrame themeKey="paper" chapterEnd>
            <ChapterAdvanceHint theme={THEMES.paper} chapter={13}/>
          </NavFrame>
        </DCArtboard>
        <DCArtboard id="epub-paged-endofbook" label="End of book · tap bounces (no nav)" width={402} height={720}>
          <NavFrame themeKey="paper" chapterEnd endOfBook>
            <BounceHintOverlay theme={THEMES.paper}/>
          </NavFrame>
        </DCArtboard>
      </DCSection>

      {/* ── ② Scroll · continuous ── */}
      <DCSection id="epub-scroll"
        title="② EPUB chapter nav · continuous scroll (#812)"
        subtitle="Chapters flow into one column. Boundary = hairline divider + uppercase heading. Mid-render = skeleton at bottom.">
        <DCArtboard id="scroll-default" label="Scroll · Chapter 1 default" width={402} height={720}>
          <ScrollFrame themeKey="paper" variant="default"/>
        </DCArtboard>
        <DCArtboard id="scroll-boundary" label="Crossing Ch1 → Ch2 (divider in view)" width={402} height={720}>
          <ScrollFrame themeKey="paper" variant="boundary"/>
        </DCArtboard>
        <DCArtboard id="scroll-midrender" label="Mid-render · next chapter loading" width={402} height={720}>
          <ScrollFrame themeKey="paper" variant="midRender"/>
        </DCArtboard>
      </DCSection>

      {/* ── ③ MD paged-mode chrome inset (#842 §1) ── */}
      <DCSection id="md-chrome"
        title="③ MD paged-mode · chrome inset fix (#842 §1)"
        subtitle="Content insets above bottom chrome. Page indicator de-duplicated: chrome scrubber shows it when visible; content-bottom shows it when chrome hidden.">
        <DCArtboard id="md-before" label="BEFORE · content extends under chrome (broken)" width={402} height={720}>
          <BrokenMDFrame themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="md-after-chrome" label="AFTER · chrome visible · content insets above" width={402} height={720}>
          <NavFrame themeKey="paper" showTopChrome showBottomChrome/>
        </DCArtboard>
        <DCArtboard id="md-after-nochrome" label="AFTER · chrome hidden · indicator at edge" width={402} height={720}>
          <NavFrame themeKey="paper" showTopChrome={false} showBottomChrome={false}/>
        </DCArtboard>
      </DCSection>

      {/* ── ④ Auto-page-turn ribbon (#842 state) ── */}
      <DCSection id="autoturn"
        title="④ Auto-page-turn ribbon (#842 state)"
        subtitle="1.5px accent ribbon at very bottom of page. Width animates 0→100% over the interval. pointer-events: none.">
        <DCArtboard id="autoturn-start" label="0% · just turned" width={402} height={460}>
          <RibbonOnlyFrame themeKey="paper" progress={0.05}/>
        </DCArtboard>
        <DCArtboard id="autoturn-mid" label="50% · half-way" width={402} height={460}>
          <RibbonOnlyFrame themeKey="paper" progress={0.5}/>
        </DCArtboard>
        <DCArtboard id="autoturn-end" label="95% · about to turn" width={402} height={460}>
          <RibbonOnlyFrame themeKey="paper" progress={0.95}/>
        </DCArtboard>
        <DCArtboard id="autoturn-dark" label="50% · Dark" width={402} height={460}>
          <RibbonOnlyFrame themeKey="dark" progress={0.5}/>
        </DCArtboard>
      </DCSection>

      {/* ── ⑤ Tap-zone discoverability ── */}
      <DCSection id="tapzones"
        title="⑤ Tap-zone discoverability (#842 §2 · #812 affordance)"
        subtitle="Subtle one-time hint on first open. Designer debug overlay shows the 30/40/30 split.">
        <DCArtboard id="tap-hint-paper" label="First-open hint · Paper" width={402} height={720}>
          <NavFrame themeKey="paper">
            <StaticHint theme={THEMES.paper}/>
          </NavFrame>
        </DCArtboard>
        <DCArtboard id="tap-hint-dark" label="First-open hint · Dark" width={402} height={720}>
          <NavFrame themeKey="dark">
            <StaticHint theme={THEMES.dark}/>
          </NavFrame>
        </DCArtboard>
        <DCArtboard id="tap-hint-photo" label="First-open hint · Photo (highest-contrast case)" width={402} height={720}>
          <NavFrame themeKey="image">
            <StaticHint theme={THEMES.image}/>
          </NavFrame>
        </DCArtboard>
        <DCArtboard id="tap-debug" label="Debug overlay · designer-only tweak" width={402} height={720}>
          <NavFrame themeKey="paper">
            <TapZoneDebug theme={THEMES.paper}/>
          </NavFrame>
        </DCArtboard>
      </DCSection>

      {/* ── ⑥ Cross-theme matrix ── */}
      <DCSection id="theme-matrix"
        title="⑥ Cross-theme matrix"
        subtitle="The fixes work uniformly across all 5 themes. Paged · chrome visible · default.">
        {['sepia','dark','oled','image'].map(k => (
          <DCArtboard key={k} id={`matrix-${k}`} label={THEMES[k].name} width={402} height={720}>
            <NavFrame themeKey={k}/>
          </DCArtboard>
        ))}
      </DCSection>
    </DesignCanvas>
  );
}

// ─────── BROKEN before-state for §3 ───────
// Same as NavFrame but with the OLD buggy bottom: 56 inset so text extends under
// chrome. Designer-only — purely for the BEFORE artboard.
function BrokenMDFrame({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  const ff = '"Source Serif 4", Georgia, serif';
  const paragraphs = [
    'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.',
    'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
    'Mr. Bennet replied that he had not.',
    'But it is, returned she; for Mrs. Long has just been here, and she told me all about it.',
    'Mr. Bennet made no answer.',
    'Do not you want to know who has taken it? cried his wife impatiently.',
    'You want to tell me, and I have no objection to hearing it. This was invitation enough.',
  ];
  return (
    <div style={{
      width: 402, height: 720, position: 'relative', overflow: 'hidden',
      background: t.bg, color: t.ink, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, height: 88, zIndex: 10,
        background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
        display: 'flex', alignItems: 'flex-end', padding: '0 14px 12px',
        justifyContent: 'space-between',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: t.accent, fontSize: 15, fontWeight: 500 }}>
          <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/>Library
        </div>
        <div style={{ fontFamily: ff, fontSize: 14, fontStyle: 'italic', fontWeight: 600, color: t.ink }}>Pride and Prejudice</div>
        <Icons.More size={20} color={t.ink} stroke={1.7}/>
      </div>

      {/* Content with the OLD 56px inset — text extends under chrome */}
      <div style={{
        position: 'absolute', top: 88, bottom: 56,
        left: 26, right: 26, overflow: 'hidden',
      }}>
        {paragraphs.map((p, i) => (
          <p key={i} style={{
            fontFamily: ff, fontSize: 17, lineHeight: 1.55, color: t.ink,
            margin: 0, marginBottom: 11,
            textIndent: i === 0 ? 0 : 24,
            textAlign: 'justify', hyphens: 'auto',
          }}>{p}</p>
        ))}
        <div style={{
          textAlign: 'center', fontSize: 11, color: t.sub, marginTop: 4,
          display: 'flex', justifyContent: 'space-between',
        }}>
          <span>34%</span><span>147 / 432</span>
        </div>
      </div>

      {/* Annotation overlay calling out the bug */}
      <div style={{
        position: 'absolute', bottom: 145, left: 16, right: 16, zIndex: 50,
        padding: '8px 12px', borderRadius: 10,
        background: 'rgba(196,68,68,0.92)', color: '#fff',
        fontSize: 11, fontWeight: 600, textAlign: 'center',
        boxShadow: '0 4px 12px rgba(0,0,0,0.3)',
      }}>↓ Text extends under chrome. Page indicator hidden. ↓</div>

      {/* Bottom chrome OPAQUE so the bug is visible */}
      <div style={{
        position: 'absolute', bottom: 0, left: 0, right: 0,
        paddingBottom: 28, paddingTop: 14, zIndex: 10,
        background: t.chrome, borderTop: `0.5px solid ${t.rule}`,
      }}>
        <div style={{ padding: '0 22px', marginBottom: 14 }}>
          <div style={{ height: 3, borderRadius: 2, background: t.rule, position: 'relative' }}>
            <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '34%', background: t.accent, borderRadius: 2 }}/>
          </div>
          <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 11, color: t.sub, marginTop: 4 }}>
            <span>Page 147</span><span>285 pages left in book</span>
          </div>
        </div>
        <div style={{ display: 'flex', justifyContent: 'space-around', padding: '0 12px' }}>
          {[Icons.TOC, Icons.Highlighter, Icons.Aa, Icons.Sparkle].map((Ico, i) => (
            <div key={i} style={{ padding: '4px 12px' }}>
              <Ico size={22} color={i === 3 ? t.accent : t.ink} stroke={1.8}/>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}

// Ribbon-only frame (truncated for the canvas)
function RibbonOnlyFrame({ themeKey = 'paper', progress = 0.5 }) {
  const t = THEMES[themeKey];
  const ff = '"Source Serif 4", Georgia, serif';
  return (
    <div style={{
      width: 402, height: 460, position: 'relative', overflow: 'hidden',
      background: t.bg, color: t.ink, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      <div style={{ padding: '40px 26px 26px' }}>
        <div style={{
          fontFamily: ff, fontSize: 13, color: t.sub,
          letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center',
          marginBottom: 18, fontWeight: 500,
        }}>Chapter 1</div>
        <p style={{
          fontFamily: ff, fontSize: 17, lineHeight: 1.55, color: t.ink,
          margin: 0, textAlign: 'justify',
        }}>
          <span style={{ fontSize: 44, lineHeight: 0.85, float: 'left', marginRight: 6, marginTop: 4, color: t.accent, fontWeight: 600 }}>I</span>
          t is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife. However little known the feelings or views of such a man may be on his first entering a neighbourhood…
        </p>
      </div>
      <div style={{
        position: 'absolute', bottom: 32, left: 0, right: 0,
        textAlign: 'center', fontSize: 11, color: t.sub, opacity: 0.65,
        letterSpacing: 0.5,
      }}>147 / 432</div>
      <FrozenRibbon theme={t} progress={progress}/>
    </div>
  );
}

// Static (non-animated) hint overlay for canvas artboards. Mirrors TapZoneHint's
// final state.
function StaticHint({ theme }) {
  const t = theme;
  const baseTint = t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)';
  const accentTint = t.isDark ? `${t.accent}28` : `${t.accent}18`;
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 25, pointerEvents: 'none',
      display: 'flex',
    }}>
      <HintCol t={t} side="left"   flex={3} tint={accentTint}
        glyph={<Icons.ChevronL size={26} color={t.accent} stroke={2.2}/>}
        label="Tap to go back" dashed/>
      <HintCol t={t} side="center" flex={4} tint={baseTint}
        glyph={<div style={{ width: 8, height: 8, borderRadius: 4, background: t.sub }}/>}
        label="Tap to toggle controls"/>
      <HintCol t={t} side="right"  flex={3} tint={accentTint}
        glyph={<Icons.Chevron size={26} color={t.accent} stroke={2.2}/>}
        label="Tap to advance" dashed/>
    </div>
  );
}
function HintCol({ t, side, flex, tint, glyph, label, dashed }) {
  return (
    <div style={{
      flex, position: 'relative', background: tint,
      borderRight: side === 'left' && dashed ? `0.5px dashed ${t.rule}` : 'none',
      borderLeft: side === 'right' && dashed ? `0.5px dashed ${t.rule}` : 'none',
      display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', gap: 14,
    }}>
      <div style={{
        width: 56, height: 56, borderRadius: 28,
        background: t.isDark ? 'rgba(0,0,0,0.45)' : 'rgba(255,255,255,0.65)',
        boxShadow: '0 4px 14px rgba(0,0,0,0.18)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{glyph}</div>
      <div style={{
        fontSize: 11.5, fontWeight: 600, letterSpacing: 0.4,
        color: t.ink, textAlign: 'center', padding: '0 8px',
        textTransform: 'uppercase',
        textShadow: t.isDark ? '0 1px 2px rgba(0,0,0,0.45)' : '0 1px 2px rgba(255,255,255,0.65)',
      }}>{label}</div>
    </div>
  );
}

Object.assign(window, { NavCanvasRoot });
