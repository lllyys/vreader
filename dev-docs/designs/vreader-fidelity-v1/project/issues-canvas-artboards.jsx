// Canvas artboards for the five `needs-design` issues:
//   #865 — Tap-on-annotated-text note-preview presenter (feature #55)
//   #864 — Per-chapter re-translate menu + provider-override picker (feature #56)
//   #863 — Translate-entire-book entry / confirm / progress / cancel (feature #56)
//   #862 — Settings profile-header identity + reading-stats dashboard (#67 / #58)
//   #860 — HighlightsSheet filter content with standalone notes (feature #62)

const I_BOOK = (typeof BOOKS !== 'undefined' && BOOKS.find(b => b.id === 'pp')) || {
  title: 'Pride and Prejudice', author: 'Jane Austen', year: 1813, format: 'EPUB',
};

// Phone-width artboards. Borderless w/ subtle device shadow so artboards read as
// finished phone surfaces rather than dialog boxes.
const PHONE_W = 402;

function PhoneFrame({ themeKey = 'paper', children, height = 720, withFakePage = true }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      {withFakePage && <FakeReader t={t}/>}
      {children}
    </div>
  );
}

// Reader-page background for sheets to dim over. Lightly muted text in serif.
function FakeReader({ t }) {
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '60px 26px 50px', opacity: 0.5 }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11,
        color: t.sub, letterSpacing: 2, textTransform: 'uppercase',
        textAlign: 'center', marginBottom: 16,
      }}>Chapter 1</div>
      {[
        'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
        'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families…',
        'My dear Mr. Bennet, said his lady to him one day, have you heard that Netherfield Park is let at last?',
      ].map((p, i) => (
        <p key={i} style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, lineHeight: 1.55, color: t.ink,
          margin: '0 0 12px', textIndent: i === 0 ? 0 : 18,
          textAlign: 'justify',
        }}>{p}</p>
      ))}
    </div>
  );
}

function FakeReaderWithAnnotation({ t }) {
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '70px 26px 50px' }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 11,
        color: t.sub, letterSpacing: 2, textTransform: 'uppercase',
        textAlign: 'center', marginBottom: 16,
      }}>Chapter 3</div>
      <p style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 16, lineHeight: 1.6, color: t.ink, textAlign: 'justify',
        margin: 0,
      }}>
        Mr. Bingley had soon made himself acquainted with all the principal
        people in the room; he was lively and unreserved, danced every dance,
        was angry that the ball closed so early, and talked of giving one himself
        at Netherfield.{' '}
        <span data-annotation-anchor style={{
          background: 'rgba(240,210,90,0.45)', borderRadius: 2,
          padding: '0 1px', boxShadow: 'inset 0 -1px 0 rgba(0,0,0,0.04)',
        }}>Such amiable qualities must speak for themselves.</span>
        {' '}He danced with Mrs. Hurst and Miss Bingley, was introduced to Miss
        Bennet, and afterwards danced with Elizabeth.
      </p>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Section 1 — #865 Note-preview presenter
// ════════════════════════════════════════════════════
function NotePreviewArtboard({ themeKey, mode = 'reading', side = 'below', presenter = 'callout' }) {
  const t = THEMES[themeKey];
  const highlight = {
    id: 'h99', color: 'yellow', text: 'Such amiable qualities must speak for themselves.',
    date: 'Apr 18',
    note: mode === 'empty' ? '' :
      'Bingley\'s charm is presented through external impression — \"speak for themselves\" — which the rest of the chapter then undermines. Compare with how Darcy is introduced.',
  };
  // synthetic anchor rect — where the underline sits in the demo page
  const anchorRect = { left: 70, top: 198, width: 250, height: 24, containerW: PHONE_W };

  if (presenter === 'sheet') {
    return (
      <PhoneFrame themeKey={themeKey} withFakePage={false}>
        <FakeReaderWithAnnotation t={t}/>
        <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.25)' }}/>
        <NotePreviewSheet theme={t} highlight={highlight} onEdit={() => {}} onClose={() => {}}/>
      </PhoneFrame>
    );
  }

  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <FakeReaderWithAnnotation t={t}/>
      <NoteCallout theme={t} highlight={highlight} anchorRect={anchorRect}
        side={side} mode={mode}
        onEdit={() => {}} onClose={() => {}}/>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// Section 2 — #864 Per-chapter re-translate
// ════════════════════════════════════════════════════

// Fake top chrome + More-popover frame — to show the row in context.
function MorePopoverFrame({ themeKey, state = 'idle' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey}>
      <FakeTopChromeReader t={t}/>
      {/* popover */}
      <div style={{
        position: 'absolute', top: 92, right: 14, zIndex: 75,
        width: 268, borderRadius: 16, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        padding: '6px 0',
      }}>
        <div style={{
          position: 'absolute', top: -6, right: 24,
          width: 12, height: 12, transform: 'rotate(45deg)',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}/>
        <MiniRow theme={t} icon={Icons.Volume} label="Read aloud" sub="Start text-to-speech"/>
        <MiniRow theme={t} icon={Icons.Timer} label="Auto-turn pages" sub="Off" toggle={false}/>
        <MiniRow theme={t} icon={Icons.Translate} label="Bilingual mode" sub="English ↔ Chinese" toggle={true} active/>
        <ReTranslateMoreRow theme={t} state={state}
          provider="Claude · Sonnet 4.5"
          progress={state === 'running' ? 38 : 0}/>
        <div style={{ height: 0.5, background: t.rule, margin: '4px 14px' }}/>
        <MiniRow theme={t} icon={Icons.Info} label="Book details" trailing/>
      </div>
    </PhoneFrame>
  );
}

function MiniRow({ theme: t, icon: Ico, label, sub, toggle, active, trailing }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px',
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 8,
        background: active ? `${t.accent}1a` : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ico size={15} color={active ? t.accent : t.ink} stroke={1.7}/>
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 14.5, color: t.ink, fontWeight: 500 }}>{label}</div>
        {sub && <div style={{ fontSize: 11, color: t.sub, marginTop: 2 }}>{sub}</div>}
      </div>
      {toggle !== undefined && <PillSwitch on={!!toggle} theme={t}/>}
      {trailing && <Icons.Chevron size={13} color={t.sub} stroke={2}/>}
    </div>
  );
}

function FakeTopChromeReader({ t, bilingualOn = true }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, paddingTop: 50, paddingBottom: 12, zIndex: 30,
      background: t.chrome, borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 14px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 4, color: t.accent, fontSize: 15, fontWeight: 500 }}>
          <Icons.ChevronL size={20} color={t.accent} stroke={2.2}/> Library
        </div>
        <div style={{
          flex: 1, textAlign: 'center', padding: '0 8px',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, fontWeight: 600, color: t.ink, fontStyle: 'italic',
        }}>
          Pride and Prejudice
          {bilingualOn && typeof BilingualPill !== 'undefined' && <BilingualPill theme={t} lang="Chinese"/>}
        </div>
        <div style={{ display: 'flex' }}>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icons.Search size={18} color={t.ink} stroke={1.7}/>
          </div>
          <div style={{ width: 36, height: 36, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icons.Bookmark size={18} color={t.ink} stroke={1.7}/>
          </div>
          <div style={{
            width: 36, height: 36, borderRadius: 18, display: 'flex',
            alignItems: 'center', justifyContent: 'center',
            background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
          }}>
            <Icons.More size={20} color={t.ink} stroke={1.7}/>
          </div>
        </div>
      </div>
    </div>
  );
}

function ProviderPickerArtboard({ themeKey, state = 'idle', error = null,
                                  provider = 'claude', styleK = 'natural' }) {
  const t = THEMES[themeKey];
  const v = { provider, model: PROVIDERS.find(p => p.id === provider).models[0], style: styleK, glossary: true };
  return (
    <PhoneFrame themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.35)' }}/>
      <ReTranslatePickerSheet theme={t} value={v} onChange={() => {}}
        state={state} progress={state === 'running' ? 38 : 0}
        error={error}
        onCancel={() => {}} onSubmit={() => {}}/>
    </PhoneFrame>
  );
}

function TOCSwipeArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <Sheet theme={t} onClose={() => {}} height={720} title="Pride and Prejudice">
        <div style={{ padding: '8px 18px 0' }}>
          <div style={{
            display: 'flex', borderRadius: 10, padding: 3,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          }}>
            <div style={{
              flex: 1, padding: '7px 0', borderRadius: 8,
              background: t.isDark ? '#3a3530' : '#fff',
              color: t.ink, fontSize: 13, fontWeight: 500, textAlign: 'center',
              boxShadow: '0 1px 2px rgba(0,0,0,0.08)',
            }}>Contents</div>
            <div style={{ flex: 1, padding: '7px 0', color: t.ink, fontSize: 13, fontWeight: 500, textAlign: 'center' }}>
              Bookmarks
            </div>
          </div>
        </div>
        <div style={{ padding: '14px 0 8px' }}>
          {[
            { ch: 1, title: 'Bingley arrives at Netherfield', page: 1, translated: true, current: false },
            { ch: 2, title: 'Mr. Bennet pays his call', page: 12, translated: true, current: false },
            { ch: 3, title: 'The Meryton assembly', page: 18, translated: true, current: true, swiped: true },
            { ch: 4, title: 'Jane and Elizabeth in private', page: 28, translated: true, current: false },
            { ch: 5, title: 'Sir William and Charlotte Lucas', page: 34, translated: true, current: false },
            { ch: 6, title: 'Bingleys and Bennets visit Lucas Lodge', page: 40, translated: false, current: false },
          ].map(c => (
            <div key={c.ch} style={{ position: 'relative', height: 48 }}>
              <div style={{
                position: 'absolute', inset: 0,
                display: 'flex', alignItems: 'baseline', gap: 14,
                padding: '12px 18px',
                background: c.current
                  ? (t.isDark ? `${t.accent}1f` : `${t.accent}10`)
                  : 'transparent',
                transform: c.swiped ? 'translateX(-88px)' : 'translateX(0)',
                transition: 'transform 0.2s ease',
              }}>
                <span style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 12, color: t.sub, fontWeight: 500, width: 24, textAlign: 'right',
                }}>{c.ch}</span>
                <span style={{
                  flex: 1, fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: 15, color: c.current ? t.accent : t.ink,
                  fontWeight: c.current ? 600 : 400,
                  overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
                }}>{c.title}</span>
                {c.translated && (
                  <div title="Translated" style={{
                    width: 16, height: 16, borderRadius: 8,
                    background: 'rgba(58,106,90,0.18)', color: '#3a6a5a',
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                  }}>
                    <Icons.Translate size={9} color="#3a6a5a" stroke={2.4}/>
                  </div>
                )}
                <span style={{ fontSize: 12, color: t.sub }}>p. {c.page}</span>
              </div>
              {c.swiped && (
                <div style={{
                  position: 'absolute', top: 0, bottom: 0, right: 0, width: 88,
                }}>
                  <ChapterSwipeAction theme={t} label="Re-translate" onClick={() => {}}/>
                </div>
              )}
            </div>
          ))}
        </div>
      </Sheet>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// Section 3 — #863 Translate entire book
// ════════════════════════════════════════════════════

// Book Details sheet artboard — surfaces the new Actions row in context.
function BookDetailsEntryArtboard({ themeKey, status = 'idle' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <Sheet theme={t} onClose={() => {}} height={720} title="Book details">
        <div style={{ padding: '18px 22px 28px' }}>
          {/* compact cover + title */}
          <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12, marginBottom: 16 }}>
            {typeof BookCover !== 'undefined' && (
              <BookCover book={I_BOOK} width={104} height={156} radius={4}/>
            )}
            <div style={{ textAlign: 'center' }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 20, fontStyle: 'italic', fontWeight: 600,
                color: t.ink, lineHeight: 1.15,
              }}>{I_BOOK.title}</div>
              <div style={{ fontSize: 12.5, color: t.sub, marginTop: 4 }}>
                {I_BOOK.author} · {I_BOOK.year}
              </div>
            </div>
          </div>

          <SectionLabel theme={t}>Actions</SectionLabel>
          <div style={{
            marginTop: 8, borderRadius: 14, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          }}>
            <ActionRow theme={t} icon={Icons.Image} label="Replace cover…"/>
            <TranslateBookActionRow theme={t} status={status}
              progress={status === 'running' ? { done: 12, total: 61 } : null}
              onOpen={() => {}}/>
            <ActionRow theme={t} icon={Icons.Share} label="Share book…"/>
            <ActionRow theme={t} icon={Icons.Download} label="Export annotations…" last/>
          </div>
        </div>
      </Sheet>
    </PhoneFrame>
  );
}

function ActionRow({ theme: t, icon: Ico, label, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0,
        background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ico size={15} color={t.ink} stroke={1.7}/>
      </div>
      <div style={{ flex: 1, fontSize: 14.5, color: t.ink, fontWeight: 500 }}>{label}</div>
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </div>
  );
}

function LibraryLongPressArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  // mock library card with iOS-style context menu floating over it
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      {/* Library top bar */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, padding: '54px 18px 12px',
      }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 32, fontWeight: 700, color: t.ink, letterSpacing: -0.6,
        }}>Library</div>
      </div>
      {/* dim */}
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.5)', backdropFilter: 'blur(6px)' }}/>
      {/* the highlighted card */}
      <div style={{
        position: 'absolute', top: 132, left: 90, width: 130,
        animation: 'popIn 0.2s cubic-bezier(0.32, 0.72, 0, 1)',
      }}>
        <div style={{ position: 'relative', borderRadius: 8, overflow: 'hidden', boxShadow: '0 16px 50px rgba(0,0,0,0.5)' }}>
          {typeof BookCover !== 'undefined' && <BookCover book={I_BOOK} width={130} height={196} radius={6}/>}
        </div>
        <div style={{
          marginTop: 10, fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13.5, fontStyle: 'italic', fontWeight: 600, color: '#f6f1e6', textAlign: 'center',
        }}>{I_BOOK.title}</div>
      </div>
      {/* context menu */}
      <div style={{
        position: 'absolute', top: 360, left: 90, width: 220,
        borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(40,38,34,0.96)' : 'rgba(252,248,240,0.96)',
        backdropFilter: 'blur(20px)',
        boxShadow: '0 12px 40px rgba(0,0,0,0.4)',
      }}>
        {[
          { ico: Icons.Bookmark,  label: 'Mark as finished' },
          { ico: Icons.Translate, label: 'Translate entire book…', accent: true },
          { ico: Icons.Share,     label: 'Share' },
          { ico: Icons.Info,      label: 'Book details' },
          { ico: Icons.Close,     label: 'Remove from library', danger: true },
        ].map((m, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '11px 14px',
            borderTop: i === 0 ? 'none' : `0.5px solid ${t.rule}`,
            color: m.danger ? '#c44' : (m.accent ? t.accent : t.ink),
            fontFamily: 'inherit', fontSize: 14, fontWeight: m.accent ? 600 : 500,
          }}>
            <span>{m.label}</span>
            <m.ico size={15} color={m.danger ? '#c44' : (m.accent ? t.accent : t.ink)} stroke={1.7}/>
          </div>
        ))}
      </div>
    </PhoneFrame>
  );
}

function ConfirmAlertArtboard({ themeKey }) {
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: THEMES[themeKey].bg }}/>
      <FakeReader t={THEMES[themeKey]}/>
      <TranslateBookConfirmAlert theme={THEMES[themeKey]} book={I_BOOK}
        provider="Claude · Sonnet 4.5"
        onChangeProvider={() => {}} onCancel={() => {}} onConfirm={() => {}}/>
    </PhoneFrame>
  );
}

function LibraryBadgeArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <div style={{ position: 'absolute', top: 60, left: 0, right: 0, padding: '0 18px' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 30, fontWeight: 700, color: t.ink, letterSpacing: -0.6, marginBottom: 16,
        }}>Library</div>
        <div style={{
          display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 16,
        }}>
          {[
            { book: BOOKS.find(b => b.id === 'pp'),  badge: 'running' },
            { book: BOOKS.find(b => b.id === 'bi'),  badge: 'idle' },
            { book: BOOKS.find(b => b.id === 'ddia'), badge: 'translated' },
            { book: BOOKS.find(b => b.id === 'prag'), badge: 'idle' },
            { book: BOOKS.find(b => b.id === 'med'),  badge: 'idle' },
            { book: BOOKS.find(b => b.id === '3b'),   badge: 'idle' },
          ].filter(x => x.book).map((x, i) => (
            <div key={i}>
              <div style={{ position: 'relative', width: '100%', aspectRatio: '2/3' }}>
                {typeof BookCover !== 'undefined' && <BookCover book={x.book} width={110} height={165} radius={4}/>}
                {(x.badge === 'running' || x.badge === 'translated') && (
                  <LibraryCardTranslateBadge theme={t} status={x.badge}
                    progress={{ done: 12, total: 61 }}/>
                )}
              </div>
              <div style={{
                marginTop: 8, fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 11.5, fontStyle: 'italic', fontWeight: 600, color: t.ink,
                lineHeight: 1.25, overflow: 'hidden', display: '-webkit-box',
                WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
              }}>{x.book.title}</div>
              <div style={{ fontSize: 10, color: t.sub, marginTop: 2 }}>{x.book.author}</div>
            </div>
          ))}
        </div>
      </div>
    </PhoneFrame>
  );
}

function ReaderBannerArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <FakeReader t={t}/>
      <FakeTopChromeReader t={t} bilingualOn={true}/>
      <ReaderTranslateBanner theme={t} progress={{ done: 12, total: 61 }}
        onOpen={() => {}} onCancel={() => {}}/>
    </PhoneFrame>
  );
}

function StatusSheetArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <TranslateStatusSheet theme={t} book={I_BOOK} onClose={() => {}} onCancelAll={() => {}}/>
    </PhoneFrame>
  );
}

function CancelAlertArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <TranslateStatusSheet theme={t} book={I_BOOK} onClose={() => {}} onCancelAll={() => {}}/>
      <TranslateCancelAlert theme={t} progress={{ done: 12, total: 61 }}
        onKeep={() => {}} onConfirm={() => {}}/>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// Section 4 — #862 Profile-card + reading stats dashboard
// ════════════════════════════════════════════════════

function SettingsHeaderArtboard({ themeKey, variant = 'library', name = 'Tom' }) {
  const t = THEMES[themeKey];
  const Card = variant === 'library' ? ProfileCardLibrary
            : variant === 'named'   ? ProfileCardNamed
            : ProfileCardStatsHero;
  const props = variant === 'named' ? { name } : {};
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <Sheet theme={t} onClose={() => {}} height={720} title="Settings">
        <div style={{ padding: '16px 18px 32px' }}>
          <Card theme={t} {...props}/>

          {/* a couple of settings rows below to anchor the card in context */}
          <div style={{ marginTop: 18 }}>
            <SectionLabel theme={t}>Cloud & Sync</SectionLabel>
            <div style={{
              marginTop: 8, borderRadius: 14, overflow: 'hidden',
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            }}>
              <SettingsRow theme={t} icon={<Icons.Cloud size={17} color="#fff" stroke={1.8}/>}
                color="#3a8ac8" title="WebDAV backup" detail="Nutstore · last sync 2h ago" value="On"/>
              <SettingsRow theme={t} icon={<Icons.Folder size={17} color="#fff" stroke={1.8}/>}
                color="#7c6ad6" title="OPDS catalogs" value="3"/>
              <SettingsRow theme={t} icon={<Icons.Library size={17} color="#fff" stroke={1.8}/>}
                color="#3a6a5a" title="Book sources" value="12" last/>
            </div>
          </div>

          <div style={{ marginTop: 18 }}>
            <SectionLabel theme={t}>AI</SectionLabel>
            <div style={{
              marginTop: 8, borderRadius: 14, overflow: 'hidden',
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            }}>
              <SettingsRow theme={t} icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
                color="#8c2f2f" title="AI provider" value="Claude"/>
              <SettingsRow theme={t} icon={<Icons.Translate size={17} color="#fff" stroke={1.8}/>}
                color="#c87a3a" title="Translation languages" value="9" last/>
            </div>
          </div>
        </div>
      </Sheet>
    </PhoneFrame>
  );
}

function SettingsRow({ theme: t, icon, color, title, detail, value, last }) {
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

function StatsDashboardArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <FullStatsDashboard theme={t} onClose={() => {}}/>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// Section 5 — #860 Unified HighlightsSheet
// ════════════════════════════════════════════════════
function HighlightsUnifiedArtboard({ themeKey, filter = 'all', empty = false }) {
  const t = THEMES[themeKey];
  return (
    <PhoneFrame themeKey={themeKey} withFakePage={false}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <HighlightsSheetV3 theme={t}
        highlights={empty ? [] : SAMPLE_HIGHLIGHTS_PLUS_NOTES}
        standalones={empty ? [] : SAMPLE_STANDALONE}
        filter={filter} onClose={() => {}}/>
    </PhoneFrame>
  );
}

// ════════════════════════════════════════════════════
// CanvasRoot
// ════════════════════════════════════════════════════
function CanvasRoot() {
  return (
    <DesignCanvas>
      {/* ───── #865 ───── */}
      <DCSection id="i865" title="#865 — Note-preview presenter"
        subtitle="Tap an annotated passage → reveal the attached note. Anchored callout with empty/edit states.">
        <DCArtboard id="callout-default" label="Callout · default (canonical)" width={PHONE_W} height={460}>
          <NotePreviewArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="callout-above" label="Callout · above passage" width={PHONE_W} height={460}>
          <NotePreviewArtboard themeKey="paper" side="above"/>
        </DCArtboard>
        <DCArtboard id="callout-empty" label="Empty / no-note state" width={PHONE_W} height={460}>
          <NotePreviewArtboard themeKey="sepia" mode="empty"/>
        </DCArtboard>
        <DCArtboard id="callout-editing" label="Editing inline" width={PHONE_W} height={460}>
          <NotePreviewArtboard themeKey="paper" mode="editing"/>
        </DCArtboard>
        <DCArtboard id="callout-dark" label="Dark theme" width={PHONE_W} height={460}>
          <NotePreviewArtboard themeKey="dark"/>
        </DCArtboard>
        <DCArtboard id="callout-sheet" label="Bottom-sheet fallback (long notes / VO)" width={PHONE_W} height={480}>
          <NotePreviewArtboard themeKey="paper" presenter="sheet"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={3} width={220}>
          The callout is the canonical form — it keeps the note adjacent to the passage so the read-the-note loop stays tight. The sheet variant is the fallback for very long notes and VoiceOver.
        </DCPostIt>
      </DCSection>

      {/* ───── #864 ───── */}
      <DCSection id="i864" title="#864 — Per-chapter re-translate"
        subtitle="Affordance lives in the More popover (canonical) + TOC swipe action. Provider picker is a half-sheet with cost preview.">
        <DCArtboard id="more-idle" label="More popover — idle" width={PHONE_W} height={460}>
          <MorePopoverFrame themeKey="paper" state="idle"/>
        </DCArtboard>
        <DCArtboard id="more-running" label="More popover — running" width={PHONE_W} height={460}>
          <MorePopoverFrame themeKey="paper" state="running"/>
        </DCArtboard>
        <DCArtboard id="more-error" label="More popover — error" width={PHONE_W} height={460}>
          <MorePopoverFrame themeKey="paper" state="error"/>
        </DCArtboard>
        <DCArtboard id="toc-swipe" label="TOC swipe action" width={PHONE_W} height={520}>
          <TOCSwipeArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="picker-default" label="Provider picker · idle" width={PHONE_W} height={720}>
          <ProviderPickerArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="picker-local" label="Picker · Local (free)" width={PHONE_W} height={720}>
          <ProviderPickerArtboard themeKey="paper" provider="local"/>
        </DCArtboard>
        <DCArtboard id="picker-running" label="Picker · running" width={PHONE_W} height={400}>
          <ProviderPickerArtboard themeKey="paper" state="running"/>
        </DCArtboard>
        <DCArtboard id="picker-error" label="Picker · error" width={PHONE_W} height={720}>
          <ProviderPickerArtboard themeKey="paper" error="Provider returned 429 — rate-limited. Try again in 30 s or pick a different provider."/>
        </DCArtboard>
        <DCArtboard id="picker-dark" label="Picker · dark" width={PHONE_W} height={720}>
          <ProviderPickerArtboard themeKey="dark"/>
        </DCArtboard>
      </DCSection>

      {/* ───── #863 ───── */}
      <DCSection id="i863" title="#863 — Translate entire book"
        subtitle="Entry: Book Details > Actions + library long-press. Confirmation alert · in-progress badges · status sheet · cancel.">
        <DCArtboard id="details-idle" label="Book Details · idle (entry)" width={PHONE_W} height={720}>
          <BookDetailsEntryArtboard themeKey="paper" status="idle"/>
        </DCArtboard>
        <DCArtboard id="details-running" label="Book Details · running" width={PHONE_W} height={720}>
          <BookDetailsEntryArtboard themeKey="paper" status="running"/>
        </DCArtboard>
        <DCArtboard id="details-translated" label="Book Details · translated" width={PHONE_W} height={720}>
          <BookDetailsEntryArtboard themeKey="paper" status="translated"/>
        </DCArtboard>
        <DCArtboard id="library-longpress" label="Library long-press menu" width={PHONE_W} height={720}>
          <LibraryLongPressArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="confirm" label="Confirmation alert" width={PHONE_W} height={720}>
          <ConfirmAlertArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="lib-badges" label="Library · running badge + done check" width={PHONE_W} height={720}>
          <LibraryBadgeArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="reader-banner" label="Reader · in-progress banner" width={PHONE_W} height={720}>
          <ReaderBannerArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="status-sheet" label="Status sheet · per-chapter" width={PHONE_W} height={720}>
          <StatusSheetArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="status-dark" label="Status sheet · dark" width={PHONE_W} height={720}>
          <StatusSheetArtboard themeKey="dark"/>
        </DCArtboard>
        <DCArtboard id="cancel-alert" label="Cancel confirmation alert" width={PHONE_W} height={720}>
          <CancelAlertArtboard themeKey="paper"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={-2} width={240}>
          Cancel says exactly what's lost (nothing) and what stays cached. The whole reason this surface exists is to fight the user's instinct that hitting Cancel throws money away.
        </DCPostIt>
      </DCSection>

      {/* ───── #862 ───── */}
      <DCSection id="i862" title="#862 — Profile-header identity + reading-stats dashboard"
        subtitle="Identity options A/B/C — canonical = Library-as-identity. Stats dashboard adds time-window bar + sortable per-book table.">
        <DCArtboard id="profile-library" label="A · Library-as-identity (canonical)" width={PHONE_W} height={520}>
          <SettingsHeaderArtboard themeKey="paper" variant="library"/>
        </DCArtboard>
        <DCArtboard id="profile-named" label="B · User-set display name" width={PHONE_W} height={520}>
          <SettingsHeaderArtboard themeKey="paper" variant="named" name="Tom Foley"/>
        </DCArtboard>
        <DCArtboard id="profile-stats" label="C · Stats-as-hero" width={PHONE_W} height={520}>
          <SettingsHeaderArtboard themeKey="paper" variant="stats"/>
        </DCArtboard>
        <DCArtboard id="profile-dark" label="A · Dark" width={PHONE_W} height={520}>
          <SettingsHeaderArtboard themeKey="dark" variant="library"/>
        </DCArtboard>
        <DCArtboard id="stats-30d" label="Stats dashboard · 30d" width={PHONE_W} height={720}>
          <StatsDashboardArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="stats-dark" label="Stats dashboard · dark" width={PHONE_W} height={720}>
          <StatsDashboardArtboard themeKey="dark"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={240}>
          Identity option A wins on honesty — the app has no user, so the card represents the LIBRARY. Layout is lossless if we ever add accounts: avatar slot becomes user photo, label becomes display name.
        </DCPostIt>
      </DCSection>

      {/* ───── #860 ───── */}
      <DCSection id="i860" title="#860 — HighlightsSheet · standalone notes"
        subtitle="Extends v2 to render BOTH HighlightRecord and standalone AnnotationRecord cards. Notes filter merges both kinds.">
        <DCArtboard id="all-filter" label="All · merged stream" width={PHONE_W} height={680}>
          <HighlightsUnifiedArtboard themeKey="paper" filter="all"/>
        </DCArtboard>
        <DCArtboard id="highlights-filter" label="Highlights only" width={PHONE_W} height={680}>
          <HighlightsUnifiedArtboard themeKey="paper" filter="highlights"/>
        </DCArtboard>
        <DCArtboard id="notes-filter" label="Notes · highlight-notes + standalones" width={PHONE_W} height={680}>
          <HighlightsUnifiedArtboard themeKey="paper" filter="notes"/>
        </DCArtboard>
        <DCArtboard id="all-empty" label="Empty state · All" width={PHONE_W} height={680}>
          <HighlightsUnifiedArtboard themeKey="paper" filter="all" empty/>
        </DCArtboard>
        <DCArtboard id="all-dark" label="All · dark" width={PHONE_W} height={680}>
          <HighlightsUnifiedArtboard themeKey="dark" filter="all"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={-2} width={240}>
          Decision: option 2 from the issue — extend the design. Folding standalones into highlight-notes is a data-model change with a migration; deprecating standalones loses a wired feature + breaks export.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot });
