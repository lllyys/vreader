// Canvas artboards for #1455 — Chat-tab AI scope selector + sources toggle + on-demand retrieval.
// Feature #86 parts 2 (annotation sources) & 3 (read-everywhere scope / on-demand retrieval).
//
// The Summarize tab already has scope chips (Section / Chapter / Book so far). Chat is a
// CONVERSATION with a persistent composer, so its scope+sources are a property of the THREAD,
// not of a one-shot action. Canonical answer: a persistent CONTEXT BAR docked directly above
// the composer, with a scope menu + a sources popover, and an in-place retrieval progress state.
//
// Sections:
//   A — Context bar (CANONICAL): default · scope menu · sources popover · across themes
//   S — Scope states: Section / Chapter / Book so far / Whole book + answer citations
//   R — On-demand retrieval: armed → reading (progress) → ready, with spoiler-aware citation
//   B — Top chips (rejected — Summarize-parity, for comparison)
//   C — Composer tray (alternate)
//   D — Anatomy · true size

const ACCENT_GREEN = '#3a6a5a';   // "on" / "ready" — matches PillSwitch ON across the app
const SERIF = '"Source Serif 4", Georgia, serif';

// Token / count facts reused everywhere
const SCOPES = [
  { k: 'section', label: 'Section',     desc: 'Just the passage you’re reading', tok: '~600 tokens' },
  { k: 'chapter', label: 'Chapter',     desc: 'The whole current chapter',       tok: '~4.2k tokens' },
  { k: 'sofar',   label: 'Book so far', desc: 'Everything up to your page',       tok: '~58k tokens' },
  { k: 'whole',   label: 'Whole book',  desc: 'Reads the entire book on demand',  tok: 'on-demand', ahead: true },
];
const SCOPE_LABEL = Object.fromEntries(SCOPES.map(s => [s.k, s.label]));
const SOURCES_DEFAULT = { notes: true, highlights: true, bookmarks: false };
const SOURCE_META = [
  { k: 'notes',      label: 'Notes',      count: 18, icon: 'Note' },
  { k: 'highlights', label: 'Highlights', count: 47, icon: 'Highlighter' },
  { k: 'bookmarks',  label: 'Bookmarks',  count: 5,  icon: 'Bookmark' },
];

// ────────────────────────────────────────────────────
// Spinner (local; each babel script has its own scope)
// ────────────────────────────────────────────────────
function CSpinner({ size = 14, color = '#fff', stroke = 2 }) {
  return (
    <div style={{ width: size, height: size, display: 'inline-block' }}>
      <style>{`@keyframes ccspin { to { transform: rotate(360deg); } }`}</style>
      <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
           style={{ animation: 'ccspin 0.8s linear infinite' }}>
        <circle cx="12" cy="12" r="9" stroke={color} strokeOpacity="0.25" strokeWidth={stroke}/>
        <path d="M21 12a9 9 0 00-9-9" stroke={color} strokeWidth={stroke} strokeLinecap="round"/>
      </svg>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Phone shell — faded reader page + a docked bottom sheet
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
// The AI sheet, Chat tab — header + segmented tabs + messages + slot for context cluster
// ════════════════════════════════════════════════════
function ChatSheet({ t, height = 650, children, scope = 'chapter', overlay = null }) {
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0, height,
      background: t.isDark ? '#222020' : '#fcf8f0',
      borderTopLeftRadius: 22, borderTopRightRadius: 22,
      boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
      display: 'flex', flexDirection: 'column', overflow: 'hidden',
    }}>
      {/* grabber */}
      <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
        <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }}/>
      </div>
      {/* header */}
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '14px 18px 4px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{
            width: 28, height: 28, borderRadius: 14,
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Sparkle size={15} color="#fff" stroke={2}/>
          </div>
          <div>
            <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>AI Assistant</div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: -1 }}>Claude · with this book’s context</div>
          </div>
        </div>
        <button style={closeBtn(t)}><Icons.Close size={14} color={t.sub} stroke={2}/></button>
      </div>
      {/* segmented tabs — Chat active */}
      <div style={{ padding: '12px 18px 0' }}>
        <div style={{ display: 'flex', borderRadius: 10, padding: 3, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
          {[['summary','Summarize'],['chat','Chat'],['translate','Translate']].map(([k,label]) => (
            <div key={k} style={{
              flex: 1, padding: '7px 0', borderRadius: 8, textAlign: 'center',
              background: k === 'chat' ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
              color: k === 'chat' ? t.ink : t.sub,
              fontSize: 12.5, fontWeight: 500,
              boxShadow: k === 'chat' ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
            }}>{label}</div>
          ))}
        </div>
      </div>
      {/* body — messages + composer cluster, plus optional popover overlay */}
      <div style={{ position: 'relative', flex: 1, minHeight: 0, display: 'flex', flexDirection: 'column' }}>
        {children}
        {overlay}
      </div>
    </div>
  );
}

function closeBtn(t) {
  return {
    background: 'rgba(0,0,0,0.06)', border: 'none', width: 28, height: 28, borderRadius: 14,
    padding: 0, cursor: 'pointer', display: 'flex', alignItems: 'center', justifyContent: 'center',
  };
}

// ════════════════════════════════════════════════════
// Messages
// ════════════════════════════════════════════════════
function Messages({ t, withCitation = false, citeAhead = false, dim = false }) {
  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '16px 18px 8px', opacity: dim ? 0.55 : 1 }}>
      <AsstBubble t={t} text="Hi! I’ve got this book’s context loaded. Ask me anything about it — characters, themes, references, or to clarify a passage you’re reading."/>
      <UserBubble t={t} text="Why does Mr. Bennet tease his wife about visiting Bingley?"/>
      <AsstBubble t={t}
        text="It’s how Austen draws the marriage between them: she is all anxious matchmaking, he deflects with dry irony. The teasing signals he sees through the social scramble even as he’ll quietly play along."
        citation={withCitation ? (citeAhead
          ? { items: [{ label: 'Ch. 1', kind: 'text' }, { label: 'Ch. 7 · ahead', kind: 'ahead' }, { label: 'your note', kind: 'note' }] }
          : { items: [{ label: 'Ch. 1', kind: 'text' }, { label: 'your note', kind: 'note' }] }) : null}/>
    </div>
  );
}

function UserBubble({ t, text }) {
  return (
    <div style={{ display: 'flex', justifyContent: 'flex-end', marginBottom: 12 }}>
      <div style={{ maxWidth: '80%', padding: '10px 14px', borderRadius: 18, borderTopRightRadius: 6, background: t.accent, color: '#fff', fontSize: 14, lineHeight: 1.4 }}>{text}</div>
    </div>
  );
}

function AsstBubble({ t, text, citation }) {
  return (
    <div style={{ display: 'flex', gap: 8, marginBottom: 14 }}>
      <div style={{
        width: 24, height: 24, borderRadius: 12, flexShrink: 0, marginTop: 2,
        background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Sparkle size={12} color="#fff" stroke={2}/>
      </div>
      <div style={{ maxWidth: '85%' }}>
        <div style={{ padding: '4px 0', fontFamily: SERIF, fontSize: 14.5, lineHeight: 1.5, color: t.ink }}>{text}</div>
        {citation && <CitationRow t={t} items={citation.items}/>}
      </div>
    </div>
  );
}

// Retrieval affordance at the answer level — what the reply actually drew on.
function CitationRow({ t, items }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', flexWrap: 'wrap', gap: 6, marginTop: 8 }}>
      <span style={{ fontSize: 10.5, color: t.sub, letterSpacing: 0.4, textTransform: 'uppercase', fontWeight: 600 }}>Drew on</span>
      {items.map((it, i) => {
        const ahead = it.kind === 'ahead';
        const note = it.kind === 'note';
        return (
          <span key={i} style={{
            display: 'inline-flex', alignItems: 'center', gap: 4,
            padding: '3px 8px', borderRadius: 100, fontSize: 11, fontWeight: 500,
            background: ahead ? 'rgba(180,120,40,0.13)' : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
            color: ahead ? (t.isDark ? '#e8b465' : '#9a6a1f') : t.sub,
            border: ahead ? `0.5px solid ${t.isDark ? 'rgba(232,180,101,0.4)' : 'rgba(154,106,31,0.3)'}` : 'none',
          }}>
            {note && <Icons.Note size={11} color={t.sub} stroke={1.7}/>}
            {ahead && <Icons.Info size={11} color={t.isDark ? '#e8b465' : '#9a6a1f'} stroke={2}/>}
            {it.label}
          </span>
        );
      })}
    </div>
  );
}

// ════════════════════════════════════════════════════
// CANONICAL — the context cluster: context bar + composer, sharing one top rule
// ════════════════════════════════════════════════════
function ContextCluster({ t, scope = 'chapter', sources = SOURCES_DEFAULT, openMenu = null }) {
  const count = Object.values(sources).filter(Boolean).length;
  return (
    <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
      <ContextBar t={t} scope={scope} sourcesCount={count} active={openMenu}/>
      <Composer t={t}/>
    </div>
  );
}

function ContextBar({ t, scope, sourcesCount, active }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 14px 2px' }}>
      <ChipScope t={t} scope={scope} open={active === 'scope'}/>
      <ChipSources t={t} count={sourcesCount} open={active === 'sources'}/>
    </div>
  );
}

function ChipScope({ t, scope, open }) {
  return (
    <button style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 10px 6px 11px',
      borderRadius: 100, border: `0.5px solid ${open ? t.accent : t.rule}`, cursor: 'pointer',
      background: open ? (t.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.07)') : 'transparent',
      color: t.ink, fontFamily: 'inherit',
    }}>
      <Icons.Sparkle size={13} color={t.accent} stroke={2}/>
      <span style={{ fontSize: 12, color: t.sub, fontWeight: 500 }}>Context</span>
      <span style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>{SCOPE_LABEL[scope]}</span>
      <Icons.ChevronD size={13} color={t.sub} stroke={2.2}/>
    </button>
  );
}

function ChipSources({ t, count, open }) {
  const on = count > 0;
  return (
    <button style={{
      display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 11px', borderRadius: 100,
      border: `0.5px solid ${open ? t.accent : (on ? 'transparent' : t.rule)}`, cursor: 'pointer',
      background: on ? (t.isDark ? 'rgba(58,106,90,0.22)' : 'rgba(58,106,90,0.12)') : 'transparent',
      color: t.ink, fontFamily: 'inherit',
    }}>
      <Icons.Note size={13} color={on ? ACCENT_GREEN : t.sub} stroke={1.8}/>
      <span style={{ fontSize: 12.5, fontWeight: 500, color: on ? t.ink : t.sub }}>Sources</span>
      {on
        ? <span style={{ fontSize: 11, fontWeight: 700, color: '#fff', background: ACCENT_GREEN, borderRadius: 100, minWidth: 16, height: 16, padding: '0 5px', display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>{count}</span>
        : <span style={{ fontSize: 12, color: t.sub }}>Off</span>}
    </button>
  );
}

function Composer({ t, placeholder = 'Ask about this book…', disabled = false }) {
  return (
    <div style={{ padding: '6px 14px 16px' }}>
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8, padding: '6px 6px 6px 14px', borderRadius: 22,
        background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)', opacity: disabled ? 0.55 : 1,
      }}>
        <span style={{ flex: 1, fontSize: 14, color: t.sub }}>{placeholder}</span>
        <div style={{
          width: 32, height: 32, borderRadius: 16,
          background: t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Send size={15} color="#fff" stroke={2}/>
        </div>
      </div>
    </div>
  );
}

// ── Scope menu — popover opening upward from the Context chip ──
function ScopeMenu({ t, scope = 'chapter' }) {
  return (
    <div style={{ position: 'absolute', left: 14, bottom: 78, width: 286, zIndex: 5 }}>
      <Popover t={t}>
        <PopHeader t={t} title="Chat context" hint="How much of the book the assistant reads"/>
        <div style={{ padding: '4px 0' }}>
          {SCOPES.map((s, i) => {
            const sel = s.k === scope;
            return (
              <div key={s.k} style={{
                display: 'flex', alignItems: 'flex-start', gap: 10, padding: '10px 14px',
                background: sel ? (t.isDark ? 'rgba(214,136,90,0.12)' : 'rgba(140,47,47,0.05)') : 'transparent',
              }}>
                <div style={{ width: 18, height: 18, borderRadius: 9, marginTop: 1, flexShrink: 0,
                  border: sel ? 'none' : `1.5px solid ${t.rule}`, background: sel ? t.accent : 'transparent',
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  {sel && <Icons.Check size={12} color="#fff" stroke={2.6}/>}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                    <span style={{ fontSize: 14, fontWeight: 600, color: t.ink }}>{s.label}</span>
                    {s.ahead && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: t.accent, background: t.isDark ? 'rgba(214,136,90,0.16)' : 'rgba(140,47,47,0.08)', padding: '2px 6px', borderRadius: 100 }}>On-demand</span>}
                  </div>
                  <div style={{ fontSize: 12, color: t.sub, marginTop: 2, lineHeight: 1.35 }}>{s.desc}</div>
                </div>
                <span style={{ fontSize: 11, color: t.sub, marginTop: 2, whiteSpace: 'nowrap' }}>{s.tok}</span>
              </div>
            );
          })}
        </div>
        <PopFooter t={t} icon="Info" text={scope === 'whole'
          ? 'Whole book can reference pages ahead of you — answers may contain spoilers.'
          : 'Larger scopes give fuller answers but cost more per message.'}/>
      </Popover>
      <Notch t={t} left={26}/>
    </div>
  );
}

// ── Sources popover — toggles for the reader's own annotations ──
function SourcesMenu({ t, sources = SOURCES_DEFAULT }) {
  return (
    <div style={{ position: 'absolute', right: 14, bottom: 78, width: 280, zIndex: 5 }}>
      <Popover t={t}>
        <PopHeader t={t} title="Your annotations" hint="Add what you’ve marked to the context"/>
        <div style={{ padding: '4px 0' }}>
          {SOURCE_META.map(s => {
            const on = sources[s.k];
            const Glyph = Icons[s.icon];
            return (
              <div key={s.k} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 14px' }}>
                <div style={{ width: 28, height: 28, borderRadius: 8, flexShrink: 0,
                  background: on ? (t.isDark ? 'rgba(58,106,90,0.25)' : 'rgba(58,106,90,0.12)') : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
                  display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                  <Glyph size={15} color={on ? ACCENT_GREEN : t.sub} stroke={1.8}/>
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 14, color: t.ink, fontWeight: 500 }}>{s.label}</div>
                  <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>{s.count} in this book</div>
                </div>
                <Toggle t={t} on={on}/>
              </div>
            );
          })}
        </div>
        <PopFooter t={t} icon="Info" text="Included alongside the book text so answers can cite what you marked."/>
      </Popover>
      <Notch t={t} right={26}/>
    </div>
  );
}

function Popover({ t, children }) {
  return (
    <div style={{
      borderRadius: 16, overflow: 'hidden',
      background: t.isDark ? '#2b2926' : '#fff',
      border: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.07)'}`,
      boxShadow: '0 12px 36px rgba(0,0,0,0.28)',
    }}>{children}</div>
  );
}
function PopHeader({ t, title, hint }) {
  return (
    <div style={{ padding: '13px 14px 9px', borderBottom: `0.5px solid ${t.rule}` }}>
      <div style={{ fontFamily: SERIF, fontSize: 15, fontWeight: 600, color: t.ink }}>{title}</div>
      <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>{hint}</div>
    </div>
  );
}
function PopFooter({ t, icon, text }) {
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

// ════════════════════════════════════════════════════
// RETRIEVAL — the context bar morphs in place while reading the whole book
// ════════════════════════════════════════════════════
function RetrievalCluster({ t, state = 'reading', progress = 0.38 }) {
  return (
    <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
      {state === 'armed' && <ArmedBar t={t}/>}
      {state === 'reading' && <ReadingBar t={t} progress={progress}/>}
      {state === 'ready' && <ReadyBar t={t}/>}
      <Composer t={t}
        placeholder={state === 'reading' ? 'Reading… ask once the book is ready' : 'Ask about anything in this book…'}
        disabled={state === 'reading'}/>
    </div>
  );
}

function ArmedBar({ t }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 14px 2px' }}>
      <button style={{
        display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 10px 6px 11px', borderRadius: 100,
        border: `0.5px solid ${t.accent}`, background: t.isDark ? 'rgba(214,136,90,0.14)' : 'rgba(140,47,47,0.07)', color: t.ink,
      }}>
        <Icons.Sparkle size={13} color={t.accent} stroke={2}/>
        <span style={{ fontSize: 12, color: t.sub, fontWeight: 500 }}>Context</span>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>Whole book</span>
        <Icons.ChevronD size={13} color={t.sub} stroke={2.2}/>
      </button>
      <span style={{ fontSize: 11.5, color: t.sub }}>Reads on your next question</span>
    </div>
  );
}

function ReadingBar({ t, progress }) {
  return (
    <div style={{ padding: '10px 14px 4px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 9, marginBottom: 8 }}>
        <CSpinner size={14} color={t.accent} stroke={2.4}/>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>Reading the whole book…</span>
        <span style={{ fontSize: 12, color: t.sub, fontVariantNumeric: 'tabular-nums' }}>{Math.round(progress * 100)}%</span>
        <span style={{ flex: 1 }}/>
        <span style={{ fontSize: 11.5, color: t.sub }}>23 / 61 ch</span>
        <button style={{ width: 22, height: 22, borderRadius: 11, border: 'none', cursor: 'pointer',
          background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icons.Close size={12} color={t.sub} stroke={2.2}/>
        </button>
      </div>
      <div style={{ height: 3, borderRadius: 2, background: t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)', overflow: 'hidden' }}>
        <div style={{ height: '100%', width: `${progress * 100}%`, background: t.accent, borderRadius: 2 }}/>
      </div>
    </div>
  );
}

function ReadyBar({ t }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 14px 2px' }}>
      <button style={{
        display: 'inline-flex', alignItems: 'center', gap: 6, padding: '6px 10px 6px 11px', borderRadius: 100,
        border: '0.5px solid transparent', background: t.isDark ? 'rgba(58,106,90,0.22)' : 'rgba(58,106,90,0.12)', color: t.ink,
      }}>
        <Icons.Check size={13} color={ACCENT_GREEN} stroke={2.6}/>
        <span style={{ fontSize: 12, color: t.sub, fontWeight: 500 }}>Context</span>
        <span style={{ fontSize: 12.5, fontWeight: 600, color: t.ink }}>Whole book</span>
        <Icons.ChevronD size={13} color={t.sub} stroke={2.2}/>
      </button>
      <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, fontSize: 11.5, color: ACCENT_GREEN, fontWeight: 600 }}>
        <Icons.Check size={12} color={ACCENT_GREEN} stroke={2.6}/>Indexed · ready
      </span>
    </div>
  );
}

// ════════════════════════════════════════════════════
// ALTERNATE B — top chips (Summarize-parity). Rejected.
// ════════════════════════════════════════════════════
function TopChipsBody({ t }) {
  return (
    <>
      <div style={{ padding: '12px 18px 4px' }}>
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap' }}>
          {['Section', 'Chapter', 'Book so far', 'Whole book'].map((s, i) => (
            <span key={s} style={{
              padding: '6px 12px', borderRadius: 100, fontSize: 12, fontWeight: 500, whiteSpace: 'nowrap',
              background: i === 1 ? t.accent : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
              color: i === 1 ? '#fff' : t.ink,
            }}>{s}</span>
          ))}
          <span style={{ padding: '6px 12px', borderRadius: 100, fontSize: 12, fontWeight: 500,
            display: 'inline-flex', alignItems: 'center', gap: 5,
            background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)', color: t.ink }}>
            <Icons.Note size={12} color={t.sub} stroke={1.7}/>Sources · 2
          </span>
        </div>
      </div>
      <Messages t={t}/>
      <div style={{ borderTop: `0.5px solid ${t.rule}` }}><Composer t={t}/></div>
    </>
  );
}

// ════════════════════════════════════════════════════
// ALTERNATE C — composer-integrated tray (expands above the input)
// ════════════════════════════════════════════════════
function ComposerTrayCluster({ t }) {
  return (
    <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
      <div style={{ padding: '12px 14px 4px' }}>
        <div style={{ borderRadius: 14, overflow: 'hidden', border: `0.5px solid ${t.rule}`, background: t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.02)' }}>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '9px 12px', borderBottom: `0.5px solid ${t.rule}` }}>
            <span style={{ fontSize: 11, fontWeight: 600, letterSpacing: 0.5, textTransform: 'uppercase', color: t.sub }}>Read scope</span>
          </div>
          <div style={{ display: 'flex', padding: 4, gap: 0 }}>
            {['Section', 'Chapter', 'Book', 'Whole'].map((s, i) => (
              <div key={s} style={{ flex: 1, padding: '7px 0', textAlign: 'center', borderRadius: 8, fontSize: 12, fontWeight: 500,
                background: i === 1 ? (t.isDark ? '#3a3530' : '#fff') : 'transparent', color: i === 1 ? t.ink : t.sub,
                boxShadow: i === 1 ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>{s}</div>
            ))}
          </div>
          <div style={{ display: 'flex', gap: 7, padding: '4px 10px 11px', flexWrap: 'wrap' }}>
            {SOURCE_META.map((s, i) => {
              const on = i < 2; const Glyph = Icons[s.icon];
              return (
                <span key={s.k} style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '5px 10px', borderRadius: 100, fontSize: 11.5, fontWeight: 500,
                  background: on ? (t.isDark ? 'rgba(58,106,90,0.22)' : 'rgba(58,106,90,0.12)') : 'transparent',
                  border: on ? 'none' : `0.5px solid ${t.rule}`, color: on ? t.ink : t.sub }}>
                  <Glyph size={12} color={on ? ACCENT_GREEN : t.sub} stroke={1.7}/>{s.label}
                  {on && <Icons.Check size={11} color={ACCENT_GREEN} stroke={2.6}/>}
                </span>
              );
            })}
          </div>
        </div>
      </div>
      <div style={{ padding: '6px 14px 16px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '6px 6px 6px 8px', borderRadius: 22, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)' }}>
          <div style={{ width: 30, height: 30, borderRadius: 15, display: 'flex', alignItems: 'center', justifyContent: 'center', background: t.accent }}>
            <Icons.Sparkle size={14} color="#fff" stroke={2}/>
          </div>
          <span style={{ flex: 1, fontSize: 14, color: t.sub }}>Ask about this book…</span>
          <div style={{ width: 32, height: 32, borderRadius: 16, background: t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.1)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <Icons.Send size={15} color="#fff" stroke={2}/>
          </div>
        </div>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Full-screen Chat artboard assembler
// ════════════════════════════════════════════════════
function ChatScreen({ themeKey = 'paper', scope = 'chapter', sources = SOURCES_DEFAULT, overlay = null, withCitation = false, citeAhead = false, variant = 'A', retrieval = null, height = 760, sheetH = 650 }) {
  const t = THEMES[themeKey];
  let body, ov = null;
  if (variant === 'B') {
    body = <TopChipsBody t={t}/>;
  } else if (variant === 'C') {
    body = <><Messages t={t}/><ComposerTrayCluster t={t}/></>;
  } else if (retrieval) {
    body = <><Messages t={t} withCitation={withCitation} citeAhead={citeAhead} dim={retrieval === 'reading'}/><RetrievalCluster t={t} state={retrieval} progress={0.38}/></>;
  } else {
    const open = overlay;
    body = <><Messages t={t} withCitation={withCitation} citeAhead={citeAhead}/><ContextCluster t={t} scope={scope} sources={sources} openMenu={open}/></>;
    if (overlay === 'scope') ov = <ScopeMenu t={t} scope={scope}/>;
    if (overlay === 'sources') ov = <SourcesMenu t={t} sources={sources}/>;
  }
  return (
    <PhoneShell themeKey={themeKey} height={height}>
      <ChatSheet t={t} height={sheetH} overlay={ov}>{body}</ChatSheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// CANVAS
// ════════════════════════════════════════════════════
const PW = 402;

function ChatContextCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>
      <DCSection id="intro" title="Chat-tab context: scope + sources + on-demand retrieval · #1455"
        subtitle="Feature #86 pts 2–3. The Summarize tab scopes a one-shot block; Chat is a thread, so its scope + sources are persistent properties of the conversation. Canonical: a CONTEXT BAR docked above the composer — a scope menu on the left, a sources popover on the right — with the whole-book read shown as an in-place progress state, never a blocking modal.">
        <DCPostIt top={-34} right={30} rotate={-2} width={330}>
          <b>Pick A.</b> One slim bar glued to the composer carries both controls on every
          message and costs ~40px. Top chips (B) scroll away and read as a one-shot action;
          the composer tray (C) is heavier than the job needs.
        </DCPostIt>
      </DCSection>

      {/* ───────── A — canonical ───────── */}
      <DCSection id="A" title="A — Context bar (canonical)"
        subtitle="Default Chat tab. Left chip = how much book the assistant reads (tap → scope menu). Right chip = your annotations in context (tap → sources popover). Accent is reserved for the assistant + send; the bar uses quiet outline / green-count treatments so it can live there permanently.">
        <DCArtboard id="A-default" label="Default · Chapter scope · 2 sources" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter"/>
        </DCArtboard>
        <DCArtboard id="A-scope" label="Scope menu open" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter" overlay="scope"/>
        </DCArtboard>
        <DCArtboard id="A-sources" label="Sources popover open" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter" overlay="sources"/>
        </DCArtboard>
        <DCArtboard id="A-dark" label="Default · dark" width={PW} height={760}>
          <ChatScreen themeKey="dark" scope="chapter"/>
        </DCArtboard>
        <DCArtboard id="A-scope-dark" label="Scope menu · dark" width={PW} height={760}>
          <ChatScreen themeKey="dark" scope="sofar" overlay="scope"/>
        </DCArtboard>
      </DCSection>

      {/* ───────── S — scope states ───────── */}
      <DCSection id="S" title="S — Each scope selected"
        subtitle="The left chip always names the live scope. When an answer arrives, a “Drew on” citation row under it names what was actually read — the retrieval affordance at the message level.">
        <DCArtboard id="S-section" label="Section" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="section" withCitation/>
        </DCArtboard>
        <DCArtboard id="S-chapter" label="Chapter (default)" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter" withCitation/>
        </DCArtboard>
        <DCArtboard id="S-sofar" label="Book so far" width={PW} height={760}>
          <ChatScreen themeKey="sepia" scope="sofar" withCitation/>
        </DCArtboard>
        <DCArtboard id="S-whole" label="Whole book · cites a page ahead" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="whole" withCitation citeAhead/>
        </DCArtboard>
      </DCSection>

      {/* ───────── Sources on/off ───────── */}
      <DCSection id="src" title="Sources · on / off"
        subtitle="Sources count = the toggled annotation kinds. When all three are off, the chip collapses to “Off” and nothing of the reader’s own marks is sent.">
        <DCArtboard id="src-on" label="All on · Sources · 3" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter" sources={{ notes: true, highlights: true, bookmarks: true }} overlay="sources"/>
        </DCArtboard>
        <DCArtboard id="src-off" label="All off · Sources · Off" width={PW} height={760}>
          <ChatScreen themeKey="paper" scope="chapter" sources={{ notes: false, highlights: false, bookmarks: false }} overlay="sources"/>
        </DCArtboard>
      </DCSection>

      {/* ───────── R — on-demand retrieval ───────── */}
      <DCSection id="R" title="R — On-demand whole-book read"
        subtitle="Selecting “Whole book” reads the entire book — including pages ahead — so it can answer about anything. The progress lives in the bar in place (non-blocking), and the answer’s citation flags pages ahead with a spoiler-aware tag.">
        <DCArtboard id="R-armed" label="Armed · reads on next question" width={PW} height={760}>
          <ChatScreen themeKey="paper" retrieval="armed"/>
        </DCArtboard>
        <DCArtboard id="R-reading" label="Reading · in-place progress + cancel" width={PW} height={760}>
          <ChatScreen themeKey="paper" retrieval="reading"/>
        </DCArtboard>
        <DCArtboard id="R-ready" label="Indexed · ready" width={PW} height={760}>
          <ChatScreen themeKey="paper" retrieval="ready" withCitation citeAhead/>
        </DCArtboard>
        <DCArtboard id="R-reading-dark" label="Reading · dark" width={PW} height={760}>
          <ChatScreen themeKey="dark" retrieval="reading"/>
        </DCArtboard>
        <DCPostIt bottom={-30} left={20} rotate={2} width={300}>
          The whole-book read is the only heavy/slow path, so it’s the only one that
          shows progress. Cancel keeps whatever was already indexed — the user never
          loses the read by backing out.
        </DCPostIt>
      </DCSection>

      {/* ───────── B — rejected ───────── */}
      <DCSection id="B" title="B — Top chips (rejected · Summarize-parity)"
        subtitle="Literal reuse of the Summarize scope chips at the top of the tab. Honest parity, but the controls scroll away with the conversation and read as a one-shot action rather than a standing context.">
        <DCArtboard id="B-paper" label="Top chips" width={PW} height={760}>
          <ChatScreen themeKey="paper" variant="B"/>
        </DCArtboard>
        <DCPostIt top={-26} right={28} rotate={2} width={290}>
          Rejected: after two messages the chips are above the scroll line and gone.
          Scope is a property of <i>every</i> question, so it has to stay on screen.
        </DCPostIt>
      </DCSection>

      {/* ───────── C — alternate ───────── */}
      <DCSection id="C" title="C — Composer tray (alternate)"
        subtitle="A segmented scope control + source chips packed into a tray above the input. More expressive in one glance, but taller and busier — kept as the fallback if scope/sources ever need to be edited together often.">
        <DCArtboard id="C-paper" label="Composer tray" width={PW} height={760}>
          <ChatScreen themeKey="paper" variant="C"/>
        </DCArtboard>
      </DCSection>

      {/* ───────── D — anatomy ───────── */}
      <DCSection id="D" title="D — Anatomy · true size"
        subtitle="The four pieces of the cluster at 1:1 so weight + rhythm are directly comparable.">
        <DCArtboard id="D-bar" label="Context bar" width={PW} height={120}>
          <AnatomyWrap><ContextBar t={THEMES.paper} scope="chapter" sourcesCount={2}/></AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-scope" label="Scope menu" width={320} height={360}>
          <AnatomyWrap pad={16}><div style={{ width: 286 }}><Popover t={THEMES.paper}>
            <PopHeader t={THEMES.paper} title="Chat context" hint="How much of the book the assistant reads"/>
            <div style={{ padding: '4px 0' }}>
              {SCOPES.map(s => {
                const sel = s.k === 'chapter';
                return (
                  <div key={s.k} style={{ display: 'flex', alignItems: 'flex-start', gap: 10, padding: '10px 14px', background: sel ? 'rgba(140,47,47,0.05)' : 'transparent' }}>
                    <div style={{ width: 18, height: 18, borderRadius: 9, marginTop: 1, flexShrink: 0, border: sel ? 'none' : '1.5px solid rgba(29,26,20,0.12)', background: sel ? '#8c2f2f' : 'transparent', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      {sel && <Icons.Check size={12} color="#fff" stroke={2.6}/>}
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
                        <span style={{ fontSize: 14, fontWeight: 600, color: '#1d1a14' }}>{s.label}</span>
                        {s.ahead && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase', color: '#8c2f2f', background: 'rgba(140,47,47,0.08)', padding: '2px 6px', borderRadius: 100 }}>On-demand</span>}
                      </div>
                      <div style={{ fontSize: 12, color: 'rgba(29,26,20,0.55)', marginTop: 2 }}>{s.desc}</div>
                    </div>
                    <span style={{ fontSize: 11, color: 'rgba(29,26,20,0.55)', marginTop: 2, whiteSpace: 'nowrap' }}>{s.tok}</span>
                  </div>
                );
              })}
            </div>
          </Popover></div></AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-sources" label="Sources popover" width={320} height={300}>
          <AnatomyWrap pad={16}><div style={{ width: 280 }}><Popover t={THEMES.paper}>
            <PopHeader t={THEMES.paper} title="Your annotations" hint="Add what you’ve marked to the context"/>
            <div style={{ padding: '4px 0' }}>
              {SOURCE_META.map((s, i) => {
                const on = i < 2; const Glyph = Icons[s.icon];
                return (
                  <div key={s.k} style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '11px 14px' }}>
                    <div style={{ width: 28, height: 28, borderRadius: 8, flexShrink: 0, background: on ? 'rgba(58,106,90,0.12)' : 'rgba(0,0,0,0.04)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                      <Glyph size={15} color={on ? ACCENT_GREEN : 'rgba(29,26,20,0.55)'} stroke={1.8}/>
                    </div>
                    <div style={{ flex: 1 }}>
                      <div style={{ fontSize: 14, color: '#1d1a14', fontWeight: 500 }}>{s.label}</div>
                      <div style={{ fontSize: 11.5, color: 'rgba(29,26,20,0.55)', marginTop: 1 }}>{s.count} in this book</div>
                    </div>
                    <Toggle t={THEMES.paper} on={on}/>
                  </div>
                );
              })}
            </div>
          </Popover></div></AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-retrieval" label="Retrieval bar" width={PW} height={120}>
          <AnatomyWrap><ReadingBar t={THEMES.paper} progress={0.38}/></AnatomyWrap>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

function AnatomyWrap({ children, pad = 0 }) {
  return (
    <div style={{ width: '100%', height: '100%', background: '#fcf8f0', borderRadius: 14, padding: pad,
      display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
      <div style={{ width: '100%' }}>{children}</div>
    </div>
  );
}

Object.assign(window, { ChatContextCanvas });
