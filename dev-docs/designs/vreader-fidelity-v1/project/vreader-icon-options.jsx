// VReader app icon options — six directions
// Each <Icon*> renders into a 1024×1024 viewBox; the wrapper crops to a macOS squircle.

// ─── Squircle clip (macOS / iOS ~22.5%) ──────────────────────
function SquircleFrame({ size, children, bg, label }) {
  // Apple icon corner radius ≈ size * 0.2237 (squircle), we use a CSS-rounded rect approximation
  const r = size * 0.2237;
  return (
    <div style={{
      width: size, height: size, borderRadius: r,
      position: 'relative', overflow: 'hidden',
      background: bg,
      boxShadow: '0 1px 0 rgba(255,255,255,0.6) inset, 0 -1px 0 rgba(0,0,0,0.06) inset, 0 12px 36px rgba(0,0,0,0.18), 0 2px 4px rgba(0,0,0,0.08)',
    }}>
      {children}
    </div>
  );
}

// ─── Shared decorations ──────────────────────────────────────
function PaperGrain({ opacity = 0.4 }) {
  // Tiny SVG noise approximation via radial dots
  return (
    <svg viewBox="0 0 1024 1024" style={{
      position: 'absolute', inset: 0, width: '100%', height: '100%',
      pointerEvents: 'none', opacity, mixBlendMode: 'multiply',
    }}>
      <defs>
        <filter id="grain">
          <feTurbulence type="fractalNoise" baseFrequency="2.5" numOctaves="2" seed="3"/>
          <feColorMatrix values="0 0 0 0 0.2 0 0 0 0 0.15 0 0 0 0 0.08 0 0 0 0.4 0"/>
        </filter>
      </defs>
      <rect width="1024" height="1024" filter="url(#grain)"/>
    </svg>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 1 — Literary Monogram (matches the "classic" cover style)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconLiteraryMonogram({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="linear-gradient(135deg, #f6efde 0%, #ead8b4 100%)">
      <PaperGrain opacity={0.35}/>
      {/* vignette */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse at center, transparent 55%, rgba(60,40,20,0.18) 100%)',
        pointerEvents: 'none',
      }}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        {/* Top hairline rule (like the classic cover) */}
        <line x1="240" y1="220" x2="480" y2="220" stroke="#8c2f2f" strokeWidth="6" opacity="0.85"/>
        {/* Big italic serif V */}
        <text x="512" y="700"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="720" fontWeight="600" fontStyle="italic"
              fill="#3a2913" textAnchor="middle"
              style={{ paintOrder: 'stroke fill', filter: 'drop-shadow(0 4px 0 rgba(0,0,0,0.04))' }}>V</text>
        {/* author-line style */}
        <text x="512" y="850"
              fontFamily='"Source Serif 4", Georgia, serif'
              fontSize="44" letterSpacing="8" fontWeight="500"
              fill="rgba(58,41,19,0.6)" textAnchor="middle">READER</text>
      </svg>
    </SquircleFrame>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 2 — Letterpress (recessed V)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconLetterpress({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="linear-gradient(160deg, #efe4ca 0%, #d8c79b 100%)">
      <PaperGrain opacity={0.55}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <filter id="press" x="-20%" y="-20%" width="140%" height="140%">
            {/* dark inner shadow */}
            <feGaussianBlur in="SourceAlpha" stdDeviation="10"/>
            <feOffset dx="6" dy="10"/>
            <feComposite in2="SourceAlpha" operator="arithmetic" k2="-1" k3="1" result="shadowDiff"/>
            <feFlood floodColor="#3a2410" floodOpacity="0.5"/>
            <feComposite in2="shadowDiff" operator="in"/>
            <feComposite in2="SourceGraphic" operator="over"/>
          </filter>
          <linearGradient id="vfill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#6e2222"/>
            <stop offset="1" stopColor="#8c2f2f"/>
          </linearGradient>
        </defs>
        {/* recessed V — dark fill + subtle inset */}
        <text x="512" y="710"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="780" fontWeight="700" fontStyle="italic"
              fill="url(#vfill)" textAnchor="middle"
              filter="url(#press)">V</text>
        {/* highlight ridge along top of V */}
        <text x="512" y="710"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="780" fontWeight="700" fontStyle="italic"
              fill="none" stroke="rgba(255,255,255,0.18)" strokeWidth="2"
              textAnchor="middle" style={{ transform: 'translate(-2px, -3px)', transformOrigin: 'center' }}>V</text>
      </svg>
    </SquircleFrame>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 3 — Open Pages (V formed by two angled book pages)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconOpenPages({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="#8c2f2f">
      {/* deep oxblood background w/ subtle gradient */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'radial-gradient(ellipse at 40% 30%, #a13838 0%, #8c2f2f 50%, #6e2222 100%)',
      }}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="pageL" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor="#fcf8ec"/>
            <stop offset="1" stopColor="#e8d9b8"/>
          </linearGradient>
          <linearGradient id="pageR" x1="1" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#fcf8ec"/>
            <stop offset="1" stopColor="#e8d9b8"/>
          </linearGradient>
        </defs>
        {/* left page */}
        <path d="M 200 280 L 510 260 L 510 820 L 200 740 Z"
              fill="url(#pageL)"/>
        {/* right page */}
        <path d="M 514 260 L 824 280 L 824 740 L 514 820 Z"
              fill="url(#pageR)"/>
        {/* center fold shadow */}
        <path d="M 510 260 L 510 820 L 514 820 L 514 260 Z" fill="rgba(0,0,0,0.12)"/>
        <path d="M 480 264 L 510 260 L 510 820 L 480 818 Z" fill="rgba(0,0,0,0.04)"/>
        <path d="M 514 260 L 544 264 L 544 818 L 514 820 Z" fill="rgba(0,0,0,0.04)"/>
        {/* text lines, left */}
        {[420, 480, 540, 600, 660].map(y => (
          <line key={y} x1="250" y1={y - (y-540)*0.04} x2="470" y2={y - (y-540)*0.04 + 4}
                stroke="rgba(58,41,19,0.35)" strokeWidth="6"/>
        ))}
        {/* text lines, right */}
        {[420, 480, 540, 600, 660].map(y => (
          <line key={y} x1="554" y1={y - (540-y)*0.04 + 4} x2="774" y2={y - (540-y)*0.04}
                stroke="rgba(58,41,19,0.35)" strokeWidth="6"/>
        ))}
        {/* page edges hairline */}
        <path d="M 200 280 L 510 260 L 824 280" fill="none" stroke="rgba(0,0,0,0.18)" strokeWidth="2"/>
      </svg>
    </SquircleFrame>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 4 — Book Spine (foiled monogram on cloth)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconBookSpine({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="#3a2113">
      {/* cloth gradient */}
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(180deg, #4a2a18 0%, #2a160a 100%)',
      }}/>
      {/* cloth texture lines */}
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0, opacity: 0.25 }}>
        {Array.from({length: 50}).map((_, i) => (
          <line key={i} x1="0" y1={i * 22} x2="1024" y2={i * 22}
                stroke="rgba(255,230,200,0.15)" strokeWidth="0.6"/>
        ))}
        {Array.from({length: 24}).map((_, i) => (
          <line key={`v${i}`} x1={i * 44} y1="0" x2={i * 44} y2="1024"
                stroke="rgba(0,0,0,0.18)" strokeWidth="0.6"/>
        ))}
      </svg>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="gold" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#e8c878"/>
            <stop offset="0.5" stopColor="#c79b52"/>
            <stop offset="1" stopColor="#8a6a30"/>
          </linearGradient>
          <linearGradient id="goldShine" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="rgba(255,240,200,0.7)"/>
            <stop offset="0.4" stopColor="rgba(255,240,200,0)"/>
          </linearGradient>
        </defs>
        {/* top + bottom horizontal bands (raised bands) */}
        <rect x="0" y="180" width="1024" height="14" fill="rgba(0,0,0,0.35)"/>
        <rect x="0" y="180" width="1024" height="3" fill="rgba(255,230,200,0.18)"/>
        <rect x="0" y="830" width="1024" height="14" fill="rgba(0,0,0,0.35)"/>
        <rect x="0" y="830" width="1024" height="3" fill="rgba(255,230,200,0.18)"/>
        {/* gilt-foil V */}
        <text x="512" y="690"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="640" fontWeight="700"
              fill="url(#gold)" textAnchor="middle"
              style={{ filter: 'drop-shadow(0 2px 0 rgba(0,0,0,0.4))' }}>V</text>
        {/* shine sweep */}
        <text x="512" y="690"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="640" fontWeight="700"
              fill="url(#goldShine)" textAnchor="middle"
              clipPath="inset(0 0 60% 0)">V</text>
      </svg>
    </SquircleFrame>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 5 — Modern Solid (oxblood field, ivory V)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconModernSolid({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="#8c2f2f">
      <div style={{
        position: 'absolute', inset: 0,
        background: 'linear-gradient(160deg, #a13838 0%, #8c2f2f 50%, #6e2222 100%)',
      }}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        <text x="512" y="700"
              fontFamily='"Source Serif 4", "EB Garamond", Georgia, serif'
              fontSize="720" fontWeight="600" fontStyle="italic"
              fill="#fcf8ec" textAnchor="middle">V</text>
        {/* tiny accent dot under the V — like a colophon */}
        <circle cx="512" cy="800" r="6" fill="#fcf8ec" opacity="0.85"/>
      </svg>
    </SquircleFrame>
  );
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Option 6 — Folded Bookmark (V is a folded ribbon)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
function IconBookmark({ size = 1024 }) {
  return (
    <SquircleFrame size={size} bg="linear-gradient(135deg, #f6efde 0%, #e0caa0 100%)">
      <PaperGrain opacity={0.4}/>
      <svg viewBox="0 0 1024 1024" style={{ position: 'absolute', inset: 0 }}>
        <defs>
          <linearGradient id="ribbon" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#a23838"/>
            <stop offset="1" stopColor="#7a2424"/>
          </linearGradient>
          <linearGradient id="ribbonInner" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#6e2020"/>
            <stop offset="1" stopColor="#4a1414"/>
          </linearGradient>
        </defs>
        {/* shadow under the ribbon */}
        <ellipse cx="512" cy="780" rx="240" ry="22" fill="rgba(0,0,0,0.18)"/>
        {/* ribbon left half */}
        <path d="M 290 200 L 512 200 L 512 800 L 460 720 L 290 800 Z"
              fill="url(#ribbon)"/>
        {/* ribbon right half */}
        <path d="M 512 200 L 734 200 L 734 800 L 564 720 L 512 800 Z"
              fill="url(#ribbon)"/>
        {/* center fold darker */}
        <path d="M 460 720 L 512 800 L 564 720 L 512 770 Z"
              fill="url(#ribbonInner)"/>
        {/* highlight stripe down the middle of each half */}
        <path d="M 320 220 L 320 760 L 330 770" fill="none"
              stroke="rgba(255,230,220,0.18)" strokeWidth="14"/>
        <path d="M 704 220 L 704 760 L 694 770" fill="none"
              stroke="rgba(255,230,220,0.18)" strokeWidth="14"/>
      </svg>
    </SquircleFrame>
  );
}

Object.assign(window, {
  IconLiteraryMonogram, IconLetterpress, IconOpenPages,
  IconBookSpine, IconModernSolid, IconBookmark,
});
