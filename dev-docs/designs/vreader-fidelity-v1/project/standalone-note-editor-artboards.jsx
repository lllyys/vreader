// Canvas artboards · issue #1296 — standalone-note editor PRESENTATION
// for the Edit handoff (feature #1121 WI-3).
//
// What's already built (not in scope here):
//   • AnnotationEditSheet { initialContent, onSave } — the editor surface.
//   • updateAnnotation(annotationId:content:) — the persistence call.
//   • StandaloneNoteCardV4 + NotesActionMenu (⋯ → Edit · Copy · Delete) — #1103.
//   • The HIGHLIGHT Edit path (WI-1/WI-2, shipped v3.41.7/.8): tap Edit →
//     dismiss the sheet → navigate to the highlight → the existing popover
//     modifier auto-opens the editor over the page. "After the jump."
//
// The open question (#1121 / #1296): a STANDALONE note has no anchored
// highlight and no reader-level editor mount point. When the user taps
// ⋯ → Edit on a standalone-note card, where does AnnotationEditSheet present?
//     A) OVER the HighlightsSheet, non-dismissing (sheet-over-sheet), or
//     B) AFTER dismissing the sheet + navigating to the locator (reader-level).
// The design's stated intent was (B) "after the jump"; the issue flags that
// (A) "may be cleaner." Rule 51: this is the design call to make.
//
// ─────────────────────────────────────────────────────────────
// DECISION: A — present AnnotationEditSheet as a sheet stacked OVER the
// HighlightsSheet, non-dismissing. After Save, the editor dismisses back to
// the list, in place. Rationale, in §5:
//   1. The entry context is TRIAGE, not reading. Edit is a "fix the wording"
//      micro-task; tearing down the sheet to fly to the reader is
//      disproportionate. A returns the user exactly where they were.
//   2. A standalone note has NO passage to re-anchor to. The reason the
//      highlight path navigates is that a highlight's note is ABOUT a visible
//      passage — the popover anchors there. Navigating for a standalone note
//      reveals ordinary body text the note doesn't quote; the jump does no
//      work for the edit.
//   3. Clean gesture grammar: tap the card body = "go read there" (jump);
//      ⋯ → Edit = "change the text" (in place). B collapses both into
//      navigate-then-edit and makes Edit redundant with tap-to-jump.
//   4. Lighter to build: reuses the dim + keyboard-anchored sheet primitive
//      the editor already is. B needs a new reader-level observer + mount.
//   5. The consistency that matters — the editor SURFACE — is identical in
//      both paths. Only the container differs, because the data differs.

// ─────────────────────────────────────────────────────
// Geometry + sample data
// ─────────────────────────────────────────────────────
const SE_PHONE_W = 402;
const SE_PHONE_H = 720;
const SE_KB = 291;

const SE_SERIF = '"Source Serif 4", Georgia, serif';
const SE_FONT = '"Inter", system-ui, -apple-system, sans-serif';

const SE_NOTE = {
  id: 's1', chapter: 'Chapter 6', page: 47, date: 'Apr 18',
  body: "Charlotte's pragmatism here is the inverse of Elizabeth's — \"happiness in marriage is entirely a matter of chance.\" Worth re-reading next to Lizzy's reaction.",
};
const SE_NOTE_EDITED = {
  ...SE_NOTE,
  body: SE_NOTE.body + ' Cross-ref the Collins proposal in Ch. 19 — same logic, played for comedy.',
};
const SE_NOTE_LONG = {
  id: 's-long', chapter: 'Chapter 6', page: 47, date: 'Apr 18',
  body: "Charlotte's thesis — and the novel's most chilling line, almost throwaway. Three things to track on a re-read:\n\n1. Austen plants it BEFORE Charlotte commits, so it can't be read as post-hoc rationalisation.\n2. It mirrors the opening line — a universal-truth-stated-as-fact the book half-endorses, half-undercuts.\n3. Compare with Elizabeth's rebuttal on the next page; the novel never resolves it, just lets both views stand.",
};
const SE_NOTE_CJK = {
  id: 's-zh', chapter: '第六章', page: 47, date: '四月 18',
  body: '夏洛特的实用主义恰是伊丽莎白的反面——"婚姻幸福全凭运气"。这句几乎是随口道出，却是全书最冷峻的一句。值得与丽兹在下一页的反驳对照重读。',
};

const SE_STANDALONES = [
  SE_NOTE,
  { id: 's2', kind: 'standalone', chapter: 'Chapter 11', page: 89, date: 'Yesterday',
    body: "Note: the ball scene is the structural midpoint of the first volume. Track Darcy's reluctance vs. his actions." },
];
const SE_HIGHLIGHTS = [
  { id: 'h1', kind: 'highlight',
    text: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.',
    color: 'yellow', chapter: 'Chapter 1', page: 1, date: 'Apr 12' },
  { id: 'h3', kind: 'highlight', text: 'She is tolerable, but not handsome enough to tempt me.',
    color: 'blue', chapter: 'Chapter 3', page: 18, date: 'Apr 15',
    note: 'The line that sets up the whole arc.' },
];

function seDanger(t) { return t.isDark ? '#e89090' : '#a83a3a'; }

// ─────────────────────────────────────────────────────
// Phone frame
// ─────────────────────────────────────────────────────
function SEPhone({ themeKey = 'paper', children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: SE_PHONE_W, height: SE_PHONE_H, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      {children}
    </div>
  );
}

// Reader page at the note's locator (Chapter 6). Standalone notes anchor to a
// LOCATOR, not a passage — so there's no highlight to land on. A thin accent
// tick in the margin marks where the note lives.
function SEReaderCh6({ themeKey = 'paper', showLocator = true, dim = 0 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{ position: 'absolute', inset: 0, background: t.bg }}>
      <div style={{
        height: 44, display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 18px 4px', fontSize: 12, color: t.ink, fontWeight: 600, opacity: 0.75,
      }}>
        <span>9:41</span><span style={{ letterSpacing: 1 }}>•••</span>
      </div>
      <div style={{
        fontFamily: SE_SERIF, fontSize: 10.5, color: t.sub, letterSpacing: 2,
        textTransform: 'uppercase', textAlign: 'center', margin: '8px 0 16px',
      }}>Chapter 6 · p. 47</div>
      <div style={{ position: 'relative', padding: '0 28px' }}>
        {showLocator && (
          <div style={{ position: 'absolute', left: 10, top: 4, display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 3 }}>
            <div style={{ width: 9, height: 9, borderRadius: 3, background: `${t.accent}22`, color: t.accent, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <svg width="5" height="6" viewBox="0 0 7 8"><path d="M0.5 0.5h5l1 1v6h-6z" fill="currentColor" opacity="0.9"/></svg>
            </div>
            <div style={{ width: 2, height: 64, borderRadius: 1, background: `${t.accent}55` }} />
          </div>
        )}
        <p style={{
          fontFamily: SE_SERIF, fontSize: 15, lineHeight: 1.62, color: t.ink, margin: 0, textAlign: 'justify',
        }}>
          Sir William Lucas had been formerly in trade in Meryton, where he had made a tolerable
          fortune and risen to the honour of knighthood. "Happiness in marriage is entirely a
          matter of chance," said Charlotte. The distinction had perhaps been felt too strongly,
          and the family removed to a house about a mile from the town, denominated from that
          period Lucas Lodge.
        </p>
      </div>
      {dim > 0 && <div style={{ position: 'absolute', inset: 0, background: `rgba(0,0,0,${dim})` }} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// The HighlightsSheet review surface (reuses the committed V4 sheet/cards)
// ─────────────────────────────────────────────────────
function SEList({ themeKey = 'paper', filter = 'notes', forcedRowId = null, forcedState = null, standalones = SE_STANDALONES }) {
  const t = THEMES[themeKey];
  return (
    <SEPhone themeKey={themeKey}>
      <SEReaderCh6 themeKey={themeKey} showLocator={false} />
      <HighlightsSheetV4 theme={t}
        highlights={SE_HIGHLIGHTS} standalones={standalones}
        filter={filter} forcedRowId={forcedRowId} forcedState={forcedState}
        onClose={() => {}} onJump={() => {}} />
    </SEPhone>
  );
}

// ─────────────────────────────────────────────────────
// StandaloneNoteEditSheet — the AnnotationEditSheet surface, drawn for a
// standalone (anchorless) note: same sheet chrome as the highlight-note
// editor, but a LOCATOR strip replaces the quoted-passage excerpt.
// Body is rendered as a static div (artboards don't type) with an optional
// faux caret. Reuses the committed FakeIOSKeyboard.
// ─────────────────────────────────────────────────────
function SEPin({ t, size = 8 }) {
  return (
    <div style={{
      width: size + 4, height: size + 4, borderRadius: 3,
      background: `${t.accent}22`, color: t.accent,
      display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
    }}>
      <svg width={size - 1} height={size} viewBox="0 0 7 8">
        <path d="M0.5 0.5h5l1 1v6h-6z" fill="currentColor" opacity="0.9"/>
        <path d="M1.8 3h3.2M1.8 4.6h2.2" stroke={t.isDark ? '#26231f' : '#fcf8f0'} strokeWidth="0.7"/>
      </svg>
    </div>
  );
}

function SESaveBtn({ t, label, disabled, destructive, saving }) {
  const bg = disabled ? (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)')
    : destructive ? seDanger(t) : t.accent;
  const fg = disabled ? (t.isDark ? 'rgba(216,210,197,0.4)' : 'rgba(29,26,20,0.35)') : '#fff';
  return (
    <div style={{
      padding: '7px 16px', borderRadius: 100, background: bg, color: fg,
      fontFamily: SE_FONT, fontSize: 14, fontWeight: 600,
      display: 'inline-flex', alignItems: 'center', gap: 6, minWidth: 60, justifyContent: 'center',
    }}>
      {saving && <span style={{ width: 12, height: 12, borderRadius: 6, border: `1.5px solid ${fg}55`, borderTopColor: fg, display: 'inline-block', animation: 'spin 0.7s linear infinite' }} />}
      {label}
    </div>
  );
}

function SEStandaloneEditSheet({
  themeKey = 'paper', note = SE_NOTE, draft = null,
  title, state = 'idle', forceDirty = null, isNew = false,
  showKeyboard = true, keyboardHeight = SE_KB, dimOpacity = 0.32,
  showCaret = false, cjk = false, scroll = false, inputSource = 'English',
}) {
  const t = THEMES[themeKey];
  const original = note?.body || '';
  const text = draft != null ? draft : original;
  const dirty = forceDirty != null ? forceDirty : (text !== original);
  const willClear = original && (text || '').trim() === '';
  const sheetBottom = showKeyboard ? keyboardHeight : 0;
  const label = state === 'saving' ? 'Saving…' : willClear ? 'Clear' : 'Save';
  const ttl = title || (isNew ? 'New note' : 'Edit note');
  const bodyFont = cjk ? '"Source Han Serif SC", "Songti SC", "Noto Serif SC", ' + SE_SERIF : SE_SERIF;

  return (
    <>
      <div style={{ position: 'absolute', inset: 0, zIndex: 200, background: `rgba(0,0,0,${dimOpacity})` }} />
      <div style={{
        position: 'absolute', left: 0, right: 0, bottom: sheetBottom, zIndex: 205,
        borderTopLeftRadius: 18, borderTopRightRadius: 18,
        background: t.isDark ? '#26231f' : '#fcf8f0',
        boxShadow: '0 -10px 32px rgba(0,0,0,0.32)',
        display: 'flex', flexDirection: 'column',
        maxHeight: `calc(100% - ${sheetBottom + 40}px)`,
        height: scroll ? `calc(100% - ${sheetBottom + 40}px)` : undefined,
        overflow: 'hidden',
      }}>
        {/* grabber */}
        <div style={{ display: 'flex', justifyContent: 'center', padding: '8px 0 4px' }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }} />
        </div>
        {/* header */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '6px 12px 10px', borderBottom: `0.5px solid ${t.rule}`,
        }}>
          <div style={{ fontFamily: SE_FONT, fontSize: 15, color: t.accent, padding: '6px 8px' }}>Cancel</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <SEPin t={t} />
            <div style={{ fontFamily: SE_SERIF, fontSize: 16, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap' }}>{ttl}</div>
          </div>
          <SESaveBtn t={t} label={label} disabled={!dirty || state === 'saving'} destructive={willClear} saving={state === 'saving'} />
        </div>

        {/* locator strip — stands in for the highlight excerpt; a standalone
            note has no quoted passage, only a chapter/page anchor. */}
        <div style={{
          padding: '11px 18px 10px', display: 'flex', gap: 10, alignItems: 'center',
          borderBottom: `0.5px solid ${t.rule}`,
          background: t.isDark ? 'rgba(255,255,255,0.02)' : 'rgba(0,0,0,0.015)',
        }}>
          <SEPin t={t} size={10} />
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 10, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 }}>
              {note?.chapter} · p. {note?.page}
            </div>
            <div style={{ fontSize: 12, color: t.sub, opacity: 0.9, marginTop: 1 }}>Standalone note — no quoted passage</div>
          </div>
        </div>

        {/* body */}
        <div style={{ flex: 1, minHeight: scroll ? 0 : 150, padding: '14px 18px 0', overflowY: scroll ? 'auto' : 'hidden' }} className="hide-scroll">
          {text ? (
            <div style={{
              fontFamily: bodyFont, fontSize: 17, lineHeight: cjk ? 1.85 : 1.55,
              color: t.ink, whiteSpace: 'pre-wrap', textAlign: cjk ? 'left' : 'left',
            }}>
              {text}
              {showCaret && <span style={{ display: 'inline-block', width: 2, height: cjk ? 22 : 19, background: t.accent, marginLeft: 1, transform: 'translateY(3px)', animation: 'seCaret 1s steps(1) infinite' }} />}
            </div>
          ) : (
            <div style={{ fontFamily: bodyFont, fontSize: 17, lineHeight: 1.55, color: t.sub, opacity: 0.7 }}>
              Write a note for this spot in the chapter…
              {showCaret && <span style={{ display: 'inline-block', width: 2, height: 19, background: t.accent, marginLeft: 1, transform: 'translateY(3px)', animation: 'seCaret 1s steps(1) infinite' }} />}
            </div>
          )}
        </div>

        {/* footer */}
        <div style={{
          padding: '8px 14px 10px', display: 'flex', alignItems: 'center', gap: 10,
          borderTop: `0.5px solid ${t.rule}`, fontSize: 12, color: t.sub,
        }}>
          <span>{cjk ? `${[...text.replace(/\s+/g, '')].length} 字` : text ? `${text.trim().split(/\s+/).filter(Boolean).length} words` : 'Empty'}</span>
          <div style={{ flex: 1 }} />
          {!isNew && (
            <span style={{ display: 'inline-flex', alignItems: 'center', gap: 5, color: seDanger(t), fontWeight: 500, fontSize: 12.5 }}>
              <svg width="12" height="12" viewBox="0 0 14 14" fill="none" stroke={seDanger(t)} strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round">
                <path d="M2.5 4h9M6 2h2a1 1 0 011 1v1H5V3a1 1 0 011-1zM3.5 4l.6 8.2A1 1 0 005.1 13h3.8a1 1 0 001-.8L10.5 4M6 7v3.5M8 7v3.5"/>
              </svg>
              Delete note
            </span>
          )}
        </div>
      </div>

      {showKeyboard && <FakeIOSKeyboard theme={t} height={keyboardHeight} inputSource={inputSource} script={cjk ? 'cjk' : 'latin'} />}
    </>
  );
}

// ─────────────────────────────────────────────────────
// Annotation chips (shared vocabulary with the contrast canvases)
// ─────────────────────────────────────────────────────
function SEChip({ tone = 'info', children }) {
  const map = {
    reject: { bg: 'rgba(168,58,58,0.94)', fg: '#fff' },
    pick:   { bg: 'rgba(42,122,68,0.96)', fg: '#fff' },
    alt:    { bg: 'rgba(166,120,40,0.96)', fg: '#fff' },
    info:   { bg: 'rgba(40,36,30,0.86)', fg: '#fff' },
    step:   { bg: '#fff', fg: '#2a251f' },
  }[tone];
  return (
    <span style={{
      display: 'inline-flex', alignItems: 'center', gap: 5,
      padding: '3px 9px', borderRadius: 100, background: map.bg, color: map.fg,
      fontSize: 11, fontWeight: 700, letterSpacing: 0.3, fontFamily: SE_FONT,
      boxShadow: '0 3px 9px rgba(0,0,0,0.16)',
    }}>{children}</span>
  );
}
function SENote({ top, left, right, bottom, tone, children }) {
  return <div style={{ position: 'absolute', top, left, right, bottom, zIndex: 6 }}><SEChip tone={tone}>{children}</SEChip></div>;
}
function SEStepBadge({ n, children }) {
  return (
    <div style={{ position: 'absolute', top: 16, left: 16, zIndex: 6, display: 'flex', alignItems: 'center', gap: 8 }}>
      <span style={{ width: 24, height: 24, borderRadius: 12, background: '#2a251f', color: '#fff', display: 'flex', alignItems: 'center', justifyContent: 'center', fontSize: 12, fontWeight: 700, fontFamily: SE_FONT, boxShadow: '0 3px 9px rgba(0,0,0,0.2)' }}>{n}</span>
      {children && <span style={{ padding: '4px 10px', borderRadius: 100, background: 'rgba(255,255,255,0.94)', color: '#2a251f', fontSize: 11.5, fontWeight: 600, fontFamily: SE_FONT, boxShadow: '0 3px 9px rgba(0,0,0,0.16)' }}>{children}</span>}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Comparison card — A vs B across the criteria that decide it
// ─────────────────────────────────────────────────────
function SECompareCard() {
  const t = THEMES.paper;
  const rows = [
    ['After Edit, the user is…', 'back in the annotations list — same filter, same scroll', 'in the reader at the locator; the list is gone'],
    ['The navigation does…', 'nothing — there is nowhere to go', 'scrolls the book to a locator showing ordinary text — no passage to land on'],
    ['Taps to resume triaging notes', 'zero — already there', 're-open Annotations, re-pick the filter, re-scroll'],
    ['New surface to build', 'none — reuses the dim + keyboard sheet primitive', 'a reader-level observer + AnnotationEditSheet mount point'],
    ['Editor surface', 'AnnotationEditSheet { initialContent, onSave }', 'identical — AnnotationEditSheet { initialContent, onSave }'],
    ['Fits the anchorless model', 'yes — edit the text where you found it', 'no — implies the note has a passage to read'],
    ['Vs. the highlight Edit path', 'same gesture grammar + same editor; container differs by design', 'same container, but for a reason that doesn\u2019t apply here'],
  ];
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: '#fcf8f0', padding: '30px 34px', fontFamily: SE_FONT, color: t.ink, overflow: 'hidden' }}>
      <div style={{ fontFamily: SE_SERIF, fontSize: 23, fontWeight: 700, marginBottom: 14 }}>Why edit over the sheet</div>
      <div style={{ display: 'grid', gridTemplateColumns: '210px 1fr 1fr', gap: 0 }}>
        <div style={{ padding: '0 0 10px' }} />
        <div style={{ padding: '0 14px 10px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <SEChip tone="pick">A · RECOMMEND</SEChip>
          <span style={{ fontSize: 12.5, fontWeight: 700 }}>Over the sheet</span>
        </div>
        <div style={{ padding: '0 14px 10px', display: 'flex', alignItems: 'center', gap: 8 }}>
          <SEChip tone="reject">B</SEChip>
          <span style={{ fontSize: 12.5, fontWeight: 700 }}>Dismiss + navigate</span>
        </div>
        {rows.map((r, i) => (
          <React.Fragment key={i}>
            <div style={{ padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, fontSize: 12.5, fontWeight: 600, color: t.ink }}>{r[0]}</div>
            <div style={{ padding: '11px 14px', borderTop: `0.5px solid ${t.rule}`, fontSize: 12.5, color: t.ink, lineHeight: 1.4, background: 'rgba(42,122,68,0.05)' }}>{r[1]}</div>
            <div style={{ padding: '11px 14px', borderTop: `0.5px solid ${t.rule}`, fontSize: 12.5, color: t.sub, lineHeight: 1.4 }}>{r[2]}</div>
          </React.Fragment>
        ))}
      </div>
      <div style={{ marginTop: 16, fontSize: 12.5, color: t.sub, lineHeight: 1.5 }}>
        Consistency with the highlight path is preserved where it counts — the <b>editor surface and the gesture</b> are the
        same. The container differs because the data differs: a highlight note is anchored to a visible passage (navigate, then
        the popover anchors there); a standalone note is anchored only to a locator (nothing to show), so it edits in place.
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// "Two intents" grammar card
// ─────────────────────────────────────────────────────
function SEGrammarCard() {
  const t = THEMES.paper;
  const Box = ({ tone, gesture, intent, outcome }) => (
    <div style={{ flex: 1, borderRadius: 14, padding: '16px 16px 18px', background: '#fffdf7', boxShadow: 'inset 0 0 0 0.5px rgba(0,0,0,0.06)' }}>
      <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', color: tone, marginBottom: 8 }}>{gesture}</div>
      <div style={{ fontFamily: SE_SERIF, fontSize: 17, fontWeight: 600, color: t.ink, marginBottom: 4 }}>{intent}</div>
      <div style={{ fontSize: 13, color: t.sub, lineHeight: 1.45 }}>{outcome}</div>
    </div>
  );
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', background: '#fcf8f0', padding: '30px 34px', fontFamily: SE_FONT, color: t.ink }}>
      <div style={{ fontFamily: SE_SERIF, fontSize: 23, fontWeight: 700, marginBottom: 4 }}>Two intents, one card</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 18, lineHeight: 1.45 }}>
        The standalone-note card already carries two separable intents. Keeping Edit in-sheet makes them visibly different
        outcomes — instead of collapsing both into "navigate, then edit."
      </div>
      <div style={{ display: 'flex', gap: 14 }}>
        <Box tone={t.accent} gesture="Tap the card body" intent="“Go read there”" outcome="Dismiss the sheet, navigate to the locator. The existing onJump — unchanged." />
        <Box tone="#2a7a44" gesture="⋯ → Edit note" intent="“Fix the wording”" outcome="Open AnnotationEditSheet over the list. Save returns you to the list, in place." />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// Spec card — binding plumbing contract
// ─────────────────────────────────────────────────────
function SESpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '150px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 13.5, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace', background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: SE_FONT, overflow: 'auto' }}>
      <div style={{ fontFamily: SE_SERIF, fontSize: 25, fontWeight: 700, marginBottom: 4 }}>WI-3 — standalone-note Edit, presentation contract</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 16 }}>
        Resolves the open question in #1121 / #1296. Decision: present over the HighlightsSheet, non-dismissing.
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Trigger</div>
        <div style={valStyle}>
          <span style={code}>edit()</span>'s <span style={code}>.standalone</span> branch posts an
          <span style={code}>editAnnotation(id)</span> request — observed at the <b>HighlightsSheet</b> level, not the reader.
          The sheet stays mounted.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Present</div>
        <div style={valStyle}>
          The observer presents <span style={code}>AnnotationEditSheet</span> as a sheet over the list
          (<span style={code}>.sheet</span> / keyboard-anchored), seeded with <span style={code}>initialContent: annotation.content</span>.
          No dismiss, no navigation.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Save</div>
        <div style={valStyle}>
          <span style={code}>onSave</span> → <span style={code}>updateAnnotation(annotationId:content:)</span> → dismiss the editor
          back to the list. The row reflects the new text in place; a "Note saved" toast confirms.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Cancel</div>
        <div style={valStyle}>
          Clean draft → dismiss to the list. Dirty draft → DiscardNoteAlert (the committed #914 alert), then dismiss to the list.
          Empty content is not a valid standalone note — Save reads "Clear" and routes through Delete confirm.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Locator strip</div>
        <div style={valStyle}>
          Replaces the highlight excerpt: chapter · page + a "Standalone note" hint. The user knows which note they're editing
          without a quoted passage to show.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Reuse, don't build</div>
        <div style={valStyle}>
          AnnotationEditSheet, FakeIOSKeyboard, DiscardNoteAlert, the saved toast — all committed. No reader-level mount point is
          added. The "tap card → jump" path (<span style={code}>onJump</span>) is unchanged.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Parity</div>
        <div style={valStyle}>
          Highlight Edit keeps its shipped behaviour (navigate + popover). Only the standalone branch is defined here. Same editor
          surface, same gesture grammar across both.
        </div>
      </div>
      <div style={rowStyle}>
        <div style={labelStyle}>Source of truth</div>
        <div style={valStyle}>
          Feature #1121 WI-3 (parent). Editor surface from #914; card + ⋯ menu from #1103.
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function StandaloneNoteEditorCanvas() {
  const W = SE_PHONE_W, H = SE_PHONE_H;
  return (
    <DesignCanvas>

      {/* ─── 1. Decision ─── */}
      <DCSection id="decision"
        title="#1296 — Standalone-note editor presentation (WI-3)"
        subtitle="When the user taps ⋯ → Edit on a standalone note, the editor opens OVER the Annotations sheet — non-dismissing — and returns there on Save. Not 'after the jump': a standalone note has no passage to navigate to. End-state below.">
        <DCArtboard id="rec-paper" label="Recommended · editor over the list" width={W} height={H}>
          <SEPhone themeKey="paper">
            <SEReaderCh6 themeKey="paper" showLocator={false} />
            <HighlightsSheetV4 theme={THEMES.paper} highlights={SE_HIGHLIGHTS} standalones={SE_STANDALONES} filter="notes" onClose={() => {}} onJump={() => {}} />
            <SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} showCaret />
          </SEPhone>
        </DCArtboard>
        <DCArtboard id="rec-dark" label="Recommended · dark" width={W} height={H}>
          <SEPhone themeKey="dark">
            <SEReaderCh6 themeKey="dark" showLocator={false} />
            <HighlightsSheetV4 theme={THEMES.dark} highlights={SE_HIGHLIGHTS} standalones={SE_STANDALONES} filter="notes" onClose={() => {}} onJump={() => {}} />
            <SEStandaloneEditSheet themeKey="dark" note={SE_NOTE} showCaret />
          </SEPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={36} rotate={2} width={262}>
          The list stays mounted behind the dim. The editor is the same keyboard-anchored sheet the highlight-note editor already is — just stacked over the review sheet instead of the page.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. Entry point ─── */}
      <DCSection id="entry"
        title="Entry point · ⋯ → Edit"
        subtitle="The committed StandaloneNoteCard (#1103) already carries a ⋯ menu with Edit · Copy · Delete. This issue is only about what 'Edit note' does next.">
        <DCArtboard id="card-menu" label="Standalone card · ⋯ menu open" width={W} height={H}>
          <SEList themeKey="paper" filter="notes" forcedRowId="s1" forcedState="menu-open" />
        </DCArtboard>
        <DCArtboard id="card-rest" label="The two notes, at rest" width={W} height={H}>
          <SEList themeKey="paper" filter="notes" />
        </DCArtboard>
        <DCArtboard id="grammar" label="Two intents, one card" width={620} height={H}>
          <SEGrammarCard />
        </DCArtboard>
        <DCPostIt top={-34} left={36} rotate={-2} width={232}>
          Tapping the card body already means "go read there." So Edit should mean something else — fix the text — not a second route to the same jump.
        </DCPostIt>
      </DCSection>

      {/* ─── 3. Option A storyboard ─── */}
      <DCSection id="optionA"
        title="Option A · edit over the sheet (recommended)"
        subtitle="Edit opens the editor as a sheet stacked over the dimmed Annotations list. The user types, saves, and lands back in the list exactly where they were — filter and scroll intact.">
        <DCArtboard id="a1" label="1 · Tap Edit note" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEList themeKey="paper" filter="notes" forcedRowId="s1" forcedState="menu-open" />
            <SEStepBadge n="1">⋯ → Edit note</SEStepBadge>
          </div>
        </DCArtboard>
        <DCArtboard id="a2" label="2 · Editor rises over the list" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper">
              <SEReaderCh6 themeKey="paper" showLocator={false} />
              <HighlightsSheetV4 theme={THEMES.paper} highlights={SE_HIGHLIGHTS} standalones={SE_STANDALONES} filter="notes" onClose={() => {}} onJump={() => {}} />
              <SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} showCaret />
            </SEPhone>
            <SEStepBadge n="2" />
            <SENote bottom={SE_KB + 14} right={16} tone="info">list still mounted behind</SENote>
          </div>
        </DCArtboard>
        <DCArtboard id="a3" label="3 · Editing · Save enabled" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper">
              <SEReaderCh6 themeKey="paper" showLocator={false} />
              <HighlightsSheetV4 theme={THEMES.paper} highlights={SE_HIGHLIGHTS} standalones={SE_STANDALONES} filter="notes" onClose={() => {}} onJump={() => {}} />
              <SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} draft={SE_NOTE_EDITED.body} showCaret forceDirty />
            </SEPhone>
            <SEStepBadge n="3" />
            <SENote bottom={SE_KB + 14} right={16} tone="pick">draft dirty · Save on</SENote>
          </div>
        </DCArtboard>
        <DCArtboard id="a4" label="4 · Save → back in the list, updated" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper">
              <SEReaderCh6 themeKey="paper" showLocator={false} />
              <HighlightsSheetV4 theme={THEMES.paper} highlights={SE_HIGHLIGHTS} standalones={[SE_NOTE_EDITED, SE_STANDALONES[1]]} filter="notes" onClose={() => {}} onJump={() => {}} />
              <NoteSavedToast theme={THEMES.paper} message="Note saved" />
            </SEPhone>
            <SEStepBadge n="4" />
            <SENote top={64} right={16} tone="pick">same filter · same scroll</SENote>
          </div>
        </DCArtboard>
        <DCPostIt top={-34} right={36} rotate={2} width={236}>
          Four taps, zero context lost. The user never leaves the triage surface they opened — the whole point of the Annotations sheet.
        </DCPostIt>
      </DCSection>

      {/* ─── 4. Option B storyboard ─── */}
      <DCSection id="optionB"
        title="Option B · dismiss + navigate (the prior 'intent')"
        subtitle="The originally-sketched path: Edit dismisses the sheet, flies the reader to the locator, then presents the editor there. It mirrors the highlight path's container — but the reason that path navigates doesn't apply to an anchorless note.">
        <DCArtboard id="b1" label="1 · Tap Edit note" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEList themeKey="paper" filter="notes" forcedRowId="s1" forcedState="menu-open" />
            <SEStepBadge n="1">⋯ → Edit note</SEStepBadge>
          </div>
        </DCArtboard>
        <DCArtboard id="b2" label="2 · Sheet dismissed · reader jumps" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator /></SEPhone>
            <SEStepBadge n="2" />
            <SENote top={150} right={16} tone="reject">list + filter gone</SENote>
            <SENote top={300} left={64} tone="alt">no passage to land on</SENote>
          </div>
        </DCArtboard>
        <DCArtboard id="b3" label="3 · Editor presents at reader level" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper">
              <SEReaderCh6 themeKey="paper" showLocator />
              <SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} draft={SE_NOTE_EDITED.body} showCaret forceDirty />
            </SEPhone>
            <SEStepBadge n="3" />
            <SENote bottom={SE_KB + 14} right={16} tone="alt">needs a new reader-level mount</SENote>
          </div>
        </DCArtboard>
        <DCArtboard id="b4" label="4 · Save → stranded in the reader" width={W} height={H}>
          <div style={{ position: 'relative', width: '100%', height: '100%' }}>
            <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator /><NoteSavedToast theme={THEMES.paper} message="Note saved" /></SEPhone>
            <SEStepBadge n="4" />
            <SENote top={150} right={16} tone="reject">re-open Annotations to keep triaging</SENote>
          </div>
        </DCArtboard>
        <DCPostIt top={-34} left={36} rotate={-2} width={244}>
          The jump is the cost, not the feature. For a highlight, navigating shows the passage the note is about. For a standalone note there's nothing to show — so B spends a full screen transition to reveal unrelated text.
        </DCPostIt>
      </DCSection>

      {/* ─── 5. Why A ─── */}
      <DCSection id="why"
        title="Why A wins"
        subtitle="Same editor, same gesture, lighter build — and it respects what a standalone note actually is.">
        <DCArtboard id="compare" label="A vs B · decision matrix" width={860} height={476}>
          <SECompareCard />
        </DCArtboard>
      </DCSection>

      {/* ─── 6. Editor states ─── */}
      <DCSection id="states"
        title="Editor states"
        subtitle="The standalone editor reuses the committed #914 surface vocabulary: editing, dirty/Save, saving, discard-confirm, plus long-form and CJK. Sepia + dark inherit ReaderThemeV2 tokens.">
        <DCArtboard id="st-edit" label="Editing existing · idle" width={W} height={H}>
          <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator={false} /><SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} showCaret /></SEPhone>
        </DCArtboard>
        <DCArtboard id="st-saving" label="Saving…" width={W} height={H}>
          <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator={false} /><SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} draft={SE_NOTE_EDITED.body} state="saving" forceDirty /></SEPhone>
        </DCArtboard>
        <DCArtboard id="st-discard" label="Discard alert · dirty Cancel" width={W} height={H}>
          <SEPhone themeKey="paper">
            <SEReaderCh6 themeKey="paper" showLocator={false} />
            <SEStandaloneEditSheet themeKey="paper" note={SE_NOTE} draft={SE_NOTE_EDITED.body} forceDirty />
            <DiscardNoteAlert theme={THEMES.paper} addingNew={false} onKeep={() => {}} onDiscard={() => {}} />
          </SEPhone>
        </DCArtboard>
        <DCArtboard id="st-long" label="Long note · scrolls" width={W} height={H}>
          <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator={false} /><SEStandaloneEditSheet themeKey="paper" note={SE_NOTE_LONG} scroll /></SEPhone>
        </DCArtboard>
        <DCArtboard id="st-cjk" label="Chinese · IME" width={W} height={H}>
          <SEPhone themeKey="paper"><SEReaderCh6 themeKey="paper" showLocator={false} /><SEStandaloneEditSheet themeKey="paper" note={SE_NOTE_CJK} cjk inputSource="拼音" showCaret /></SEPhone>
        </DCArtboard>
        <DCArtboard id="st-sepia" label="Sepia" width={W} height={H}>
          <SEPhone themeKey="sepia"><SEReaderCh6 themeKey="sepia" showLocator={false} /><SEStandaloneEditSheet themeKey="sepia" note={SE_NOTE} showCaret /></SEPhone>
        </DCArtboard>
      </DCSection>

      {/* ─── 7. Spec ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="The binding contract — what WI-3's plumbing builds against.">
        <DCArtboard id="spec-card" label="" width={760} height={560}>
          <SESpecCard />
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { StandaloneNoteEditorCanvas });
