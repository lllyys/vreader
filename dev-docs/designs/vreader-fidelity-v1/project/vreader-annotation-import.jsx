// Annotation-import affordance — issue #963 / feature #62 (HighlightsSheet)
//
// The legacy `AnnotationsPanelView` carried a trailing-slot Import button
// (.fileImporter for .json). Feature #62 deletes that panel; HighlightsSheetV3
// keeps an export/share button in its trailing slot but has no import home.
// BookDetailsSheet's Actions card has "Export annotations…" but no Import row.
//
// This pass explores three families:
//
//   A) Trailing slot on HighlightsSheet
//      A1 — overflow (•••) menu holding Share + Import  (RECOMMENDED)
//      A2 — two bare icon buttons side-by-side          (anti-pattern for comparison)
//      A3 — Share stays primary; small Import chip below the title row
//
//   B) BookDetailsSheet Actions card
//      B1 — "Import annotations…" row, paired with the existing Export row
//      B2 — "Manage annotations…" single row → secondary half-sheet w/ import+export
//
//   C) Discoverability extras (compose with A or B; not standalone)
//      C1 — Secondary CTA on HighlightsSheet's empty state ("Import from file")
//
// Plus a post-pick preview sheet ("Import 44 highlights · 12 notes? They will
// be merged into Pride and Prejudice.") — same surface regardless of trigger.
//
// CANONICAL PICK: A1 + C1.
//   • A1 keeps import within reach of the annotations stream — same context
//     where the user lives when migrating from another reader. The Share/Export
//     button does not lose its slot; it just shares the menu.
//   • B1/B2 work but bury import a level deeper. Acceptable as a backstop, not
//     a primary home — most users never open Book Details.
//   • C1 adds first-run discoverability on the empty state; one-line cost.

// ────────────────────────────────────────────────────
// IconUpload — local icon (icons.js has Download but not Upload)
// ────────────────────────────────────────────────────
const IconUpload = ({ size = 16, color = 'currentColor', stroke = 1.7 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <path d="M12 17V4M7 9l5-5 5 5M5 20h14"
      stroke={color} strokeWidth={stroke}
      strokeLinecap="round" strokeLinejoin="round"/>
  </svg>
);

const IconFileJson = ({ size = 16, color = 'currentColor', stroke = 1.7 }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <path d="M7 3h8l4 4v14H7z" stroke={color} strokeWidth={stroke} strokeLinejoin="round"/>
    <path d="M15 3v4h4" stroke={color} strokeWidth={stroke} strokeLinejoin="round"/>
    <path d="M10 13c-1 0-1 2-2 2M14 13c1 0 1 2 2 2" stroke={color} strokeWidth={stroke} strokeLinecap="round"/>
  </svg>
);

// ────────────────────────────────────────────────────
// Shared bits
// ────────────────────────────────────────────────────
function trailingIconBtn(t) {
  return {
    background: 'none', border: 'none', padding: 6,
    cursor: 'pointer', display: 'flex',
  };
}

// Sheet header trailing-slot variants ──────────────────────────────────────

// A1 — overflow (•••) trigger. Mounts a small dropdown menu below it.
function HighlightsSheetTrailingOverflow({ t, open }) {
  return (
    <div style={{ position: 'relative' }}>
      <button style={trailingIconBtn(t)} aria-label="More">
        <Icons.More size={20} color={t.accent} stroke={1.8}/>
      </button>
      {open && (
        <div style={{
          position: 'absolute', top: 32, right: -8, width: 232, zIndex: 20,
          borderRadius: 14, overflow: 'hidden',
          background: t.isDark ? 'rgba(40,38,34,0.98)' : 'rgba(252,248,240,0.98)',
          backdropFilter: 'blur(20px)',
          boxShadow: '0 12px 36px rgba(0,0,0,0.28), 0 0 0 0.5px ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
        }}>
          {/* tiny tip */}
          <div style={{
            position: 'absolute', top: -5, right: 14,
            width: 10, height: 10, transform: 'rotate(45deg)',
            background: t.isDark ? 'rgba(40,38,34,0.98)' : 'rgba(252,248,240,0.98)',
            boxShadow: '-1px -1px 0 0 ' + (t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'),
          }}/>
          <OverflowRow t={t} icon={<Icons.Share size={15} color={t.ink} stroke={1.7}/>}
            label="Share annotations…"
            sub="Markdown · JSON · VReader JSON"/>
          <div style={{ height: 0.5, background: t.rule, margin: '0 0 0 44px' }}/>
          <OverflowRow t={t} icon={<IconUpload size={15} color={t.ink} stroke={1.7}/>}
            label="Import from file…"
            sub="VReader · Readwise · Apple Books"/>
        </div>
      )}
    </div>
  );
}

function OverflowRow({ t, icon, label, sub }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', gap: 12,
      padding: '11px 14px', cursor: 'pointer',
    }}>
      <div style={{
        width: 22, height: 22, flexShrink: 0,
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>{icon}</div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 14, color: t.ink, fontWeight: 500, lineHeight: 1.2 }}>{label}</div>
        {sub && <div style={{
          fontSize: 11, color: t.sub, marginTop: 2,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{sub}</div>}
      </div>
    </div>
  );
}

// A2 — anti-pattern: two bare icon buttons in the 50pt slot. Shown to make
// the crowding argument the issue calls out concrete.
function HighlightsSheetTrailingTwoIcons({ t }) {
  return (
    <div style={{ display: 'flex', gap: 2 }}>
      <button style={trailingIconBtn(t)} aria-label="Import annotations">
        <IconUpload size={18} color={t.accent} stroke={1.8}/>
      </button>
      <button style={trailingIconBtn(t)} aria-label="Share annotations">
        <Icons.Share size={18} color={t.accent} stroke={1.8}/>
      </button>
    </div>
  );
}

// A3 — Share keeps the trailing slot; Import becomes a small "Import…" text
// pill anchored under the filter chips. Less hidden than overflow, more
// surface area than icon-only, but adds visual weight to the chip area.
function ImportPillRow({ t }) {
  return (
    <div style={{ padding: '0 18px 4px', display: 'flex' }}>
      <button style={{
        display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '5px 12px 5px 8px', borderRadius: 100, border: 'none',
        background: 'transparent', color: t.accent, cursor: 'pointer',
        fontFamily: 'inherit', fontSize: 12, fontWeight: 600,
        marginLeft: 'auto',
      }}>
        <IconUpload size={13} color={t.accent} stroke={2}/>
        Import…
      </button>
    </div>
  );
}

// ────────────────────────────────────────────────────
// HighlightsSheet wrapper — copies just enough of V3's shell to host the
// trailing-slot variants. (We could re-export V3 with a trailing prop, but
// inlining keeps each artboard's behaviour visible at the call site.)
// ────────────────────────────────────────────────────
function HighlightsSheetForImport({ theme, variant = 'A1-overflow',
                                    menuOpen = false, filter = 'all',
                                    highlights = SAMPLE_HIGHLIGHTS_PLUS_NOTES,
                                    standalones = SAMPLE_STANDALONE,
                                    onClose }) {
  const t = theme;

  let trailing;
  if (variant === 'A1-overflow')      trailing = <HighlightsSheetTrailingOverflow t={t} open={menuOpen}/>;
  else if (variant === 'A2-twoicons') trailing = <HighlightsSheetTrailingTwoIcons t={t}/>;
  else /* A3-share-only */            trailing = (
    <button style={trailingIconBtn(t)} aria-label="Share annotations">
      <Icons.Share size={18} color={t.accent} stroke={1.8}/>
    </button>
  );

  const counts = {
    all: highlights.length + standalones.length,
    highlights: highlights.length,
    notes: standalones.length + highlights.filter(h => h.note).length,
    bookmarks: 0,
  };

  const stream = filter === 'all'
    ? [...highlights.map(h => ({ ...h, kind: 'highlight' })),
       ...standalones.map(s => ({ ...s, kind: 'standalone' }))].reverse()
    : highlights.map(h => ({ ...h, kind: 'highlight' }));

  return (
    <Sheet theme={t} onClose={onClose} height={680} title="Annotations" trailing={trailing}>
      {/* filter chips */}
      <div style={{ padding: '10px 18px 6px', display: 'flex', gap: 6, overflowX: 'auto' }}
           className="hide-scroll">
        {[
          { k: 'all',        label: 'All' },
          { k: 'highlights', label: 'Highlights' },
          { k: 'notes',      label: 'Notes' },
          { k: 'bookmarks',  label: 'Bookmarks' },
        ].map(o => {
          const active = filter === o.k;
          return (
            <div key={o.k} style={{
              padding: '6px 13px', borderRadius: 100,
              fontSize: 12, fontWeight: 500,
              background: active ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
              color: active ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
              display: 'inline-flex', alignItems: 'center', gap: 6, whiteSpace: 'nowrap',
            }}>
              <span>{o.label}</span>
              <span style={{
                fontSize: 10.5, opacity: 0.7, padding: '1px 5px', borderRadius: 100,
                background: active ? (t.isDark ? 'rgba(0,0,0,0.18)' : 'rgba(255,255,255,0.2)') : 'transparent',
              }}>{counts[o.k]}</span>
            </div>
          );
        })}
      </div>

      {variant === 'A3-pill' && <ImportPillRow t={t}/>}

      <div style={{ padding: '8px 18px 24px' }}>
        {stream.map(item => item.kind === 'standalone'
          ? <StandaloneNoteCard key={item.id} t={t} note={item}/>
          : <HighlightCardV3 key={item.id} t={t} h={item}/>)}
      </div>
    </Sheet>
  );
}

// ────────────────────────────────────────────────────
// C1 — empty-state secondary CTA. Composes with V3's existing EmptyState (cta prop).
// ────────────────────────────────────────────────────
function HighlightsSheetEmpty({ theme, onClose }) {
  const t = theme;
  return (
    <Sheet theme={t} onClose={onClose} height={680} title="Annotations"
      trailing={<HighlightsSheetTrailingOverflow t={t} open={false}/>}>
      <div style={{ padding: '10px 18px 6px', display: 'flex', gap: 6 }}>
        {['All', 'Highlights', 'Notes', 'Bookmarks'].map((label, i) => (
          <div key={label} style={{
            padding: '6px 13px', borderRadius: 100,
            fontSize: 12, fontWeight: 500,
            background: i === 0 ? t.ink : (t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.04)'),
            color: i === 0 ? (t.isDark ? '#1a1815' : '#fcf8f0') : t.ink,
            display: 'inline-flex', alignItems: 'center', gap: 6,
          }}>
            <span>{label}</span>
            <span style={{ fontSize: 10.5, opacity: 0.7 }}>0</span>
          </div>
        ))}
      </div>
      <EmptyStateWithImport t={t}/>
    </Sheet>
  );
}

function EmptyStateWithImport({ t }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column',
      alignItems: 'center', justifyContent: 'center',
      padding: '36px 36px 56px', textAlign: 'center', gap: 14,
    }}>
      <div style={{ width: 96, height: 96, opacity: 0.85 }}>
        <EmptyHighlightsArt t={t}/>
      </div>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 18, fontWeight: 600, color: t.ink, lineHeight: 1.2,
      }}>No highlights or notes yet</div>
      <div style={{
        fontSize: 13, color: t.sub, lineHeight: 1.5, maxWidth: 280, textWrap: 'pretty',
      }}>
        Long-press any passage to highlight or add a note. Or bring your existing notes over from another reader.
      </div>
      <button style={{
        marginTop: 6, display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '8px 14px', borderRadius: 100, border: `1px solid ${t.accent}`,
        background: 'transparent', color: t.accent, cursor: 'pointer',
        fontFamily: 'inherit', fontSize: 12.5, fontWeight: 600,
      }}>
        <IconUpload size={13} color={t.accent} stroke={2}/>
        Import annotations from file…
      </button>
      <div style={{ fontSize: 10.5, color: t.sub, opacity: 0.75, marginTop: 2 }}>
        VReader JSON · Readwise · Apple Books
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// B1 — BookDetailsSheet Actions card with Import row paired with Export
// B2 — Single "Manage annotations…" row → secondary half-sheet
// ────────────────────────────────────────────────────
function BookDetailsActionsCard({ theme, variant = 'B1-paired' }) {
  const t = theme;

  // Re-create the action rows in BookDetails order. The Cover and Share rows
  // are identical to the canonical sheet; only the annotation rows differ.
  const PencilIcon = (p) => (
    <svg width={p.size} height={p.size} viewBox="0 0 24 24" fill="none">
      <path d="M14 4l6 6-11 11H3v-6z" stroke={p.color} strokeWidth={p.stroke || 1.7} strokeLinejoin="round"/>
    </svg>
  );

  return (
    <div>
      <SectionLabel theme={t}>Actions</SectionLabel>
      <div style={{
        marginTop: 8, borderRadius: 14, overflow: 'hidden',
        background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        boxShadow: t.isDark ? 'none' : '0 1px 0 rgba(0,0,0,0.04)',
      }}>
        <BDRow t={t} icon={PencilIcon}     label="Replace cover…"/>
        <BDRow t={t} icon={Icons.Share}    label="Share book…"/>

        {variant === 'B1-paired' && (
          <>
            <BDRow t={t} icon={Icons.Download} label="Export annotations…"
              sub="Markdown · JSON · VReader JSON"/>
            <BDRow t={t} icon={IconUpload}    label="Import annotations…"
              sub="VReader JSON · Readwise · Apple Books"
              accent last/>
          </>
        )}

        {variant === 'B2-combined' && (
          <BDRow t={t} icon={IconFileJson} label="Annotations…"
            sub="Import or export · 47 highlights · 12 notes" last/>
        )}
      </div>
      {variant === 'B1-paired' && (
        <div style={{
          fontSize: 11, color: t.sub, opacity: 0.7, marginTop: 8,
          padding: '0 4px', lineHeight: 1.4,
        }}>
          Imports merge into this book by passage match; existing notes are not overwritten.
        </div>
      )}
    </div>
  );
}

function BDRow({ t, icon: Ico, label, sub, accent, last }) {
  return (
    <button style={{
      display: 'flex', alignItems: 'center', gap: 12, width: '100%',
      padding: '12px 14px', border: 'none', background: 'transparent',
      borderBottom: last ? 'none' : `0.5px solid ${t.rule}`,
      cursor: 'pointer', textAlign: 'left',
    }}>
      <div style={{
        width: 28, height: 28, borderRadius: 8, flexShrink: 0,
        background: accent ? `${t.accent}1a`
                   : (t.isDark ? 'rgba(255,255,255,0.05)' : 'rgba(0,0,0,0.04)'),
        display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <Ico size={14} color={accent ? t.accent : t.ink} stroke={1.7}/>
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 14.5, fontWeight: 500, lineHeight: 1.2,
          color: accent ? t.accent : t.ink,
        }}>{label}</div>
        {sub && <div style={{
          fontSize: 11, color: t.sub, marginTop: 2,
          overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
        }}>{sub}</div>}
      </div>
      <Icons.Chevron size={13} color={t.sub} stroke={2}/>
    </button>
  );
}

// B2 secondary half-sheet — what "Annotations…" opens into.
function ManageAnnotationsHalfSheet({ theme }) {
  const t = theme;
  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      borderRadius: '20px 20px 0 0',
      background: t.isDark ? '#211e1b' : '#f6f0e4',
      boxShadow: '0 -10px 30px rgba(0,0,0,0.25)',
      padding: '12px 0 28px',
      animation: 'slideUp 0.3s cubic-bezier(0.32, 0.72, 0, 1)',
    }}>
      <div style={{
        width: 36, height: 4, borderRadius: 2, margin: '0 auto 14px',
        background: t.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)',
      }}/>
      <div style={{
        padding: '0 22px 16px',
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 18, fontWeight: 600, color: t.ink, letterSpacing: -0.2,
      }}>Annotations</div>

      <div style={{ padding: '0 18px' }}>
        <div style={{
          padding: '12px 14px', borderRadius: 12,
          background: t.isDark ? 'rgba(255,255,255,0.05)' : '#fff',
          marginBottom: 12,
          fontSize: 12, color: t.sub, lineHeight: 1.5,
        }}>
          Pride and Prejudice has <span style={{ color: t.ink, fontWeight: 600 }}>47 highlights</span> and <span style={{ color: t.ink, fontWeight: 600 }}>12 notes</span>.
        </div>

        <div style={{
          borderRadius: 14, overflow: 'hidden',
          background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
        }}>
          <BDRow t={t} icon={Icons.Download} label="Export…"
            sub="Markdown, JSON, or VReader JSON"/>
          <BDRow t={t} icon={IconUpload} label="Import from file…"
            sub="VReader · Readwise · Apple Books" accent last/>
        </div>
      </div>
    </div>
  );
}

// ────────────────────────────────────────────────────
// Post-pick preview / confirm sheet — surfaces what's in the file BEFORE
// merging. Same surface regardless of which entry triggered it.
// ────────────────────────────────────────────────────
function ImportPreviewSheet({ theme, source = 'vreader', sample, error }) {
  const t = theme;
  const sources = {
    vreader:    { label: 'VReader JSON',  fname: 'pride-and-prejudice.vreader.json' },
    readwise:   { label: 'Readwise',      fname: 'readwise-export-2026-05-19.json' },
    apple:      { label: 'Apple Books',   fname: 'apple-books-annotations.json' },
  };
  const s = sources[source];

  return (
    <div style={{
      position: 'absolute', left: 0, right: 0, bottom: 0,
      borderRadius: '20px 20px 0 0',
      background: t.isDark ? '#211e1b' : '#f6f0e4',
      boxShadow: '0 -10px 30px rgba(0,0,0,0.25)',
      padding: '12px 0 28px', maxHeight: '88%',
      animation: 'slideUp 0.3s cubic-bezier(0.32, 0.72, 0, 1)',
    }}>
      <div style={{
        width: 36, height: 4, borderRadius: 2, margin: '0 auto 14px',
        background: t.isDark ? 'rgba(255,255,255,0.15)' : 'rgba(0,0,0,0.15)',
      }}/>

      {/* file header */}
      <div style={{ padding: '0 22px 14px', display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{
          width: 40, height: 40, borderRadius: 10, flexShrink: 0,
          background: `${t.accent}1a`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>
          <IconFileJson size={20} color={t.accent} stroke={1.7}/>
        </div>
        <div style={{ flex: 1, minWidth: 0 }}>
          <div style={{
            fontFamily: '"Source Serif 4", Georgia, serif',
            fontSize: 17, fontWeight: 600, color: t.ink, lineHeight: 1.15,
            textWrap: 'pretty',
          }}>Import annotations</div>
          <div style={{
            fontSize: 11.5, color: t.sub, marginTop: 2,
            fontFamily: '"SF Mono", Menlo, monospace',
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
          }}>{s.fname}</div>
        </div>
        <div style={{
          padding: '3px 9px', borderRadius: 100,
          background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
          fontSize: 10.5, color: t.sub, fontWeight: 600,
          letterSpacing: 0.4, textTransform: 'uppercase',
        }}>{s.label}</div>
      </div>

      {error ? (
        <div style={{ padding: '0 22px 16px' }}>
          <div style={{
            padding: '12px 14px', borderRadius: 12,
            background: '#c44a1a14', border: `1px solid #c44a1a55`,
            fontSize: 12.5, color: '#a43a14', lineHeight: 1.45,
          }}>{error}</div>
        </div>
      ) : (
        <>
          {/* count chips */}
          <div style={{ padding: '0 22px 14px', display: 'flex', gap: 8 }}>
            <CountChip t={t} label="Highlights" value="44" highlight/>
            <CountChip t={t} label="Notes"      value="12"/>
            <CountChip t={t} label="Skipped"    value="3" muted/>
          </div>

          {/* sample list */}
          <div style={{ padding: '0 22px 12px' }}>
            <div style={{
              fontSize: 10.5, color: t.sub, letterSpacing: 0.5,
              textTransform: 'uppercase', fontWeight: 600, marginBottom: 8,
            }}>Preview · first three</div>
            <div style={{
              borderRadius: 12, overflow: 'hidden',
              background: t.isDark ? 'rgba(255,255,255,0.04)' : '#fff',
            }}>
              {(sample || DEFAULT_SAMPLE).map((row, i, a) => (
                <div key={i} style={{
                  padding: '10px 14px',
                  borderBottom: i === a.length - 1 ? 'none' : `0.5px solid ${t.rule}`,
                }}>
                  <div style={{
                    fontSize: 10.5, color: t.sub, marginBottom: 4,
                    display: 'flex', gap: 6, alignItems: 'center',
                  }}>
                    <div style={{
                      width: 8, height: 8, borderRadius: 2,
                      background: row.color || '#f0d25a',
                    }}/>
                    <span>{row.chapter}</span>
                    <span style={{ opacity: 0.5 }}>·</span>
                    <span>p. {row.page}</span>
                  </div>
                  <div style={{
                    fontFamily: '"Source Serif 4", Georgia, serif',
                    fontSize: 13, fontStyle: 'italic', color: t.ink,
                    lineHeight: 1.4,
                    display: '-webkit-box', WebkitLineClamp: 2, WebkitBoxOrient: 'vertical',
                    overflow: 'hidden',
                  }}>"{row.text}"</div>
                </div>
              ))}
            </div>
            <div style={{ fontSize: 11, color: t.sub, marginTop: 8, lineHeight: 1.45 }}>
              Imports merge into <span style={{ color: t.ink, fontWeight: 500 }}>Pride and Prejudice</span> by passage match. Existing notes are not overwritten.
            </div>
          </div>
        </>
      )}

      {/* actions */}
      <div style={{
        padding: '8px 22px 0', display: 'flex', gap: 10,
      }}>
        <button style={{
          flex: 1, padding: '12px 0', borderRadius: 12, border: 'none',
          background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)',
          color: t.ink, fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
          cursor: 'pointer',
        }}>Cancel</button>
        <button style={{
          flex: 1.2, padding: '12px 0', borderRadius: 12, border: 'none',
          background: error ? (t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.06)') : t.accent,
          color: error ? t.sub : '#fff',
          fontFamily: 'inherit', fontSize: 14, fontWeight: 600,
          cursor: error ? 'not-allowed' : 'pointer',
        }}>{error ? 'Import 0 items' : 'Import 56 items'}</button>
      </div>
    </div>
  );
}

function CountChip({ t, label, value, highlight, muted }) {
  return (
    <div style={{
      flex: 1, padding: '10px 12px', borderRadius: 10,
      background: highlight ? `${t.accent}14`
                 : muted ? (t.isDark ? 'rgba(255,255,255,0.03)' : 'rgba(0,0,0,0.025)')
                 : (t.isDark ? 'rgba(255,255,255,0.05)' : '#fff'),
      border: highlight ? `1px solid ${t.accent}30` : `0.5px solid ${t.rule}`,
    }}>
      <div style={{
        fontFamily: '"Source Serif 4", Georgia, serif',
        fontSize: 22, fontWeight: 700, lineHeight: 1,
        color: muted ? t.sub : (highlight ? t.accent : t.ink),
        letterSpacing: -0.5,
      }}>{value}</div>
      <div style={{
        fontSize: 10.5, color: t.sub, marginTop: 4,
        textTransform: 'uppercase', letterSpacing: 0.5, fontWeight: 600,
      }}>{label}</div>
    </div>
  );
}

const DEFAULT_SAMPLE = [
  { color: '#f0d25a', chapter: 'Chapter 1',  page: 1,
    text: 'It is a truth universally acknowledged, that a single man in possession of a good fortune, must be in want of a wife.' },
  { color: '#8cb4e8', chapter: 'Chapter 3',  page: 18,
    text: 'She is tolerable, but not handsome enough to tempt me.' },
  { color: '#e88ca0', chapter: 'Chapter 6',  page: 47,
    text: 'Happiness in marriage is entirely a matter of chance.' },
];

Object.assign(window, {
  HighlightsSheetForImport, HighlightsSheetEmpty,
  HighlightsSheetTrailingOverflow, HighlightsSheetTrailingTwoIcons,
  BookDetailsActionsCard, ManageAnnotationsHalfSheet,
  ImportPreviewSheet, IconUpload, IconFileJson,
});
