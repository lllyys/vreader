// Canvas artboards for issue #1068 — AI Assistant + Data & Privacy toggle rows.
//
// Shows the AI section in the SettingsSheet with three variant treatments
// across the states the design must cover (per the issue):
//   • AI off (default — only master toggle visible)
//   • AI on + consent off
//   • AI on + consent on
//   • dark theme

const PHONE_W = 402;
const I_BOOK_PLACEHOLDER = { title: 'Pride and Prejudice', author: 'Jane Austen' };

function PhoneFrame({ themeKey = 'paper', children, height = 720 }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W, height, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      {children}
    </div>
  );
}

// Renders the SettingsSheet in context, with one of the three AI-section
// variants slotted in. The surrounding sections (profile card, Cloud & Sync)
// are included as a reduced-fidelity wrapper so the AI section reads in its
// real visual neighborhood — same idea as the #862 SettingsHeaderArtboard.
function SettingsAIArtboard({ themeKey, variant, aiOn, consentOn }) {
  const t = THEMES[themeKey];
  const Variant = variant === 'A' ? AISectionVariantA
                : variant === 'B' ? AISectionVariantB
                : AISectionVariantC;
  return (
    <PhoneFrame themeKey={themeKey}>
      <div style={{ position: 'absolute', inset: 0, background: t.bg }}/>
      <Sheet theme={t} onClose={() => {}} height={720} title="Settings">
        <div style={{ padding: '16px 18px 32px' }}>
          {/* Reduced-fidelity profile card — anchors the AI section */}
          <div style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: 14, borderRadius: 14, marginBottom: 18,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          }}>
            <div style={{
              width: 48, height: 48, borderRadius: 24,
              background: `linear-gradient(135deg, ${t.accent}, #5a3a3a)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              color: '#fff', fontFamily: '"Source Serif 4", Georgia, serif',
              fontSize: 20, fontWeight: 600,
            }}>L</div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 16, fontWeight: 600, color: t.ink }}>lllyys</div>
              <div style={{ fontSize: 12, color: t.sub, marginTop: 1 }}>
                152 books · 41h read this month
              </div>
            </div>
          </div>

          {/* Cloud & Sync — to show the AI section in its actual neighbor context */}
          <div style={{ marginBottom: 18 }}>
            <SectionLabel theme={t}>Cloud &amp; Sync</SectionLabel>
            <div style={{
              marginTop: 8, borderRadius: 14, overflow: 'hidden',
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
              boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
            }}>
              <SettingsRow theme={t}
                icon={<Icons.Cloud size={17} color="#fff" stroke={1.8}/>}
                color="#3a8ac8" title="WebDAV backup"
                detail="Nutstore · last sync 2h ago" value="On"/>
              <SettingsRow theme={t}
                icon={<Icons.Folder size={17} color="#fff" stroke={1.8}/>}
                color="#7c6ad6" title="OPDS catalogs" value="3" last/>
            </div>
          </div>

          {/* THE section under design */}
          <Variant theme={t} aiOn={aiOn} consentOn={consentOn}/>
        </div>
      </Sheet>
    </PhoneFrame>
  );
}

// Bare-rows artboard — surfaces the individual SettingsToggleRow up close so
// the row treatment can be evaluated on its own, free of sheet/chrome.
function ToggleRowSpecArtboard({ themeKey }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: PHONE_W, padding: 24, background: t.bg,
      borderRadius: 18, position: 'relative',
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.35)',
    }}>
      <SectionLabel theme={t}>AI · master toggle</SectionLabel>
      <div style={{
        marginTop: 8, marginBottom: 22, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <SettingsToggleRow theme={t}
          icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
          color="#8c2f2f"
          title="Enable AI Assistant"
          detail="Translation, summarize, ask about the text"
          on={false} last/>
      </div>

      <SectionLabel theme={t}>AI · master toggle, on</SectionLabel>
      <div style={{
        marginTop: 8, marginBottom: 22, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <SettingsToggleRow theme={t}
          icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
          color="#8c2f2f"
          title="Enable AI Assistant"
          detail="Translation, summarize, ask about the text"
          on={true} last/>
      </div>

      <SectionLabel theme={t}>Consent toggle</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <SettingsToggleRow theme={t}
          icon={<ShieldIcon size={17} color="#fff" stroke={1.8}/>}
          color="#4a6a8a"
          title="Allow AI data sharing"
          detail="Send passages and chat history for better answers"
          on={false}/>
        <SettingsToggleRow theme={t}
          icon={<ShieldIcon size={17} color="#fff" stroke={1.8}/>}
          color="#4a6a8a"
          title="Allow AI data sharing"
          detail="Send passages and chat history for better answers"
          on={true} last/>
      </div>
    </div>
  );
}

// ════════════════════════════════════════════════════
// CanvasRoot
// ════════════════════════════════════════════════════
function CanvasRoot() {
  return (
    <DesignCanvas>
      {/* ───── Specimen — the bare row treatment ───── */}
      <DCSection id="spec" title="#1068 — Row specimen"
        subtitle="The two new row types in isolation: colored tile + PillSwitch trail. Same vocabulary as the AI Provider row WI-5 shipped (#8c2f2f sparkle), extended with a shield tile (#4a6a8a) for the privacy switch.">
        <DCArtboard id="spec-paper" label="Specimen · paper" width={PHONE_W} height={560}>
          <ToggleRowSpecArtboard themeKey="paper"/>
        </DCArtboard>
        <DCArtboard id="spec-dark" label="Specimen · dark" width={PHONE_W} height={560}>
          <ToggleRowSpecArtboard themeKey="dark"/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={240}>
          <strong>Why a shield tile in this color?</strong><br/>
          #4a6a8a lives next to the existing Cloud (#3a8ac8) and Folder (#7c6ad6) in the cool-blue family — reads as "system / safety" the same way #8c2f2f reads as "AI / energy".
        </DCPostIt>
      </DCSection>

      {/* ───── Variant A — canonical ───── */}
      <DCSection id="vA" title="A · Tile-parity (canonical)"
        subtitle="Both toggles live as SettingsToggleRows inside the existing AI group, peers of the AI Provider row. Simplest fit for the surrounding vocabulary. When AI is off the peer rows are hidden, not greyed.">
        <DCArtboard id="A-off" label="AI off (default)" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="A" aiOn={false} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="A-on-cons-off" label="AI on · consent off" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="A" aiOn={true} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="A-on-cons-on" label="AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="A" aiOn={true} consentOn={true}/>
        </DCArtboard>
        <DCArtboard id="A-dark" label="Dark · AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="dark" variant="A" aiOn={true} consentOn={true}/>
        </DCArtboard>
      </DCSection>

      {/* ───── Variant B — master in header ───── */}
      <DCSection id="vB" title="B · Master-as-section-header"
        subtitle="“Enable AI Assistant” gets promoted into the section label as an inline switch. The gate isn’t a peer of what it gates — strongest hierarchy. Off state shows a one-line caption instead of empty space.">
        <DCArtboard id="B-off" label="AI off" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="B" aiOn={false} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="B-on-cons-off" label="AI on · consent off" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="B" aiOn={true} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="B-on-cons-on" label="AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="B" aiOn={true} consentOn={true}/>
        </DCArtboard>
        <DCArtboard id="B-dark" label="Dark · AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="dark" variant="B" aiOn={true} consentOn={true}/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={-2} width={240}>
          <strong>Trade-off:</strong> visually distinguishes the gate, but breaks the "every section header is just a label" rule used everywhere else in Settings. Adopt only if we'd also section-gate Cloud & Sync.
        </DCPostIt>
      </DCSection>

      {/* ───── Variant C — privacy callout ───── */}
      <DCSection id="vC" title="C · Privacy-callout consent"
        subtitle="When AI is on, the consent toggle moves out of the AI group into its own Data & Privacy section, presented as a card with an explicit two-column body that names what leaves the device and what stays local. Heavier disclosure for the consent moment.">
        <DCArtboard id="C-off" label="AI off" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="C" aiOn={false} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="C-on-cons-off" label="AI on · consent off" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="C" aiOn={true} consentOn={false}/>
        </DCArtboard>
        <DCArtboard id="C-on-cons-on" label="AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="paper" variant="C" aiOn={true} consentOn={true}/>
        </DCArtboard>
        <DCArtboard id="C-dark" label="Dark · AI on · consent on" width={PHONE_W} height={720}>
          <SettingsAIArtboard themeKey="dark" variant="C" aiOn={true} consentOn={true}/>
        </DCArtboard>
        <DCPostIt top={-30} right={40} rotate={2} width={240}>
          <strong>Recommendation:</strong> ship A — peer-parity with the row WI-5 shipped, lowest implementation cost (just one new SettingsToggleRow variant + a Shield SF symbol). Hold C in reserve if the consent discussion in #67 surfaces stronger transparency requirements.
        </DCPostIt>
      </DCSection>
    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot });
