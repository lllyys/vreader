// Bilingual follow-up suite — issues #1640 / #1646 / #1650.
//
//   #1650 — heading-translation treatment (feature #100)
//     BSHeadingPair — translated chapter-heading row. Canonical: centered echo.
//   #1646 — sentence-granularity interlinear (bug #344)
//     BSSentencePara / BSSentenceSlot — per-sentence translation rows.
//   #1640 — translation-settings re-entry (feature #99)
//     BSMorePopover (bilingual cluster w/ Translation settings row),
//     BSSettingsSheet (edit-framed BilingualSetupSheet), BSRetranslateBanner,
//     BSPillPressed (secondary affordance: tap the EN↔中 pill).
//
// All names prefixed BS to avoid collisions with the committed bundle.

const BS_SERIF = '"Source Serif 4", Georgia, serif';
const BS_CJK   = '"Noto Serif SC", "Songti SC", "Source Han Serif", serif';
const BS_JP    = '"Noto Serif JP", "Songti SC", serif';

// ────────────────────────────────────────────────────
// Sample content — P&P chapter 1, hand-paired per sentence.
// ────────────────────────────────────────────────────
const BS_PARAS = [
  { sentences: [{
      en: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
      cn: '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
  }]},
  { sentences: [{
      en: '"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"',
      cn: '有一天，班纳特太太对她丈夫说："我的好老爷，尼日斐花园终于租出去了，你听说过没有？"',
  }]},
  { sentences: [
    { en: 'Mr. Bennet replied that he had not.',
      cn: '班纳特先生回答道，没有听说过。' },
    { en: '"But it is," returned she; "for Mrs. Long has just been here, and she told me all about it."',
      cn: '"的确租出去了，"她说，"朗格太太刚刚上这儿来过，她把这件事的底细，一五一十地告诉了我。"' },
  ]},
  { sentences: [
    { en: '"You want to tell me, and I have no objection to hearing it."',
      cn: '"既然是你要说给我听，我听一听也无妨。"' },
    { en: 'This was invitation enough.',
      cn: '这句话足以鼓励她讲下去了。' },
  ]},
];

const BS_HEADINGS = {
  ch1:     { en: 'Chapter 1',  tr: '第一章' },
  ch12:    { en: 'Chapter 12', tr: '第十二章' },
  preface: { en: 'Preface',    tr: '序言' },
  long:    { en: 'On the Method of Reading Old Books', tr: '论读旧书之法' },
};

const BS_JP_P1 = '相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。';

// Mini uppercase label (SectionLabel is not window-exported from panels)
function BSuiteLabel({ t, children }) {
  return (
    <div style={{
      fontSize: 11, color: t.sub, letterSpacing: 0.8,
      textTransform: 'uppercase', fontWeight: 600,
    }}>{children}</div>
  );
}

// ────────────────────────────────────────────────────
// #1650 — heading translation row
// ────────────────────────────────────────────────────
// variant: 'centered' (canonical) | 'inline' (short headings alt) | 'border' (rejected)
// state:   'translated' | 'loading'
function BSHeadingPair({ t, en, tr, variant = 'centered', state = 'translated',
                         marginBottom = 18, lang = 'Chinese' }) {
  const trFF = lang === 'Japanese' ? BS_JP : BS_CJK;
  const enStrip = (
    <div style={{
      fontFamily: BS_SERIF, fontSize: 13, color: t.sub,
      letterSpacing: 2, textTransform: 'uppercase',
      textAlign: 'center', fontWeight: 500,
    }}>{en}</div>
  );

  if (variant === 'inline') {
    return (
      <div style={{ textAlign: 'center', marginBottom, marginTop: 8 }}>
        <span style={{
          fontFamily: BS_SERIF, fontSize: 13, color: t.sub,
          letterSpacing: 2, textTransform: 'uppercase', fontWeight: 500,
        }}>{en}</span>
        <span style={{ color: t.sub, opacity: 0.5, margin: '0 7px', fontSize: 12 }}>·</span>
        <span style={{
          fontFamily: trFF, fontSize: 14.5, color: t.sub,
          letterSpacing: 3, fontWeight: 600,
        }}>{tr}</span>
      </div>
    );
  }

  if (variant === 'border') {
    // Rejected — paragraph-row vocabulary applied to a centered heading.
    return (
      <div style={{ marginBottom, marginTop: 8 }}>
        {enStrip}
        <div style={{
          margin: '8px auto 0', maxWidth: 220,
          paddingLeft: 11, borderLeft: `2px solid ${t.accent}55`,
          fontFamily: trFF, fontSize: 13.5, color: t.sub,
          textAlign: 'left', letterSpacing: 1,
        }}>{tr}</div>
      </div>
    );
  }

  // canonical — centered echo
  return (
    <div style={{ marginBottom, marginTop: 8 }}>
      {enStrip}
      {state === 'loading' ? (
        <div style={{ display: 'flex', justifyContent: 'center', marginTop: 9 }}>
          <div style={{
            width: 72, height: 9, borderRadius: 5,
            background: `linear-gradient(90deg, ${t.rule}, ${t.isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.10)'}, ${t.rule})`,
          }}/>
        </div>
      ) : (
        <div style={{
          marginTop: 6, textAlign: 'center',
          fontFamily: trFF, fontSize: 15.5, color: t.sub,
          letterSpacing: lang === 'Chinese' || lang === 'Japanese' ? 5 : 1,
          fontWeight: 600,
        }}>{tr}</div>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// #1646 — sentence-granularity interlinear
// ────────────────────────────────────────────────────
// Translation slot under ONE sentence. Same vocabulary as the committed
// paragraph row, one step lighter: 0.85× size, 40-alpha border, tighter gaps.
// state: 'cached' | 'loading' | 'pending'
function BSSentenceSlot({ t, state = 'cached', cn, fontSize = 16, lang = 'Chinese' }) {
  const trFF = lang === 'Japanese' ? BS_JP : BS_CJK;
  const base = {
    margin: '4px 0 0',
    paddingLeft: fontSize * 0.6,
    borderLeft: `2px solid ${t.accent}40`,
  };
  if (state === 'loading') {
    return (
      <div style={{ ...base, display: 'flex', flexDirection: 'column', gap: 5, padding: `3px 0 3px ${fontSize * 0.6}px` }}>
        <div style={{ height: 8, width: '72%', borderRadius: 4,
          background: t.isDark ? 'rgba(255,255,255,0.10)' : 'rgba(0,0,0,0.07)' }}/>
        <div style={{ height: 8, width: '46%', borderRadius: 4,
          background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)' }}/>
      </div>
    );
  }
  if (state === 'pending') {
    return (
      <div style={{ ...base, borderLeft: `2px solid ${t.accent}26`, padding: `4px 0 4px ${fontSize * 0.6}px` }}>
        <div style={{
          height: 0, borderTop: `2px dashed ${t.isDark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.12)'}`,
          width: '38%', borderRadius: 1, margin: '4px 0',
        }}/>
      </div>
    );
  }
  return (
    <p style={{
      ...base,
      fontFamily: trFF, fontSize: fontSize * 0.85, lineHeight: 1.5,
      color: t.sub,
    }}>{cn}</p>
  );
}

// One paragraph in sentence mode. `first` ⇒ drop cap on the first sentence.
// states: optional array overriding per-sentence slot state.
function BSSentencePara({ t, sentences, first = false, fontSize = 16, states, lang = 'Chinese' }) {
  return (
    <div style={{ marginBottom: fontSize * 0.9 }}>
      {sentences.map((s, i) => (
        <div key={i} style={{ marginTop: i === 0 ? 0 : 7 }}>
          <p style={{
            fontFamily: BS_SERIF, fontSize, lineHeight: 1.55, color: t.ink, margin: 0,
            textIndent: !first && i === 0 ? `${fontSize * 1.4}px` : 0,
            textAlign: 'justify', hyphens: 'auto',
          }}>
            {first && i === 0 && (
              <span style={{
                fontFamily: BS_SERIF, fontSize: fontSize * 2.6, lineHeight: 0.85,
                float: 'left', marginRight: 6, marginTop: 4,
                color: t.accent, fontWeight: 600,
              }}>{s.en[0]}</span>
            )}
            {first && i === 0 ? s.en.slice(1) : s.en}
          </p>
          <BSSentenceSlot t={t} fontSize={fontSize} cn={s.cn} lang={lang}
            state={states ? states[i] : 'cached'}/>
        </div>
      ))}
    </div>
  );
}

// One paragraph in committed PARAGRAPH mode (for comparison artboards).
function BSParagraphPara({ t, sentences, first = false, fontSize = 16, state = 'cached', lang = 'Chinese', jp }) {
  const en = sentences.map(s => s.en).join(' ');
  const cn = jp || sentences.map(s => s.cn).join('');
  const trFF = lang === 'Japanese' ? BS_JP : BS_CJK;
  return (
    <div style={{ marginBottom: fontSize * 0.9 }}>
      <p style={{
        fontFamily: BS_SERIF, fontSize, lineHeight: 1.55, color: t.ink, margin: 0,
        textIndent: first ? 0 : `${fontSize * 1.4}px`,
        textAlign: 'justify', hyphens: 'auto',
      }}>
        {first && (
          <span style={{
            fontFamily: BS_SERIF, fontSize: fontSize * 2.6, lineHeight: 0.85,
            float: 'left', marginRight: 6, marginTop: 4,
            color: t.accent, fontWeight: 600,
          }}>{en[0]}</span>
        )}
        {first ? en.slice(1) : en}
      </p>
      {state === 'pending' ? (
        <div style={{
          margin: '6px 0 0', paddingLeft: fontSize * 0.7,
          borderLeft: `2px solid ${t.accent}26`,
        }}>
          <div style={{
            height: 0, borderTop: `2px dashed ${t.isDark ? 'rgba(255,255,255,0.14)' : 'rgba(0,0,0,0.12)'}`,
            width: '38%', margin: '8px 0',
          }}/>
        </div>
      ) : (
        <p style={{
          fontFamily: trFF, fontSize: fontSize * 0.88, lineHeight: 1.55,
          color: t.sub, margin: '6px 0 0',
          paddingLeft: fontSize * 0.7,
          borderLeft: `2px solid ${t.accent}55`,
        }}>{cn}</p>
      )}
    </div>
  );
}

// Full reading-page body — heading pair + paragraphs in either mode.
function BSReadingPage({ t, mode = 'sentence', heading = BS_HEADINGS.ch1,
                         headingVariant = 'centered', headingState = 'translated',
                         paras = BS_PARAS, fontSize = 16, margin = 22,
                         paraStates, lang = 'Chinese', showHeading = true }) {
  return (
    <div style={{
      position: 'absolute', top: 92, bottom: 36, left: margin, right: margin,
      overflow: 'hidden',
    }}>
      {showHeading && (
        <BSHeadingPair t={t} en={heading.en} tr={heading.tr}
          variant={headingVariant} state={headingState} lang={lang}/>
      )}
      {paras.map((p, i) => mode === 'sentence' ? (
        <BSSentencePara key={i} t={t} sentences={p.sentences} first={i === 0}
          fontSize={fontSize} states={paraStates ? paraStates[i] : undefined} lang={lang}/>
      ) : (
        <BSParagraphPara key={i} t={t} sentences={p.sentences} first={i === 0}
          fontSize={fontSize}
          state={paraStates ? paraStates[i] : 'cached'}
          lang={lang} jp={lang === 'Japanese' && i === 0 ? BS_JP_P1 : undefined}/>
      ))}
    </div>
  );
}

// ────────────────────────────────────────────────────
// #1640 — More-menu bilingual cluster + Translation settings row
// ────────────────────────────────────────────────────
function BSToggle({ t, on }) {
  return (
    <div style={{
      width: 34, height: 20, borderRadius: 10, position: 'relative', flexShrink: 0,
      background: on ? '#3a6a5a' : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'),
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 16 : 2,
        width: 16, height: 16, borderRadius: 8, background: '#fff',
        boxShadow: '0 1px 2px rgba(0,0,0,0.2)',
      }}/>
    </div>
  );
}

function BSMoreRow({ t, icon: Ico, label, sub, toggle, active, chevron, inset }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: inset ? '9px 14px 9px 14px' : '11px 14px',
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 8, flexShrink: 0,
        background: active
          ? (t.isDark ? `${t.accent}33` : `${t.accent}1a`)
          : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ico size={15} color={active ? t.accent : t.ink} stroke={1.7}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14.5, color: t.ink, fontWeight: 500, lineHeight: 1.2 }}>{label}</div>
        {sub && <div style={{ fontSize: 11, color: t.sub, marginTop: 2, lineHeight: 1.2 }}>{sub}</div>}
      </div>
      {toggle !== undefined && <BSToggle t={t} on={toggle}/>}
      {chevron && <Icons.Chevron size={13} color={t.sub} stroke={2}/>}
    </div>
  );
}

// The popover with the NEW cluster. bilingualOn drives whether the
// Translation settings row exists at all (absent when off, like #864's row).
function BSMorePopover({ t, bilingualOn = true, lang = 'Chinese',
                         granularity = 'Paragraph', provider = 'Claude',
                         settingsPressed = false }) {
  const divider = <div style={{ height: 0.5, background: t.rule, margin: '4px 14px' }}/>;
  return (
    <div style={{
      position: 'absolute', top: 92, right: 14, zIndex: 75,
      width: 268, borderRadius: 16,
      background: t.isDark ? '#2a2724' : '#fcf8f0',
      boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      padding: '6px 0', overflow: 'hidden',
    }}>
      <div style={{
        position: 'absolute', top: -6, right: 24,
        width: 12, height: 12, transform: 'rotate(45deg)',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
      }}/>
      <BSMoreRow t={t} icon={Icons.Volume} label="Read aloud" sub="Start text-to-speech" chevron/>
      <BSMoreRow t={t} icon={Icons.Timer} label="Auto-turn pages" sub="Off" toggle={false}/>

      {/* bilingual cluster — toggle + (new) settings row share one tinted group */}
      <div style={{
        margin: '3px 8px', borderRadius: 12,
        background: bilingualOn
          ? (t.isDark ? `${t.accent}14` : `${t.accent}0d`)
          : 'transparent',
      }}>
        <BSMoreRow t={t} icon={Icons.Translate} label="Bilingual mode"
          sub={bilingualOn ? `English ↔ ${lang}` : 'Translate inline'}
          toggle={bilingualOn} active={bilingualOn}/>
        {bilingualOn && (
          <>
            <div style={{ height: 0.5, background: t.rule, margin: '0 14px 0 54px' }}/>
            <div style={{
              background: settingsPressed
                ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.045)')
                : 'transparent',
              borderRadius: '0 0 12px 12px',
            }}>
              <BSMoreRow t={t} icon={Icons.Settings} label="Translation settings"
                sub={`${lang} · ${granularity} · ${provider}`} chevron/>
            </div>
          </>
        )}
      </div>

      {divider}
      <BSMoreRow t={t} icon={Icons.Info} label="Book details" chevron/>
      <BSMoreRow t={t} icon={Icons.Share} label="Share book" chevron/>
      <BSMoreRow t={t} icon={Icons.Download} label="Export annotations"
        sub="Markdown · JSON · VReader JSON" chevron/>
    </div>
  );
}

// ────────────────────────────────────────────────────
// #1640 — edit-framed settings sheet (reuses BilingualSetupSheet vocabulary)
// ────────────────────────────────────────────────────
const BS_LANGS = [
  { k: 'Chinese',  glyph: '中', cjk: true,  cached: true },
  { k: 'Japanese', glyph: '日', cjk: true,  cached: false },
  { k: 'Korean',   glyph: '한', cjk: true,  cached: false },
  { k: 'Spanish',  glyph: 'Es', cjk: false, cached: false },
  { k: 'French',   glyph: 'Fr', cjk: false, cached: true },
  { k: 'German',   glyph: 'De', cjk: false, cached: false },
];

function BSLangTile({ t, l, active }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 8,
      padding: '10px 10px', borderRadius: 12, position: 'relative',
      background: active
        ? (t.isDark ? `${t.accent}26` : `${t.accent}14`)
        : (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff'),
      boxShadow: active ? `inset 0 0 0 1.5px ${t.accent}` : `inset 0 0 0 0.5px ${t.rule}`,
    }}>
      <span style={{
        width: 22, height: 22, borderRadius: 6, flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        background: active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'),
        color: active ? '#fff' : t.ink, fontWeight: 700,
        fontFamily: l.cjk ? BS_CJK : 'inherit',
        fontSize: l.cjk ? 13 : 11,
      }}>{l.glyph}</span>
      <span style={{ fontSize: 12.5, color: t.ink, fontWeight: active ? 600 : 500 }}>{l.k}</span>
      {l.cached && (
        <span style={{
          position: 'absolute', top: -4, right: -4,
          width: 15, height: 15, borderRadius: 8,
          background: t.isDark ? '#3f6a58' : '#3a6a5a',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          boxShadow: `0 0 0 2px ${t.isDark ? '#222020' : '#fcf8f0'}`,
        }}>
          <svg width="8" height="8" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.4"
            strokeLinecap="round" strokeLinejoin="round"><path d="M4 13l5 5L20 7"/></svg>
        </span>
      )}
    </div>
  );
}

// kind: 'clean' | 'new-lang' | 'cached-lang' | 'granularity'
function BSCostStrip({ t, kind, lang = 'Japanese' }) {
  const isNew = kind === 'new-lang';
  const copy = {
    'clean':       null,
    'new-lang':    { head: `${lang} is new for this book`, sub: 'Pages re-translate as you read · ≈ $0.31 for the rest of the book.' },
    'cached-lang': { head: 'Cached — switches instantly', sub: 'This language was translated before. Nothing is re-paid.' },
    'granularity': { head: 'Granularity change re-translates', sub: 'Cached rows are per-granularity · starts from this page.' },
  }[kind];
  if (!copy) return null;
  return (
    <div style={{
      marginTop: 10, padding: '9px 12px', borderRadius: 10,
      display: 'flex', alignItems: 'flex-start', gap: 9,
      background: isNew ? `${t.accent}12` : (t.isDark ? 'rgba(255,255,255,0.04)' : 'rgba(0,0,0,0.03)'),
      border: `0.5px solid ${isNew ? `${t.accent}44` : t.rule}`,
    }}>
      <div style={{ marginTop: 1 }}>
        {isNew
          ? <Icons.Sparkle size={13} color={t.accent} stroke={2}/>
          : <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={t.sub} strokeWidth="2.4"
              strokeLinecap="round" strokeLinejoin="round"><path d="M4 13l5 5L20 7"/></svg>}
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 12, color: isNew ? t.accent : t.ink, fontWeight: 600 }}>{copy.head}</div>
        <div style={{ fontSize: 11, color: t.sub, marginTop: 2, lineHeight: 1.4 }}>{copy.sub}</div>
      </div>
    </div>
  );
}

// The whole edit-framed sheet, static. dirty: 'none' | 'new-lang' | 'cached-lang' | 'granularity'
function BSSettingsSheet({ t, selLang = 'Chinese', granularity = 'paragraph', dirty = 'none' }) {
  return (
    <Sheet theme={t} onClose={() => {}} height={604}
      title={<span style={{ whiteSpace: 'nowrap' }}>Translation settings</span>}
      leading={
        <button style={{
          background: 'none', border: 'none', padding: 0, cursor: 'pointer',
          fontFamily: 'inherit', fontSize: 13.5, color: t.accent, fontWeight: 500,
        }}>Cancel</button>
      }>
      <div style={{ padding: '10px 22px 24px' }}>
        {/* context strip — which book this edits */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14,
          fontSize: 11.5, color: t.sub,
        }}>
          <Icons.Translate size={12} color={t.sub} stroke={2}/>
          <span style={{ whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>Bilingual mode is on · <i style={{ fontFamily: BS_SERIF }}>Pride and Prejudice</i></span>
        </div>

        <BSuiteLabel t={t}>Target language</BSuiteLabel>
        <div style={{
          marginTop: 10, display: 'grid',
          gridTemplateColumns: 'repeat(3, 1fr)', gap: 8,
        }}>
          {BS_LANGS.map(l => <BSLangTile key={l.k} t={t} l={l} active={l.k === selLang}/>)}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 8 }}>
          <span style={{
            width: 11, height: 11, borderRadius: 6, flexShrink: 0,
            background: t.isDark ? '#3f6a58' : '#3a6a5a',
            display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="6" height="6" viewBox="0 0 24 24" fill="none" stroke="#fff" strokeWidth="3.6"
              strokeLinecap="round" strokeLinejoin="round"><path d="M4 13l5 5L20 7"/></svg>
          </span>
          <span style={{ fontSize: 10.5, color: t.sub }}>Already translated — switching back is instant</span>
        </div>

        {(dirty === 'new-lang' || dirty === 'cached-lang') && (
          <BSCostStrip t={t} kind={dirty} lang={selLang}/>
        )}

        <div style={{ marginTop: 18 }}>
          <BSuiteLabel t={t}>Granularity</BSuiteLabel>
          <div style={{
            display: 'flex', marginTop: 10, borderRadius: 12, padding: 3,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          }}>
            {[
              { k: 'paragraph', label: 'Paragraph', sub: 'Translate after each ¶' },
              { k: 'sentence',  label: 'Sentence',  sub: 'Translate after each sentence' },
            ].map(o => (
              <div key={o.k} style={{
                flex: 1, padding: '10px 10px', borderRadius: 10, textAlign: 'center',
                background: granularity === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                boxShadow: granularity === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
              }}>
                <div style={{ fontSize: 13, fontWeight: 600, color: t.ink }}>{o.label}</div>
                <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{o.sub}</div>
              </div>
            ))}
          </div>
          {dirty === 'granularity' && <BSCostStrip t={t} kind="granularity"/>}
        </div>

        {/* engine row, compact */}
        <div style={{
          marginTop: 18, padding: '10px 12px', borderRadius: 12,
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          border: `0.5px solid ${t.rule}`,
          display: 'flex', alignItems: 'center', gap: 10,
        }}>
          <div style={{
            width: 24, height: 24, borderRadius: 12, flexShrink: 0,
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Sparkle size={12} color="#fff" stroke={2}/>
          </div>
          <div style={{ flex: 1, fontSize: 12.5, color: t.ink, fontWeight: 600 }}>
            Claude · with this book&rsquo;s context
          </div>
          <span style={{ fontSize: 11.5, color: t.accent, fontWeight: 600 }}>Change…</span>
        </div>

        {/* footer CTA */}
        <button style={{
          width: '100%', marginTop: 20, padding: '13px 0', borderRadius: 14,
          border: 'none', fontFamily: 'inherit', fontSize: 15, fontWeight: 600,
          cursor: 'pointer',
          background: dirty === 'none'
            ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)')
            : t.accent,
          color: dirty === 'none' ? t.ink : '#fff',
          boxShadow: dirty === 'none' ? 'none' : `0 4px 14px ${t.accent}55`,
        }}>
          {dirty === 'none' ? 'Done'
            : dirty === 'cached-lang' ? 'Switch to ' + selLang
            : 'Apply · re-translate as you read'}
        </button>
      </div>
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// #1640 — confirmed state: re-translating banner under the top chrome
// ────────────────────────────────────────────────────
function BSRetranslateBanner({ t, lang = 'Japanese', detail = 'Cached Chinese stays — switch back anytime' }) {
  return (
    <div style={{
      position: 'absolute', top: 100, left: 14, right: 14, zIndex: 40,
      padding: '9px 13px', borderRadius: 12,
      display: 'flex', alignItems: 'center', gap: 10,
      background: t.isDark ? 'rgba(42,39,36,0.96)' : 'rgba(252,248,240,0.96)',
      border: `0.5px solid ${t.accent}44`,
      boxShadow: '0 6px 20px rgba(0,0,0,0.16)',
    }}>
      <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke={t.accent}
        strokeWidth="2.6" strokeLinecap="round">
        <path d="M12 3a9 9 0 109 9"/>
      </svg>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12.5, color: t.ink, fontWeight: 600 }}>Re-translating in {lang}…</div>
        <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{detail}</div>
      </div>
      <span style={{ fontSize: 11, color: t.sub, flexShrink: 0, whiteSpace: 'nowrap' }}>p. 3 →</span>
    </div>
  );
}

// ────────────────────────────────────────────────────
// #1640 — secondary affordance: the EN↔中 pill is tappable
// ────────────────────────────────────────────────────
function BSBilingualPill({ t, lang = 'Chinese', pressed = false }) {
  const glyph = lang === 'Japanese' ? '日' : '中';
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 3,
      padding: '2px 7px 2px 3px', borderRadius: 100, marginLeft: 6,
      background: pressed ? `${t.accent}33` : `${t.accent}1a`,
      boxShadow: pressed ? `0 0 0 2px ${t.accent}55` : 'none',
      color: t.accent, fontStyle: 'normal',
      fontFamily: '"Inter", system-ui', fontSize: 9.5, fontWeight: 600,
      verticalAlign: 'middle',
    }}>
      <span style={{
        width: 14, height: 14, borderRadius: 7, background: t.accent,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', fontSize: 8, fontWeight: 700,
      }}>EN</span>
      <span style={{ opacity: 0.7, fontSize: 8 }}>↔</span>
      <span style={{ fontFamily: BS_CJK, fontWeight: 700, fontSize: 11 }}>{glyph}</span>
    </span>
  );
}

Object.assign(window, {
  BS_PARAS, BS_HEADINGS, BS_SERIF, BS_CJK,
  BSuiteLabel, BSHeadingPair, BSSentenceSlot, BSSentencePara, BSParagraphPara,
  BSReadingPage, BSMorePopover, BSSettingsSheet, BSCostStrip,
  BSRetranslateBanner, BSBilingualPill,
});
