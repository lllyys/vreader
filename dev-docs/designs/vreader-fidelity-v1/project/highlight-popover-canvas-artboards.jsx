// Canvas artboards for issue #949 —
// Unified cross-format highlight-action popover.
//
// Reads as a buildable spec for the merged surface that replaces:
//   • Feature #55 NoteCallout (read-only, EPUB/AZW3 only — was)
//   • Feature #53 HighlightActionPopover (rich, TXT/MD/PDF only — was)
//
// Sections:
//   1. Intent             — the one card, canonical anchored form
//   2. State machine      — has-note · empty · editing · long · confirm-delete
//   3. Color row          — selected · pressed · cross-color result
//   4. Format consistency — same card over TXT, MD, PDF, EPUB, AZW3 backdrops
//   5. CJK + RTL          — first-class script support
//   6. Themes             — paper / sepia / dark / OLED
//   7. Bottom-sheet form  — VoiceOver + long-note fallback
//   8. Migration          — before / after surfaces side-by-side
//   9. Spec card          — binding contract

const HP_PHONE_W = 402;
const HP_PHONE_H = 720;

// ─────────────────────────────────────────────────────
// Sample highlights
// ─────────────────────────────────────────────────────
const HP_H_LATIN = {
  id: 'h-en', color: 'yellow',
  chapter: 'Chapter 3', page: 18, date: 'Apr 18',
  text: 'Such amiable qualities must speak for themselves.',
  note: 'Bingley is introduced by external impression — "speak for themselves" — which the rest of the chapter undermines. Compare with how Darcy is presented.',
};
const HP_H_EMPTY = {
  id: 'h-empty', color: 'pink',
  chapter: 'Chapter 11', page: 89, date: 'Yesterday',
  text: 'Vanity and pride are different things, though the words are often used synonymously.',
  note: '',
};
const HP_H_LONG = {
  id: 'h-long', color: 'green',
  chapter: 'Chapter 6', page: 47, date: 'Apr 22',
  text: 'Happiness in marriage is entirely a matter of chance.',
  note: 'Charlotte\'s thesis — and the novel\'s most chilling line, almost throwaway, but it sets up the whole Collins decision. Three things to notice on a re-read: Austen plants it BEFORE Charlotte commits, so we can\'t dismiss it as post-hoc rationalisation; the structure mirrors the opening line — another universal-truth-stated-as-fact that the book half-endorses, half-undercuts; compare with Elizabeth\'s rebuttal on the next page.',
};
const HP_H_BLUE = {
  id: 'h-blue', color: 'blue',
  chapter: 'Chapter 1', page: 3, date: 'Apr 12',
  text: 'It is a truth universally acknowledged…',
  note: 'The hook. Worth re-reading after finishing the book — Austen\'s irony has a different temperature on the second pass.',
};

const HP_H_CJK = {
  id: 'h-zh', color: 'yellow',
  chapter: '第一章', page: 1, date: '四月 12',
  text: '凡是有钱的单身汉，总想娶位太太，这已经成了一条举世公认的真理。',
  note: '小说开篇即以反讽语气抛出"举世公认的真理"——其实只是周围太太们的偏见。这种把局部成见冒充普遍真理的手法贯穿全书，是奥斯汀的核心讽刺武器。',
};
const HP_H_RTL = {
  id: 'h-rtl', color: 'pink',
  chapter: 'الفصل الثالث', page: 18, date: 'أبريل 18',
  text: 'مثل هذه الصفات اللطيفة يجب أن تتحدث عن نفسها.',
  note: 'يقدّم بنغلي هنا من خلال الانطباع الخارجي — "تتحدث عن نفسها" — وهذا ما يقوّضه باقي الفصل تدريجياً.',
};

// ─────────────────────────────────────────────────────
// Phone frame + reader-page backdrop with the highlight
// ─────────────────────────────────────────────────────
function HPPhone({ themeKey, children, format = 'epub' }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: HP_PHONE_W, height: HP_PHONE_H,
      position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.32)',
    }}>
      <HPReaderBackdrop theme={t} format={format}/>
      {children}
    </div>
  );
}

// Mini reader backdrop — varies by format to demonstrate the popover is
// truly format-agnostic.  Highlight is positioned at a known anchor rect
// the artboard caller can target.
function HPReaderBackdrop({ theme, format }) {
  const t = theme;
  const baseBodyStyle = {
    fontFamily: '"Source Serif 4", Georgia, serif',
    fontSize: 14.5, lineHeight: 1.6, color: t.ink,
    margin: 0, textAlign: 'justify',
  };
  return (
    <div style={{ position: 'absolute', inset: 0 }}>
      {/* status bar */}
      <div style={{
        height: 44, display: 'flex', alignItems: 'flex-end',
        justifyContent: 'space-between', padding: '0 18px 4px',
        fontSize: 12, color: t.ink, fontWeight: 600, opacity: 0.7,
      }}>
        <span>9:41</span><span style={{ letterSpacing: 1 }}>•••</span>
      </div>
      {format === 'pdf'
        ? <HPBackdropPDF theme={t} bodyStyle={baseBodyStyle}/>
        : format === 'md'
          ? <HPBackdropMD theme={t} bodyStyle={baseBodyStyle}/>
          : format === 'txt'
            ? <HPBackdropTXT theme={t} bodyStyle={baseBodyStyle}/>
            : format === 'azw3'
              ? <HPBackdropAZW3 theme={t} bodyStyle={baseBodyStyle}/>
              : <HPBackdropEPUB theme={t} bodyStyle={baseBodyStyle}/>}
    </div>
  );
}

function HPHeader({ theme, label }) {
  return (
    <div style={{
      fontFamily: '"Source Serif 4", Georgia, serif',
      fontSize: 10.5, color: theme.sub, letterSpacing: 2,
      textTransform: 'uppercase', textAlign: 'center', marginBottom: 16,
    }}>{label}</div>
  );
}

function HPHighlightedSpan({ children }) {
  return (
    <span style={{
      background: 'rgba(240,210,90,0.45)', borderRadius: 2, padding: '0 1px',
    }}>{children}</span>
  );
}

function HPBackdropEPUB({ theme, bodyStyle }) {
  return (
    <div style={{ padding: '12px 28px 0' }}>
      <HPHeader theme={theme} label="Chapter 3"/>
      <p style={bodyStyle}>
        Mr. Bingley had soon made himself acquainted with all the principal
        people in the room; he was lively and unreserved, danced every dance,
        was angry that the ball closed so early, and talked of giving one
        himself at Netherfield.{' '}
        <HPHighlightedSpan>Such amiable qualities must speak for themselves.</HPHighlightedSpan>
        {' '}He danced with Mrs. Hurst and Miss Bingley, was introduced to
        Miss Bennet, and afterwards danced with Elizabeth.
      </p>
      <p style={{ ...bodyStyle, marginTop: 14 }}>
        Such an effect, in spite of his small fortune, was not lost on the
        company. Mrs. Bennet would have been more pleased had Mr. Bingley
        bestowed his particular attention on her own daughter, but the night
        was still full of promise.
      </p>
    </div>
  );
}

function HPBackdropTXT({ theme, bodyStyle }) {
  return (
    <div style={{ padding: '12px 22px 0' }}>
      <HPHeader theme={theme} label="pride-and-prejudice.txt"/>
      <pre style={{
        ...bodyStyle, fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace',
        fontSize: 12.5, whiteSpace: 'pre-wrap', margin: 0,
      }}>
{`Mr. Bingley had soon made himself acquainted with
all the principal people in the room; he was lively
and unreserved, danced every dance, was angry that
the ball closed so early, and talked of giving one
himself at Netherfield. `}<HPHighlightedSpan>Such amiable</HPHighlightedSpan>
        <HPHighlightedSpan>{`
qualities must speak for themselves.`}</HPHighlightedSpan>{` He danced
with Mrs. Hurst and Miss Bingley, was introduced
to Miss Bennet, and afterwards danced with Elizabeth.`}
      </pre>
    </div>
  );
}

function HPBackdropMD({ theme, bodyStyle }) {
  return (
    <div style={{ padding: '12px 24px 0' }}>
      <div style={{
        fontFamily: '"SF Mono", monospace', fontSize: 10,
        color: theme.sub, textAlign: 'center', marginBottom: 8,
      }}>chapter-03.md</div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 19, fontWeight: 700, color: theme.ink, marginBottom: 4,
      }}># Chapter 3</div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 14.5, fontWeight: 600, color: theme.ink,
        marginTop: 10, marginBottom: 6,
      }}>## The ball at Meryton</div>
      <p style={bodyStyle}>
        Mr. Bingley had soon made himself acquainted with the principal
        people in the room. He was lively, unreserved, and danced every
        dance.{' '}
        <HPHighlightedSpan>Such amiable qualities must speak for themselves.</HPHighlightedSpan>
        {' '}He danced with Mrs. Hurst, was introduced to Miss Bennet, and
        afterwards danced with Elizabeth.
      </p>
    </div>
  );
}

function HPBackdropPDF({ theme, bodyStyle }) {
  return (
    <div style={{ padding: '12px 18px 0' }}>
      <div style={{
        background: theme.isDark ? '#26231f' : '#fff',
        boxShadow: '0 0 0 0.5px rgba(0,0,0,0.18), 0 2px 8px rgba(0,0,0,0.08)',
        borderRadius: 4, padding: '24px 26px', minHeight: 320,
      }}>
        <div style={{
          fontFamily: 'Georgia, "Times New Roman", serif',
          fontSize: 11, color: theme.sub, textAlign: 'right', marginBottom: 12,
        }}>p. 18</div>
        <p style={{ ...bodyStyle, fontFamily: 'Georgia, "Times New Roman", serif' }}>
          Mr. Bingley had soon made himself acquainted with all the
          principal people in the room; he was lively and unreserved,
          danced every dance, was angry that the ball closed so early.{' '}
          <HPHighlightedSpan>Such amiable qualities must speak for themselves.</HPHighlightedSpan>
          {' '}He danced with Mrs. Hurst, Miss Bingley, and afterwards
          Elizabeth.
        </p>
      </div>
    </div>
  );
}

function HPBackdropAZW3({ theme, bodyStyle }) {
  return (
    <div style={{ padding: '12px 28px 0' }}>
      <HPHeader theme={theme} label="Loc 1,284 of 12,400"/>
      <p style={bodyStyle}>
        Bingley had soon made himself acquainted with all the principal
        people in the room. He was lively and unreserved, danced every
        dance, and talked of giving one himself.{' '}
        <HPHighlightedSpan>Such amiable qualities must speak for themselves.</HPHighlightedSpan>
        {' '}He danced with Mrs. Hurst, was introduced to Miss Bennet, and
        afterwards Elizabeth.
      </p>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Anchor rect for the canonical "Such amiable…" highlight
// ─────────────────────────────────────────────────────
function hpAnchorEPUB() { return { left: 28, top: 196, width: 270, height: 22, containerW: HP_PHONE_W }; }
function hpAnchorTXT()  { return { left: 22, top: 178, width: 250, height: 36, containerW: HP_PHONE_W }; }
function hpAnchorMD()   { return { left: 24, top: 246, width: 268, height: 22, containerW: HP_PHONE_W }; }
function hpAnchorPDF()  { return { left: 38, top: 250, width: 280, height: 22, containerW: HP_PHONE_W }; }
function hpAnchorAZW3() { return { left: 28, top: 184, width: 290, height: 22, containerW: HP_PHONE_W }; }
function hpAnchorFor(f) {
  return f === 'pdf' ? hpAnchorPDF() : f === 'md' ? hpAnchorMD()
       : f === 'txt' ? hpAnchorTXT() : f === 'azw3' ? hpAnchorAZW3()
       : hpAnchorEPUB();
}

// ─────────────────────────────────────────────────────
// Artboard helper
// ─────────────────────────────────────────────────────
function HPArt({
  themeKey = 'paper', format = 'epub',
  highlight = HP_H_LATIN, mode = 'reading',
  pressedColor = null, draftOverride = null,
  side = 'above', anchor = null,
  showDim = true,
}) {
  const t = THEMES[themeKey];
  return (
    <HPPhone themeKey={themeKey} format={format}>
      <HighlightActionCard
        theme={t} highlight={highlight}
        anchorRect={anchor || hpAnchorFor(format)}
        side={side}
        mode={mode}
        pressedColor={pressedColor}
        draftOverride={draftOverride}
        showDim={showDim}
        onChangeColor={() => {}} onEdit={() => {}} onSaveNote={() => {}}
        onCancelEdit={() => {}} onCopy={() => {}} onShare={() => {}}
        onDelete={() => {}} onConfirmDelete={() => {}} onClose={() => {}}
      />
    </HPPhone>
  );
}

function HPSheetArt({ themeKey = 'paper', highlight = HP_H_LONG, mode = 'reading' }) {
  const t = THEMES[themeKey];
  return (
    <HPPhone themeKey={themeKey} format="epub">
      <HighlightActionSheet
        theme={t} highlight={highlight} mode={mode}
        onChangeColor={() => {}} onEdit={() => {}} onSaveNote={() => {}}
        onCancelEdit={() => {}} onCopy={() => {}} onShare={() => {}}
        onDelete={() => {}} onConfirmDelete={() => {}} onClose={() => {}}
      />
    </HPPhone>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function HighlightPopoverCanvas() {
  return (
    <DesignCanvas>

      {/* ─── 1. Intent ─── */}
      <DCSection id="intent"
        title="#949 — Unified highlight-action popover"
        subtitle="One styled card, same gesture, every format. Tap an existing highlight → this surface. Reconciles the read-only #55 NoteCallout (EPUB/AZW3) and the rich #53 HighlightActionPopover (TXT/MD/PDF). Anchored to the tapped passage with a pointer notch; bottom-sheet fallback for VoiceOver and very long notes.">
        <DCArtboard id="canonical" label="Canonical · has-note · anchored above"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt/>
        </DCArtboard>
        <DCArtboard id="canonical-no-note" label="Color-only highlight · no note attached"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={{ ...HP_H_LATIN, note: '' }}/>
        </DCArtboard>
        <DCArtboard id="below-anchor" label="Anchored below · top-of-page highlight"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={HP_H_BLUE}
            anchor={{ left: 28, top: 76, width: 200, height: 22, containerW: HP_PHONE_W }}
            side="below"/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={2} width={260}>
          The card unifies what were two surfaces. <i>All</i> formats now share the same actions: change color, view/edit the note, copy, share, delete. EPUB/AZW3 finally get one-step delete; TXT/MD/PDF get the same note region as EPUB.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. State machine ─── */}
      <DCSection id="states"
        title="State machine"
        subtitle="Reading is the entry state. Tapping the note region promotes to editing. Tapping Delete promotes to confirm-delete (inline, no separate alert — keeps the card a single visual unit). Saving or confirming returns to reading; the host then closes the card.">
        <DCArtboard id="reading" label="reading · short note"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt/>
        </DCArtboard>
        <DCArtboard id="reading-long" label="reading · long note · clamped"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={HP_H_LONG}/>
        </DCArtboard>
        <DCArtboard id="empty" label="empty · Add a note CTA"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={{ ...HP_H_LATIN, note: '' }}/>
        </DCArtboard>
        <DCArtboard id="editing" label="editing · inline textarea"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt mode="editing"/>
        </DCArtboard>
        <DCArtboard id="editing-empty" label="editing · adding to empty highlight"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={{ ...HP_H_LATIN, note: '' }}
            mode="editing" draftOverride="First thought, partway done…"/>
        </DCArtboard>
        <DCArtboard id="confirm-delete" label="confirm-delete · inline, destructive"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt mode="confirm-delete"/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={-2} width={260}>
          Inline edit handles tiny tweaks ("typo", "+ ref ch.4"). For substantial edits or VoiceOver, the small "Expand" hint promotes to the committed full editor (vreader-note-editor.jsx — issue #914), which now sits behind this surface as the long-form path.
        </DCPostIt>
      </DCSection>

      {/* ─── 3. Color row ─── */}
      <DCSection id="color"
        title="Color row · highlight palette"
        subtitle="Current color carries the accent ring and a quiet check glyph. Press feedback expands a soft halo before the cross-color is committed. The excerpt's left bar tracks the active color so the change is visible without dismissing the card.">
        <DCArtboard id="color-yellow" label="yellow · current"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt/>
        </DCArtboard>
        <DCArtboard id="color-pressing-blue" label="pressing blue · halo"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt pressedColor="blue"/>
        </DCArtboard>
        <DCArtboard id="color-after-blue" label="after · highlight is blue"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={{ ...HP_H_LATIN, color: 'blue' }}/>
        </DCArtboard>
        <DCArtboard id="color-green" label="green · existing"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={{ ...HP_H_LONG, color: 'green' }}/>
        </DCArtboard>
      </DCSection>

      {/* ─── 4. Format consistency ─── */}
      <DCSection id="formats"
        title="Format consistency · one card, every format"
        subtitle="The point of #949. Same card, same actions, same gesture, whether the user is in TXT, MD, PDF, EPUB, or AZW3. The backdrops vary; the surface does not.">
        <DCArtboard id="fmt-txt" label="TXT · plaintext file"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt format="txt"/>
        </DCArtboard>
        <DCArtboard id="fmt-md" label="MD · Markdown reader"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt format="md"/>
        </DCArtboard>
        <DCArtboard id="fmt-pdf" label="PDF · page-faithful reflow"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt format="pdf"/>
        </DCArtboard>
        <DCArtboard id="fmt-epub" label="EPUB · canonical"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt format="epub"/>
        </DCArtboard>
        <DCArtboard id="fmt-azw3" label="AZW3 / MOBI · Kindle source"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt format="azw3"/>
        </DCArtboard>
      </DCSection>

      {/* ─── 5. CJK & RTL ─── */}
      <DCSection id="i18n"
        title="CJK & RTL · first-class"
        subtitle="Excerpt + note bodies cascade to Source Han Serif / Songti SC / Noto Serif SC for zh, and to Noto Serif JP / Yu Mincho for ja. dir=&quot;auto&quot; on the textarea flips Arabic / Hebrew. CJK gets a looser line-height (1.7 vs 1.5) because dense glyphs need the air.">
        <DCArtboard id="cjk-reading" label="zh · reading"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={HP_H_CJK}
            anchor={{ left: 28, top: 200, width: 320, height: 50, containerW: HP_PHONE_W }}/>
        </DCArtboard>
        <DCArtboard id="cjk-editing" label="zh · editing"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={HP_H_CJK} mode="editing"
            anchor={{ left: 28, top: 200, width: 320, height: 50, containerW: HP_PHONE_W }}/>
        </DCArtboard>
        <DCArtboard id="rtl-reading" label="ar · RTL · reading"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt highlight={HP_H_RTL}
            anchor={{ left: 28, top: 200, width: 320, height: 50, containerW: HP_PHONE_W }}/>
        </DCArtboard>
      </DCSection>

      {/* ─── 6. Themes ─── */}
      <DCSection id="themes"
        title="ReaderThemeV2 tokens"
        subtitle="Card uses sheet-paper background — `t.isDark ? #2a2724 : #fcf8f0` — and inherits ink / sub / accent / rule. Delete is the only place destructive ink appears; everywhere else the accent is the brand red (paper / sepia) or warm orange (dark).">
        <DCArtboard id="theme-paper" label="paper · canonical"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="theme-sepia" label="sepia · warm paper"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt themeKey="sepia"/>
        </DCArtboard>
        <DCArtboard id="theme-dark" label="dark · cushioned"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt themeKey="dark"/>
        </DCArtboard>
        <DCArtboard id="theme-oled" label="OLED · true-black bg, same card"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt themeKey="oled"/>
        </DCArtboard>
        <DCArtboard id="theme-dark-confirm" label="dark · confirm-delete"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt themeKey="dark" mode="confirm-delete"/>
        </DCArtboard>
      </DCSection>

      {/* ─── 7. Bottom-sheet fallback ─── */}
      <DCSection id="sheet"
        title="Bottom-sheet fallback"
        subtitle="Same content, no pointer notch. Routed to when (a) VoiceOver is on, or (b) the anchored card would overflow the viewport. Pure platform decision — no user-visible toggle.">
        <DCArtboard id="sheet-reading" label="sheet · long note"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPSheetArt highlight={HP_H_LONG}/>
        </DCArtboard>
        <DCArtboard id="sheet-editing" label="sheet · editing"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPSheetArt highlight={HP_H_LATIN} mode="editing"/>
        </DCArtboard>
        <DCArtboard id="sheet-confirm" label="sheet · confirm-delete"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPSheetArt highlight={HP_H_LATIN} mode="confirm-delete"/>
        </DCArtboard>
        <DCArtboard id="sheet-dark" label="sheet · dark"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPSheetArt themeKey="dark" highlight={HP_H_LONG}/>
        </DCArtboard>
      </DCSection>

      {/* ─── 8. Migration: before / after ─── */}
      <DCSection id="migration"
        title="Migration · what this replaces"
        subtitle="The two surfaces that fragmented the highlight-tap gesture before #949. Both are deleted by this design; their useful primitives (NoteCallout's anchored geometry, HighlightActionPopover's color/action rows) survive inside HighlightActionCard.">
        <DCArtboard id="before-55" label="BEFORE · #55 NoteCallout (EPUB/AZW3, read-only)"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPBefore55Phone/>
        </DCArtboard>
        <DCArtboard id="before-53" label="BEFORE · #53 HighlightActionPopover (TXT/MD/PDF)"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPBefore53Phone/>
        </DCArtboard>
        <DCArtboard id="after" label="AFTER · #949 unified card"
          width={HP_PHONE_W} height={HP_PHONE_H}>
          <HPArt/>
        </DCArtboard>
        <DCPostIt top={-32} right={36} rotate={2} width={260}>
          NoteCallout's "Open in panel" action does <i>not</i> survive the merge — it overlapped with both Share (export) and Edit (full editor). The unified card collapses to three actions: Copy / Share / Delete, plus the color row and the tap-to-edit note.
        </DCPostIt>
      </DCSection>

      {/* ─── 9. Spec card ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what #64 (and the format adapters) need to build off this surface.">
        <DCArtboard id="spec-card" label="" width={HP_PHONE_W * 2 + 30} height={620}>
          <HPSpecCard/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

// ─────────────────────────────────────────────────────
// "Before" mocks — small enough not to deserve their own files
// ─────────────────────────────────────────────────────
function HPBefore55Phone() {
  const t = THEMES.paper;
  return (
    <div style={{
      width: HP_PHONE_W, height: HP_PHONE_H, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
    }}>
      <HPReaderBackdrop theme={t} format="epub"/>
      {/* dim */}
      <div style={{
        position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.18)',
      }}/>
      {/* a faithful tiny re-creation of NoteCallout */}
      <div style={{
        position: 'absolute', left: 40, top: 224, width: 304,
        borderRadius: 14, background: '#fcf8f0',
        boxShadow: '0 14px 40px rgba(0,0,0,0.28)',
      }}>
        <div style={{ padding: '11px 14px 8px',
          display: 'flex', alignItems: 'center', gap: 8 }}>
          <div style={{ width: 8, height: 8, borderRadius: 2, background: '#f0d25a' }}/>
          <span style={{ fontSize: 10.5, color: t.sub, fontWeight: 600, letterSpacing: 0.8, textTransform: 'uppercase' }}>Note</span>
          <span style={{ fontSize: 11, color: t.sub, opacity: 0.7 }}>· Apr 18</span>
        </div>
        <div style={{
          padding: '0 14px 10px', borderLeft: '2px solid #f0d25a',
          marginLeft: 14, paddingLeft: 10,
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 11.5, fontStyle: 'italic', color: t.sub,
        }}>"Such amiable qualities must speak for themselves."</div>
        <div style={{
          padding: '4px 14px 12px',
          fontFamily: '"Source Serif 4", Georgia, serif',
          fontSize: 15, lineHeight: 1.55, color: t.ink,
        }}>Bingley's charm is presented through external impression — the rest of the chapter undermines it.</div>
        <div style={{
          display: 'flex', gap: 4, padding: '4px 6px 6px',
          borderTop: `0.5px solid ${t.rule}`,
        }}>
          {['Edit', 'Share', 'Open in panel'].map((l, i) => (
            <div key={i} style={{
              flex: 1, padding: '6px 4px', textAlign: 'center',
              fontSize: 10, color: t.sub, fontWeight: 500,
            }}>{l}</div>
          ))}
        </div>
      </div>
      <HPRedX top={130} right={28} label="No color row"/>
      <HPRedX top={158} right={28} label="No Delete"/>
    </div>
  );
}

function HPBefore53Phone() {
  const t = THEMES.paper;
  return (
    <div style={{
      width: HP_PHONE_W, height: HP_PHONE_H, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
    }}>
      <HPReaderBackdrop theme={t} format="txt"/>
      <div style={{
        position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.18)',
      }}/>
      {/* a tiny re-creation of the bare UIMenu */}
      <div style={{
        position: 'absolute', left: '50%', top: 240,
        transform: 'translateX(-50%)',
        background: 'rgba(56,52,46,0.92)',
        color: '#f4eee0', borderRadius: 10,
        padding: '8px 16px', fontSize: 13, fontWeight: 500,
        boxShadow: '0 10px 28px rgba(0,0,0,0.36)',
        display: 'flex', alignItems: 'center', gap: 14,
      }}>
        <span>Copy</span>
        <span style={{ opacity: 0.3 }}>|</span>
        <span style={{ color: '#ff7a7a', fontWeight: 600 }}>Delete Highlight</span>
      </div>
      <HPRedX top={154} right={28} label="No note view / edit"/>
      <HPRedX top={182} right={28} label="No color row"/>
      <HPRedX top={210} right={28} label="No Share"/>
    </div>
  );
}

function HPRedX({ top, right, label }) {
  return (
    <div style={{
      position: 'absolute', top, right,
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
function HPSpecCard() {
  const t = THEMES.paper;
  const rowStyle = {
    display: 'grid', gridTemplateColumns: '160px 1fr',
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
      }}>HighlightActionCard — binding contract</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 18 }}>
        Source of truth for feature{' '}
        <span style={codeStyle}>#64</span>'s adapter layer. Same component
        instance is mounted from all five format adapters.
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Trigger</div>
        <div style={valStyle}>
          Single tap on an existing highlight. Long-press route stays on the
          selection popover (creating <i>new</i> highlights — out of scope).
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Anchoring</div>
        <div style={valStyle}>
          Anchored to the tapped passage with pointer notch. Card prefers
          above; flips below if it would overflow the top. If neither fits
          (very tall card on a small viewport, e.g. iPhone SE), host
          mounts <span style={codeStyle}>HighlightActionSheet</span> instead.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Actions</div>
        <div style={valStyle}>
          <span style={codeStyle}>onChangeColor(color)</span> · in-place,
          excerpt bar updates. <span style={codeStyle}>onEdit()</span> →
          enters editing mode. <span style={codeStyle}>onSaveNote(draft)</span> →
          {' '}<span style={codeStyle}>HighlightPersisting.updateHighlightNote</span>.
          {' '}<span style={codeStyle}>onCopy()</span> · copies excerpt + note (if any) to pasteboard.
          {' '}<span style={codeStyle}>onShare()</span> · system share sheet w/ excerpt + note + book ref.
          {' '}<span style={codeStyle}>onDelete()</span> → confirm-delete state.
          {' '}<span style={codeStyle}>onConfirmDelete()</span> → removes highlight, dismiss.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Edit-mode</div>
        <div style={valStyle}>
          Inline textarea handles short edits. For long-form authoring or
          VoiceOver the host promotes to{' '}
          <span style={codeStyle}>HighlightNoteEditSheet</span> (vreader-note-editor.jsx, #914).
          A small "Expand" hint inside the inline editor signals the path.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>States covered</div>
        <div style={valStyle}>
          reading (short / long / clamped) · empty / no-note · editing · editing-empty ·
          confirm-delete · color-press · sheet variant · zh CJK · ar RTL · paper / sepia / dark / OLED.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Format adapters</div>
        <div style={valStyle}>
          TXT, MD, PDF, EPUB, AZW3 each compute the anchor rect in viewport
          coordinates and hand it to the card. The card itself reads no
          format-specific state — it's pure UI on top of the
          {' '}<span style={codeStyle}>Highlight</span> model.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Supersedes</div>
        <div style={valStyle}>
          {' '}<span style={codeStyle}>NoteCallout</span> +
          {' '}<span style={codeStyle}>NotePreviewSheet</span> (#55) and
          {' '}<span style={codeStyle}>HighlightActionPopover</span> (#53).
          {' '}<span style={codeStyle}>#914</span> Edit-slice work folds in.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Out of scope</div>
        <div style={valStyle}>
          Creating new highlights (selection popover); multi-note per highlight;
          rich text inside the note; per-highlight tagging; cross-book share.
        </div>
      </div>

      <div style={rowStyle}>
        <div style={labelStyle}>Accessibility</div>
        <div style={valStyle}>
          accessibilityViewIsModal=true on either form. Focus enters on the
          note region (reading) or the textarea (editing). VoiceOver users
          land in the sheet form regardless of available anchor space; Dynamic
          Type scales the excerpt + note bodies up to xxxLarge.
        </div>
      </div>
    </div>
  );
}

Object.assign(window, { HighlightPopoverCanvas });
