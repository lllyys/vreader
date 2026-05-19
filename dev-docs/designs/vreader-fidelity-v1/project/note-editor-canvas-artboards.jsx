// Canvas artboards for issue #914 — highlight-note edit surface.
//
// Surface lives at the END of the read-the-note loop: NoteCallout > Edit > here.
// Reads as a buildable spec for the Edit slice of feature #55.

const PHONE_W_NE = 402;
const PHONE_H_NE = 720;

// ─────────────────────────────────────────────────────
// Sample highlights — Latin, CJK, RTL
// ─────────────────────────────────────────────────────
const H_LATIN = {
  id: 'h-en', color: 'yellow',
  chapter: 'Chapter 3', page: 18, date: 'Apr 18',
  text: 'Such amiable qualities must speak for themselves.',
  note: 'Bingley\'s charm is presented through external impression — "speak for themselves" — which the rest of the chapter then undermines. Compare with how Darcy is introduced.',
};
const H_EMPTY = {
  id: 'h-empty', color: 'pink',
  chapter: 'Chapter 11', page: 89, date: 'Yesterday',
  text: 'Vanity and pride are different things, though the words are often used synonymously.',
  note: '',
};
const H_LONG = {
  id: 'h-long', color: 'green',
  chapter: 'Chapter 6', page: 47, date: 'Apr 22',
  text: 'Happiness in marriage is entirely a matter of chance.',
  note: 'Charlotte\'s thesis — and the novel\'s most chilling line, almost throwaway, but it sets up the whole Collins decision. Three things to notice on a re-read:\n\n1. Austen plants it BEFORE Charlotte commits, so the reader can\'t dismiss it as post-hoc rationalisation.\n2. The structure mirrors the opening line — another universal-truth-stated-as-fact that the book half-endorses, half-undercuts.\n3. Compare with Elizabeth\'s rebuttal on the next page; the novel never resolves the disagreement, just lets both views stand.\n\nWorth tracking how each marriage in the book functions as evidence for one position or the other.',
};

// CJK — Chinese (zh-Hans) on the Pride & Prejudice opening, plus translator's
// note in Chinese. This is the canonical "user reads PP in zh, wants to note
// in zh" use case.
const H_CJK_ZH = {
  id: 'h-zh', color: 'yellow',
  chapter: '第一章', page: 1, date: '四月 12',
  text: '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
  note: '小说开篇即以反讽语气抛出"举世公认的真理"——其实只是周围太太们的偏见。这种把局部成见冒充普遍真理的手法贯穿全书，是奥斯汀的核心讽刺武器。需要对照后文 Mrs. Bennet 对待 Bingley 的态度，可见此句的语气并非全然否定，而是双面：既是叙事者的反讽，也是 Mrs. Bennet 本人会真心点头的话。',
};

// CJK — Japanese on a different excerpt (Genji / Soseki style). Includes IME
// compose state for the "in the middle of typing" artboard.
const H_CJK_JA = {
  id: 'h-ja', color: 'blue',
  chapter: '第三章', page: 22, date: '4月 18',
  text: '愛すべき性質は、自ら語って然るべきである。',
  note: 'ビングリーの魅力は外面的印象によって描かれる。「自ら語って然るべき」という表現には、',
};

// RTL — Arabic note on the same passage.
const H_RTL = {
  id: 'h-rtl', color: 'pink',
  chapter: 'الفصل الثالث', page: 18, date: 'أبريل 18',
  text: 'مثل هذه الصفات اللطيفة يجب أن تتحدث عن نفسها.',
  note: 'يقدّم بنغلي هنا من خلال الانطباع الخارجي — "تتحدث عن نفسها" — وهذا ما يقوّضه باقي الفصل تدريجياً. قارن مع طريقة تقديم دارسي في الفصل التالي؛ الانطباع الأول يخدع.',
};

// ─────────────────────────────────────────────────────
// Phone frame + dimmed reader page behind the sheet
// ─────────────────────────────────────────────────────
function NEPhone({ themeKey, children, height = PHONE_H_NE, withDim = true }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W_NE, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <DimmedReaderBg theme={t} highlight={H_LATIN}/>
      {children}
    </div>
  );
}

// A small mocked reader page in the background so the sheet has a context
// behind it.  Lightly dimmed.
function DimmedReaderBg({ theme, highlight }) {
  const t = theme;
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* status bar mock */}
      <div style={{
        height: 44, display: 'flex', alignItems: 'flex-end',
        justifyContent: 'space-between', padding: '0 18px 4px',
        fontSize: 12, color: t.ink, fontWeight: 600, opacity: 0.7,
      }}>
        <span>9:41</span>
        <span style={{ letterSpacing: 1 }}>•••</span>
      </div>
      <div style={{ padding: '12px 26px 0', opacity: 0.45 }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 10.5,
          color: t.sub, letterSpacing: 2, textTransform: 'uppercase',
          textAlign: 'center', marginBottom: 14,
        }}>{highlight?.chapter || 'Chapter 3'}</div>
        <p style={{
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 14, lineHeight: 1.55, color: t.ink,
          margin: 0, textAlign: 'justify',
        }}>
          Mr. Bingley had soon made himself acquainted with all the principal people
          in the room; he was lively and unreserved, danced every dance, was angry
          that the ball closed so early, and talked of giving one himself at
          Netherfield.{' '}
          <span style={{
            background: 'rgba(240,210,90,0.45)', borderRadius: 2,
            padding: '0 1px',
          }}>{highlight?.text || 'Such amiable qualities must speak for themselves.'}</span>
          {' '}He danced with Mrs. Hurst and Miss Bingley, was introduced to Miss
          Bennet, and afterwards danced with Elizabeth.
        </p>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Artboard builders
// ─────────────────────────────────────────────────────
function EditorArt({
  themeKey = 'paper', highlight = H_LATIN,
  initial, mode = 'edit', state = 'idle', error = null,
  showKeyboard = true, keyboardHeight = 291,
  inputSource = 'English', imeComposing = null,
  overlay = null,  // 'discard' | 'saved'
}) {
  const t = THEMES[themeKey];
  const addingNew = !(highlight?.note);
  return (
    <NEPhone themeKey={themeKey}>
      <HighlightNoteEditSheet
        theme={t} highlight={highlight} mode={mode}
        state={state} error={error}
        initial={initial}
        showKeyboard={showKeyboard} keyboardHeight={keyboardHeight}
        inputSource={inputSource} imeComposing={imeComposing}
        onSave={() => {}} onCancel={() => {}}
      />
      {overlay === 'discard' && (
        <DiscardNoteAlert theme={t} addingNew={addingNew}
          onKeep={() => {}} onDiscard={() => {}}/>
      )}
      {overlay === 'saved' && (
        <NoteSavedToast theme={t} message="Note saved"/>
      )}
    </NEPhone>
  );
}

function FullScreenArt({ themeKey = 'paper', highlight = H_LATIN, initial, state = 'idle' }) {
  const t = THEMES[themeKey];
  return (
    <NEPhone themeKey={themeKey}>
      <FullScreenNoteEditor
        theme={t} highlight={highlight} initial={initial} state={state}
        onSave={() => {}} onCancel={() => {}}
      />
    </NEPhone>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function NoteEditorCanvas() {
  return (
    <DesignCanvas>

      {/* ─── Header / intent ─── */}
      <DCSection id="intent"
        title="#914 — Highlight-note edit surface"
        subtitle="The committed editor opened from the Edit action on the feature #55 NoteCallout / NotePreviewSheet. Keyboard-anchored half-sheet is canonical; full-screen variant for VoiceOver + long-form. CJK is first-class.">
        <DCArtboard id="canonical" label="Canonical · editing existing note"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="empty-add" label="Empty highlight · add a note"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_EMPTY} initial=""/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={250}>
          Sheet sits <i>above</i> the keyboard, not behind. Header is the only place Save lives — keyboard accessory bar would compete with iOS's own input controls and feels self-designed. Excerpt stays visible so a user editing on the bottom sheet (no page behind) still knows which highlight this is.
        </DCPostIt>
      </DCSection>

      {/* ─── Save flow + edge states ─── */}
      <DCSection id="flow" title="Save flow & edge states"
        subtitle="Save copy flips to “Clear” (destructive ink) when the user empties an existing note. Discard alert only fires with unsaved changes. Save errors surface inline above the textarea with a Retry.">
        <DCArtboard id="dirty" label="Dirty draft · Save enabled"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper"
            initial={H_LATIN.note + ' Re-read this w/ Ch.4 — does the rest of the room agree?'}/>
        </DCArtboard>
        <DCArtboard id="will-clear" label="Emptied · Save reads “Clear”"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" initial=""/>
        </DCArtboard>
        <DCArtboard id="saving" label="Saving…"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper"
            initial={H_LATIN.note + ' (edited)'} state="saving"/>
        </DCArtboard>
        <DCArtboard id="saved" label="Just-saved toast (then auto-dismiss)"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" overlay="saved"/>
        </DCArtboard>
        <DCArtboard id="error" label="Save error · inline banner"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper"
            initial={H_LATIN.note + ' (edited)'}
            state="error"
            error="Storage write failed (disk full). The note is still in memory — Retry or copy your text before dismissing."/>
        </DCArtboard>
        <DCArtboard id="discard" label="Discard alert · unsaved changes on Cancel"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper"
            initial={H_LATIN.note + ' Re-read with Ch.4 in mind…'}
            overlay="discard"/>
        </DCArtboard>
        <DCArtboard id="discard-new" label="Discard alert · empty highlight path"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_EMPTY}
            initial="A first thought on this, partway done…"
            overlay="discard"/>
        </DCArtboard>
      </DCSection>

      {/* ─── CJK & RTL ─── */}
      <DCSection id="i18n" title="CJK & RTL · first-class"
        subtitle="Body font cascades to Source Han Serif / Songti SC / Noto Serif SC for zh, Noto Serif JP / Yu Mincho for ja. CJK content gets line-height 1.85 (vs 1.55 Latin). dir=&quot;auto&quot; flips Arabic + Hebrew. IME compose state has a visible indicator so users mid-pinyin always know they're composing.">
        <DCArtboard id="cjk-zh" label="Chinese · filled note"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_CJK_ZH} inputSource="拼音"/>
        </DCArtboard>
        <DCArtboard id="cjk-zh-composing" label="Chinese · mid-IME compose"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_CJK_ZH}
            initial={H_CJK_ZH.note + '另外，'}
            inputSource="拼音"
            imeComposing="zhushi"/>
        </DCArtboard>
        <DCArtboard id="cjk-ja" label="Japanese · in progress"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_CJK_JA}
            inputSource="日本語"/>
        </DCArtboard>
        <DCArtboard id="rtl" label="Arabic · RTL flip"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="paper" highlight={H_RTL} inputSource="عربي"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={-2} width={260}>
          CJK note text rendered at 1.85 line-height (Latin uses 1.55) — dense glyphs read poorly when crammed. Punctuation marks like 「」、。 also need the air. Tested with Source Han Serif and Songti SC; both ship on all VReader target devices.
        </DCPostIt>
      </DCSection>

      {/* ─── Themes ─── */}
      <DCSection id="themes" title="ReaderThemeV2 tokens"
        subtitle="Editor surface uses sheet-paper background (t.isDark ? #26231f : #fcf8f0), inherits ink + accent. Sepia uses the warm-paper bg.">
        <DCArtboard id="dark" label="Dark · editing existing"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="dark"/>
        </DCArtboard>
        <DCArtboard id="dark-empty" label="Dark · empty / add a note"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="dark" highlight={H_EMPTY} initial=""/>
        </DCArtboard>
        <DCArtboard id="sepia" label="Sepia · editing existing"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="sepia"/>
        </DCArtboard>
        <DCArtboard id="dark-cjk" label="Dark · Chinese note"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="dark" highlight={H_CJK_ZH} inputSource="拼音"/>
        </DCArtboard>
        <DCArtboard id="dark-error" label="Dark · save error"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <EditorArt themeKey="dark"
            initial={H_LATIN.note + ' (edited)'}
            state="error"
            error="Network unreachable. The note is held locally and will sync when you're back online."/>
        </DCArtboard>
      </DCSection>

      {/* ─── Alternative form: full-screen ─── */}
      <DCSection id="fullscreen"
        title="Alternative form · full-screen editor"
        subtitle="Same content, occupies the whole screen. Used for VoiceOver (the half-sheet's keyboard-anchored geometry is awkward for the VO cursor) and for long-form authoring (notes >300 characters / scroll-heavy). Selected via accessibility settings, not user-facing UI.">
        <DCArtboard id="fs-long" label="Long note · scrolls naturally"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <FullScreenArt themeKey="paper" highlight={H_LONG}/>
        </DCArtboard>
        <DCArtboard id="fs-cjk" label="Full-screen · Chinese"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <FullScreenArt themeKey="paper" highlight={H_CJK_ZH}/>
        </DCArtboard>
        <DCArtboard id="fs-dark" label="Full-screen · dark"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <FullScreenArt themeKey="dark" highlight={H_LATIN}/>
        </DCArtboard>
        <DCArtboard id="fs-empty" label="Full-screen · empty / add"
          width={PHONE_W_NE} height={PHONE_H_NE}>
          <FullScreenArt themeKey="paper" highlight={H_EMPTY} initial=""/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={250}>
          Don't expose the full-screen variant as an "expand" affordance — that would imply the sheet is cramped. Route to it on VoiceOver and on notes longer than the sheet can fit at its widest content. Pure platform decision.
        </DCPostIt>
      </DCSection>

      {/* ─── Spec notes ─── */}
      <DCSection id="spec" title="Implementation notes"
        subtitle="What feature #55's Edit slice needs to build off this surface. Source of truth: dev-docs/plans/20260519-feature-55-tap-annotated-text-note-preview.md §2.8 / §8.">
        <DCArtboard id="spec-card" label="" width={PHONE_W_NE * 2 + 30} height={520}>
          <SpecCard/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — surfaces the binding contract.
// ─────────────────────────────────────────────────────
function SpecCard() {
  const t = THEMES.paper;
  const rowStyle = {
    display: 'grid', gridTemplateColumns: '160px 1fr',
    gap: 16, padding: '12px 0',
    borderTop: `0.5px solid ${t.rule}`,
    alignItems: 'baseline',
  };
  const labelStyle = {
    fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase',
    color: t.sub, fontWeight: 600,
  };
  const valStyle = {
    fontSize: 14, color: t.ink, lineHeight: 1.5, fontFamily: 'inherit',
  };
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
      borderRadius: 18,
      overflow: 'auto',
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 26, fontWeight: 700, color: t.ink, marginBottom: 4,
      }}>HighlightNoteEditSheet — binding contract</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 20 }}>
        Replaces the inline <span style={codeStyle}>editing</span> stub in vreader-note-preview.jsx as the committed Edit-action target.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Entry</div>
        <div style={valStyle}>
          Tap <span style={codeStyle}>Edit</span> on <span style={codeStyle}>NoteCallout</span> (always) or
          {' '}<span style={codeStyle}>NotePreviewSheet</span> (long-note fallback). Animation:
          callout fades to dim, sheet slides up from bottom, keyboard rises after sheet settles.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Persist</div>
        <div style={valStyle}>
          Save calls{' '}
          <span style={codeStyle}>HighlightPersisting.updateHighlightNote(highlightId:, note:)</span>{' '}
          with the trimmed draft. Empty / whitespace-only drafts send <span style={codeStyle}>nil</span>
          {' '}(clears the note; the highlight itself is preserved).
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Cancel</div>
        <div style={valStyle}>
          Clean draft → dismiss. Dirty draft → confirm via DiscardNoteAlert. Dismiss-on-dim-tap is
          gated on dirty=false; can't lose work by tapping outside.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Tokens</div>
        <div style={valStyle}>
          Sheet bg: <span style={codeStyle}>t.isDark ? #26231f : #fcf8f0</span> · ink, sub, accent, rule from{' '}
          <span style={codeStyle}>ReaderThemeV2</span>. Body font cascades to CJK / RTL stack per detected script.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>States covered</div>
        <div style={valStyle}>
          editing-existing · adding-to-color-only · clearing-to-empty · saving · save-error · discard-confirm ·
          long-content · zh CJK · ja CJK + IME-compose · ar RTL · dark · sepia.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Out of scope</div>
        <div style={valStyle}>
          Rich text · multi-note per highlight · note color picking (lives on long-press popover) ·
          attaching images / audio · sharing the note in isolation (use Share from the read-mode callout).
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Accessibility</div>
        <div style={valStyle}>
          VoiceOver routes to the full-screen variant. Sheet has{' '}
          <span style={codeStyle}>accessibilityViewIsModal=true</span>. Focus enters on the textarea;
          Save / Cancel reachable by VO swipe. Dynamic Type scales body up to xxxLarge before the
          textarea introduces its own scroll.
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { NoteEditorCanvas });
