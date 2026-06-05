// Canvas artboards for #1477 — AI conversation sessions: picker / switcher / new. Feature #88.
//
// Today the Chat tab is a single ephemeral thread. This adds multiple, switchable
// conversations per book.
//
// CANONICAL placement: a slim SESSION BAR docked directly under the Chat segmented tab —
// left = the active conversation's title + chevron (tap → Conversations sheet), right = a
// "New" compose button. Scoping it to the Chat tab (not the shared sheet header) keeps it
// off the Summarize / Translate tabs, where conversations don't exist, and mirrors where
// the Summarize tab puts its scope chips.
//
// The switcher itself is a nested "Conversations" sheet: a New-conversation row on top,
// then the list (title · preview · timestamp), current row accent-tinted + dotted. Rename
// and Delete live behind a row swipe.

const PW = 402;

const SESSIONS = [
  { id: 's1', title: 'Mr. Bennet’s irony', preview: 'It’s how Austen draws the marriage between them — she matchmakes, he deflects…', when: 'Now', active: true, msgs: 6 },
  { id: 's2', title: 'Marriage & class', preview: 'In P&P marriage works as both romance and economic contract; Charlotte’s…', when: '2h ago', msgs: 14 },
  { id: 's3', title: 'Who is Mr. Darcy?', preview: 'Fitzwilliam Darcy is introduced as proud and aloof at the Meryton assembly…', when: 'Yesterday', msgs: 9 },
  { id: 's4', title: '“Entailment” explained', preview: 'An entail restricts inheritance to male heirs, which is why Longbourn passes…', when: 'Apr 18', msgs: 4 },
  { id: 's5', title: 'Chapter 1 questions', preview: 'The opening line functions as the novel’s ironic thesis statement about…', when: 'Apr 12', msgs: 11 },
];

// ════════════════════════════════════════════════════
// Chat-tab session bar (canonical entry point)
// ════════════════════════════════════════════════════
function SessionBar({ t, title = 'Mr. Bennet’s irony', open = false }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '10px 14px 10px 16px', borderBottom: `0.5px solid ${t.rule}` }}>
      <button style={{
        display: 'inline-flex', alignItems: 'center', gap: 7, padding: '4px 8px 4px 4px', borderRadius: 100,
        border: 'none', background: open ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)') : 'transparent',
        cursor: 'pointer', maxWidth: '74%', fontFamily: 'inherit',
      }}>
        <span style={{ width: 22, height: 22, borderRadius: 11, flexShrink: 0,
          background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.05)',
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
          <ChatGlyph size={12} color={t.sub}/>
        </span>
        <span style={{ fontFamily: SERIF, fontSize: 14.5, fontWeight: 600, color: t.ink,
          whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{title}</span>
        <Icons.ChevronD size={14} color={t.sub} stroke={2.2} style={{ flexShrink: 0,
          transform: open ? 'rotate(180deg)' : 'none', transition: 'transform .15s' }}/>
      </button>
      <button style={{ display: 'inline-flex', alignItems: 'center', gap: 5, padding: '6px 11px 6px 9px',
        borderRadius: 100, border: `0.5px solid ${t.rule}`, background: 'transparent', cursor: 'pointer',
        color: t.ink, fontFamily: 'inherit', flexShrink: 0 }}>
        <Icons.Plus size={14} color={t.accent} stroke={2.4}/>
        <span style={{ fontSize: 12.5, fontWeight: 600 }}>New</span>
      </button>
    </div>
  );
}

function ChatGlyph({ size = 14, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 5h16v11H9l-4 3v-3H4z"/>
    </svg>
  );
}

// ════════════════════════════════════════════════════
// Chat-tab bodies
// ════════════════════════════════════════════════════
function ThreadMessages({ t }) {
  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '16px 18px 8px' }}>
      <AsstBubble t={t} text="Hi! I’ve got this book’s context loaded. Ask me anything about it."/>
      <UserBubble t={t} text="Why does Mr. Bennet tease his wife about visiting Bingley?"/>
      <AsstBubble t={t} text="It’s how Austen draws the marriage between them: she is all anxious matchmaking, he deflects with dry irony. The teasing signals he sees through the social scramble even as he’ll quietly play along."/>
    </div>
  );
}

function NewThreadBody({ t }) {
  return (
    <div style={{ flex: 1, overflow: 'hidden', padding: '22px 18px 8px', display: 'flex', flexDirection: 'column' }}>
      <div style={{ textAlign: 'center', marginTop: 8, marginBottom: 22 }}>
        <div style={{ width: 44, height: 44, borderRadius: 22, margin: '0 auto 12px',
          background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
          <Icons.Sparkle size={22} color="#fff" stroke={1.9}/>
        </div>
        <div style={{ fontFamily: SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>New conversation</div>
        <div style={{ fontSize: 12.5, color: t.sub, marginTop: 3 }}>About <i>Pride and Prejudice</i> · Chapter 1</div>
      </div>
      <div style={{ fontSize: 11, fontWeight: 600, color: t.sub, letterSpacing: 0.8, textTransform: 'uppercase', marginBottom: 8 }}>Try asking</div>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
        {['Who are the Bennet daughters?', 'What tone does the first paragraph set?', 'Explain the irony of the opening line.'].map((q, i) => (
          <button key={i} style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '12px 14px', borderRadius: 12, border: 'none',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff', color: t.ink,
            fontFamily: SERIF, fontSize: 13.5, cursor: 'pointer', textAlign: 'left',
            boxShadow: '0 1px 0 rgba(0,0,0,0.03)' }}>
            <span>{q}</span><Icons.Chevron size={14} color={t.sub} stroke={2}/>
          </button>
        ))}
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// Conversations sheet (nested switcher)
// ════════════════════════════════════════════════════
function ConversationsSheet({ t, mode = 'list', height = 560 }) {
  // mode: 'list' | 'empty' | 'swipe' | 'rename'
  return (
    <div style={{ position: 'absolute', inset: 0, zIndex: 30, display: 'flex', flexDirection: 'column', justifyContent: 'flex-end', background: 'rgba(0,0,0,0.32)' }}>
      <div style={{ background: t.isDark ? '#222020' : '#fcf8f0', height,
        borderTopLeftRadius: 22, borderTopRightRadius: 22, boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
        display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }}/>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '12px 16px 12px 18px',
          borderBottom: `0.5px solid ${t.rule}` }}>
          <div style={{ fontFamily: SERIF, fontSize: 17, fontWeight: 600, color: t.ink }}>Conversations</div>
          <button style={iconBtn(t)}><Icons.Close size={14} color={t.sub} stroke={2}/></button>
        </div>

        {/* New conversation row */}
        <div style={{ padding: '12px 14px 6px' }}>
          <button style={{ display: 'flex', alignItems: 'center', gap: 12, width: '100%', padding: '12px 14px',
            borderRadius: 14, border: `1px dashed ${t.isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.16)'}`,
            background: 'transparent', cursor: 'pointer', fontFamily: 'inherit' }}>
            <span style={{ width: 30, height: 30, borderRadius: 15, flexShrink: 0,
              background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
              <Icons.Plus size={16} color="#fff" stroke={2.4}/>
            </span>
            <span style={{ fontSize: 14.5, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap' }}>New conversation</span>
          </button>
        </div>

        {mode === 'empty' ? (
          <EmptyConversations t={t}/>
        ) : (
          <div style={{ flex: 1, overflow: 'hidden', padding: '6px 8px 16px' }} className="hide-scroll">
            {SESSIONS.map((s, i) => {
              if (mode === 'rename' && s.active) return <RenameRow key={s.id} t={t}/>;
              if (mode === 'swipe' && i === 1) return <SwipeRow key={s.id} t={t} s={s}/>;
              return <SessionRow key={s.id} t={t} s={s}/>;
            })}
          </div>
        )}
      </div>
    </div>
  );
}

function SessionRow({ t, s }) {
  return (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 11, padding: '12px 12px', borderRadius: 12,
      background: s.active ? (t.isDark ? 'rgba(214,136,90,0.12)' : 'rgba(140,47,47,0.06)') : 'transparent' }}>
      <span style={{ width: 30, height: 30, borderRadius: 15, flexShrink: 0, marginTop: 1,
        background: s.active ? t.accent : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)'),
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <ChatGlyph size={14} color={s.active ? '#fff' : t.sub}/>
      </span>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 7 }}>
          <span style={{ fontFamily: SERIF, fontSize: 14.5, fontWeight: 600, color: s.active ? t.accent : t.ink,
            whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.title}</span>
          {s.active && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: 0.4, textTransform: 'uppercase',
            color: '#fff', background: ACCENT_GREEN, padding: '1px 6px', borderRadius: 100, flexShrink: 0 }}>Active</span>}
        </div>
        <div style={{ fontSize: 12.5, color: t.sub, marginTop: 2, lineHeight: 1.35,
          overflow: 'hidden', textOverflow: 'ellipsis', display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical' }}>{s.preview}</div>
        <div style={{ fontSize: 11, color: t.sub, marginTop: 4, opacity: 0.85 }}>{s.msgs} messages · {s.when}</div>
      </div>
    </div>
  );
}

// Swipe-revealed Rename / Delete actions
function SwipeRow({ t, s }) {
  return (
    <div style={{ position: 'relative', borderRadius: 12, overflow: 'hidden', marginBottom: 0 }}>
      <div style={{ position: 'absolute', inset: 0, display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 78,
          background: t.isDark ? 'rgba(255,255,255,0.1)' : 'rgba(0,0,0,0.08)', color: t.ink, gap: 4, flexDirection: 'column' }}>
          <Icons.Note size={16} color={t.ink} stroke={1.8}/>
          <span style={{ fontSize: 11, fontWeight: 600 }}>Rename</span>
        </div>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', width: 78,
          background: '#c0443a', color: '#fff', gap: 4, flexDirection: 'column' }}>
          <TrashGlyph size={16} color="#fff"/>
          <span style={{ fontSize: 11, fontWeight: 600 }}>Delete</span>
        </div>
      </div>
      <div style={{ transform: 'translateX(-156px)', background: t.isDark ? '#222020' : '#fcf8f0' }}>
        <SessionRow t={t} s={s}/>
      </div>
    </div>
  );
}

function RenameRow({ t }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 11, padding: '10px 12px', borderRadius: 12,
      background: t.isDark ? 'rgba(214,136,90,0.12)' : 'rgba(140,47,47,0.06)' }}>
      <span style={{ width: 30, height: 30, borderRadius: 15, flexShrink: 0, background: t.accent,
        display: 'inline-flex', alignItems: 'center', justifyContent: 'center' }}>
        <ChatGlyph size={14} color="#fff"/>
      </span>
      <div style={{ flex: 1, display: 'flex', alignItems: 'center', gap: 8,
        background: t.isDark ? '#2b2926' : '#fff', borderRadius: 10, padding: '8px 10px',
        border: `1.5px solid ${t.accent}` }}>
        <span style={{ fontFamily: SERIF, fontSize: 14.5, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap' }}>Mr. Bennet’s irony</span>
        <span style={{ width: 1.5, height: 16, background: t.accent, marginLeft: -2, animation: 'aishblink 1s steps(2,start) infinite' }}/>
      </div>
      <button style={{ border: 'none', background: 'none', color: t.accent, fontFamily: 'inherit',
        fontSize: 13.5, fontWeight: 600, cursor: 'pointer', padding: '4px 6px' }}>Done</button>
    </div>
  );
}

function EmptyConversations({ t }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '0 40px 40px', textAlign: 'center' }}>
      <div style={{ width: 52, height: 52, borderRadius: 16, marginBottom: 14,
        background: t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)',
        display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
        <ChatGlyph size={24} color={t.sub}/>
      </div>
      <div style={{ fontFamily: SERIF, fontSize: 16, fontWeight: 600, color: t.ink }}>No past conversations</div>
      <div style={{ fontSize: 13, color: t.sub, marginTop: 5, lineHeight: 1.45 }}>
        This is your first chat about <i>Pride and Prejudice</i>. Start a new conversation any time and it’ll be saved here.
      </div>
    </div>
  );
}

function TrashGlyph({ size = 16, color = 'currentColor' }) {
  return (
    <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round">
      <path d="M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13"/>
    </svg>
  );
}

// ════════════════════════════════════════════════════
// Quick-switch dropdown (alternate)
// ════════════════════════════════════════════════════
function QuickSwitchScreen({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <SessionBar t={t} open/>
        <ThreadMessages t={t}/>
        <div style={{ borderTop: `0.5px solid ${t.rule}` }}><Composer t={t}/></div>
        {/* dropdown popover from the title */}
        <div style={{ position: 'absolute', left: 14, top: 50, width: 280, zIndex: 6 }}>
          <Popover t={t}>
            <div style={{ padding: '4px 0', maxHeight: 320, overflow: 'hidden' }}>
              {SESSIONS.slice(0, 4).map(s => (
                <div key={s.id} style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 14px',
                  background: s.active ? (t.isDark ? 'rgba(214,136,90,0.12)' : 'rgba(140,47,47,0.05)') : 'transparent' }}>
                  <span style={{ width: 7, height: 7, borderRadius: 4, flexShrink: 0, background: s.active ? ACCENT_GREEN : 'transparent' }}/>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ fontSize: 13.5, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{s.title}</div>
                    <div style={{ fontSize: 11, color: t.sub }}>{s.when}</div>
                  </div>
                </div>
              ))}
              <div style={{ borderTop: `0.5px solid ${t.rule}`, marginTop: 4 }}>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 14px', color: t.accent }}>
                  <Icons.Plus size={15} color={t.accent} stroke={2.4}/>
                  <span style={{ fontSize: 13.5, fontWeight: 600 }}>New conversation</span>
                </div>
                <div style={{ display: 'flex', alignItems: 'center', gap: 8, padding: '11px 14px', color: t.sub }}>
                  <ChatGlyph size={14} color={t.sub}/>
                  <span style={{ fontSize: 13.5, fontWeight: 500 }}>See all conversations</span>
                </div>
              </div>
            </div>
          </Popover>
          <Notch t={t} left={26}/>
        </div>
      </AISheet>
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// Full chat screens
// ════════════════════════════════════════════════════
function SessionChatScreen({ themeKey = 'paper', body = 'thread', sheet = null, sheetMode = 'list', barOpen = false }) {
  const t = THEMES[themeKey];
  return (
    <PhoneShell themeKey={themeKey} height={760}>
      <AISheet t={t} height={650} tab="chat">
        <SessionBar t={t} title={body === 'new' ? 'New conversation' : 'Mr. Bennet’s irony'} open={barOpen}/>
        {body === 'new' ? <NewThreadBody t={t}/> : <ThreadMessages t={t}/>}
        <div style={{ borderTop: `0.5px solid ${t.rule}` }}>
          <Composer t={t} placeholder={body === 'new' ? 'Ask anything to begin…' : 'Ask about this book…'}/>
        </div>
      </AISheet>
      {sheet && <ConversationsSheet t={t} mode={sheetMode}/>}
    </PhoneShell>
  );
}

// ════════════════════════════════════════════════════
// CANVAS
// ════════════════════════════════════════════════════
function SessionSwitcherCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>
      <DCSection id="intro" title="AI conversation sessions · #1477"
        subtitle="Feature #88. Multiple switchable conversations per book. Canonical: a slim session bar under the Chat tab — the active conversation’s title + chevron opens a Conversations sheet, and “New” starts a fresh thread. The bar lives on the Chat tab only, since Summarize and Translate have no conversations.">
        <DCPostIt top={-36} right={26} rotate={-2} width={330}>
          <b>Title bar, not sheet header.</b> The AI sheet header is shared by all three
          tabs. Conversations only exist for Chat, so the entry point is a Chat-scoped bar —
          where the Summarize tab already puts its scope chips.
        </DCPostIt>
      </DCSection>

      {/* A — canonical */}
      <DCSection id="A" title="A — Session bar + Conversations sheet (canonical)"
        subtitle="The bar names the active conversation. Tapping it opens the Conversations sheet: a New-conversation row on top, then the saved threads (title · 2-line preview · message count · time). The current one is accent-tinted with a green “Active” tag.">
        <DCArtboard id="A-bar" label="Chat · session bar" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="thread"/>
        </DCArtboard>
        <DCArtboard id="A-list" label="Conversations sheet · populated" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="thread" sheet sheetMode="list" barOpen/>
        </DCArtboard>
        <DCArtboard id="A-new" label="New conversation · fresh thread" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="new"/>
        </DCArtboard>
      </DCSection>

      {/* States */}
      <DCSection id="S" title="S — Switch · rename · delete · empty"
        subtitle="Swipe a row to reveal Rename (neutral) and Delete (red); Rename edits the title in place. The empty state covers a book’s first-ever chat — the New-conversation row stays, the list explains itself.">
        <DCArtboard id="S-swipe" label="Swipe row · Rename / Delete" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="thread" sheet sheetMode="swipe" barOpen/>
        </DCArtboard>
        <DCArtboard id="S-rename" label="Rename in place" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="thread" sheet sheetMode="rename" barOpen/>
        </DCArtboard>
        <DCArtboard id="S-empty" label="Empty · first chat" width={PW} height={760}>
          <SessionChatScreen themeKey="paper" body="thread" sheet sheetMode="empty" barOpen/>
        </DCArtboard>
      </DCSection>

      {/* Dark */}
      <DCSection id="dark" title="Dark"
        subtitle="Same surface on the dark theme — accent tint + green Active tag carry the current-session indicator.">
        <DCArtboard id="d-list" label="Conversations · dark" width={PW} height={760}>
          <SessionChatScreen themeKey="dark" body="thread" sheet sheetMode="list" barOpen/>
        </DCArtboard>
        <DCArtboard id="d-new" label="New conversation · dark" width={PW} height={760}>
          <SessionChatScreen themeKey="dark" body="new"/>
        </DCArtboard>
      </DCSection>

      {/* Alternate */}
      <DCSection id="B" title="B — Quick-switch dropdown (alternate)"
        subtitle="A compact popover dropping from the title for fast hops between recent threads, with “See all” falling through to the full sheet. Kept as a secondary affordance — good for switching, too cramped for rename/delete and 2-line previews.">
        <DCArtboard id="B-dd" label="Quick-switch popover" width={PW} height={760}>
          <QuickSwitchScreen themeKey="paper"/>
        </DCArtboard>
        <DCPostIt bottom={-28} left={22} rotate={2} width={296}>
          The dropdown wins on speed but can’t hold management actions. Ship the sheet as
          canonical; the dropdown is a later add if switching frequency justifies it.
        </DCPostIt>
      </DCSection>

      {/* Anatomy */}
      <DCSection id="D" title="D — Pieces · true size"
        subtitle="Session bar and one list row at 1:1.">
        <DCArtboard id="D-bar" label="Session bar" width={PW} height={92}>
          <AnatomyWrap><SessionBar t={THEMES.paper}/></AnatomyWrap>
        </DCArtboard>
        <DCArtboard id="D-row" label="Active row" width={360} height={120}>
          <AnatomyWrap pad={12}><SessionRow t={THEMES.paper} s={SESSIONS[0]}/></AnatomyWrap>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { SessionSwitcherCanvas });
