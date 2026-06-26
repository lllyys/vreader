// Issue #1797 / Feature #110 (Android Phase-3) — TTS read-aloud control bar.
//
// iOS read-aloud (#26/#72) is backed by AVSpeechSynthesizer; Android has
// android.speech.tts.TextToSpeech (no credentials, on-device engines) but no
// committed control-bar UI, so per rule 51 it had to be designed. Rendered in
// VReader's own reader vocabulary (the paper/dark THEMES, Source-Serif body,
// #8c2f2f / #d6885a accent) so read-aloud reads as the same product.
//
// Decision: a glassy transport bar docked at the foot of the reader (not a
// system media-notification surrogate). The bar owns play/pause, sentence
// prev/next, speed, and the voice/engine chip; the reader behind it shows the
// spoken sentence highlighted with an accent wash + an auto-scroll keepline.
// Engine/voice selection is the genuinely-Android part: on-device engines
// (Google, Samsung), per-language voices, and "voice data not installed →
// Download" — none of which iOS's AVSpeech surface has.

const TTS_SERIF = '"Source Serif 4", Georgia, serif';
const TTS_SANS = "'Inter', -apple-system, system-ui, sans-serif";

// Chapter prose, split into sentences so one can be the spoken chunk.
const TTS_PARAS = [
  [
    'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families, that he is considered the rightful property of some one or other of their daughters.',
  ],
  [
    '"My dear Mr. Bennet," said his lady to him one day, "have you heard that Netherfield Park is let at last?"',
    'Mr. Bennet replied that he had not.',
    '"But it is," returned she; "for Mrs. Long has just been here, and she told me all about it."',
  ],
  [
    'Mr. Bennet made no answer.',
    '"Do you not want to know who has taken it?" cried his wife impatiently.',
    '"You want to tell me, and I have no objection to hearing it."',
  ],
];

function ttsTheme(key) { return window.THEMES[key]; }

// ── device frame in the reader's theme ───────────────────────
function TtsFrame({ t, height = 880, children }) {
  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
      fontFamily: TTS_SANS, WebkitFontSmoothing: 'antialiased',
    }}>{children}</div>
  );
}

// Android status strip — minimal, themed.
function StatusStrip({ t }) {
  return (
    <div style={{
      height: 32, display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '0 20px', color: t.ink, fontSize: 12.5, fontWeight: 600, opacity: 0.7, flexShrink: 0,
    }}>
      <span style={{ fontVariantNumeric: 'tabular-nums' }}>9:41</span>
      <span style={{ display: 'flex', gap: 5, alignItems: 'center' }}>
        <svg width="16" height="11" viewBox="0 0 16 11" fill="none"><path d="M1 9a14 14 0 0114 0M3.3 6.5a10 10 0 019.4 0M5.6 4a6 6 0 014.8 0" stroke={t.ink} strokeWidth="1.3" strokeLinecap="round"/><circle cx="8" cy="9.5" r="1" fill={t.ink}/></svg>
        <svg width="22" height="11" viewBox="0 0 22 11" fill="none"><rect x="0.6" y="0.6" width="18" height="9.8" rx="2.2" stroke={t.ink} strokeWidth="1.1" opacity="0.5"/><rect x="2" y="2" width="13" height="7" rx="1" fill={t.ink}/><rect x="20" y="3.5" width="1.6" height="4" rx="0.8" fill={t.ink} opacity="0.5"/></svg>
      </span>
    </div>
  );
}

// Reader chrome — back chevron + chapter title (the reader's own top bar).
function ReaderChrome({ t }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 10, padding: '4px 16px 10px', flexShrink: 0,
    }}>
      <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ opacity: 0.8 }}><path d="M15 6l-6 6 6 6"/></svg>
      <div style={{ flex: 1, fontFamily: TTS_SERIF, fontStyle: 'italic', fontSize: 15, color: t.ink, opacity: 0.78, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
        Pride and Prejudice
      </div>
      <div style={{ fontSize: 12.5, color: t.sub, fontVariantNumeric: 'tabular-nums' }}>Ch. 1</div>
    </div>
  );
}

// The reading surface. `spoken` = {p, s} index of the currently-spoken
// sentence; sentences before it are dimmed (already read), the spoken one
// carries the accent wash + a left keyline, the rest are upcoming.
function ReaderProse({ t, spoken, active = true, dimAll = false }) {
  const accentWash = t.isDark ? 'rgba(214,136,90,0.20)' : 'rgba(140,47,47,0.13)';
  let idx = 0;
  return (
    <div style={{ flex: 1, overflow: 'hidden', position: 'relative', padding: '4px 26px 0' }}>
      <div style={{
        fontFamily: TTS_SERIF, fontSize: 18.5, lineHeight: 1.62, color: t.ink,
        textWrap: 'pretty',
      }}>
        {TTS_PARAS.map((para, pi) => (
          <p key={pi} style={{ margin: '0 0 17px' }}>
            {para.map((sent, si) => {
              const isSpoken = spoken && spoken.p === pi && spoken.s === si;
              const before = spoken && (pi < spoken.p || (pi === spoken.p && si < spoken.s));
              idx += 1;
              return (
                <span key={si} style={{
                  background: isSpoken ? accentWash : 'transparent',
                  boxShadow: isSpoken ? `inset 2px 0 0 ${t.accent}` : 'none',
                  color: dimAll ? t.sub : (before ? t.sub : t.ink),
                  opacity: dimAll ? 0.6 : 1,
                  borderRadius: 2, padding: isSpoken ? '1px 3px' : 0,
                  margin: isSpoken ? '0 -3px' : 0,
                  transition: 'background .2s',
                }}>{sent}{' '}</span>
              );
            })}
          </p>
        ))}
      </div>
      {/* auto-scroll keepline indicator — only while actively speaking */}
      {active && spoken && (
        <div style={{ position: 'absolute', right: 8, top: '34%', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3, color: t.accent, opacity: 0.55 }}>
          <svg width="13" height="13" viewBox="0 0 24 24" fill="none" stroke={t.accent} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"><path d="M6 9l6 6 6-6"/></svg>
        </div>
      )}
      {/* fade the prose into the control bar */}
      <div style={{ position: 'absolute', left: 0, right: 0, bottom: 0, height: 70, background: `linear-gradient(to bottom, transparent, ${t.bg})`, pointerEvents: 'none' }} />
    </div>
  );
}

function RoundBtn({ t, children, size = 40, faded }) {
  return (
    <div style={{
      width: size, height: size, borderRadius: size / 2, display: 'flex', alignItems: 'center', justifyContent: 'center',
      color: t.ink, opacity: faded ? 0.4 : 0.92,
    }}>{children}</div>
  );
}

// Transport glyphs not in the shared Icons set.
function PrevGlyph({ c }) { return <svg width="26" height="26" viewBox="0 0 24 24" fill={c}><path d="M7 5v14h2.2V5zM20 5l-9 7 9 7z"/></svg>; }
function NextGlyph({ c }) { return <svg width="26" height="26" viewBox="0 0 24 24" fill={c}><path d="M17 5v14h-2.2V5zM4 5l9 7-9 7z"/></svg>; }

// ════════════════════════════════════════════════════════════
// TtsBar — the docked read-aloud transport.
//   state: 'idle' | 'speaking' | 'paused' | 'error'
// ════════════════════════════════════════════════════════════
function TtsBar({ t, state = 'speaking', speed = '1.0×', voice = 'Google · English (US)', progress = 0.32 }) {
  const glass = t.isDark ? 'rgba(28,26,23,0.86)' : 'rgba(252,248,240,0.9)';
  const playing = state === 'speaking';
  const err = state === 'error';

  const Chip = ({ icon, label, strong }) => (
    <div style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '7px 11px', borderRadius: 100,
      background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(29,26,20,0.05)',
      fontFamily: TTS_SANS, fontSize: 13, fontWeight: strong ? 700 : 500, color: t.ink,
      whiteSpace: 'nowrap',
    }}>{icon}{label}
      <svg width="11" height="11" viewBox="0 0 12 12" fill="none" stroke={t.sub} strokeWidth="1.8" strokeLinecap="round"><path d="M2 4l4 4 4-4"/></svg>
    </div>
  );

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      background: glass, backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
      borderTop: `0.5px solid ${t.rule}`, padding: '0 0 12px', flexShrink: 0,
    }}>
      {/* chunk progress line */}
      <div style={{ height: 3, background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(29,26,20,0.08)', position: 'relative' }}>
        {!err && <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: `${progress * 100}%`, background: t.accent }} />}
      </div>

      {err ? (
        <div style={{ padding: '16px 18px 6px' }}>
          <div style={{ display: 'flex', alignItems: 'flex-start', gap: 11 }}>
            <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={t.accent} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" style={{ flexShrink: 0, marginTop: 1 }}><path d="M12 3l9 16H3z"/><path d="M12 10v4M12 17v.01"/></svg>
            <div style={{ flex: 1 }}>
              <div style={{ fontFamily: TTS_SANS, fontSize: 14.5, fontWeight: 600, color: t.ink }}>No voice for English (US)</div>
              <div style={{ fontFamily: TTS_SANS, fontSize: 13, color: t.sub, lineHeight: 1.45, marginTop: 2 }}>
                Google Speech Services has no voice data installed for this language.
              </div>
            </div>
          </div>
          <div style={{ display: 'flex', gap: 9, marginTop: 13 }}>
            <button style={{
              flex: 1, border: 'none', borderRadius: 11, padding: '11px 0', cursor: 'pointer',
              background: t.accent, color: '#fff', fontFamily: TTS_SANS, fontSize: 14, fontWeight: 600,
            }}>Install voice data</button>
            <button style={{
              border: `1px solid ${t.rule}`, borderRadius: 11, padding: '11px 16px', cursor: 'pointer',
              background: 'transparent', color: t.ink, fontFamily: TTS_SANS, fontSize: 14, fontWeight: 500,
            }}>System TTS</button>
          </div>
        </div>
      ) : (
        <>
          {/* status row */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '11px 18px 3px' }}>
            <span style={{ fontFamily: TTS_SANS, fontSize: 12.5, fontWeight: 600, letterSpacing: 0.3, color: playing ? t.accent : t.sub, textTransform: 'uppercase' }}>
              {state === 'idle' ? 'Ready to read aloud' : playing ? 'Reading aloud' : 'Paused'}
            </span>
            <span style={{ fontFamily: TTS_SANS, fontSize: 12.5, color: t.sub, fontVariantNumeric: 'tabular-nums' }}>
              {state === 'idle' ? 'Chapter 1 · ~14 min' : '2:14 · ~9 min left'}
            </span>
          </div>

          {/* transport row */}
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '4px 18px 0' }}>
            <div onClick={() => {}} style={{ cursor: 'pointer' }}><Chip label={speed} strong /></div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <RoundBtn t={t}><PrevGlyph c={t.ink}/></RoundBtn>
              <div style={{
                width: 60, height: 60, borderRadius: 30, background: t.accent, display: 'flex', alignItems: 'center', justifyContent: 'center',
                boxShadow: `0 4px 16px ${t.isDark ? 'rgba(0,0,0,0.4)' : 'rgba(140,47,47,0.3)'}`,
              }}>
                {playing
                  ? <svg width="26" height="26" viewBox="0 0 24 24" fill="#fff"><rect x="6" y="5" width="4.4" height="14" rx="1.2"/><rect x="13.6" y="5" width="4.4" height="14" rx="1.2"/></svg>
                  : <svg width="28" height="28" viewBox="0 0 24 24" fill="#fff"><path d="M7 4.5l13 7.5-13 7.5z"/></svg>}
              </div>
              <RoundBtn t={t}><NextGlyph c={t.ink}/></RoundBtn>
            </div>
            <div style={{ width: 56, display: 'flex', justifyContent: 'flex-end' }}>
              <div style={{
                width: 40, height: 40, borderRadius: 20, display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: t.ink, opacity: 0.85,
              }}>
                <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round"><path d="M6 6l12 12M18 6L6 18"/></svg>
              </div>
            </div>
          </div>

          {/* voice/engine row */}
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 10 }}>
            <div style={{ cursor: 'pointer' }}>
              <Chip icon={<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke={t.ink} strokeWidth="1.7"><circle cx="12" cy="12" r="9"/><path d="M3 12h18M12 3c2.5 2.5 2.5 15 0 18M12 3c-2.5 2.5-2.5 15 0 18"/></svg>} label={voice} />
            </div>
          </div>
        </>
      )}
    </div>
  );
}

// Full reader screen + bar in one of the bar states.
function TtsScreen({ themeKey = 'paper', state = 'speaking', height = 880 }) {
  const t = ttsTheme(themeKey);
  const spoken = state === 'idle' ? { p: 0, s: 0 } : { p: 1, s: 0 };
  return (
    <TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <StatusStrip t={t} />
        <ReaderChrome t={t} />
        <ReaderProse t={t} spoken={state === 'error' ? null : spoken} active={state === 'speaking'} dimAll={state === 'error'} />
        <TtsBar t={t} state={state} />
      </div>
    </TtsFrame>
  );
}

// ── voice / engine selection sheet ───────────────────────────
function VoiceRow({ ui, name, sub, selected, action }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', minHeight: 56, padding: '0 16px', position: 'relative' }}>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontFamily: TTS_SANS, fontSize: 15.5, fontWeight: 500, color: ui.ink }}>{name}</div>
        {sub && <div style={{ fontFamily: TTS_SANS, fontSize: 12.5, color: ui.sec, marginTop: 1 }}>{sub}</div>}
      </div>
      {action === 'download' && (
        <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontFamily: TTS_SANS, fontSize: 13.5, fontWeight: 600, color: ui.tint }}>
          <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="1.9" strokeLinecap="round" strokeLinejoin="round"><path d="M12 3v13M7 11l5 5 5-5M5 20h14"/></svg>
          1.4 MB
        </span>
      )}
      {action === 'downloading' && (
        <span style={{ fontFamily: TTS_SANS, fontSize: 13, color: ui.sec, fontVariantNumeric: 'tabular-nums' }}>62%</span>
      )}
      {selected && (
        <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke={ui.tint} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><path d="M5 12l5 5L20 7"/></svg>
      )}
      <div style={{ position: 'absolute', left: 16, right: 0, bottom: 0, height: 0.5, background: ui.sep }} />
    </div>
  );
}

function VoiceSheet({ ui, height = 880 }) {
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <AppSheet ui={ui} title="Voice"
        leading={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: TTS_SANS, fontSize: 15, color: ui.sec }}>Cancel</button>}
        trailing={<button style={{ background: 'none', border: 'none', padding: 0, fontFamily: TTS_SANS, fontSize: 15, fontWeight: 600, color: ui.tint }}>Done</button>}
        height={height - 36}>
        <div style={{ padding: '14px 16px 32px' }}>
          <GroupHeader ui={ui}>Engine</GroupHeader>
          <Card ui={ui}>
            <VoiceRow ui={ui} name="Google Speech Services" sub="On-device · default" selected />
            <VoiceRow ui={ui} name="Samsung text-to-speech" sub="On-device" />
          </Card>
          <GroupFooter ui={ui}>Engines are provided by Android. Add more from <span style={{ color: ui.ink }}>System settings → Text-to-speech</span>.</GroupFooter>

          <div style={{ height: 18 }} />
          <GroupHeader ui={ui}>English (US) voices</GroupHeader>
          <Card ui={ui}>
            <VoiceRow ui={ui} name="English (US) · Voice 1" sub="Female · network-free" selected />
            <VoiceRow ui={ui} name="English (US) · Voice 4" sub="Male · network-free" />
            <VoiceRow ui={ui} name="English (UK) · Voice 2" sub="Not installed" action="download" />
            <VoiceRow ui={ui} name="Français · Voix 3" sub="Installing…" action="downloading" />
          </Card>
          <GroupFooter ui={ui}>VReader follows the book's language when a matching voice is installed. Otherwise it uses the engine default.</GroupFooter>
        </div>
      </AppSheet>
    </PhoneFrame>
  );
}

// ── speed control sheet ──────────────────────────────────────
function SpeedSheet({ ui, height = 880 }) {
  const speeds = ['0.5×', '0.75×', '1.0×', '1.25×', '1.5×', '1.75×', '2.0×'];
  const sel = '1.0×';
  return (
    <PhoneFrame ui={ui} height={height}>
      <div style={{ position: 'absolute', inset: 0, background: ui.bg }} />
      <div style={{ position: 'absolute', inset: 0, zIndex: 200, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.35)' }}>
        <div style={{ background: ui.sheetBg, borderTopLeftRadius: 22, borderTopRightRadius: 22, padding: '8px 0 26px', boxShadow: '0 -8px 28px rgba(0,0,0,0.25)' }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 4, paddingBottom: 8 }}>
            <div style={{ width: 36, height: 5, borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
          </div>
          <div style={{ fontFamily: TTS_SERIF, fontSize: 17, fontWeight: 600, color: ui.ink, textAlign: 'center', paddingBottom: 6 }}>Speaking rate</div>
          <div style={{ textAlign: 'center', fontFamily: TTS_SERIF, fontSize: 40, fontWeight: 700, color: ui.tint, padding: '6px 0 14px' }}>1.0×</div>
          {/* slider */}
          <div style={{ padding: '0 26px' }}>
            <div style={{ height: 5, borderRadius: 3, background: ui.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)', position: 'relative' }}>
              <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '40%', background: ui.tint, borderRadius: 3 }} />
              <div style={{ position: 'absolute', left: '40%', top: '50%', width: 24, height: 24, borderRadius: 12, background: '#fff', transform: 'translate(-50%,-50%)', boxShadow: '0 1px 5px rgba(0,0,0,0.22)' }} />
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', marginTop: 10, fontFamily: TTS_SANS, fontSize: 11.5, color: ui.sec }}>
              <span>Slower</span><span>Faster</span>
            </div>
          </div>
          {/* preset pills */}
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 8, padding: '20px 22px 0', justifyContent: 'center' }}>
            {speeds.map((s) => {
              const on = s === sel;
              return (
                <span key={s} style={{
                  fontFamily: TTS_SANS, fontSize: 13.5, fontWeight: on ? 700 : 500,
                  color: on ? '#fff' : ui.ink,
                  background: on ? ui.tint : (ui.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(29,26,20,0.05)'),
                  borderRadius: 100, padding: '8px 14px',
                }}>{s}</span>
              );
            })}
          </div>
        </div>
      </div>
    </PhoneFrame>
  );
}

// ── entry affordance: the reader toolbar with read-aloud ─────
function TtsEntry({ themeKey = 'paper', height = 880 }) {
  const t = ttsTheme(themeKey);
  const toolbar = ['TOC', 'Volume', 'Aa', 'Sparkle'];
  return (
    <TtsFrame t={t} height={height}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', flexDirection: 'column' }}>
        <StatusStrip t={t} />
        <ReaderChrome t={t} />
        <ReaderProse t={t} spoken={null} active={false} />
        {/* reader bottom toolbar with read-aloud (Volume) highlighted */}
        <div style={{
          display: 'flex', justifyContent: 'space-around', alignItems: 'center',
          padding: '12px 18px 16px', borderTop: `0.5px solid ${t.rule}`,
          background: t.chrome, flexShrink: 0,
        }}>
          {toolbar.map((k) => {
            const I = window.Icons[k];
            const on = k === 'Volume';
            return (
              <div key={k} style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
                <div style={{
                  width: 44, height: 44, borderRadius: 14, display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: on ? (t.isDark ? 'rgba(214,136,90,0.18)' : 'rgba(140,47,47,0.1)') : 'transparent',
                }}>
                  <I size={23} color={on ? t.accent : t.ink} stroke={1.7} />
                </div>
                {on && <span style={{ fontFamily: TTS_SANS, fontSize: 10.5, fontWeight: 600, color: t.accent }}>Read aloud</span>}
              </div>
            );
          })}
        </div>
      </div>
    </TtsFrame>
  );
}

Object.assign(window, {
  TtsFrame, StatusStrip, ReaderChrome, ReaderProse, TtsBar, TtsScreen,
  VoiceSheet, SpeedSheet, TtsEntry,
});
