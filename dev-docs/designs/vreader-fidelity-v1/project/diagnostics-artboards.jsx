// Canvas artboards for issue #1597 — Settings → Diagnostics entry + log viewer
// (feature #96).
//
// Sections:
//   E — Entry: the new Support group row in SettingsView, paper + dark.
//   V — Viewer: canonical default state, paper + dark.
//   F — Filters: error-filter-active, category-filter-active, combined empty.
//   S — Read-back states: loading, empty (fresh install), empty dark.
//   X — Export: share-sheet presented + two non-canonical alternatives.
//   A — Anatomy: log-row spec close-up (levels, truncation, expanded), both themes.

const I1597_W = 402;
const I1597_H = 768;

function DiagPhone({ themeKey = 'paper', children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: I1597_W, height: I1597_H, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      {children}
    </div>
  );
}

// ── E — Settings entry in context ──
// Reduced-fidelity SettingsView wrapper (library hero per #862, Reading group)
// so the new Support group reads in its real neighborhood, scrolled to bottom.
function DiagEntryArt({ themeKey, highlight = true, errorBadge = false }) {
  const t = THEMES[themeKey];
  return (
    <DiagPhone themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}></div>
      <Sheet theme={t} onClose={() => {}} height={740} title="Settings">
        <div style={{ padding: '16px 18px 32px' }}>
          {/* Library-as-identity hero (#862 canonical) — reduced fidelity */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: 14, borderRadius: 14, marginBottom: 18,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          }}>
            <div style={{
              width: 48, height: 48, borderRadius: 24, flexShrink: 0,
              background: `linear-gradient(135deg, ${t.accent}, #5a3a3a)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icons.Library size={22} color="#fff" stroke={1.7}/>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{
                fontFamily: '"Source Serif 4", Georgia, serif', fontStyle: 'italic',
                fontSize: 16, fontWeight: 600, color: t.ink,
              }}>Your library</div>
              <div style={{ fontSize: 12, color: t.sub, marginTop: 1 }}>
                152 books · 41h read this month
              </div>
            </div>
          </div>

          {/* Reading group — neighborhood context */}
          <div style={{ marginBottom: 18 }}>
            <SectionLabel theme={t}>Reading</SectionLabel>
            <div style={{
              marginTop: 8, borderRadius: 14, overflow: 'hidden',
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
              boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
            }}>
              <DiagSettingsRow theme={t}
                icon={<Icons.Volume size={17} color="#fff" stroke={1.8}/>}
                color="#3a3a8c" title="Text-to-speech"/>
              <DiagSettingsRow theme={t}
                icon={<Icons.Note size={17} color="#fff" stroke={1.8}/>}
                color="#a8804a" title="Replacement rules" value="5" last/>
            </div>
          </div>

          {/* THE new group under design */}
          <DiagSupportGroup theme={t} highlight={highlight} errorBadge={errorBadge}/>
        </div>
      </Sheet>
    </DiagPhone>
  );
}

// ── viewer artboard wrapper ──
function DiagViewerArt({ themeKey, ...props }) {
  const t = THEMES[themeKey];
  return (
    <DiagPhone themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}></div>
      <DiagLogViewer theme={t} height={740} {...props}/>
    </DiagPhone>
  );
}

// ── A — anatomy: row spec close-up, free of sheet chrome ──
function DiagRowSpecArt({ themeKey }) {
  const t = THEMES[themeKey];
  const Card = ({ children }) => (
    <div style={{
      marginTop: 8, marginBottom: 20, borderRadius: 14, overflow: 'hidden',
      background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
      boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
    }}>{children}</div>
  );
  const longEntry = {
    id: 99, ts: '14:32:07.412', level: 'error', cat: 'Persistence',
    msg: 'Failed to save ReadingSession: CKError 4 (networkUnavailable) — retry queued for next launch. Underlying: <CKError 0x14d2a8: "Network Unavailable" (3/4); "Couldn\'t send a valid signature">. Record: ReadingSession(id: 8F2C…E1, book: pride-and-prejudice, span: 14:02–14:31)',
  };
  return (
    <div style={{
      width: I1597_W, padding: 24, background: t.bg,
      borderRadius: 18, position: 'relative',
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <SectionLabel theme={t}>Row · three levels</SectionLabel>
      <Card>
        <DiagLogRow theme={t} entry={DIAG_LOG[0]}/>
        <DiagLogRow theme={t} entry={DIAG_LOG[4]}/>
        <DiagLogRow theme={t} entry={DIAG_LOG[3]} last/>
      </Card>

      <SectionLabel theme={t}>Long message · truncated (3-line clamp)</SectionLabel>
      <Card>
        <DiagLogRow theme={t} entry={longEntry} last/>
      </Card>

      <SectionLabel theme={t}>Long message · tapped → expanded + copy</SectionLabel>
      <Card>
        <DiagLogRow theme={t} entry={longEntry} expanded last/>
      </Card>

      <SectionLabel theme={t}>Settings row · the entry</SectionLabel>
      <Card>
        <DiagSettingsRow theme={t}
          icon={<DiagPulseIcon size={17} color="#fff" stroke={1.8}/>}
          color={DIAG_TILE} title="Diagnostics"
          detail="View and export app logs" last/>
      </Card>
    </div>
  );
}

// ════════════════════════════════════════════════════
function CanvasRoot1597() {
  return (
    <DesignCanvas>
      <DCSection id="intro" title="Diagnostics log viewer · #1597"
        subtitle="Feature #96 — in-app error/debug log capture, viewer, and export. A new Support group row in Settings pushes a Diagnostics screen: level + category chip filters, monospace log list, share trigger in the nav bar, pinned capture-status footer.">
        <DCPostIt top={-34} right={40} rotate={-2} width={330}>
          <b>Canonical:</b> Settings → Support → Diagnostics, pushed in the
          Settings nav. Share lives in the nav-bar trailing slot (iOS-standard
          home for export). Filters are the app's chip vocabulary — the Errors
          chip tints red when active so a filtered list is legible at a glance.
          Capture is always on in Release; the footer says so instead of
          offering a toggle.
        </DCPostIt>
      </DCSection>

      <DCSection id="E" title="E — Settings entry"
        subtitle="A new “Support” group above the sheet's end: Diagnostics (steel tile, pulse glyph) + About VReader. Scripted bug-report ask becomes “Settings → Diagnostics → share icon”.">
        <DCArtboard id="E1" label="Settings · Support group · paper" width={I1597_W} height={I1597_H}>
          <DiagEntryArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="E2" label="Settings · Support group · dark" width={I1597_W} height={I1597_H}>
          <DiagEntryArt themeKey="dark"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="V" title="V — Log viewer · default"
        subtitle="Newest first, grouped by day. Meta line: mono timestamp · colored level · category pill. Message is monospace, clamped to 3 lines. Footer: scope + “Capturing” status.">
        <DCArtboard id="V1" label="Viewer · default · paper" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="V2" label="Viewer · default · dark" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="dark"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="F" title="F — Filter states"
        subtitle="Level chips carry counts; the active Errors chip takes the error tint. Category chips scroll horizontally. Footer reflects the filtered scope. Both filters compose; an empty result offers Clear filters.">
        <DCArtboard id="F1" label="Errors active · footer shows 12 of 487" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" level="error" entries={DIAG_LOG_ERRORS}
            footerLeft="Showing 12 of 487 · errors"/>
        </DCArtboard>
        <DCArtboard id="F2" label="Category active · Persistence" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" category="Persistence" entries={DIAG_LOG_PERSISTENCE}
            footerLeft="Showing 38 of 487 · Persistence"/>
        </DCArtboard>
        <DCArtboard id="F3" label="Combined · no matches · clear filters" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" state="filtered-empty" level="error" category="DebugBridge"/>
        </DCArtboard>
        <DCArtboard id="F4" label="Errors active · dark" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="dark" level="error" entries={DIAG_LOG_ERRORS}
            footerLeft="Showing 12 of 487 · errors"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="S" title="S — Read-back states"
        subtitle="OSLogStore read-back is async → a real loading state (spinner + subsystem line). Fresh install → empty state that says capture needs nothing turned on. Filters and share hide when there is nothing to filter or export.">
        <DCArtboard id="S1" label="Loading · reading log store" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" state="loading"/>
        </DCArtboard>
        <DCArtboard id="S2" label="Empty · no logs captured · paper" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" state="empty"/>
        </DCArtboard>
        <DCArtboard id="S3" label="Empty · dark" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="dark" state="empty"/>
        </DCArtboard>
      </DCSection>

      <DCSection id="X" title="X — Export trigger + alternatives"
        subtitle="Canonical: share icon in the nav trailing slot → system share sheet with a .txt payload (filename + size header is ours to spec). Alternatives shown for comparison, not chosen.">
        <DCArtboard id="X1" label="① Share tapped · system sheet (canonical)" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" state="share" emphasizeShare/>
        </DCArtboard>
        <DCArtboard id="X2" label="Alt · pinned “Export log…” footer CTA" width={I1597_W} height={I1597_H}>
          <DiagViewerArt themeKey="paper" footerVariant="export-cta"/>
        </DCArtboard>
        <DCArtboard id="X3" label="Alt · error-count badge on the entry row" width={I1597_W} height={I1597_H}>
          <DiagEntryArt themeKey="paper" highlight={false} errorBadge/>
        </DCArtboard>
        <DCPostIt top={-34} right={40} rotate={2} width={290}>
          <b>Why not the alternatives:</b> the pinned CTA spends permanent
          vertical space on a rare action and crowds the status footer. The
          badged entry row makes Settings feel alarming for errors the user
          can't act on — diagnostics are for when something already went wrong,
          not an invitation to worry.
        </DCPostIt>
      </DCSection>

      <DCSection id="A" title="A — Anatomy · row spec"
        subtitle="The three level treatments, 3-line truncation vs tapped-expanded with Copy entry, and the Settings row — true size, free of sheet chrome.">
        <DCArtboard id="A1" label="Row spec · paper" width={I1597_W} height={920}>
          <DiagRowSpecArt themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="A2" label="Row spec · dark" width={I1597_W} height={920}>
          <DiagRowSpecArt themeKey="dark"/>
        </DCArtboard>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot1597 });
