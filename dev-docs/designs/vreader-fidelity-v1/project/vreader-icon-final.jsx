// VReader Icon — Literary Monogram (final)
//
// Two variants:
//   IconFull   — paper, rule, italic V, "READER" caption. Used 256px and up.
//   IconSmall  — paper + italic V only. Used below 256px.
//
// All sizing is proportional to the requested px so the icon renders crisp
// at any resolution; SVG text inherits viewBox scaling.

function VReaderIcon({ size = 1024, variant = 'auto', radius }) {
  const useSmall = variant === 'small' || (variant === 'auto' && size < 256);
  // macOS / iOS app-icon squircle ≈ 22.37% of side
  const r = radius != null ? radius : size * 0.2237;
  return (
    <div style={{
      width: size, height: size, borderRadius: r,
      position: 'relative', overflow: 'hidden',
      background: 'linear-gradient(135deg, #f6efde 0%, #ead8b4 100%)',
      boxShadow: '0 1px 0 rgba(255,255,255,0.65) inset, 0 -1px 0 rgba(0,0,0,0.05) inset',
    }}>
      {/* paper grain */}
      <svg viewBox="0 0 1024 1024" style={{
        position: 'absolute', inset: 0, width: '100%', height: '100%',
        pointerEvents: 'none', mixBlendMode: 'multiply',
        opacity: useSmall ? 0.28 : 0.36,
      }}>
        <defs>
          <filter id={`grain-${size}`}>
            <feTurbulence type="fractalNoise" baseFrequency="2.8" numOctaves="2" seed="3"/>
            <feColorMatrix values="0 0 0 0 0.2 0 0 0 0 0.15 0 0 0 0 0.08 0 0 0 0.42 0"/>
          </filter>
        </defs>
        <rect width="1024" height="1024" filter={`url(#grain-${size})`}/>
      </svg>
      {/* vignette */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse at center, transparent 50%, rgba(60,40,20,0.16) 100%)',
        pointerEvents: 'none',
      }}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0, width: '100%', height: '100%' }}>
        {/* The V — Source Serif 4 italic, dominant */}
        <text
          x="512" y={useSmall ? 730 : 660}
          fontFamily="'Source Serif 4', 'EB Garamond', 'Iowan Old Style', Georgia, serif"
          fontSize={useSmall ? 820 : 700}
          fontWeight="600"
          fontStyle="italic"
          fill="#2a1c0b"
          textAnchor="middle"
        >V</text>

        {!useSmall && (
          <>
            {/* Decorative swelled rule below the V */}
            <line x1="378" y1="730" x2="488" y2="730" stroke="#8c2f2f" strokeWidth="3" strokeLinecap="round" opacity="0.9"/>
            <line x1="536" y1="730" x2="646" y2="730" stroke="#8c2f2f" strokeWidth="3" strokeLinecap="round" opacity="0.9"/>
            {/* Tiny diamond in the middle */}
            <polygon points="512,723 519,730 512,737 505,730" fill="#8c2f2f" opacity="0.95"/>
            {/* caption */}
            <text x="512" y="820"
              fontFamily="'Source Serif 4', Georgia, serif"
              fontSize="40" letterSpacing="10" fontWeight="500"
              fill="rgba(58,41,19,0.6)" textAnchor="middle">READER</text>
          </>
        )}
      </svg>
    </div>
  );
}

// A version with the surrounding drop shadow (for non-OS contexts: dock, home screen).
function VReaderIconShadow({ size = 1024, variant = 'auto' }) {
  return (
    <div style={{
      filter: `drop-shadow(0 ${size * 0.014}px ${size * 0.04}px rgba(0,0,0,0.22))`,
      display: 'inline-block', lineHeight: 0,
    }}>
      <VReaderIcon size={size} variant={variant}/>
    </div>
  );
}

Object.assign(window, { VReaderIcon, VReaderIconShadow });
