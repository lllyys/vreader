// Shared AI-sheet shell for the four "needs-design" AI canvases:
//   #1476 stop control · #1477 session switcher · #1478 bilingual summarize · #1483 tool activity
//
// Each canvas's own *-artboards.jsx redefines its issue-specific pieces, but the phone
// shell, the faded reader page, the AI sheet chrome (grabber + header + segmented tabs),
// chat bubbles, the composer base, and the popover primitives are all the same surface —
// so they live here once and are pulled in via window globals (like Icons / THEMES).
//
// Loads AFTER vreader-themes.jsx + vreader-icons.jsx, BEFORE the artboards file.

const SERIF = '"Source Serif 4", Georgia, serif';
const SANS  = '"Inter", -apple-system, system-ui, sans-serif';
const ACCENT_GREEN = '#3a6a5a';   // "on" / positive — matches PillSwitch ON across the app

// ────────────────────────────────────────────────────
// Spinner (each babel script keeps its own; this is the shared one)
// ────────────────────────────────────────────────────
function CSpinner({ size = 14, color = '#fff', stroke = 2 }) {
  return (
    <div style={{ width: size, height: size, display: 'inline-block' }}>
      <style>{`@keyframes aishspin { to { transform: rotate(360deg); } }`}</style>
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
           style={{ animation: 'aishspin 0.8s linear infinite' }}>
        <circle cx="12" cy="12" r="9" stroke={color} strokeOpacity="0.25" strokeWidth={stroke}/>
        <path d="M21 12a9 9 0 00-9-9" stroke={color} strokeWidth={stroke} strokeLinecap="round"/>
      </svg>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Phone shell — faded reader page behind a docked bottom sheet
// ════════════════════════════════════════════════════
function PhoneShell({ themeKey = 'paper', height = 760, children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 402, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 20,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 12px 40px rgba(0,0,0,0.35)',
    }}>
      <FadedPage t={t}/>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.38)' }}/>
      {children}
    </div>
  );
}

function FadedPage({ t }) {
  return (
    <div style={{ position: 'absolute', inset: 0, padding: '60px 26px', opacity: 0.5 }}>
      <div style={{
        fontFamily: SERIF, fontSize: 11, color: t.sub, letterSpacing: 2,
        textTransform: 'uppercase', textAlign: 'center', marginBottom: 16,
      }}>Chapter 1</div>
      {[
        'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
        'However little known the feelings or views of such a man may be on his first entering a neighbourhood, this truth is so well fixed in the minds of the surrounding families…',
      ].map((p, i) => (
        <p key={i} style={{
          fontFamily: SERIF, fontSize: 14, lineHeight: 1.55, color: t.ink,
          margin: '0 0 12px', textAlign: 'justify',
        }}>{p}</p>
      ))}
    </div>
  );
}

// ════════════════════════════════════════════════════
// AI sheet chrome — grabber, header (sparkle avatar + title/subtitle + optional
// trailing controls + close), segmented tabs, body slot + optional overlay.
// ════════════════════════════════════════════════════
function AISheet({
  t, height = 650, tab = 'chat', subtitle = "Claude · with this book’s context",
  title = 'AI Assistant', headerRight = null, headerTitleNode = null,
  children, overlay = null,
}) {
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height,
      background: t.isDark ? '#222020' : '#fcf8f0',
      borderTopLeftRadius: 22, borderTopRightRadius: 22,
      boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }}/>
      </div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 18px 4px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, minWidth: 0 }}>
          <div style={{
            width: 28, height: 28, borderRadius: 14, flexShrink: 0,
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Sparkle size={15} color="#fff" stroke={2}/>
          </div>
          {headerTitleNode || (
            <div style={{ minWidth: 0 }}>
              <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>{title}</div>
              <div style={{ fontSize: 11, color: t.sub, marginTop: -1, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{subtitle}</div>
            </div>
          )}
        </div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
          {headerRight}
          <button style={iconBtn(t)}><Icons.Close size={14} color={t.sub} stroke={2}/></button>
        </div>
      </div>
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{ display: 'flex', borderRadius: 10, padding: 3, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
          {[['summary','Summarize'],['chat','Chat'],['translate','Translate']].map(([k,label]) => (
            <div key={k} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, textAlign: 'center',
              background: k === tab ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: k === tab ? t.ink : t.sub,
              fontSize: 12.5, fontWeight: 500,
              boxShadow: k === tab ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{label}</div>
          ))}
        </div>
      </div>
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
        {children}
        {overlay}
      </div>
    </div>
  );
}

function iconBtn(t) {
  return {
    background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)', border: 'none',
    width: 28, height: 28, borderRadius: 14, padding: 0, cursor: 'pointer',
    display: 'flex', alignItems: 'center', justifyContent: 'center',
  };
}

// ════════════════════════════════════════════════════
// Chat bubbles
// ════════════════════════════════════════════════════
function UserBubble({ t, text }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
      <div style={{ maxWidth: '80%', padding: '10px 14px', borderRadius: 18, borderTopRightRadius: 6, background: t.accent, color: '#fff', fontSize: 14, lineHeight: 1.4 }}>{text}</div>
    </div>
  );
}

// Assistant bubble. `text` for the body; `above` renders before the body (tool
// activity), `footer` renders after (citations). `streaming` appends a caret.
function AsstBubble({ t, text, above = null, footer = null, streaming = false, children }) {
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
      <div style={{
        width: 24, height: 24, borderRadius: 12, flexShrink: 0, marginTop: 2,
        background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Sparkle size={12} color="#fff" stroke={2}/>
      </div>
      <div style={{ maxWidth: '85%', minWidth: 0, flex: '0 1 auto' }}>
        {above}
        {(text || children) && (
          <div style={{ padding: '4px 0', fontFamily: SERIF, fontSize: 14.5, lineHeight: 1.5, color: t.ink }}>
            {children || text}
            {streaming && <Caret t={t}/>}
          </div>
        )}
        {footer}
      </div>
    </div>
  );
}

function Caret({ t }) {
  return (
    <span style={{
      display: 'inline-block', width: 2, height: '1.05em', verticalAlign: '-0.18em',
      marginLeft: 2, background: t.accent, borderRadius: 1,
      animation: 'aishblink 1s steps(2, start) infinite',
    }}>
      <style>{`@keyframes aishblink { 50% { opacity: 0; } }`}</style>
    </span>
  );
}

// ════════════════════════════════════════════════════
// Composer base. `button` is the trailing control (send / stop / morph).
// ════════════════════════════════════════════════════
function Composer({ t, placeholder = 'Ask about this book…', value = null, disabled = false, button }) {
  const filled = value != null;
  return (
    <div style={{ padding: '6px 14px 16px' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, padding: '6px 6px 6px 14px', borderRadius: 22,
        background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)', opacity: disabled ? 0.7 : 1,
      }}>
        <span style={{ flex: 1, fontSize: 14, color: filled ? t.ink : t.sub, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>
          {filled ? value : placeholder}
        </span>
        {button || <SendButton t={t} state={filled ? 'send' : 'disabled'}/>}
      </div>
    </div>
  );
}

// Default send button (used by canvases that don't override it).
function SendButton({ t, state = 'send' }) {
  const bg = state === 'send' ? t.accent : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)');
  return (
    <div style={{ width: 32, height: 32, borderRadius: 16, background: bg, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <Icons.Send size={15} color="#fff" stroke={2}/>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Popover primitives (scope/sources/menus)
// ════════════════════════════════════════════════════
function Popover({ t, children, style }) {
  return (
    <div style={{
      borderRadius: 16, overflow: 'hidden',
      background: t.isDark ? '#2b2926' : '#fff',
      border: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'}`,
      boxShadow: '0 12px 36px rgba(0,0,0,0.28)', ...style,
    }}>{children}</div>
  );
}
function PopHeader({ t, title, hint }) {
  return (
    <div style={{ padding: '13px 14px 9px', borderBottom: `0.5px solid ${t.rule}` }}>
      <div style={{ fontFamily: SERIF, fontSize: 15, fontWeight: 600, color: t.ink }}>{title}</div>
      {hint && <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>{hint}</div>}
    </div>
  );
}
function PopFooter({ t, icon = 'Info', text }) {
  const Glyph = Icons[icon];
  return (
    <div style={{ display: 'flex', gap: 7, padding: '10px 14px 12px', borderTop: `0.5px solid ${t.rule}`,
      background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)' }}>
      <Glyph size={13} color={t.sub} stroke={2} style={{ flexShrink: 0, marginTop: 1 }}/>
      <span style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.4 }}>{text}</span>
    </div>
  );
}
function Notch({ t, left, right }) {
  return (
    <div style={{
      position: 'absolute', bottom: -6, left, right, width: 14, height: 14,
      background: t.isDark ? '#2b2926' : '#fff', transform: 'rotate(45deg)',
      borderRight: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'}`,
      borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'}`,
    }}/>
  );
}

function Toggle({ t, on }) {
  return (
    <div style={{ width: 38, height: 22, borderRadius: 11, flexShrink: 0, position: 'relative',
      background: on ? ACCENT_GREEN : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'), transition: 'background .15s' }}>
      <div style={{ position: 'absolute', top: 2, left: on ? 18 : 2, width: 18, height: 18, borderRadius: 9, background: '#fff', boxShadow: '0 1px 2px rgba(0,0,0,0.2)' }}/>
    </div>
  );
}

// A light wrapper for "true size" anatomy artboards.
function AnatomyWrap({ children, pad = 0, bg = '#fcf8f0' }) {
  return (
    <div style={{ width: '100%', height: '100%', background: bg, borderRadius: 14, padding: pad,
      display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div style={{ width: '100%' }}>{children}</div>
    </div>
  );
}

Object.assign(window, {
  SERIF, SANS, ACCENT_GREEN,
  CSpinner, PhoneShell, FadedPage, AISheet, iconBtn,
  UserBubble, AsstBubble, Caret, Composer, SendButton,
  Popover, PopHeader, PopFooter, Notch, Toggle, AnatomyWrap,
});
