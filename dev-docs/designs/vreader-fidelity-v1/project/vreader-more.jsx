// More-menu popover — anchored to the "..." button in reader top chrome.
// Issue #760: design the contents of the More menu.

function MorePopover({ theme, state, onToggle, onAction, onClose }) {
  const t = theme;
  const s = state || {};

  const Row = ({ icon, label, sub, value, toggle, active, danger, divider, on }) => {
    if (divider) {
      return <div style={{
        height: 0.5, background: t.rule, margin: '4px 14px',
      }}/>;
    }
    const Ico = icon;
    return (
      <button onClick={on} style={{
        display: 'flex', alignItems: 'center', gap: 12,
        padding: '11px 14px', width: '100%', border: 'none',
        background: 'transparent', cursor: 'pointer', textAlign: 'left',
      }}>
        <div style={{
          width: 28, height: 28, borderRadius: 8,
          background: active
            ? (t.isDark ? `${t.accent}33` : `${t.accent}1a`)
            : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexShrink: 0,
        }}>
          <Ico size={15} color={active ? t.accent : t.ink} stroke={1.7}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontSize: 14.5, color: danger ? '#c44' : t.ink,
            fontWeight: 500, lineHeight: 1.2,
          }}>{label}</div>
          {sub && (
            <div style={{
              fontSize: 11, color: t.sub, marginTop: 2, lineHeight: 1.2,
            }}>{sub}</div>
          )}
        </div>
        {toggle !== undefined && (
          <ToggleSwitch on={!!toggle} theme={t}/>
        )}
        {value && (
          <span style={{ fontSize: 12, color: t.sub, marginRight: 2 }}>{value}</span>
        )}
        {!toggle && value === undefined && (
          <Icons.Chevron size={13} color={t.sub} stroke={2}/>
        )}
      </button>
    );
  };

  return (
    <>
      {/* dim backdrop */}
      <div onClick={onClose} style={{
        position: 'absolute', inset: 0, zIndex: 70,
        background: 'transparent',
      }}/>
      {/* popover */}
      <div style={{
        position: 'absolute', top: 92, right: 14, zIndex: 75,
        width: 268, borderRadius: 16,
        background: t.isDark ? '#2a2724' : '#fcf8f0',
        boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        padding: '6px 0', overflow: 'hidden',
      }}>
        {/* notch pointing to ... button */}
        <div style={{
          position: 'absolute', top: -6, right: 24,
          width: 12, height: 12, transform: 'rotate(45deg)',
          background: t.isDark ? '#2a2724' : '#fcf8f0',
          boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}/>

        <Row icon={Icons.Volume} label="Read aloud"
             sub={s.ttsPlaying ? 'Playing · System voice' : 'Start text-to-speech'}
             active={s.ttsPlaying}
             on={() => onAction('tts')}/>

        <Row icon={Icons.Timer} label="Auto-turn pages"
             sub={s.autoTurn ? `Every ${s.autoTurnInterval || 30}s` : 'Off'}
             toggle={s.autoTurn}
             active={s.autoTurn}
             on={() => onToggle('autoTurn')}/>

        <Row icon={Icons.Translate} label="Bilingual mode"
             sub={s.bilingual ? `English ↔ ${s.bilingualLang || 'Chinese'}` : 'Translate inline'}
             toggle={s.bilingual}
             active={s.bilingual}
             on={() => onToggle('bilingual')}/>

        <Row divider/>

        <Row icon={Icons.Info} label="Book details"
             on={() => onAction('details')}/>

        <Row icon={Icons.Share} label="Share book"
             on={() => onAction('share')}/>

        <Row icon={Icons.Download} label="Export annotations"
             sub="Markdown · JSON · VReader JSON"
             on={() => onAction('export')}/>
      </div>
    </>
  );
}

// Tiny iOS-style toggle
function ToggleSwitch({ on, theme }) {
  const t = theme;
  return (
    <div style={{
      width: 34, height: 20, borderRadius: 10, position: 'relative',
      background: on ? '#3a6a5a' : (t.isDark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.12)'),
      transition: 'background 0.15s',
      flexShrink: 0,
    }}>
      <div style={{
        position: 'absolute', top: 2, left: on ? 16 : 2,
        width: 16, height: 16, borderRadius: 8, background: '#fff',
        transition: 'left 0.15s',
        boxShadow: '0 1px 2px rgba(0,0,0,0.2), 0 0.5px 0 rgba(0,0,0,0.06)',
      }}/>
    </div>
  );
}

Object.assign(window, { MorePopover });
