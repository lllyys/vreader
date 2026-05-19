// Canvas artboards for issue #963 — annotation-import affordance.
//
// Sections mirror the three families in vreader-annotation-import.jsx:
//   A — HighlightsSheet trailing slot (overflow vs two-icons vs share-only+pill)
//   B — BookDetailsSheet Actions (Import row, or combined Manage row)
//   C — Empty-state secondary CTA (discoverability layer; composes with A or B)
//   P — Post-pick preview / confirm sheet (shared surface across triggers)

const PHONE_W963 = 402;
const I963_BOOK = (typeof BOOKS !== 'undefined' && BOOKS.find(b => b.id === 'pp')) || {
  title: 'Pride and Prejudice', author: 'Jane Austen', year: 1813, format: 'EPUB',
  pages: 432, size: '1.2 MB',
};

function Phone963({ themeKey = 'paper', children, height = 720 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W963, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>{children}</div>
  );
}

// ════════════════════════════════════════════════════
// A — HighlightsSheet trailing slot
// ════════════════════════════════════════════════════
function A_HighlightsTrailingArtboard({ themeKey, variant, menuOpen = false }) {
  const t = THEMES[themeKey];
  return (
    <Phone963 themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <HighlightsSheetForImport theme={t} variant={variant} menuOpen={menuOpen} filter="all"/>
    </Phone963>
  );
}

// Detail view — zoom on just the sheet header, showing the trailing slot
// candidates side-by-side at true size. Helps the crowding argument.
function A_TrailingDetailArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: 720, padding: '24px 28px', background: t.bg, borderRadius: 12,
      border: `0.5px solid ${t.rule}`, display: 'flex', flexDirection: 'column', gap: 18,
    }}>
      {[
        { key: 'A1-overflow', label: '••• overflow → menu (canonical)',
          trailing: <HighlightsSheetTrailingOverflow t={t} open={false}/>,
          note: 'Single tap target. Surfaces Share + Import + future actions without crowding.' },
        { key: 'A2-twoicons', label: 'Two bare icons (anti-pattern)',
          trailing: <HighlightsSheetTrailingTwoIcons t={t}/>,
          note: 'The issue\'s exact concern: two icon buttons crowd the 50pt slot. Also ambiguous — upload-arrow reads as "share" to some users.' },
        { key: 'A3-share-only', label: 'Share only · Import pill below chips',
          trailing: <button style={{
            background: 'none', border: 'none', padding: 6,
            display: 'flex', cursor: 'pointer',
          }} aria-label="Share annotations">
            <Icons.Share size={18} color={t.accent} stroke={1.8}/>
          </button>,
          note: 'Import escapes the trailing slot entirely. More discoverable than overflow but adds weight to the chip area.' },
      ].map(r => (
        <div key={r.key} style={{
          display: 'flex', alignItems: 'flex-start', gap: 18,
          paddingBottom: 14, borderBottom: `0.5px dashed ${t.rule}`,
        }}>
          <div style={{ width: 220, flexShrink: 0 }}>
            <div style={{
              fontSize: 11, color: t.sub, letterSpacing: 0.6,
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 6,
            }}>{r.key}</div>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 500, marginBottom: 6, lineHeight: 1.3 }}>{r.label}</div>
            <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45 }}>{r.note}</div>
          </div>
          {/* faux sheet header */}
          <div style={{
            flex: 1, borderRadius: 12,
            background: t.isDark ? '#211e1b' : '#f6f0e4',
            padding: '14px 18px',
            display: 'flex', alignItems: 'center', gap: 10,
            position: 'relative',
          }}>
            <div style={{
              width: 28, height: 28, borderRadius: 14,
              background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            }}/>
            <div style={{
              flex: 1, fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 17, fontWeight: 600, color: t.ink, letterSpacing: -0.2,
            }}>Annotations</div>
            {r.trailing}
          </div>
        </div>
      ))}
    </div>
  );
}

// ════════════════════════════════════════════════════
// B — BookDetailsSheet Actions
// ════════════════════════════════════════════════════
function B_BookDetailsArtboard({ themeKey, variant, showPreview = false }) {
  const t = THEMES[themeKey];
  return (
    <Phone963 themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <Sheet theme={t} height={720} title="Book details"
        trailing={
          <button style={{
            background: 'rgba(0,0,0,0.06)', border: 'none',
            width: 28, height: 28, borderRadius: 14, padding: 0,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            cursor: 'pointer',
          }} aria-label="Share">
            <Icons.Share size={16} color={t.ink} stroke={1.7}/>
          </button>
        }>
        <div style={{ padding: '18px 22px 32px' }}>
          {/* compact cover + title */}
          <div style={{
            display: 'flex', flexDirection: 'column', alignItems: 'center',
            gap: 12, marginBottom: 16,
          }}>
            {typeof BookCover !== 'undefined' && (
              <BookCover book={I963_BOOK} width={104} height={156} radius={4}/>
            )}
            <div style={{ textAlign: 'center' }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif',
                fontSize: 20, fontStyle: 'italic', fontWeight: 600,
                color: t.ink, lineHeight: 1.15,
              }}>{I963_BOOK.title}</div>
              <div style={{ fontSize: 12.5, color: t.sub, marginTop: 4 }}>
                {I963_BOOK.author} · {I963_BOOK.year}
              </div>
            </div>
          </div>

          {/* sparse meta — just enough to anchor */}
          <SectionLabel theme={t}>Metadata</SectionLabel>
          <div style={{
            marginTop: 8, marginBottom: 22,
            borderRadius: 14, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          }}>
            {[
              ['Format', I963_BOOK.format || 'EPUB'],
              ['Pages',  '432'],
            ].map(([k, v], i, a) => (
              <div key={k} style={{
                display: 'flex', gap: 10, padding: '11px 14px',
                borderBottom: i === a.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
              }}>
                <div style={{ width: 96, fontSize: 12, color: t.sub, fontWeight: 500 }}>{k}</div>
                <div style={{
                  flex: 1, fontSize: 13.5, color: t.ink,
                  fontFamily: '"SF Mono", Menlo, monospace',
                }}>{v}</div>
              </div>
            ))}
          </div>

          <BookDetailsActionsCard theme={t} variant={variant}/>
        </div>
      </Sheet>

      {showPreview && variant === 'B2-combined' && <ManageAnnotationsHalfSheet theme={t}/>}
    </Phone963>
  );
}

// ════════════════════════════════════════════════════
// C — Empty-state secondary CTA
// ════════════════════════════════════════════════════
function C_EmptyArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <Phone963 themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <HighlightsSheetEmpty theme={t}/>
    </Phone963>
  );
}

// ════════════════════════════════════════════════════
// P — Post-pick preview / confirm sheet
// ════════════════════════════════════════════════════
function P_PreviewArtboard({ themeKey, source, error }) {
  const t = THEMES[themeKey];
  return (
    <Phone963 themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      {/* keep the highlights sheet dimmed behind so the half-sheet reads as
          a modal overlay rather than a standalone screen */}
      <HighlightsSheetForImport theme={t} variant="A1-overflow" menuOpen={false} filter="all"/>
      <div style={{ position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.35)' }}/>
      <ImportPreviewSheet theme={t} source={source} error={error}/>
    </Phone963>
  );
}

// ════════════════════════════════════════════════════
// CanvasRoot
// ════════════════════════════════════════════════════
function CanvasRoot963() {
  return (
    <DesignCanvas>
      {/* ───── A — HighlightsSheet trailing slot ───── */}
      <DCSection id="A-trailing" title="A — HighlightsSheet trailing slot"
        subtitle="Three takes on what the slot does. The canvas leads with overflow (A1) because it survives the addition of future actions without re-design.">
        <DCArtboard id="A1-closed" label="A1 · ••• overflow — closed (canonical)" width={PHONE_W963} height={680}>
          <A_HighlightsTrailingArtboard themeKey="paper" variant="A1-overflow"/>
        </DCArtboard>
        <DCArtboard id="A1-open" label="A1 · ••• overflow — menu open" width={PHONE_W963} height={680}>
          <A_HighlightsTrailingArtboard themeKey="paper" variant="A1-overflow" menuOpen/>
        </DCArtboard>
        <DCArtboard id="A1-dark" label="A1 · dark — menu open" width={PHONE_W963} height={680}>
          <A_HighlightsTrailingArtboard themeKey="dark" variant="A1-overflow" menuOpen/>
        </DCArtboard>
        <DCArtboard id="A2-twoicons" label="A2 · two bare icons (anti-pattern)" width={PHONE_W963} height={680}>
          <A_HighlightsTrailingArtboard themeKey="paper" variant="A2-twoicons"/>
        </DCArtboard>
        <DCArtboard id="A3-pill" label="A3 · Share only · Import pill below chips" width={PHONE_W963} height={680}>
          <A_HighlightsTrailingArtboard themeKey="paper" variant="A3-pill"/>
        </DCArtboard>
        <DCArtboard id="A-detail" label="Trailing-slot comparison · true-size header" width={720} height={400}>
          <A_TrailingDetailArtboard themeKey="paper"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={260}>
          Canonical: <b>A1</b>. Import is a low-frequency onboarding action — it
          doesn't earn its own 50pt slot. The overflow menu keeps Share at one
          tap and leaves room for the export-format submenu that already exists
          in production.
        </DCPostIt>
      </DCSection>

      {/* ───── B — BookDetailsSheet Actions ───── */}
      <DCSection id="B-bookdetails" title="B — BookDetailsSheet Actions"
        subtitle="Per-book home — paired with the existing Export row. Acceptable as a backstop, not the primary discovery surface (most users never open Book Details).">
        <DCArtboard id="B1-paired" label="B1 · Import row paired with Export (canonical fallback)" width={PHONE_W963} height={720}>
          <B_BookDetailsArtboard themeKey="paper" variant="B1-paired"/>
        </DCArtboard>
        <DCArtboard id="B1-dark" label="B1 · dark" width={PHONE_W963} height={720}>
          <B_BookDetailsArtboard themeKey="dark" variant="B1-paired"/>
        </DCArtboard>
        <DCArtboard id="B2-combined" label="B2 · single Annotations… row → half-sheet" width={PHONE_W963} height={720}>
          <B_BookDetailsArtboard themeKey="paper" variant="B2-combined"/>
        </DCArtboard>
        <DCArtboard id="B2-open" label="B2 · half-sheet open" width={PHONE_W963} height={720}>
          <B_BookDetailsArtboard themeKey="paper" variant="B2-combined" showPreview/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={260}>
          B1 reads as a peer to Export — that's the point: import is the inverse
          action. B2 keeps the Actions card shorter at the cost of one extra tap,
          and trades discoverability for tidiness. Pick B1 unless the Actions
          card grows past five rows.
        </DCPostIt>
      </DCSection>

      {/* ───── C — Empty-state CTA ───── */}
      <DCSection id="C-empty" title="C — Empty-state secondary CTA"
        subtitle="Composes with A or B. The empty Annotations stream is where a user migrating from another reader is most likely to be — meet them there.">
        <DCArtboard id="C1-paper" label="C1 · Empty state with Import CTA" width={PHONE_W963} height={680}>
          <C_EmptyArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="C1-dark" label="C1 · dark" width={PHONE_W963} height={680}>
          <C_EmptyArtboard themeKey="dark"/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={-2} width={240}>
          CTA is a low-weight outline button, not the accent fill — Import is a
          one-time action. The format hint underneath answers the implicit
          "from what?" question before the user has to ask.
        </DCPostIt>
      </DCSection>

      {/* ───── P — Preview sheet (shared) ───── */}
      <DCSection id="P-preview" title="P — Post-pick preview · shared across triggers"
        subtitle="After the system file picker returns a file, this half-sheet shows what's about to be merged BEFORE the engine touches data. Same surface from every entry.">
        <DCArtboard id="P-vreader" label="VReader JSON · 44 + 12 items" width={PHONE_W963} height={720}>
          <P_PreviewArtboard themeKey="paper" source="vreader"/>
        </DCArtboard>
        <DCArtboard id="P-readwise" label="Readwise import" width={PHONE_W963} height={720}>
          <P_PreviewArtboard themeKey="paper" source="readwise"/>
        </DCArtboard>
        <DCArtboard id="P-apple" label="Apple Books import" width={PHONE_W963} height={720}>
          <P_PreviewArtboard themeKey="paper" source="apple"/>
        </DCArtboard>
        <DCArtboard id="P-dark" label="Dark" width={PHONE_W963} height={720}>
          <P_PreviewArtboard themeKey="dark" source="vreader"/>
        </DCArtboard>
        <DCArtboard id="P-error" label="Error — wrong book / unmatched format" width={PHONE_W963} height={720}>
          <P_PreviewArtboard themeKey="paper" source="vreader"
            error={'This file is for "Sense and Sensibility". Open that book and try again, or pick a different file.'}/>
        </DCArtboard>

        <DCPostIt top={-30} right={40} rotate={2} width={260}>
          The preview's whole job is to make the merge feel reversible <i>before</i>
          it happens. Counts up top, three real-quote samples, an explicit
          merge rule, and a primary button labelled with the item count — not
          "Import".
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot963 });
