// Bilingual mode — feature #60 follow-up (#790)
//
// Two surfaces:
//   1. BilingualSetup — half-sheet shown the first time the More-menu toggle flips ON.
//      Picks target language, granularity, surfaces AI provider config.
//   2. BilingualReader — paragraph-interlinear renderer.
//      Each source paragraph is followed by a translated paragraph in a smaller, muted style.
//
// The More-menu row gains a third state ("Unavailable" — AI provider not configured)
// rendered via MoreBilingualRow below; the popover wires this in instead of the inline Row.

// ────────────────────────────────────────────────────
// Setup sheet
// ────────────────────────────────────────────────────
const BILINGUAL_LANGS = [
  { k: 'Chinese',  glyph: '中', script: 'cjk' },
  { k: 'Japanese', glyph: '日', script: 'cjk' },
  { k: 'Korean',   glyph: '한', script: 'cjk' },
  { k: 'Spanish',  glyph: 'Es', script: 'latin' },
  { k: 'French',   glyph: 'Fr', script: 'latin' },
  { k: 'German',   glyph: 'De', script: 'latin' },
  { k: 'Italian',  glyph: 'It', script: 'latin' },
  { k: 'Arabic',   glyph: 'ع',  script: 'rtl' },
  { k: 'Russian',  glyph: 'Ru', script: 'cyrillic' },
];

function BilingualSetupSheet({ theme, value, onChange, onClose, aiConfigured = true }) {
  const t = theme;
  const v = value || { lang: 'Chinese', granularity: 'paragraph' };
  const update = (k, val) => onChange({ ...v, [k]: val });

  return (
    <Sheet theme={t} onClose={onClose} title="Bilingual mode" height={620}>
      <div style={{ padding: '12px 22px 28px' }}>
        {/* preview strip */}
        <BilingualPreview t={t} lang={v.lang}/>

        {/* target language */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Target language</SectionLabel>
          <div style={{
            marginTop: 10, display: 'grid',
            gridTemplateColumns: 'repeat(3, 1fr)', gap: 8,
          }}>
            {BILINGUAL_LANGS.map(l => {
              const active = l.k === v.lang;
              return (
                <button key={l.k} onClick={() => update('lang', l.k)} style={{
                  display: 'flex', alignItems: 'center', gap: 8,
                  padding: '10px 10px', borderRadius: 12, border: 'none',
                  background: active
                    ? (t.isDark ? `${t.accent}26` : `${t.accent}14`)
                    : (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff'),
                  boxShadow: active
                    ? `inset 0 0 0 1.5px ${t.accent}`
                    : (t.isDark ? `inset 0 0 0 0.5px ${t.rule}` : `inset 0 0 0 0.5px ${t.rule}`),
                  cursor: 'pointer',
                }}>
                  <span style={{
                    width: 22, height: 22, borderRadius: 6, flexShrink: 0,
                    display: 'flex', alignItems: 'center', justifyContent: 'center',
                    background: active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)'),
                    color: active ? '#fff' : t.ink, fontWeight: 700,
                    fontFamily: l.script === 'cjk' || l.script === 'rtl'
                      ? '"Songti SC", "Source Han Serif", serif' : 'inherit',
                    fontSize: l.script === 'cjk' ? 13 : 11,
                  }}>{l.glyph}</span>
                  <span style={{
                    fontSize: 12.5, color: t.ink, fontWeight: active ? 600 : 500,
                  }}>{l.k}</span>
                </button>
              );
            })}
          </div>
        </div>

        {/* granularity */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Granularity</SectionLabel>
          <div style={{
            display: 'flex', marginTop: 10, borderRadius: 12,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            padding: 3,
          }}>
            {[
              { k: 'paragraph', label: 'Paragraph', sub: 'Translate after each ¶' },
              { k: 'sentence',  label: 'Sentence',  sub: 'Translate after each sentence' },
            ].map(o => (
              <button key={o.k} onClick={() => update('granularity', o.k)} style={{
                flex: 1, padding: '10px 10px', borderRadius: 10, border: 'none',
                background: v.granularity === o.k ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                color: t.ink, fontFamily: 'inherit', cursor: 'pointer',
                boxShadow: v.granularity === o.k ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
                textAlign: 'center',
              }}>
                <div style={{ fontSize: 13, fontWeight: 600 }}>{o.label}</div>
                <div style={{ fontSize: 10.5, color: t.sub, marginTop: 1 }}>{o.sub}</div>
              </button>
            ))}
          </div>
        </div>

        {/* AI provider strip */}
        <div style={{ marginTop: 22 }}>
          <SectionLabel theme={t}>Translation engine</SectionLabel>
          <div style={{
            marginTop: 8, padding: '12px 14px', borderRadius: 12,
            background: aiConfigured
              ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff')
              : `${t.accent}10`,
            border: aiConfigured ? `0.5px solid ${t.rule}` : `0.5px solid ${t.accent}55`,
            display: 'flex', alignItems: 'center', gap: 12,
          }}>
            <div style={{
              width: 28, height: 28, borderRadius: 14,
              background: aiConfigured
                ? `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`
                : 'rgba(0,0,0,0.08)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              flexShrink: 0,
            }}>
              <Icons.Sparkle size={14} color={aiConfigured ? '#fff' : t.sub} stroke={2}/>
            </div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
                {aiConfigured ? 'Claude · with this book\'s context' : 'No AI provider configured'}
              </div>
              <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
                {aiConfigured
                  ? 'Translations cached per paragraph, one page ahead.'
                  : 'Bilingual mode needs an AI provider to translate.'}
              </div>
            </div>
            <button style={{
              padding: '5px 11px', borderRadius: 100, border: 'none',
              background: aiConfigured
                ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)')
                : t.accent,
              color: aiConfigured ? t.ink : '#fff',
              fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
              flexShrink: 0,
            }}>{aiConfigured ? 'Change…' : 'Set up'}</button>
          </div>
        </div>

        {/* CTA */}
        <button onClick={onClose} style={{
          width: '100%', marginTop: 22, padding: '14px 0', borderRadius: 14,
          border: 'none', background: t.accent, color: '#fff',
          fontFamily: 'inherit', fontSize: 15, fontWeight: 600, cursor: 'pointer',
          boxShadow: `0 4px 14px ${t.accent}55`,
        }}>Turn on bilingual mode</button>
      </div>
    </Sheet>
  );
}

function BilingualPreview({ t, lang }) {
  const samples = {
    Chinese:  '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
    Japanese: '相当な財産を持っている独身の男性は妻を欲しがっているに違いない、というのは世間一般に認められた真理である。',
    Korean:   '재산이 많은 독신 남성에게 아내가 필요하다는 것은 누구나 인정하는 진리이다.',
    Spanish:  'Es una verdad universalmente reconocida que un hombre soltero en posesión de una buena fortuna necesita una esposa.',
    French:   'C\'est une vérité universellement reconnue qu\'un homme célibataire possédant une bonne fortune doit avoir besoin d\'une épouse.',
    German:   'Es ist eine allgemein anerkannte Wahrheit, dass ein lediger Mann im Besitz eines schönen Vermögens nach einer Frau verlangen muss.',
    Italian:  'È una verità universalmente riconosciuta che uno scapolo in possesso di un buon patrimonio debba volere una moglie.',
    Arabic:   'إنها حقيقة معترف بها عالميًا أن الرجل الأعزب الذي يملك ثروة جيدة لا بد أن يكون بحاجة إلى زوجة.',
    Russian:  'Общеизвестно, что холостой мужчина, обладающий приличным состоянием, должен иметь желание жениться.',
  };
  const sample = samples[lang] || samples.Chinese;
  const ff = (lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean')
    ? '"Songti SC", "Source Han Serif", serif'
    : '"Source Serif 4", Georgia, serif';

  return (
    <div style={{
      padding: '14px 14px', borderRadius: 12,
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      border: `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14, color: t.ink, lineHeight: 1.45,
      }}>It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.</div>
      <div style={{
        marginTop: 8, paddingLeft: 14, borderLeft: `2px solid ${t.accent}88`,
        fontFamily: ff,
        fontSize: 13, color: t.sub, lineHeight: 1.55,
        direction: lang === 'Arabic' ? 'rtl' : 'ltr',
      }}>{sample}</div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Paragraph-interlinear renderer
// Used by the reader when bilingual mode is on. Renders source + translation
// stacked, one source paragraph followed by its translation.
// ────────────────────────────────────────────────────
function BilingualPageContent({ page, theme, fontFamily, fontSize, lineHeight, margin,
                                pageDir, animating, pageIdx, lang = 'Chinese' }) {
  const t = theme;
  const ff = fontFamily === 'serif'
    ? '"Source Serif 4", Georgia, "Times New Roman", serif'
    : '"Inter", -apple-system, system-ui, sans-serif';
  const translatedFF = (lang === 'Chinese' || lang === 'Japanese' || lang === 'Korean')
    ? '"Songti SC", "Source Han Serif", serif'
    : ff;
  const isRTL = lang === 'Arabic';

  const animTransform = animating
    ? `translateX(${pageDir > 0 ? -8 : 8}%) ` : 'translateX(0) ';
  const animOpacity = animating ? 0 : 1;

  // Mock translations for the sample P&P paragraphs (matches vreader-data.jsx PP_PAGES)
  const TRANSLATIONS = {
    Chinese: {
      'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.':
        '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
      'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered as the rightful property of some one or other of their daughters.':
        '这样的单身汉，每逢新搬到一个地方，四邻八舍虽然完全不了解他的性情如何，见解如何，可是，既然这样的一条真理早已在人们心目中根深蒂固，因此人们总是把他看作自己某一个女儿理所应得的一笔财产。',
    },
  };
  const fallback = (en) => '【' + (lang === 'Chinese' ? '译文' : lang) + '】 ' + en.slice(0, 60) + '…';

  return (
    <div style={{
      position: 'absolute', top: 76, bottom: 56, left: margin, right: margin,
      overflow: 'hidden', transform: animTransform, opacity: animOpacity,
      transition: 'transform 0.28s cubic-bezier(0.32, 0.72, 0, 1), opacity 0.22s ease-out',
      direction: isRTL ? 'ltr' : 'ltr', // source is always LTR
    }}>
      {(pageIdx === 0 || page.chapter !== PP_PAGES[(pageIdx - 1 + PP_PAGES.length) % PP_PAGES.length].chapter) && (
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 13, color: t.sub, letterSpacing: 2,
          textTransform: 'uppercase', textAlign: 'center',
          marginBottom: 18, marginTop: 8, fontWeight: 500,
        }}>{page.chapter}</div>
      )}
      {page.paragraphs.map((para, i) => {
        const tr = (TRANSLATIONS[lang] && TRANSLATIONS[lang][para]) || fallback(para);
        return (
          <div key={i} style={{ marginBottom: lineHeight * fontSize * 0.55 }}>
            <p style={{
              fontFamily: ff, fontSize, lineHeight, color: t.ink, margin: 0,
              textIndent: i === 0 ? 0 : `${fontSize * 1.4}px`,
              textAlign: 'justify', hyphens: 'auto',
            }}>
              {i === 0 && (
                <span style={{
                  fontFamily: '"Source Serif 4", Georgia, serif',
                  fontSize: fontSize * 2.6, lineHeight: 0.85,
                  float: 'left', marginRight: 6, marginTop: 4,
                  color: t.accent, fontWeight: 600,
                }}>{para[0]}</span>
              )}
              {i === 0 ? para.slice(1) : para}
            </p>
            <p style={{
              fontFamily: translatedFF,
              fontSize: fontSize * 0.88, lineHeight: 1.55,
              color: t.sub, margin: '6px 0 0',
              paddingLeft: fontSize * 1.0, paddingRight: isRTL ? 0 : 0,
              direction: isRTL ? 'rtl' : 'ltr',
              textAlign: isRTL ? 'right' : 'left',
              borderLeft: isRTL ? 'none' : `2px solid ${t.accent}55`,
              borderRight: isRTL ? `2px solid ${t.accent}55` : 'none',
              paddingLeft: isRTL ? 0 : fontSize * 0.7,
              paddingRight: isRTL ? fontSize * 0.7 : 0,
            }}>{tr}</p>
          </div>
        );
      })}
    </div>
  );
}

// ────────────────────────────────────────────────────
// The "EN ↔ 中" pill shown in the reader top chrome when bilingual is on
// ────────────────────────────────────────────────────
function BilingualPill({ theme, lang }) {
  const t = theme;
  const glyph = (BILINGUAL_LANGS.find(l => l.k === lang) || BILINGUAL_LANGS[0]).glyph;
  return (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 4,
      padding: '2px 8px 2px 4px', borderRadius: 100, marginLeft: 6,
      background: `${t.accent}1a`, color: t.accent,
      fontFamily: '"Inter", system-ui', fontSize: 10.5, fontWeight: 600,
      verticalAlign: 'middle',
    }}>
      <span style={{
        width: 16, height: 16, borderRadius: 8, background: t.accent,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
        color: '#fff', fontSize: 9, fontWeight: 700,
      }}>EN</span>
      <span style={{ opacity: 0.7, fontSize: 9 }}>↔</span>
      <span style={{
        fontFamily: '"Songti SC", "Source Han Serif", serif',
        fontWeight: 700, fontSize: 12,
      }}>{glyph}</span>
    </div>
  );
}

Object.assign(window, {
  BILINGUAL_LANGS, BilingualSetupSheet, BilingualPageContent, BilingualPill,
});
