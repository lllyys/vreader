// Issue #1068 — Two SettingsView AI-section toggle rows that need a designed
// treatment to match the colored-icon SettingsRow vocabulary shipped in WI-5
// of feature #67.
//
// Rows in scope:
//   • AI Assistant       (master gate — always visible)
//   • Allow AI data sharing  (consent — only visible when AI Assistant is on)
//
// Shared vocabulary (matches existing SettingsRow):
//   30×30 rounded tile · colored bg · white 17px Icons glyph · 15px title ·
//   11px detail subline · trailing PillSwitch instead of value+chevron.

// ────────────────────────────────────────────────────
// Shield icon (privacy) — adds to existing Icons set
// Same chroma/stroke vocabulary as the other line icons.
// ────────────────────────────────────────────────────
const ShieldIcon = ({ size = 17, color = '#fff', stroke = 1.8 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
       stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round">
    <path d="M12 3l8 3v6c0 4.5-3.4 8.4-8 9-4.6-.6-8-4.5-8-9V6z"/>
    <path d="M9 12l2 2 4-4"/>
  </svg>
);

// ────────────────────────────────────────────────────
// SettingsRow — colored-tile nav row (already shipped in WI-5 as
// SettingsIconRow / SettingsRowPalette.aiProvider). Reproduced here for the
// artboards; production uses the canonical SwiftUI version.
// ────────────────────────────────────────────────────
function SettingsRow({ theme: t, icon, color, title, detail, value, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px', borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0,
        background: color, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{icon}</div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, color: t.ink }}>{title}</div>
        {detail && <div style={{ fontSize: 11, color: t.sub, marginTop: 1 }}>{detail}</div>}
      </div>
      {value && <div style={{ fontSize: 14, color: t.sub, marginRight: 4 }}>{value}</div>}
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </div>
  );
}

// ────────────────────────────────────────────────────
// SettingsToggleRow — colored-tile peer of SettingsRow with PillSwitch trail
// ────────────────────────────────────────────────────
function SettingsToggleRow({ theme: t, icon, color, title, detail, on, last, dimmed = false }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '12px 14px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
      opacity: dimmed ? 0.55 : 1,
      transition: 'opacity 0.2s',
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0,
        background: color, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15, color: t.ink }}>{title}</div>
        {detail && (
          <div style={{
            fontSize: 11, color: t.sub, marginTop: 2,
            lineHeight: 1.35,
          }}>{detail}</div>
        )}
      </div>
      <PillSwitch on={!!on} theme={t}/>
    </div>
  );
}

// ────────────────────────────────────────────────────
// VARIANT A — Tile-parity (canonical)
// Both toggles render as SettingsToggleRows inside the same `AI` group as the
// AI Provider row. When AI is off, AI Provider + consent are hidden.
// ────────────────────────────────────────────────────
function AISectionVariantA({ theme: t, aiOn, consentOn }) {
  return (
    <div>
      <SectionLabel theme={t}>AI</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <SettingsToggleRow theme={t}
          icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
          color="#8c2f2f"
          title="Enable AI Assistant"
          detail="Translation, summarize, ask about the text"
          on={aiOn}
          last={!aiOn}/>
        {aiOn && (
          <React.Fragment>
            <SettingsRow theme={t}
              icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
              color="#8c2f2f"
              title="AI provider"
              value="Claude"/>
            <SettingsToggleRow theme={t}
              icon={<ShieldIcon size={17} color="#fff" stroke={1.8}/>}
              color="#4a6a8a"
              title="Allow AI data sharing"
              detail="Send passages and chat history for better answers"
              on={consentOn}
              last/>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// VARIANT B — Master-as-section-header
// "Enable AI Assistant" promoted out of the row group into the section label,
// inline with a PillSwitch. The label *is* the master switch. Clearer
// hierarchy: the gate isn't a peer of what it gates.
// ────────────────────────────────────────────────────
function AISectionVariantB({ theme: t, aiOn, consentOn }) {
  return (
    <div>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 14px 0 4px',
      }}>
        <div style={{
          fontSize: 11, fontWeight: 600, letterSpacing: 0.5,
          textTransform: 'uppercase', color: t.sub,
        }}>AI Assistant</div>
        <PillSwitch on={aiOn} theme={t}/>
      </div>
      {aiOn ? (
        <div style={{
          marginTop: 8, borderRadius: 14, overflow: 'hidden',
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
          boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
        }}>
          <SettingsRow theme={t}
            icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
            color="#8c2f2f"
            title="AI provider"
            value="Claude"/>
          <SettingsToggleRow theme={t}
            icon={<ShieldIcon size={17} color="#fff" stroke={1.8}/>}
            color="#4a6a8a"
            title="Allow AI data sharing"
            detail="Send passages and chat history for better answers"
            on={consentOn}
            last/>
        </div>
      ) : (
        <div style={{
          marginTop: 8, padding: '14px 16px', borderRadius: 14,
          background: t.isDark ? 'rgba(255,255,255,0.025)' : 'rgba(0,0,0,0.025)',
          fontSize: 12.5, lineHeight: 1.45, color: t.sub,
        }}>
          AI features stay off across the whole app — no provider calls, no consent prompt, nothing to configure.
        </div>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// VARIANT C — Privacy-callout consent
// Same canonical "AI Assistant" toggle row as A. When AI is on, the consent
// row is replaced by a card with the toggle pinned top-right and a small
// two-column body that names exactly what leaves vs. what stays local. Heavier
// disclosure suited for a consent moment, lighter chrome the rest of the time.
// ────────────────────────────────────────────────────
function AISectionVariantC({ theme: t, aiOn, consentOn }) {
  return (
    <div>
      <SectionLabel theme={t}>AI</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <SettingsToggleRow theme={t}
          icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
          color="#8c2f2f"
          title="Enable AI Assistant"
          detail="Translation, summarize, ask about the text"
          on={aiOn}
          last={!aiOn}/>
        {aiOn && (
          <SettingsRow theme={t}
            icon={<Icons.Sparkle size={17} color="#fff" stroke={1.8}/>}
            color="#8c2f2f"
            title="AI provider"
            value="Claude"
            last/>
        )}
      </div>

      {aiOn && (
        <div style={{ marginTop: 14 }}>
          <SectionLabel theme={t}>Data &amp; Privacy</SectionLabel>
          <div style={{
            marginTop: 8, padding: '14px 16px 16px', borderRadius: 14,
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
          }}>
            <div style={{ display: 'flex', alignItems: 'flex-start', gap: 12 }}>
              <div style={{
                width: 30, height: 30, borderRadius: 8, flexShrink: 0, marginTop: 1,
                background: '#4a6a8a',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <ShieldIcon size={17} color="#fff" stroke={1.8}/>
              </div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 15, color: t.ink }}>Allow AI data sharing</div>
                <div style={{ fontSize: 11.5, color: t.sub, marginTop: 2, lineHeight: 1.4 }}>
                  Requests carry conversational context so the assistant remembers what you asked about.
                </div>
              </div>
              <PillSwitch on={consentOn} theme={t}/>
            </div>

            <div style={{
              marginTop: 12, paddingTop: 12,
              borderTop: `0.5px solid ${t.rule}`,
              display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 14,
            }}>
              <div>
                <div style={{
                  fontSize: 10, letterSpacing: 0.6, textTransform: 'uppercase',
                  color: t.sub, fontWeight: 600, marginBottom: 4,
                }}>Sent to provider</div>
                <div style={{ fontSize: 12, color: t.ink, lineHeight: 1.5 }}>
                  Selected passages<br/>
                  Active chat thread{consentOn && <br/>}
                  {consentOn && <span>Prior questions in session</span>}
                </div>
              </div>
              <div>
                <div style={{
                  fontSize: 10, letterSpacing: 0.6, textTransform: 'uppercase',
                  color: t.sub, fontWeight: 600, marginBottom: 4,
                }}>Stays on device</div>
                <div style={{ fontSize: 12, color: t.ink, lineHeight: 1.5 }}>
                  Library &amp; reading position<br/>
                  Highlights &amp; notes<br/>
                  Provider API keys
                </div>
              </div>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

Object.assign(window, {
  ShieldIcon,
  SettingsToggleRow,
  AISectionVariantA,
  AISectionVariantB,
  AISectionVariantC,
});
