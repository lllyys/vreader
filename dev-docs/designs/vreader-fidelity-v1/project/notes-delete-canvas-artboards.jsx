// Canvas artboards · issue #1103 — HighlightsSheet delete affordance.
//
// Companion to vreader-notes-delete.jsx. Builds a buildable spec for the
// delete affordance that resolves bug #249 / #1080 on the HighlightsSheet
// (feature #62 WI-5).

const ND_PHONE_W = 402;
const ND_PHONE_H = 720;

// ─────────────────────────────────────────────────────
// Sample data — augments the fixture in vreader-notes-unified.jsx so the
// list has enough rows to make state changes visible mid-scroll.
// ─────────────────────────────────────────────────────
const ND_HIGHLIGHTS = [
  { id: 'h1', kind: 'highlight',
    text: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    color: 'yellow', chapter: 'Chapter 1', page: 1, date: 'Apr 12' },
  { id: 'h2', kind: 'highlight',
    text: 'You take delight in vexing me. You have no compassion for my poor nerves.',
    color: 'pink', chapter: 'Chapter 1', page: 4, date: 'Apr 12',
    note: "Mrs. Bennet's catchphrase. Austen lets her self-pity become its own punchline." },
  { id: 'h3', kind: 'highlight',
    text: 'She is tolerable, but not handsome enough to tempt me.',
    color: 'blue', chapter: 'Chapter 3', page: 18, date: 'Apr 15',
    note: 'The line that sets up the whole arc.' },
];
const ND_STANDALONES = [
  { id: 's1', kind: 'standalone', chapter: 'Chapter 6', page: 47, date: 'Apr 18',
    body: "Charlotte's pragmatism here is the inverse of Elizabeth's — \"happiness in marriage is entirely a matter of chance.\" Worth re-reading next to Lizzy's reaction." },
  { id: 's2', kind: 'standalone', chapter: 'Chapter 11', page: 89, date: 'Yesterday',
    body: "Note: the ball scene is the structural midpoint of the first volume. Track Darcy's reluctance vs. his actions." },
];

// ─────────────────────────────────────────────────────
// Phone frame
// ─────────────────────────────────────────────────────
function NDPhone({ themeKey = 'paper', children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: ND_PHONE_W, height: ND_PHONE_H,
      position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.32)',
    }}>
      <NDReaderBackdrop theme={t}/>
      {children}
    </div>
  );
}

// Faded reader-page under the sheet — so the surface clearly reads as a
// modal sheet over content, not a free-floating panel.
function NDReaderBackdrop({ theme }) {
  const t = theme;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: 0.55 }}>
      <div style={{
        height: 44, display: 'flex', alignItems: 'flex-end',
        justifyContent: 'space-between', padding: '0 18px 4px',
        fontSize: 12, color: t.ink, fontWeight: 600, opacity: 0.7,
      }}>
        <span>9:41</span><span style={{ letterSpacing: 1 }}>•••</span>
      </div>
      <div style={{ padding: '6px 28px 0' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 10.5, color: t.sub, letterSpacing: 2,
          textTransform: 'uppercase', textAlign: 'center', marginBottom: 16,
        }}>Chapter 3</div>
        <p style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14.5, lineHeight: 1.6, color: t.ink, margin: 0,
          textAlign: 'justify',
        }}>
          Mr. Bingley had soon made himself acquainted with all the principal
          people in the room; he was lively and unreserved, danced every
          dance, was angry that the ball closed so early, and talked of
          giving one himself at Netherfield.
        </p>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Sheet artboard helper — renders HighlightsSheetV4 with a forced row
// state so an artboard can show a single moment in the interaction.
// ─────────────────────────────────────────────────────
function NDSheet({ themeKey = 'paper', filter = 'all',
                   forcedRowId = null, forcedState = null,
                   highlights = ND_HIGHLIGHTS, standalones = ND_STANDALONES }) {
  const t = THEMES[themeKey];
  return (
    <NDPhone themeKey={themeKey}>
      <HighlightsSheetV4 theme={t}
        highlights={highlights} standalones={standalones}
        filter={filter}
        forcedRowId={forcedRowId} forcedState={forcedState}
        onClose={() => {}} onJump={() => {}}/>
    </NDPhone>
  );
}

// Some artboards need to show the swipe-revealed state and the popover
// state at the same time on different rows — render manually below.
function NDSheetBoth({ themeKey = 'paper' }) {
  const t = THEMES[themeKey];
  return (
    <NDPhone themeKey={themeKey}>
      <div style={{
        position: 'absolute', inset: 0, zIndex: 200,
        background: 'rgba(0,0,0,0.35)',
        display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
      }}>
        <div style={{
          background: t.isDark ? '#222020' : '#fcf8f0',
          height: 680, borderTopLeftRadius: 22, borderTopRightRadius: 22,
          boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
          display: 'flex', flexDirection: 'column', overflow: 'hidden',
        }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
            <div style={{
              width: 36, height: 5, borderRadius: 3,
              background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)',
            }}/>
          </div>
          <div style={{
            display: 'flex', alignItems: 'center', justifyContent: 'space-between',
            padding: '14px 18px 12px',
            borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
          }}>
            <div style={{ width: 50 }}/>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 17, fontWeight: 600, color: t.ink,
            }}>Annotations</div>
            <div style={{ width: 50 }}/>
          </div>
          <div style={{ padding: '10px 18px 6px', display: 'flex', gap: 6 }}>
            <NDChip t={t} label="All" count={5} active/>
            <NDChip t={t} label="Highlights" count={3}/>
            <NDChip t={t} label="Notes" count={4}/>
            <NDChip t={t} label="Bookmarks" count={0}/>
          </div>
          <div style={{ padding: '8px 18px 24px' }}>
            <StandaloneNoteCardV4 t={t} note={ND_STANDALONES[1]} state="swipe-revealed"
              onJump={()=>{}} onEdit={()=>{}} onDelete={()=>{}}/>
            <HighlightCardV4 t={t} h={ND_HIGHLIGHTS[2]} state="default"
              onJump={()=>{}}/>
            <StandaloneNoteCardV4 t={t} note={ND_STANDALONES[0]} state="default"
              onJump={()=>{}}/>
          </div>
        </div>
      </div>
    </NDPhone>
  );
}

function NDChip({ t, label, count, active }) {
  return (
    <span style={{
      padding: '6px 13px', borderRadius: 100,
      fontFamily: 'inherit', fontSize: 12, fontWeight: 500,
      background: active ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
      color: active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
      display: 'inline-flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
    }}>
      <span>{label}</span>
      <span style={{
        fontSize: 10.5, opacity: 0.7,
        padding: '1px 5px', borderRadius: 100,
        background: active ? (t.isDark ? 'rgba(0,0,0,0.18)' : 'rgba(255,255,255,0.2)') : 'transparent',
      }}>{count}</span>
    </span>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function NotesDeleteCanvas() {
  return (
    <DesignCanvas>

      {/* ─── 1. Intent ─── */}
      <DCSection id="intent"
        title="#1103 — HighlightsSheet delete affordance"
        subtitle={'Resolves bug #249 (refs #1080). The committed HighlightsSheetV3 (vreader-notes-unified.jsx) ships tap-to-jump rows with no way to delete from the review surface. We add a trailing ⋯ menu — visible, discoverable, VoiceOver-safe — that reveals Edit · Copy · Delete on either card kind. iOS-native left-swipe is supported as a parallel gesture path. Confirmation mirrors HPDeleteConfirm from the in-reader highlight popover (#949); deletion stays on-surface.'}>
        <DCArtboard id="canonical" label="Canonical · ⋯ menu open on a highlight row"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="menu-open"/>
        </DCArtboard>
        <DCArtboard id="canonical-standalone" label="⋯ menu open on a standalone note"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="s1" forcedState="menu-open"/>
        </DCArtboard>
        <DCArtboard id="resting" label="Resting · ⋯ visible on every row"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={2} width={280}>
          The <i>⋯</i> sits in the meta row trailing edge, after the date. Visible at rest — no hover-to-reveal — so it's a real touch target on a real iPhone. The button is a labelled <code>aria-label</code>; VoiceOver lands on it.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. State machine ─── */}
      <DCSection id="states"
        title="Per-row state machine"
        subtitle={'Only one row is non-default at a time — selecting a row\'s ⋯ closes any other row\'s menu. State sequence: default → menu-open → confirming → deleting → (default ∪ removed) ∪ error. Cancel from any non-terminal state returns to default; the row body never loses its identity (meta row + locator stay visible) so the user can never confuse which row they\'re acting on.'}>
        <DCArtboard id="state-default" label="default"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet/>
        </DCArtboard>
        <DCArtboard id="state-menu" label="menu-open"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="menu-open"/>
        </DCArtboard>
        <DCArtboard id="state-confirming" label="confirming · inline strip"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="state-deleting" label="deleting · row dim + spinner"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="deleting"/>
        </DCArtboard>
        <DCArtboard id="state-error" label="error · Retry · Undo"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="error"/>
        </DCArtboard>
        <DCArtboard id="state-postdelete" label="post-delete · row dims out"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="dim-after-delete"/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={-2} width={280}>
          The <code>dim-after-delete</code> frame is the half-second between <code>PersistenceActor.removeHighlight</code> committing and the row leaving the LazyVStack. Without it, healthy deletes look like the row teleported away.
        </DCPostIt>
      </DCSection>

      {/* ─── 3. Confirmation — references HPDeleteConfirm ─── */}
      <DCSection id="confirm"
        title="Confirmation · mirrors HPDeleteConfirm"
        subtitle={'The issue body asks "should the review sheet match?" The in-reader popover (vreader-highlight-popover.jsx, #949) already commits HPDeleteConfirm — small inline strip, tinted destructive background, paired Cancel/Delete pills with the same copy template ("…comes off the page. Can\'t be undone."). We reuse the vocabulary directly, scoped down to the row\'s width. No system alert — the destructive surface stays inside the row.'}>
        <DCArtboard id="confirm-highlight" label="Highlight · destructive copy"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="confirm-standalone" label="Standalone note · destructive copy"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="s1" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="confirm-busy" label="Deleting · busy pill, Cancel disabled"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="deleting"/>
        </DCArtboard>
        <DCArtboard id="hp-cross-reference" label="Cross-reference · the in-reader source"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDHPCrossReference/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={2} width={280}>
          Why inline and not a system alert: an alert dismisses the sheet's scroll position and breaks the "I'm pruning a list" flow. The user is mid-curation — keep the surface visible so they can delete five rows in a row without the sheet retreating to the home screen between each.
        </DCPostIt>
      </DCSection>

      {/* ─── 4. Both card kinds ─── */}
      <DCSection id="both-kinds"
        title="Both card kinds carry the affordance"
        subtitle={'Bug #249 calls out both surfaces: HighlightRecord cards (HighlightCardV4) and standalone AnnotationRecord cards (StandaloneNoteCardV4). The ⋯ + swipe affordances are identical in both — only the destructive copy differs ("highlight" vs "note") and the menu label set adapts.'}>
        <DCArtboard id="kind-highlight-menu" label="HighlightCard · menu open"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="menu-open"/>
        </DCArtboard>
        <DCArtboard id="kind-highlight-confirm" label="HighlightCard · confirming"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="kind-standalone-menu" label="StandaloneNote · menu open"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="s1" forcedState="menu-open"/>
        </DCArtboard>
        <DCArtboard id="kind-standalone-confirm" label="StandaloneNote · confirming"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="s1" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="kind-highlight-nonote" label="HighlightCard without note · menu open"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h1" forcedState="menu-open"/>
        </DCArtboard>
      </DCSection>

      {/* ─── 5. Secondary path: iOS-native swipe ─── */}
      <DCSection id="swipe"
        title="Secondary · iOS-native left-swipe"
        subtitle={'Same destinations, gesture instead of tap. iOS users reach for the swipe in any review-list surface (Mail, Notes, Reminders) — withholding it would be a discoverability regression in the other direction. Swipe reveals Edit (amber) + Delete (destructive ink); a full-swipe trips delete directly (with the same confirm strip on release, per Apple HIG for destructive bulk gestures).'}>
        <DCArtboard id="swipe-revealed" label="Left-swipe revealed · Edit · Delete"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="swipe-revealed"/>
        </DCArtboard>
        <DCArtboard id="swipe-standalone" label="Swipe on a standalone note"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="s1" forcedState="swipe-revealed"/>
        </DCArtboard>
        <DCArtboard id="swipe-and-menu" label="Coexistence · swipe on one row, ⋯ resting on others"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheetBoth/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={-2} width={280}>
          The swipe drawer is the gesture path; the <i>⋯</i> is the visible path. Both land on the same Edit / Delete destinations. We don't ship swipe alone — Rule 51 + accessibility demand a visible target.
        </DCPostIt>
      </DCSection>

      {/* ─── 6. Edit handoff ─── */}
      <DCSection id="edit-handoff"
        title="Edit · handoff, not re-implementation"
        subtitle={'Tapping Edit hands off to the existing surfaces — HighlightActionCard for passages, the note editor for standalones. The sheet does not embed a textarea. Rationale: the in-reader popover (#949) is the single canonical editor for highlight notes; the standalone-note editor was committed legacy (AnnotationEditSheet). A second editor inside the sheet would fork the editing story.'}>
        <DCArtboard id="edit-handoff-highlight" label="Edit · jumps + opens HighlightActionCard in editing mode"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDEditHandoffHighlight/>
        </DCArtboard>
        <DCArtboard id="edit-handoff-standalone" label="Edit · jumps + opens the standalone note editor"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDEditHandoffStandalone/>
        </DCArtboard>
      </DCSection>

      {/* ─── 7. Themes ─── */}
      <DCSection id="themes"
        title="ReaderThemeV2 tokens"
        subtitle={'Destructive ink resolves per theme: #a83a3a on paper/sepia, #e89090 on dark/OLED. The confirmation strip uses a 4–6% tint of that ink as background; the row\'s identity (meta + locator + ⋯) keeps its normal token colors.'}>
        <DCArtboard id="theme-paper" label="paper · canonical"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet themeKey="paper" forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="theme-sepia" label="sepia · warm paper"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet themeKey="sepia" forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="theme-dark" label="dark · destructive ink lightens"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet themeKey="dark" forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="theme-oled" label="OLED · true-black bg"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet themeKey="oled" forcedRowId="h2" forcedState="confirming"/>
        </DCArtboard>
        <DCArtboard id="theme-dark-menu" label="dark · ⋯ menu"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet themeKey="dark" forcedRowId="h2" forcedState="menu-open"/>
        </DCArtboard>
      </DCSection>

      {/* ─── 8. Empty after delete ─── */}
      <DCSection id="empty"
        title="Empty after delete · existing empty state re-flows"
        subtitle={'When the last row of the active filter is deleted, the v3 empty state (EmptyHighlightsArt + filter-specific title/body) renders without modification. Copy is unchanged — already covered by vreader-notes-unified.jsx. No new state.'}>
        <DCArtboard id="empty-all" label="All deleted · existing empty"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet highlights={[]} standalones={[]}/>
        </DCArtboard>
        <DCArtboard id="empty-notes" label="Notes filter empty after pruning"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet filter="notes"
            highlights={[{ ...ND_HIGHLIGHTS[0] }]} standalones={[]}/>
        </DCArtboard>
      </DCSection>

      {/* ─── 9. What's broken today ─── */}
      <DCSection id="before"
        title="What's broken today · the bug #249 regression"
        subtitle={'Two reference frames: the surface as it ships (tap-to-jump only, no delete) and the rejected worktree fix (a `.contextMenu` long-press, which Codex Gate-4 audit 019e47fd flagged as a High-severity Rule-51 violation — contextual menus on app content are NOT the system-chrome restoration exemption).'}>
        <DCArtboard id="before-current" label="Current ship · no delete affordance"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDBeforeCurrent/>
        </DCArtboard>
        <DCArtboard id="before-rejected" label="Rejected · `.contextMenu` long-press (Rule-51 violation)"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDBeforeRejected/>
        </DCArtboard>
        <DCArtboard id="after" label="After · #1103 design"
          width={ND_PHONE_W} height={ND_PHONE_H}>
          <NDSheet forcedRowId="h2" forcedState="menu-open"/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={2} width={280}>
          Worktree branch <code>fix/issue-1080-highlightssheet-delete-affordance</code> tried a one-line <code>.contextMenu</code> on the cards. It worked. It was also undiscoverable, gestured-only, and Codex Gate-4 returned <code>needs-fix</code> with a High-severity Rule-51 finding. This canvas is the unlock.
        </DCPostIt>
      </DCSection>

      {/* ─── 10. Spec card ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="Binding contract for the bug #249 fix and for whoever inherits the sheet.">
        <DCArtboard id="spec-card" label="" width={ND_PHONE_W * 2 + 30} height={680}>
          <NDSpecCard/>
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

// ─────────────────────────────────────────────────────
// Cross-reference frame — HPDeleteConfirm in its in-reader habitat,
// shown side-by-side so the inheritance is obvious.
// ─────────────────────────────────────────────────────
function NDHPCrossReference() {
  const t = THEMES.paper;
  return (
    <div style={{
      width: ND_PHONE_W, height: ND_PHONE_H, position: 'relative',
      background: t.bg, borderRadius: 18, overflow: 'hidden',
      padding: 20, boxSizing: 'border-box',
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 12, color: t.sub, letterSpacing: 2,
        textTransform: 'uppercase', marginBottom: 16, textAlign: 'center',
      }}>shared destructive vocabulary</div>
      <div style={{
        background: t.isDark ? '#2a2724' : '#fcf8f0', borderRadius: 14,
        padding: '8px 14px 14px',
        boxShadow: '0 8px 20px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.06)',
        marginBottom: 14,
      }}>
        <div style={{
          fontSize: 9.5, color: t.sub, fontWeight: 700, letterSpacing: 1,
          textTransform: 'uppercase', marginBottom: 8,
        }}>From #949 · in-reader popover</div>
        {typeof HPDeleteConfirm !== 'undefined' ? (
          <HPDeleteConfirm theme={t}
            onCancel={() => {}} onConfirm={() => {}}/>
        ) : (
          <NotesDeleteConfirm t={t} kind="highlight"
            onCancel={() => {}} onConfirm={() => {}}/>
        )}
      </div>
      <div style={{
        background: t.isDark ? '#2a2724' : '#fcf8f0', borderRadius: 14,
        padding: '8px 14px 14px',
        boxShadow: '0 8px 20px rgba(0,0,0,0.10), 0 0 0 0.5px rgba(0,0,0,0.06)',
      }}>
        <div style={{
          fontSize: 9.5, color: t.sub, fontWeight: 700, letterSpacing: 1,
          textTransform: 'uppercase', marginBottom: 8,
        }}>This issue · review-sheet row</div>
        <NotesDeleteConfirm t={t} kind="highlight"
          onCancel={() => {}} onConfirm={() => {}}/>
      </div>
      <div style={{
        marginTop: 16, fontSize: 12, color: t.sub, lineHeight: 1.5,
        textWrap: 'pretty', textAlign: 'center',
      }}>
        Same title pattern, same body copy template, same Cancel/Delete pill
        pair. Different scope (row vs popover) — identical voice.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Edit handoff frames — show the destination, not the gesture
// ─────────────────────────────────────────────────────
function NDEditHandoffHighlight() {
  const t = THEMES.paper;
  return (
    <NDPhone themeKey="paper">
      {/* ghost the sheet underneath to imply the handoff direction */}
      <div style={{
        position: 'absolute', inset: 0, zIndex: 100,
        background: 'rgba(0,0,0,0.45)',
      }}/>
      {typeof HighlightActionCard !== 'undefined' ? (
        <HighlightActionCard theme={t}
          highlight={ND_HIGHLIGHTS[1]}
          anchorRect={{ left: 28, top: 260, width: 320, height: 22, containerW: ND_PHONE_W }}
          side="above" mode="editing"
          showDim={false}
          onChangeColor={()=>{}} onEdit={()=>{}} onSaveNote={()=>{}}
          onCancelEdit={()=>{}} onCopy={()=>{}} onShare={()=>{}}
          onDelete={()=>{}} onConfirmDelete={()=>{}} onClose={()=>{}}/>
      ) : (
        <NDPlaceholder t={t} label="HighlightActionCard — editing"/>
      )}
      <NDHandoffLabel label="Edit · from HighlightsSheet"
        sub="→ jumps + opens HighlightActionCard in editing mode"/>
    </NDPhone>
  );
}

function NDEditHandoffStandalone() {
  const t = THEMES.paper;
  return (
    <NDPhone themeKey="paper">
      <div style={{
        position: 'absolute', inset: 0, zIndex: 100,
        background: 'rgba(0,0,0,0.45)',
      }}/>
      <div style={{
        position: 'absolute', left: 14, right: 14, bottom: 18, zIndex: 105,
        borderRadius: 18, overflow: 'hidden',
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 18px 50px rgba(0,0,0,0.36), 0 0 0 0.5px rgba(0,0,0,0.08)',
      }}>
        <div style={{ display: 'flex', justifyContent: 'center', padding: '6px 0 0' }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.12)' }}/>
        </div>
        <div style={{
          padding: '12px 16px 10px',
          display: 'flex', alignItems: 'center', gap: 10,
          borderBottom: `0.5px solid ${t.rule}`,
        }}>
          <div style={{
            width: 14, height: 14, borderRadius: 4,
            background: `${t.accent}22`, color: t.accent,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="9" height="10" viewBox="0 0 7 8">
              <path d="M0.5 0.5h5l1 1v6h-6z" fill="currentColor" opacity="0.9"/>
              <path d="M1.8 3h3.2M1.8 4.6h2.2" stroke="#fcf8f0" strokeWidth="0.7"/>
            </svg>
          </div>
          <div style={{ flex: 1 }}>
            <div style={{
              fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 15, fontWeight: 600, color: t.ink,
            }}>Edit note</div>
            <div style={{ fontSize: 11.5, color: t.sub }}>
              Chapter 6 · p. 47 · standalone
            </div>
          </div>
          <button style={{
            padding: '6px 12px', borderRadius: 8, border: 'none',
            background: t.accent, color: '#fff',
            fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600, cursor: 'pointer',
          }}>Save</button>
        </div>
        <div style={{
          padding: '12px 16px 14px',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14.5, lineHeight: 1.55, color: t.ink, textWrap: 'pretty',
        }}>
          Charlotte's pragmatism here is the inverse of Elizabeth's —
          "happiness in marriage is entirely a matter of chance." Worth
          re-reading next to Lizzy's reaction.
          <span style={{
            display: 'inline-block', width: 1, height: 16, background: t.accent,
            marginLeft: 2, verticalAlign: 'middle', animation: 'ndCaret 1s steps(1) infinite',
          }}/>
        </div>
      </div>
      <NDHandoffLabel label="Edit · from HighlightsSheet"
        sub="→ jumps + opens the standalone-note editor"/>
    </NDPhone>
  );
}

function NDHandoffLabel({ label, sub }) {
  return (
    <div style={{
      position: 'absolute', top: 56, left: 0, right: 0, zIndex: 110,
      textAlign: 'center',
    }}>
      <div style={{
        display: 'inline-block',
        background: 'rgba(0,0,0,0.72)', color: '#fff',
        padding: '8px 14px', borderRadius: 100,
        fontFamily: '"Inter", system-ui, sans-serif',
        fontSize: 12, fontWeight: 600, letterSpacing: 0.3,
        boxShadow: '0 6px 18px rgba(0,0,0,0.32)',
      }}>{label}</div>
      <div style={{
        marginTop: 6, fontSize: 11, color: '#ddd', letterSpacing: 0.2,
        fontFamily: '"Inter", system-ui, sans-serif',
      }}>{sub}</div>
    </div>
  );
}

function NDPlaceholder({ t, label }) {
  return (
    <div style={{
      position: 'absolute', left: 24, right: 24, top: '40%', zIndex: 105,
      padding: '24px 20px', borderRadius: 14,
      background: t.isDark ? '#2a2724' : '#fcf8f0',
      boxShadow: '0 12px 30px rgba(0,0,0,0.24)',
      textAlign: 'center', fontFamily: 'monospace', fontSize: 12, color: t.sub,
    }}>{label} (placeholder — exists at runtime)</div>
  );
}

// ─────────────────────────────────────────────────────
// "Before" mocks
// ─────────────────────────────────────────────────────
function NDBeforeCurrent() {
  return (
    <NDPhone themeKey="paper">
      <HighlightsSheetV3 theme={THEMES.paper}
        highlights={ND_HIGHLIGHTS} standalones={ND_STANDALONES}
        onClose={()=>{}} onJump={()=>{}}/>
      <NDRedX top={170} right={26} label="No ⋯"/>
      <NDRedX top={290} right={26} label="No delete path"/>
      <NDRedX top={420} right={26} label="Tap = jump only"/>
    </NDPhone>
  );
}

function NDBeforeRejected() {
  const t = THEMES.paper;
  return (
    <NDPhone themeKey="paper">
      <HighlightsSheetV3 theme={t}
        highlights={ND_HIGHLIGHTS} standalones={ND_STANDALONES}
        onClose={()=>{}} onJump={()=>{}}/>
      {/* fake SwiftUI .contextMenu floating panel */}
      <div style={{
        position: 'absolute', left: 76, top: 270, zIndex: 250,
        width: 240, borderRadius: 14, overflow: 'hidden',
        background: 'rgba(244,238,224,0.96)', backdropFilter: 'blur(20px)',
        boxShadow: '0 18px 40px rgba(0,0,0,0.30), 0 0 0 0.5px rgba(0,0,0,0.08)',
        fontFamily: '-apple-system, system-ui, sans-serif',
      }}>
        <div style={{
          padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 10,
          fontSize: 15, color: '#1d1a14',
          borderBottom: '0.5px solid rgba(0,0,0,0.08)',
        }}>
          <span style={{ flex: 1 }}>Copy</span>
          <NDCopyGlyph size={18} color="#1d1a14"/>
        </div>
        <div style={{
          padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 10,
          fontSize: 15, color: '#1d1a14',
          borderBottom: '0.5px solid rgba(0,0,0,0.08)',
        }}>
          <span style={{ flex: 1 }}>Edit Note</span>
          <NDPencilGlyph size={18} color="#1d1a14"/>
        </div>
        <div style={{
          padding: '12px 16px', display: 'flex', alignItems: 'center', gap: 10,
          fontSize: 15, color: '#a83a3a', fontWeight: 600,
        }}>
          <span style={{ flex: 1 }}>Delete</span>
          <NDTrashGlyph size={18} color="#a83a3a"/>
        </div>
      </div>
      <div style={{
        position: 'absolute', left: 16, right: 16, bottom: 86, zIndex: 260,
        background: 'rgba(168,58,58,0.95)', color: '#fff',
        padding: '12px 14px', borderRadius: 12,
        fontFamily: '"Inter", system-ui, sans-serif',
        fontSize: 12, lineHeight: 1.45, textWrap: 'pretty',
        boxShadow: '0 12px 28px rgba(0,0,0,0.32)',
      }}>
        <div style={{ fontWeight: 700, marginBottom: 2 }}>Codex Gate-4 · needs-fix · High</div>
        <div>
          <code style={{ background: 'rgba(255,255,255,0.18)', padding: '0 4px', borderRadius: 3 }}>.contextMenu</code>
          {' '}on app content is not the system-chrome restoration exemption
          (Rule 51). Gestured-only · undiscoverable · no labelled control.
        </div>
        <div style={{ marginTop: 4, opacity: 0.82, fontSize: 11 }}>
          thread 019e47fd-9b06-79d3-b011-4f460107f005
        </div>
      </div>
    </NDPhone>
  );
}

function NDRedX({ top, right, label }) {
  return (
    <div style={{
      position: 'absolute', top, right, zIndex: 220,
      padding: '3px 8px', borderRadius: 100,
      background: 'rgba(168,58,58,0.92)', color: '#fff',
      fontSize: 10.5, fontWeight: 600, letterSpacing: 0.3,
      fontFamily: '"Inter", system-ui, sans-serif',
      boxShadow: '0 4px 10px rgba(0,0,0,0.18)',
      display: 'inline-flex', alignItems: 'center', gap: 5,
    }}>
      <span style={{
        width: 12, height: 12, borderRadius: 6, background: '#fff',
        color: '#a83a3a', display: 'inline-flex', alignItems: 'center',
        justifyContent: 'center', fontSize: 10, fontWeight: 700,
      }}>×</span>
      {label}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding contract
// ─────────────────────────────────────────────────────
function NDSpecCard() {
  const t = THEMES.paper;
  const rowStyle = {
    display: 'grid', gridTemplateColumns: '170px 1fr',
    gap: 16, padding: '11px 0',
    borderTop: `0.5px solid ${t.rule}`,
    alignItems: 'baseline',
  };
  const labelStyle = {
    fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase',
    color: t.sub, fontWeight: 600,
  };
  const valStyle = { fontSize: 14, color: t.ink, lineHeight: 1.5 };
  const codeStyle = {
    fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace',
    background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4,
    fontSize: 12.5, color: '#5a3a3a',
  };

  return (
    <div style={{
      width: '100%', height: '100%', boxSizing: 'border-box',
      padding: '32px 40px', background: '#fcf8f0', color: t.ink,
      fontFamily: '"Inter", system-ui, sans-serif',
      borderRadius: 18, overflow: 'auto',
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 26, fontWeight: 700, color: t.ink, marginBottom: 4,
      }}>HighlightsSheet delete affordance — binding contract</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 18 }}>
        Source of truth for bug <span style={codeStyle}>#249</span> /{' '}
        <span style={codeStyle}>#1080</span>. Resolves the regression
        introduced when <span style={codeStyle}>HighlightsSheetV3</span> shipped
        without row-level destructive actions.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Affordance · primary</div>
        <div style={valStyle}>
          Trailing <span style={codeStyle}>⋯</span> icon-button on each card's
          meta row. Tap → <span style={codeStyle}>NotesActionMenu</span> with
          Edit · Copy · Delete. Destructive (Delete) is visually separated by
          a hairline divider and uses destructive ink.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Affordance · secondary</div>
        <div style={valStyle}>
          iOS-native left-swipe revealing trailing Edit + Delete cells (amber
          + destructive ink). Same destinations as the menu. Full-swipe
          (≥ row width) trips the same confirm strip used by the tap path.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Confirmation</div>
        <div style={valStyle}>
          Inline row-replacement (<span style={codeStyle}>NotesDeleteConfirm</span>).
          Mirrors <span style={codeStyle}>HPDeleteConfirm</span> vocabulary from
          {' '}<span style={codeStyle}>vreader-highlight-popover.jsx</span> (#949):
          short title, body copy stating what's lost, paired Cancel/Delete pills.
          No system alert. The meta row stays so the user can't lose track of
          which row they're about to destroy.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Edit handoff</div>
        <div style={valStyle}>
          The sheet does NOT embed a note editor. Edit on a HighlightCard
          dismisses the sheet, jumps to the passage, and opens
          {' '}<span style={codeStyle}>HighlightActionCard</span> in
          {' '}<span style={codeStyle}>mode='editing'</span>. Edit on a
          StandaloneNote opens the standalone-note editor at the locator.
          One editor per record kind — no fork.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>States covered</div>
        <div style={valStyle}>
          default · menu-open · confirming · deleting (row dim + spinner +
          busy pill) · error (Retry + Undo, 3 s auto-dismiss) · dim-after-delete
          (transient · ~250 ms) · swipe-revealed · empty-after-delete (existing
          v3 empty state, no new copy).
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Persistence calls</div>
        <div style={valStyle}>
          HighlightCard → <span style={codeStyle}>HighlightListViewModel
          .removeHighlight(highlightId:)</span> →
          {' '}<span style={codeStyle}>PersistenceActor.removeHighlight</span>.
          StandaloneNoteCard → <span style={codeStyle}>AnnotationListViewModel
          .removeAnnotation(annotationId:)</span> →
          {' '}<span style={codeStyle}>PersistenceActor.removeAnnotation</span>.
          Failure surfaces as <span style={codeStyle}>NotesRowError</span>;
          Undo restores pre-tap state.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Mutual exclusion</div>
        <div style={valStyle}>
          At most one row in a non-default state at a time. Opening a second
          row's menu or confirm closes the first. Scroll closes the menu.
          Sheet dismiss commits any in-flight delete; cancel confirms revert.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Why not shape (a)</div>
        <div style={valStyle}>
          <span style={codeStyle}>List</span> + <span style={codeStyle}>.swipeActions</span>{' '}
          reskins the cards into iOS List rows (background, separators,
          padding all change visibly). The sheet just committed v3 cards;
          rewriting them is a visible regression. We keep the v3 layout and
          add the affordance.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Why not <code>.contextMenu</code></div>
        <div style={valStyle}>
          Codex Gate-4 audit on worktree branch
          {' '}<span style={codeStyle}>fix/issue-1080-highlightssheet-delete-affordance</span>{' '}
          (thread <span style={codeStyle}>019e47fd-9b06-79d3-b011-4f460107f005</span>)
          returned <i>needs-fix</i> with a High-severity Rule-51 finding:
          gestured-only contextual menus on app content are not the
          system-chrome restoration exemption. Visible + labelled is required.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Accessibility</div>
        <div style={valStyle}>
          The <span style={codeStyle}>⋯</span> button carries an
          {' '}<span style={codeStyle}>accessibilityLabel</span> that names the
          row ("Actions for highlight on Chapter 1, page 4"). VoiceOver rotor
          'Actions' surfaces the swipe destinations too. Confirm strip pulls
          focus to the destructive button (so the user knows what they're
          committing).
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Supersedes</div>
        <div style={valStyle}>
          The legacy <span style={codeStyle}>AnnotationListView</span>{' '}
          <span style={codeStyle}>.contextMenu</span> Edit affordance folds
          into this surface (Edit + Delete in one menu). The rejected
          worktree contextMenu fix is deleted by this design.
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { NotesDeleteCanvas });
