// In-reader AI Providers entry — issue #1380.
//
// Wires the bilingual setup sheet's "Set up" button (shown when no AI provider
// is configured, per Bug #301) to an actual AI Providers surface — which does
// not exist in-reader today (the reader's showSettings sheet is display/fonts
// only; the full SettingsView with AISettingsSection is Library-only).
//
// CANONICAL (A): a scoped "AI Providers" sheet PUSHED inside the bilingual
//   flow (nav bar: ‹ Bilingual · "AI Providers"), hosting only the provider
//   list. Empty → "Add provider" → the canonical AIProviderEditSheet
//   (vreader-ai-provider-fields.jsx, reused unchanged). On first Save the
//   provider becomes the bilingual engine and the stack pops back to Bilingual,
//   whose engine strip now reads "configured / Change…".
//
// ALTERNATIVES shown for comparison:
//   B — deep-link into the full SettingsView, scrolled to the AI section.
//   C — inline expansion of the engine strip inside the bilingual sheet.
//
// Reuses: Sheet vocabulary, SectionLabel, Icons, THEMES tokens. The provider
// tile keeps the fixed #8c2f2f brand color used by the shipped AI Provider row.

const AIPE_BRAND = '#8c2f2f';           // AI provider tile (theme-independent)
const AIPE_MONO  = 'ui-monospace, "SF Mono", "Menlo", monospace';
const AIPE_SERIF = '"Source Serif 4", Georgia, serif';

// ────────────────────────────────────────────────────
// NavSheet — bottom sheet with an iOS-style navigation bar (back + centered
// title + trailing). This is the "push within the sheet" presentation: same
// grabber + frame as Sheet, but a real back affordance instead of a grabber-
// only modal. Title is absolutely centered so a wide back label can't shove it.
// ────────────────────────────────────────────────────
function NavSheet({ theme, height = 620, title, backLabel = 'Bilingual', onBack, trailing, children }) {
  const t = theme || THEMES.paper;
  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 200,
      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
      background: 'rgba(0,0,0,0.35)',
    }}>
      <div style={{
        background: t.isDark ? '#222020' : '#fcf8f0',
        height, borderTopLeftRadius: 22, borderTopRightRadius: 22,
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
          position: 'relative', display: 'flex', alignItems: 'center',
          padding: '13px 16px 12px',
          borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
        }}>
          <button onClick={onBack} style={{
            display: 'flex', alignItems: 'center', gap: 1, zIndex: 1,
            background: 'none', border: 'none', padding: 0, cursor: 'pointer',
            color: t.accent, fontFamily: 'inherit', fontSize: 15, fontWeight: 500,
            whiteSpace: 'nowrap',
          }}>
            <Icons.ChevronL size={19} color={t.accent} stroke={2.2}/>
            <span>{backLabel}</span>
          </button>
          <div style={{
            position: 'absolute', left: 0, right: 0, textAlign: 'center',
            fontFamily: AIPE_SERIF, fontSize: 17, fontWeight: 600, color: t.ink,
            pointerEvents: 'none',
          }}>{title}</div>
          <div style={{ marginLeft: 'auto', zIndex: 1 }}>{trailing}</div>
        </div>
        <div style={{ flex: 1, overflow: 'auto' }} className="hide-scroll">{children}</div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Bilingual engine strip — standalone replica of the strip inside
// BilingualSetupSheet, so the canvas can show the before ("Set up") and after
// ("Change…") states and the flow's payoff. justChanged adds a brief accent
// ring on the freshly-configured return.
// ────────────────────────────────────────────────────
function BilingualEngineStrip({ theme, configured, providerName = 'Claude', onSetup, justChanged = false }) {
  const t = theme;
  return (
    <div>
      <SectionLabel theme={t}>Translation engine</SectionLabel>
      <div style={{
        marginTop: 8, padding: '12px 14px', borderRadius: 12,
        background: configured ? (t.isDark ? 'rgba(255,255,255,0.04)' : '#fff') : `${t.accent}10`,
        border: configured ? `0.5px solid ${t.rule}` : `0.5px solid ${t.accent}55`,
        boxShadow: justChanged ? `0 0 0 2px ${t.accent}66` : 'none',
        display: 'flex', alignItems: 'center', gap: 12,
        transition: 'box-shadow 0.3s',
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 14, flexShrink: 0,
          background: configured ? `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)` : 'rgba(0,0,0,0.08)',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Sparkle size={14} color={configured ? '#fff' : t.sub} stroke={2}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>
            {configured ? `${providerName} · with this book’s context` : 'No AI provider configured'}
          </div>
          <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
            {configured
              ? 'Translations cached per paragraph, one page ahead.'
              : 'Bilingual mode needs an AI provider to translate.'}
          </div>
        </div>
        <button onClick={onSetup} style={{
          padding: '5px 11px', borderRadius: 100, border: 'none',
          background: configured ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : t.accent,
          color: configured ? t.ink : '#fff',
          fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer',
          flexShrink: 0,
        }}>{configured ? 'Change…' : 'Set up'}</button>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Provider list row — matches the shipped SettingsRow vocabulary.
// ────────────────────────────────────────────────────
function ProviderRow({ theme, name, model, selected, onClick, last }) {
  const t = theme;
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`, cursor: 'pointer',
    }}>
      <div style={{
        width: 30, height: 30, borderRadius: 8, flexShrink: 0, background: AIPE_BRAND,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Icons.Sparkle size={17} color="#fff" stroke={1.8}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 15, color: t.ink }}>{name}</div>
        <div style={{ fontSize: 11, color: t.sub, marginTop: 1, fontFamily: AIPE_MONO }}>{model}</div>
      </div>
      {selected ? (
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, flexShrink: 0 }}>
          <span style={{ fontSize: 10.5, fontWeight: 600, color: t.accent, letterSpacing: 0.4, textTransform: 'uppercase', whiteSpace: 'nowrap' }}>In use</span>
          <Icons.Check size={16} color={t.accent} stroke={2.6}/>
        </div>
      ) : (
        <Icons.Chevron size={13} color={t.sub} stroke={2}/>
      )}
    </div>
  );
}

// ────────────────────────────────────────────────────
// AI Providers sheet body — empty + populated.
// ────────────────────────────────────────────────────
function AIProvidersSheetBody({ theme, providers, selectedId, onAdd, onSelect }) {
  const t = theme;
  const empty = !providers || providers.length === 0;
  return (
    <div style={{ padding: '14px 18px 28px' }}>
      {/* why-you're-here context — the bilingual thread, kept visible */}
      <div style={{
        display: 'flex', alignItems: 'center', gap: 10,
        padding: '10px 12px', borderRadius: 10,
        background: `${t.accent}10`, border: `0.5px solid ${t.accent}33`,
        marginBottom: 18,
      }}>
        <div style={{
          width: 22, height: 22, borderRadius: 11, flexShrink: 0,
          background: `${t.accent}1f`, display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <Icons.Translate size={13} color={t.accent} stroke={1.9}/>
        </div>
        <div style={{ fontSize: 11.5, color: t.ink, lineHeight: 1.35 }}>
          Choose the provider <b style={{ fontWeight: 600 }}>bilingual mode</b> will use to translate this book.
        </div>
      </div>

      {empty ? (
        <div style={{ textAlign: 'center', padding: '24px 12px 8px' }}>
          <div style={{
            width: 54, height: 54, borderRadius: 27, margin: '0 auto 14px',
            background: `linear-gradient(135deg, ${t.accent}, ${t.accent}aa)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            boxShadow: `0 6px 18px ${t.accent}44`,
          }}>
            <Icons.Sparkle size={26} color="#fff" stroke={1.7}/>
          </div>
          <div style={{ fontFamily: AIPE_SERIF, fontSize: 18, fontWeight: 600, color: t.ink }}>
            No providers yet
          </div>
          <div style={{ fontSize: 12.5, color: t.sub, lineHeight: 1.5, maxWidth: 268, margin: '6px auto 20px' }}>
            Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.
          </div>
          <button onClick={onAdd} style={{
            display: 'inline-flex', alignItems: 'center', gap: 7,
            padding: '11px 20px', borderRadius: 100, border: 'none',
            background: t.accent, color: '#fff',
            fontFamily: 'inherit', fontSize: 14, fontWeight: 600, cursor: 'pointer',
            boxShadow: `0 4px 14px ${t.accent}55`,
          }}>
            <Icons.Plus size={17} color="#fff" stroke={2.2}/>Add provider
          </button>
        </div>
      ) : (
        <div>
          <SectionLabel theme={t}>Providers</SectionLabel>
          <div style={{
            marginTop: 8, borderRadius: 14, overflow: 'hidden',
            background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
          }}>
            {providers.map((p) => (
              <ProviderRow key={p.id} theme={t} name={p.name} model={p.model}
                selected={p.id === selectedId} onClick={() => onSelect && onSelect(p.id)}/>
            ))}
            <div onClick={onAdd} style={{
              display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px', cursor: 'pointer',
            }}>
              <div style={{
                width: 30, height: 30, borderRadius: 8, flexShrink: 0,
                background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <Icons.Plus size={18} color={t.accent} stroke={2.2}/>
              </div>
              <div style={{ flex: 1, fontSize: 15, color: t.accent, fontWeight: 500 }}>Add provider</div>
            </div>
          </div>
          <div style={{ fontSize: 11.5, color: t.sub, lineHeight: 1.45, padding: '10px 4px 0' }}>
            Tap a provider to use it for translating this book.
          </div>
        </div>
      )}
    </div>
  );
}

function AIProvidersSheet({ theme, providers = [], selectedId, onBack, onAdd, onSelect, trailing, height = 620 }) {
  return (
    <NavSheet theme={theme} height={height} title="AI Providers" backLabel="Bilingual" onBack={onBack} trailing={trailing}>
      <AIProvidersSheetBody theme={theme} providers={providers} selectedId={selectedId} onAdd={onAdd} onSelect={onSelect}/>
    </NavSheet>
  );
}

// ────────────────────────────────────────────────────
// ALTERNATIVE C — inline expansion of the engine strip.
// Collapsed = the unconfigured strip; expanded = a minimal provider+key form
// in place. Shows why it can't host the real editor without diverging.
// ────────────────────────────────────────────────────
function EngineStripInline({ theme, expanded }) {
  const t = theme;
  const seg = ['Claude', 'OpenAI', 'Custom'];
  return (
    <div>
      <SectionLabel theme={t}>Translation engine</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 12, overflow: 'hidden',
        background: `${t.accent}10`, border: `0.5px solid ${t.accent}55`,
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '12px 14px' }}>
          <div style={{
            width: 28, height: 28, borderRadius: 14, flexShrink: 0, background: 'rgba(0,0,0,0.08)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <Icons.Sparkle size={14} color={t.sub} stroke={2}/>
          </div>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ fontSize: 13.5, color: t.ink, fontWeight: 600 }}>No AI provider configured</div>
            <div style={{ fontSize: 11.5, color: t.sub, marginTop: 1 }}>
              {expanded ? 'Add one below to translate.' : 'Bilingual mode needs an AI provider to translate.'}
            </div>
          </div>
          <button style={{
            padding: '5px 11px', borderRadius: 100, border: 'none',
            background: expanded ? (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)') : t.accent,
            color: expanded ? t.ink : '#fff',
            fontFamily: 'inherit', fontSize: 11.5, fontWeight: 600, cursor: 'pointer', flexShrink: 0,
          }}>{expanded ? 'Cancel' : 'Set up'}</button>
        </div>

        {expanded && (
          <div style={{ padding: '4px 14px 14px', borderTop: `0.5px solid ${t.accent}22` }}>
            <div style={{
              display: 'flex', marginTop: 12, borderRadius: 10, padding: 3,
              background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
            }}>
              {seg.map((s, i) => (
                <div key={s} style={{
                  flex: 1, textAlign: 'center', padding: '7px 4px', borderRadius: 8,
                  fontSize: 12.5, fontWeight: i === 0 ? 600 : 500, color: t.ink,
                  background: i === 0 ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                  boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
                }}>{s}</div>
              ))}
            </div>
            <div style={{
              marginTop: 10, padding: '10px 12px', borderRadius: 10,
              background: t.isDark ? 'rgba(255,255,255,0.05)' : '#fff',
              border: `0.5px solid ${t.rule}`,
              display: 'flex', alignItems: 'center',
            }}>
              <span style={{ fontSize: 13.5, color: t.sub, flexShrink: 0, marginRight: 10 }}>API Key</span>
              <span style={{ flex: 1 }}/>
              <span style={{ fontSize: 13.5, color: t.sub, opacity: 0.6 }}>sk-…</span>
              <span style={{ width: 2, height: 16, background: t.accent, marginLeft: 2, borderRadius: 1 }}/>
            </div>
            <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
              <button style={{
                flex: 1, padding: '9px 0', borderRadius: 10, border: `0.5px solid ${t.accent}55`,
                background: 'transparent', color: t.accent, fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer',
              }}>Test</button>
              <button style={{
                flex: 1, padding: '9px 0', borderRadius: 10, border: 'none',
                background: t.accent, color: '#fff', fontFamily: 'inherit', fontSize: 13, fontWeight: 600, cursor: 'pointer',
              }}>Add</button>
            </div>
            <div style={{ fontSize: 10.5, color: t.sub, lineHeight: 1.4, marginTop: 8, fontStyle: 'italic' }}>
              No base-URL, model, sampling, or saved-key management here — this strips the real editor down.
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// ALTERNATIVE B — full SettingsView deep-link. A compact rendering of the
// whole app-settings list with the AI group ringed + a "from bilingual" tag,
// to show the heaviness of dropping the reader into all of Settings.
// ────────────────────────────────────────────────────
function FullSettingsDeepLink({ theme }) {
  const t = theme;
  const Group = ({ header, items, highlight }) => (
    <div style={{ marginBottom: 16, position: 'relative' }}>
      <SectionLabel theme={t}>{header}</SectionLabel>
      {highlight && (
        <div style={{
          position: 'absolute', right: 0, top: -2,
          fontSize: 9.5, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase',
          color: t.accent, background: `${t.accent}18`, borderRadius: 5, padding: '2px 6px',
        }}>from bilingual</div>
      )}
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: highlight ? `0 0 0 2px ${t.accent}` : (t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)'),
      }}>
        {items.map((it, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 12, padding: '11px 14px',
            borderBottom: i === items.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
          }}>
            <div style={{
              width: 28, height: 28, borderRadius: 7, flexShrink: 0, background: it.color,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{it.icon}</div>
            <div style={{ flex: 1, fontSize: 14.5, color: t.ink }}>{it.title}</div>
            {it.value && <div style={{ fontSize: 13, color: t.sub, marginRight: 4 }}>{it.value}</div>}
            <Icons.Chevron size={12} color={t.sub} stroke={2}/>
          </div>
        ))}
      </div>
    </div>
  );
  const ic = (C, p = {}) => <C size={15} color="#fff" stroke={1.8} {...p}/>;
  return (
    <Sheet theme={t} title="Settings" height={640}
      leading={<span style={{ fontSize: 15, color: t.accent }}>Done</span>}>
      <div style={{ padding: '14px 18px 28px' }}>
        <Group header="Cloud & Sync" items={[
          { icon: ic(Icons.Cloud), color: '#3a8ac8', title: 'WebDAV backup', value: 'On' },
          { icon: ic(Icons.Folder), color: '#7c6ad6', title: 'OPDS catalogs', value: '3' },
          { icon: ic(Icons.Library), color: '#3a6a5a', title: 'Book sources', value: '12' },
        ]}/>
        <Group header="AI" highlight items={[
          { icon: ic(Icons.Sparkle), color: AIPE_BRAND, title: 'AI provider', value: 'Set up' },
          { icon: ic(Icons.Translate), color: '#c87a3a', title: 'Translation languages', value: '9' },
        ]}/>
        <Group header="Reading" items={[
          { icon: ic(Icons.Volume), color: '#3a3a8c', title: 'Text-to-speech' },
          { icon: ic(Icons.Note), color: '#a8804a', title: 'Replacement rules', value: '5' },
        ]}/>
      </div>
    </Sheet>
  );
}

Object.assign(window, {
  NavSheet, BilingualEngineStrip, ProviderRow,
  AIProvidersSheetBody, AIProvidersSheet,
  EngineStripInline, FullSettingsDeepLink,
});
