// Canvas artboards · issue #1517 — TOC filter field for feature #94 (Filterable TOC).
//
// Surface: a search/filter field at the top of the Contents (TOC) sheet
// (TOCSheet.swift). Filters the already-loaded TOC entries by title match —
// case-insensitive, diacritic-folded, CJK-aware substring — so long-TOC books
// (multi-hundred-chapter CJK web novels) are navigable without scrolling.
//
// Distinct from full-text content search (#2/#63), which the existing
// "Open Search" CTA already opens. This is a pure client-side title filter.
//
// Companion to vreader-annotations.jsx → TOCSheetV2. Builds the design bundle
// that unblocks feature #94 implementation.

const TF_PHONE_W = 402;
const TF_PHONE_H = 720;

// ─────────────────────────────────────────────────────
// Sample data
// ─────────────────────────────────────────────────────
// (a) A titled western classic — chapter titles, the simple filter case.
const MOBY_TOC = [
  { ch: 1,  title: 'Loomings',            page: 1 },
  { ch: 2,  title: 'The Carpet-Bag',      page: 9 },
  { ch: 3,  title: 'The Spouter-Inn',     page: 14 },
  { ch: 4,  title: 'The Counterpane',     page: 31 },
  { ch: 5,  title: 'Breakfast',           page: 37 },
  { ch: 6,  title: 'The Street',          page: 40 },
  { ch: 7,  title: 'The Chapel',          page: 43 },
  { ch: 8,  title: 'The Pulpit',          page: 47 },
  { ch: 9,  title: 'The Sermon',          page: 51 },
  { ch: 10, title: 'A Bosom Friend',      page: 60 },
  { ch: 11, title: 'Nightgown',           page: 66 },
  { ch: 12, title: 'Biographical',        page: 69 },
  { ch: 13, title: 'Wheelbarrow',         page: 73 },
  { ch: 14, title: 'Nantucket',           page: 79 },
  { ch: 15, title: 'Chowder',             page: 82 },
  { ch: 16, title: 'The Ship',            page: 86 },
];

// (b) A long CJK web-novel TOC — the real motivation. Hundreds of chapters,
// terse evocative titles, a recurring keyword (剑 "sword") to filter on.
function cn(n) {
  const d = ['零','一','二','三','四','五','六','七','八','九'];
  if (n < 10) return d[n];
  if (n < 20) return '十' + (n % 10 ? d[n % 10] : '');
  if (n < 100) { const t = Math.floor(n / 10), o = n % 10; return d[t] + '十' + (o ? d[o] : ''); }
  const h = Math.floor(n / 100), r = n % 100;
  let s = d[h] + '百';
  if (r === 0) return s;
  if (r < 10) return s + '零' + d[r];
  return s + cn(r);
}
const WUXIA_WORDS = [
  '夜雨入孤城','断剑重铸','残阳如血','故人来信','旧梦惊回','长安一别',
  '风雪夜归人','剑影横江','寒潭照月','古寺钟声','落花满径','惊雷动地',
  '无名之辈','剑冢藏锋','江心独钓','雁回沙塞','青锋出鞘','血诏传檄',
  '问剑山阳','烟波钓徒','铁马冰河','一剑霜寒','空山新雨','残棋未了',
  '紫电青霜','登楼远望','剑试天下','negro','千里走单骑','月下独酌',
];
const WUXIA_TOC = Array.from({ length: 142 }, (_, i) => {
  const n = i + 1;
  const w = WUXIA_WORDS[i % WUXIA_WORDS.length].replace('negro', '快意恩仇');
  return { ch: n, title: `第${cn(n)}章 · ${w}`, page: 1 + n * 6 };
});

// ─────────────────────────────────────────────────────
// Filtering — case-insensitive, diacritic-folded, substring (CJK-safe).
// ─────────────────────────────────────────────────────
function fold(s) {
  return s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '');
}
function matchRanges(title, query) {
  if (!query) return [];
  const ft = fold(title), fq = fold(query);
  const ranges = [];
  let from = 0;
  while (true) {
    const i = ft.indexOf(fq, from);
    if (i === -1) break;
    ranges.push([i, i + fq.length]);
    from = i + fq.length;
  }
  return ranges;
}
function filterToc(toc, query) {
  if (!query) return toc;
  return toc.filter(c => matchRanges(c.title, query).length > 0);
}

// Title with matched runs tinted — the "matched substring treatment".
function HighlightedTitle({ title, query, t, active }) {
  const ranges = matchRanges(title, query);
  if (!ranges.length) {
    return <span style={{ color: active ? t.accent : t.ink }}>{title}</span>;
  }
  const out = [];
  let cur = 0;
  ranges.forEach(([a, b], k) => {
    if (a > cur) out.push(<span key={`p${k}`} style={{ color: active ? t.accent : t.ink }}>{title.slice(cur, a)}</span>);
    out.push(
      <mark key={`m${k}`} style={{
        background: `${t.accent}26`, color: active ? t.accent : t.ink,
        borderRadius: 3, padding: '0 1px', boxShadow: `inset 0 -1px 0 ${t.accent}66`,
      }}>{title.slice(a, b)}</mark>
    );
    cur = b;
  });
  if (cur < title.length) out.push(<span key="end" style={{ color: active ? t.accent : t.ink }}>{title.slice(cur)}</span>);
  return <span>{out}</span>;
}

// ─────────────────────────────────────────────────────
// Phone frame + faded reader backdrop (so the sheet reads as a modal)
// ─────────────────────────────────────────────────────
function TFPhone({ themeKey = 'paper', children }) {
  const t = THEMES[themeKey];
  return (
    <div style={{
      width: TF_PHONE_W, height: TF_PHONE_H, position: 'relative', overflow: 'hidden',
      background: t.bg, borderRadius: 18,
      boxShadow: '0 0 0 1px rgba(255,255,255,0.04), 0 14px 40px rgba(0,0,0,0.32)',
    }}>
      <TFBackdrop theme={t}/>
      {children}
    </div>
  );
}
function TFBackdrop({ theme }) {
  const t = theme;
  return (
    <div style={{ position: 'absolute', inset: 0, opacity: 0.5 }}>
      <div style={{
        height: 44, display: 'flex', alignItems: 'flex-end', justifyContent: 'space-between',
        padding: '0 18px 4px', fontSize: 12, color: t.ink, fontWeight: 600, opacity: 0.7,
      }}>
        <span>9:41</span><span style={{ letterSpacing: 1 }}>•••</span>
      </div>
      <div style={{ padding: '6px 28px 0' }}>
        <div style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 10.5, color: t.sub,
          letterSpacing: 2, textTransform: 'uppercase', textAlign: 'center', marginBottom: 16,
        }}>The Spouter-Inn</div>
        <p style={{
          fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14.5, lineHeight: 1.6,
          color: t.ink, margin: 0, textAlign: 'justify',
        }}>
          Entering that gable-ended Spouter-Inn, you found yourself in a wide,
          low, straggling entry with old-fashioned wainscots, reminding one of
          the bulwarks of some condemned old craft.
        </p>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────
// The Contents sheet — chrome matches Sheet/TOCSheetV2 vocabulary, with the
// new filter field added below the segmented control.
// ─────────────────────────────────────────────────────
function ContentsSheet({
  themeKey = 'paper', bookTitle = 'Moby-Dick', toc = MOBY_TOC, currentCh = 3,
  query = '', focused = false, showCancel = false, noToc = false,
  scrollTop = 0, height = 640,
}) {
  const t = THEMES[themeKey];
  const matches = filterToc(toc, query);
  const filtering = query.length > 0;
  const currentVisible = matches.some(c => c.ch === currentCh);
  const pinCurrent = filtering && !currentVisible && !noToc;
  const currentEntry = toc.find(c => c.ch === currentCh);

  return (
    <div style={{
      position: 'absolute', inset: 0, zIndex: 200, background: 'rgba(0,0,0,0.35)',
      display: 'flex', flexDirection: 'column', justifyContent: 'flex-end',
    }}>
      <div style={{
        background: t.isDark ? '#222020' : '#fcf8f0', height,
        borderTopLeftRadius: 22, borderTopRightRadius: 22,
        boxShadow: '0 -8px 28px rgba(0,0,0,0.25)',
        display: 'flex', flexDirection: 'column', overflow: 'hidden',
      }}>
        {/* grabber */}
        <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
          <div style={{ width: 36, height: 5, borderRadius: 3, background: t.isDark ? 'rgba(255,255,255,0.18)' : 'rgba(0,0,0,0.12)' }}/>
        </div>
        {/* title */}
        <div style={{
          display: 'flex', alignItems: 'center', justifyContent: 'space-between',
          padding: '14px 18px 12px',
          borderBottom: `0.5px solid ${t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.08)'}`,
        }}>
          <div style={{ width: 50 }}/>
          <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 17, fontWeight: 600, color: t.ink, whiteSpace: 'nowrap' }}>{bookTitle}</div>
          <div style={{ width: 50, display: 'flex', justifyContent: 'flex-end' }}>
            <div style={{
              width: 28, height: 28, borderRadius: 14, background: t.isDark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icons.Close size={14} color={t.sub} stroke={2}/>
            </div>
          </div>
        </div>
        {/* segmented Contents / Bookmarks */}
        <div style={{ padding: '8px 18px 0' }}>
          <div style={{ display: 'flex', borderRadius: 10, padding: 3, background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)' }}>
            {[{ k: 'contents', label: 'Contents', count: toc.length }, { k: 'bookmarks', label: 'Bookmarks', count: 3 }].map(o => {
              const on = o.k === 'contents';
              return (
                <div key={o.k} style={{
                  flex: 1, padding: '7px 0', borderRadius: 8,
                  background: on ? (t.isDark ? '#3a3530' : '#fff') : 'transparent',
                  color: t.ink, fontSize: 13, fontWeight: 500,
                  display: 'inline-flex', justifyContent: 'center', alignItems: 'center', gap: 6,
                  boxShadow: on ? '0 1px 2px rgba(0,0,0,0.08)' : 'none',
                }}>
                  <span>{o.label}</span>
                  <span style={{
                    fontSize: 10.5, color: t.sub, fontWeight: 500, padding: '1px 6px', borderRadius: 100,
                    background: t.isDark ? 'rgba(255,255,255,0.06)' : 'rgba(0,0,0,0.05)',
                  }}>{o.count}</span>
                </div>
              );
            })}
          </div>
        </div>

        {/* ── THE NEW FILTER FIELD ── (hidden when the book ships no TOC) */}
        {!noToc && (
          <TOCFilterField t={t} query={query} focused={focused} showCancel={showCancel}
            count={matches.length} total={toc.length}/>
        )}

        {/* list / empty states */}
        {noToc ? (
          <NoTocEmpty t={t}/>
        ) : matches.length === 0 ? (
          <NoMatchEmpty t={t} query={query}/>
        ) : (
          <div style={{ flex: 1, overflow: 'hidden', position: 'relative' }}>
            {pinCurrent && <PinnedCurrentRow t={t} entry={currentEntry}/>}
            <div style={{ padding: '8px 8px 20px', transform: `translateY(${-scrollTop}px)` }}>
              {matches.map(c => {
                const active = c.ch === currentCh;
                return (
                  <div key={c.ch} style={{
                    display: 'flex', alignItems: 'baseline', gap: 14, padding: '12px 14px',
                    background: active ? (t.isDark ? `${t.accent}1f` : `${t.accent}10`) : 'transparent',
                    borderRadius: 10,
                  }}>
                    <span style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 12, color: active ? t.accent : t.sub, fontWeight: 500, width: 30, textAlign: 'right', flexShrink: 0 }}>{c.ch}</span>
                    <span style={{ flex: 1, fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 16, fontWeight: active ? 600 : 400, minWidth: 0 }}>
                      <HighlightedTitle title={c.title} query={query} t={t} active={active}/>
                    </span>
                    {active && <span style={{ fontSize: 10, color: t.accent, fontWeight: 600, letterSpacing: 0.4, textTransform: 'uppercase', flexShrink: 0 }}>Reading</span>}
                    <span style={{ fontSize: 12, color: t.sub, flexShrink: 0 }}>p.{c.page}</span>
                  </div>
                );
              })}
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

// The filter field itself — reuses the SearchBar treatment, scoped to the
// Contents sheet. Resting: subtle filled pill. Focused: accent ring + Cancel.
function TOCFilterField({ t, query, focused, showCancel, count, total }) {
  const has = query.length > 0;
  return (
    <div style={{ padding: '10px 18px 6px' }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
        <div style={{
          flex: 1, display: 'flex', alignItems: 'center', gap: 9, height: 38,
          padding: '0 11px', borderRadius: 11,
          background: t.isDark ? 'rgba(255,255,255,0.07)' : 'rgba(0,0,0,0.045)',
          boxShadow: focused ? `0 0 0 2px ${t.accent}, 0 0 0 4px ${t.isDark ? '#222020' : '#fcf8f0'}` : 'none',
        }}>
          <Icons.Search size={16} color={focused ? t.accent : t.sub} stroke={1.9}/>
          <div style={{ flex: 1, display: 'flex', alignItems: 'center', minWidth: 0, fontFamily: '"Inter", system-ui, sans-serif', fontSize: 15 }}>
            {has ? (
              <span style={{ color: t.ink, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{query}</span>
            ) : (
              <span style={{ color: t.sub }}>Filter chapters</span>
            )}
            {focused && <span style={{ display: 'inline-block', width: 1.5, height: 18, background: t.accent, marginLeft: has ? 1 : 0, animation: 'tfCaret 1s steps(1) infinite' }}/>}
          </div>
          {has && (
            <div style={{
              width: 18, height: 18, borderRadius: 9, flexShrink: 0,
              background: t.isDark ? 'rgba(255,255,255,0.16)' : 'rgba(0,0,0,0.2)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <Icons.Close size={9} color={t.isDark ? '#222' : '#fff'} stroke={2.6}/>
            </div>
          )}
        </div>
        {showCancel && (
          <span style={{ fontSize: 14, color: t.accent, fontWeight: 500, whiteSpace: 'nowrap' }}>Cancel</span>
        )}
      </div>
      {has && (
        <div style={{ padding: '7px 4px 0', fontSize: 11.5, color: t.sub, letterSpacing: 0.2 }}>
          {count === 0
            ? 'No chapters match'
            : `${count} of ${total} ${count === 1 ? 'chapter' : 'chapters'}`}
        </div>
      )}
    </div>
  );
}

// Pinned "you are here" row — keeps the current chapter reachable even when
// the query filters it out of the result list (interaction with #313 / #93).
function PinnedCurrentRow({ t, entry }) {
  if (!entry) return null;
  return (
    <div style={{
      padding: '8px 16px 8px', margin: '8px 8px 0', borderRadius: 10,
      background: t.isDark ? `${t.accent}1f` : `${t.accent}10`,
      display: 'flex', alignItems: 'baseline', gap: 12,
      borderBottom: `0.5px solid ${t.rule}`,
    }}>
      <span style={{ fontSize: 9.5, color: t.accent, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', flexShrink: 0 }}>Reading</span>
      <span style={{ flex: 1, fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 14.5, color: t.accent, fontWeight: 600, whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis' }}>{entry.title}</span>
      <span style={{ fontSize: 11.5, color: t.accent, opacity: 0.8, flexShrink: 0 }}>p.{entry.page}</span>
    </div>
  );
}

function NoMatchEmpty({ t, query }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '8px 40px 64px', textAlign: 'center', gap: 14 }}>
      <svg viewBox="0 0 96 96" width="80" height="80" style={{ opacity: 0.85 }}>
        <rect x="14" y="14" width="68" height="68" rx="4" fill="none" stroke={t.rule} strokeWidth="1.5" strokeDasharray="3 3"/>
        <path d="M28 34h28M28 44h20M28 54h24" stroke={t.sub} strokeWidth="2" strokeLinecap="round" opacity="0.35"/>
        <circle cx="62" cy="60" r="13" fill="none" stroke={t.accent} strokeWidth="2.4"/>
        <path d="M71 69l8 8" stroke={t.accent} strokeWidth="2.4" strokeLinecap="round"/>
      </svg>
      <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 18, fontWeight: 600, color: t.ink }}>No chapters match</div>
      <div style={{ fontSize: 13, color: t.sub, lineHeight: 1.5, maxWidth: 260, textWrap: 'pretty' }}>
        Nothing in this book's contents matches <span style={{ color: t.ink, fontWeight: 600 }}>“{query}”</span>. Looking for a phrase inside the text instead?
      </div>
      <div style={{
        marginTop: 2, display: 'inline-flex', alignItems: 'center', gap: 6,
        padding: '8px 14px', borderRadius: 100, border: `1px solid ${t.accent}`,
        color: t.accent, fontSize: 12.5, fontWeight: 600,
      }}>
        <Icons.Search size={13} color={t.accent} stroke={2}/>
        Search full text
      </div>
    </div>
  );
}

function NoTocEmpty({ t }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', padding: '8px 40px 64px', textAlign: 'center', gap: 16 }}>
      <svg viewBox="0 0 96 96" width="88" height="88" style={{ opacity: 0.85 }}>
        <rect x="14" y="14" width="68" height="68" rx="4" fill="none" stroke={t.rule} strokeWidth="1.5" strokeDasharray="3 3"/>
        <path d="M28 32h26M28 42h32M28 52h22M28 62h28" stroke={t.sub} strokeWidth="2" strokeLinecap="round" opacity="0.5"/>
        <circle cx="68" cy="32" r="5" fill={t.accent} opacity="0.85"/>
      </svg>
      <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 18, fontWeight: 600, color: t.ink }}>No table of contents</div>
      <div style={{ fontSize: 13, color: t.sub, lineHeight: 1.5, maxWidth: 280, textWrap: 'pretty' }}>
        This book doesn't ship a TOC. Use the scrubber to flip pages, or Search to jump to a passage.
      </div>
      <div style={{ marginTop: 4, display: 'inline-flex', alignItems: 'center', gap: 6, padding: '8px 14px', borderRadius: 100, border: 'none', background: t.accent, color: '#fff', fontSize: 12.5, fontWeight: 600 }}>
        <Icons.Search size={13} color="#fff" stroke={2}/>
        Open Search
      </div>
    </div>
  );
}

// Small annotation chips reused across sections
function TFRedX({ top, right, left, label }) {
  return (
    <div style={{
      position: 'absolute', top, right, left, zIndex: 220,
      padding: '3px 8px', borderRadius: 100, background: 'rgba(168,58,58,0.92)', color: '#fff',
      fontSize: 10.5, fontWeight: 600, fontFamily: '"Inter", system-ui, sans-serif',
      boxShadow: '0 4px 10px rgba(0,0,0,0.18)', display: 'inline-flex', alignItems: 'center', gap: 5,
    }}>
      <span style={{ width: 12, height: 12, borderRadius: 6, background: '#fff', color: '#a83a3a', display: 'inline-flex', alignItems: 'center', justifyContent: 'center', fontSize: 10, fontWeight: 700 }}>×</span>
      {label}
    </div>
  );
}

// ─────────────────────────────────────────────────────
// CanvasRoot
// ─────────────────────────────────────────────────────
function TOCFilterCanvas() {
  return (
    <DesignCanvas style={{ background: '#161310' }}>

      {/* ─── 1. Intent ─── */}
      <DCSection id="intent"
        title="#1517 — TOC filter field (feature #94)"
        subtitle={'A search/filter field pinned at the top of the Contents tab of the TOC sheet. As you type, the already-loaded chapter list narrows to titles that match — case-insensitive, diacritic-folded, CJK-aware substring. Pure client-side filter over loaded entries; it does NOT hit the full-text content search (#2/#63), which the “Open Search” CTA still owns. The unlock is long-TOC books: multi-hundred-chapter CJK web novels become navigable without an endless scroll.'}>
        <DCArtboard id="canonical-default" label="Default · field at rest, full contents" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet/></TFPhone>
        </DCArtboard>
        <DCArtboard id="canonical-filtering" label="Filtering · query “the”, list narrowed, matches tinted" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="the" currentCh={3} focused/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={2} width={300}>
          The field lives <i>below</i> the Contents / Bookmarks segmented control, so it scopes to the Contents tab only — Bookmarks keeps its own surface. It reuses the existing <code>SearchBar</code> treatment, restyled as an inline filled pill rather than a full-width nav search.
        </DCPostIt>
      </DCSection>

      {/* ─── 2. The three required states ─── */}
      <DCSection id="states"
        title="The three states the design must cover"
        subtitle={'Per the issue: default (empty query, all entries), filtering-with-results (narrowed list + matched-substring treatment), and the no-match empty state. The field carries a live result count so the user knows the filter is working before they scroll.'}>
        <DCArtboard id="state-default" label="① Default · empty query" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet/></TFPhone>
        </DCArtboard>
        <DCArtboard id="state-results" label="② Filtering · “inn” → 1 match, substring tinted" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="inn"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="state-results-many" label="② Filtering · “the” → many matches" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="the"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="state-nomatch" label="③ No-match · empty state + full-text escape hatch" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="zzqx"/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={-2} width={300}>
          The no-match state is <b>not</b> the same as the no-TOC empty state (§6). Here the book has contents, the query just didn't hit — so we offer a one-tap pivot to full-text Search (#2/#63) with the query carried over, instead of a dead end.
        </DCPostIt>
      </DCSection>

      {/* ─── 3. Matched-substring treatment ─── */}
      <DCSection id="match-treatment"
        title="Matched-substring treatment (issue asks: “please specify”)"
        subtitle={'The matched run inside each title gets a 15% accent tint with a 40% accent underline — the same highlighter vocabulary used for in-text highlights, scaled to inline type. All occurrences in a title are marked, not just the first. The current-chapter row keeps its accent ink + bold, and the match tint composes on top of it.'}>
        <DCArtboard id="match-single" label="Single occurrence · “street”" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="street"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="match-short" label="Short query · “the” marks every occurrence" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="the"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="match-detail" label="Detail · the treatment, enlarged" width={TF_PHONE_W} height={360}>
          <MatchDetailCard/>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={2} width={290}>
          Why tint + underline and not bold: chapter titles are already set in a serif that goes bold for the current chapter. A weight-based match treatment would collide with the current-chapter weight. Color + underline reads as “matched” independently of “current”.
        </DCPostIt>
      </DCSection>

      {/* ─── 4. The motivating case — long CJK TOC ─── */}
      <DCSection id="long-cjk"
        title="The motivating case · 142-chapter CJK novel"
        subtitle={'This is why #94 exists. Without the filter, a multi-hundred-chapter web novel is a wall of scroll. CJK-aware substring means typing a single character (剑 “sword”) narrows 142 chapters to the handful that contain it — no spaces, no word boundaries, no romanization required.'}>
        <DCArtboard id="cjk-before" label="Before · 142 chapters, endless scroll" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone>
            <ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37}/>
            <TFRedX top={250} right={24} label="scroll · scroll · scroll"/>
          </TFPhone>
        </DCArtboard>
        <DCArtboard id="cjk-filter-char" label="After · 剑 → narrowed instantly" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37} query="剑" focused/></TFPhone>
        </DCArtboard>
        <DCArtboard id="cjk-filter-word" label="Two-char query · 故人" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37} query="故人"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="cjk-chapnum" label="Filter by chapter number · 第十" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37} query="第十"/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={-2} width={300}>
          CJK has no whitespace tokenisation, so a naïve word-boundary filter would fail. The filter folds case + diacritics and does a raw substring scan over the title string — which is exactly right for CJK and still correct for Latin. <code>第十</code> usefully matches 第十, 第十一 … 第十九.
        </DCPostIt>
      </DCSection>

      {/* ─── 5. Current-chapter interaction ─── */}
      <DCSection id="current-chapter"
        title="Interaction with the current-chapter highlight (#93 / #313)"
        subtitle={'The TOC already tints + bolds the chapter you are reading. Two cases under filtering: (a) the current chapter survives the filter — it keeps its tint and stays in place; (b) the query filters it out — we pin a compact “Reading” row at the very top of the results so you never lose your place or the one-tap return to it.'}>
        <DCArtboard id="current-visible" label="Current chapter survives the filter" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={26} query="剑"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="current-pinned" label="Current filtered out → pinned “Reading” row" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37} query="故人"/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={2} width={290}>
          #313 / #93 want the current position to stay legible across panel state changes. Filtering is a panel state change. The pinned row is the cheapest way to honour that — it borrows the current-chapter tint and sits above the result list, divided by a hairline.
        </DCPostIt>
      </DCSection>

      {/* ─── 6. No-TOC book (filter hidden) + Open Search ─── */}
      <DCSection id="no-toc"
        title="No-TOC books · filter field hidden, “Open Search” preserved"
        subtitle={'Some EPUBs ship no TOC at all. The filter field would have nothing to filter, so it is suppressed entirely (not shown disabled) and the existing empty state + “Open Search” CTA from TOCSheetV2 renders unchanged. This keeps the new field from implying a TOC exists when it doesn\'t.'}>
        <DCArtboard id="notoc" label="No TOC · field suppressed, existing Open Search CTA" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="Untitled Draft.epub" toc={[]} noToc/></TFPhone>
        </DCArtboard>
        <DCArtboard id="notoc-vs-nomatch" label="Contrast · no-match (has TOC) vs no-TOC" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="zzqx"/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={-2} width={290}>
          Decision: suppress, don't disable. A greyed-out filter field on a book with no chapters is noise — it asks the user to act on something that can't work. Hiding it makes the no-TOC state read cleanly as “navigate another way”.
        </DCPostIt>
      </DCSection>

      {/* ─── 7. Placement rationale ─── */}
      <DCSection id="placement"
        title="Placement · below the segmented control, above the list"
        subtitle={'The issue flags placement as an open question. Two candidates: (A) above the Contents/Bookmarks segmented control — but then it visually owns both tabs, while it only filters Contents. (B) below the control, scoped to the Contents tab. We commit to B. The field scrolls away with the list on a long TOC is the only remaining question — answered: it stays pinned.'}>
        <DCArtboard id="place-rejected" label="Rejected · A · field above the tabs" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPlacementRejected/>
        </DCArtboard>
        <DCArtboard id="place-chosen" label="Chosen · B · field below the tabs, scoped to Contents" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet query="the"/></TFPhone>
        </DCArtboard>
        <DCArtboard id="place-pinned" label="Pinned · field stays put while the list scrolls" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone><ContentsSheet bookTitle="孤剑寒江录" toc={WUXIA_TOC} currentCh={37} scrollTop={520}/></TFPhone>
        </DCArtboard>
        <DCPostIt top={-34} right={32} rotate={2} width={290}>
          The field is part of the sheet header stack, not the scroll content — so on a 142-chapter TOC it never scrolls out of reach. Only the chapter rows below it move.
        </DCPostIt>
      </DCSection>

      {/* ─── 8. Themes ─── */}
      <DCSection id="themes"
        title="ReaderTheme tokens"
        subtitle={'The field background is a 4.5–7% ink/paper wash; focus ring + match tint + count text all resolve from the theme accent. Verified across the four reader themes.'}>
        <DCArtboard id="theme-paper" label="paper" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone themeKey="paper"><ContentsSheet themeKey="paper" query="the" focused/></TFPhone>
        </DCArtboard>
        <DCArtboard id="theme-sepia" label="sepia" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone themeKey="sepia"><ContentsSheet themeKey="sepia" query="the" focused/></TFPhone>
        </DCArtboard>
        <DCArtboard id="theme-dark" label="dark" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone themeKey="dark"><ContentsSheet themeKey="dark" query="the" focused/></TFPhone>
        </DCArtboard>
        <DCArtboard id="theme-oled" label="OLED" width={TF_PHONE_W} height={TF_PHONE_H}>
          <TFPhone themeKey="oled"><ContentsSheet themeKey="oled" query="剑" toc={WUXIA_TOC} bookTitle="孤剑寒江录" currentCh={26} focused/></TFPhone>
        </DCArtboard>
      </DCSection>

      {/* ─── 9. Spec card ─── */}
      <DCSection id="spec"
        title="Implementation notes"
        subtitle="Binding contract for feature #94 — what TOCSheet.swift must build.">
        <DCArtboard id="spec-card" label="" width={TF_PHONE_W * 2 + 30} height={720}>
          <TFSpecCard/>
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

// ─────────────────────────────────────────────────────
// Match-treatment detail card
// ─────────────────────────────────────────────────────
function MatchDetailCard() {
  const t = THEMES.paper;
  const Row = ({ ch, title, query, active, page }) => (
    <div style={{
      display: 'flex', alignItems: 'baseline', gap: 14, padding: '12px 14px',
      background: active ? `${t.accent}10` : 'transparent', borderRadius: 10,
    }}>
      <span style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 13, color: active ? t.accent : t.sub, fontWeight: 500, width: 26, textAlign: 'right' }}>{ch}</span>
      <span style={{ flex: 1, fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 19, fontWeight: active ? 600 : 400 }}>
        <HighlightedTitle title={title} query={query} t={t} active={active}/>
      </span>
      <span style={{ fontSize: 12, color: t.sub }}>p.{page}</span>
    </div>
  );
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '24px 30px', background: '#fcf8f0', borderRadius: 18, fontFamily: '"Inter", system-ui, sans-serif' }}>
      <div style={{ fontSize: 11, letterSpacing: 1, textTransform: 'uppercase', color: t.sub, fontWeight: 600, marginBottom: 14 }}>Query “the” · matched runs tinted</div>
      <Row ch={3} title="The Spouter-Inn" query="the" active page={14}/>
      <Row ch={7} title="The Chapel" query="the" page={43}/>
      <Row ch={6} title="The Street" query="the" page={40}/>
      <div style={{ marginTop: 16, display: 'flex', gap: 22, fontSize: 12.5, color: t.sub, lineHeight: 1.5 }}>
        <div><span style={{ display: 'inline-block', width: 28, height: 14, background: `${t.accent}26`, boxShadow: `inset 0 -2px 0 ${t.accent}66`, borderRadius: 3, verticalAlign: '-2px', marginRight: 6 }}/> matched run</div>
        <div><span style={{ color: t.accent, fontWeight: 600 }}>accent ink + bold</span> = current chapter</div>
      </div>
    </div>
  );
}

// Rejected placement — field above the segmented control
function TFPlacementRejected() {
  const t = THEMES.paper;
  return (
    <TFPhone themeKey="paper">
      <div style={{ position: 'absolute', inset: 0, zIndex: 200, background: 'rgba(0,0,0,0.35)', display: 'flex', flexDirection: 'column', justifyContent: 'flex-end' }}>
        <div style={{ background: '#fcf8f0', height: 640, borderTopLeftRadius: 22, borderTopRightRadius: 22, display: 'flex', flexDirection: 'column', overflow: 'hidden' }}>
          <div style={{ display: 'flex', justifyContent: 'center', paddingTop: 8 }}>
            <div style={{ width: 36, height: 5, borderRadius: 3, background: 'rgba(0,0,0,0.12)' }}/>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', padding: '14px 18px 12px', borderBottom: '0.5px solid rgba(0,0,0,0.08)' }}>
            <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 17, fontWeight: 600, color: t.ink }}>Moby-Dick</div>
          </div>
          <div style={{ position: 'relative' }}>
            <TOCFilterField t={t} query="" focused={false} count={16} total={16}/>
            <TFRedX top={14} right={20} label="owns both tabs"/>
          </div>
          <div style={{ padding: '4px 18px 0' }}>
            <div style={{ display: 'flex', borderRadius: 10, padding: 3, background: 'rgba(0,0,0,0.05)' }}>
              {['Contents', 'Bookmarks'].map((l, i) => (
                <div key={l} style={{ flex: 1, padding: '7px 0', borderRadius: 8, textAlign: 'center', fontSize: 13, fontWeight: 500, color: t.ink, background: i === 0 ? '#fff' : 'transparent', boxShadow: i === 0 ? '0 1px 2px rgba(0,0,0,0.08)' : 'none' }}>{l}</div>
              ))}
            </div>
          </div>
          <div style={{ padding: '12px 8px', opacity: 0.5 }}>
            {MOBY_TOC.slice(0, 6).map(c => (
              <div key={c.ch} style={{ display: 'flex', gap: 14, padding: '12px 14px', alignItems: 'baseline' }}>
                <span style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 12, color: t.sub, width: 26, textAlign: 'right' }}>{c.ch}</span>
                <span style={{ flex: 1, fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 16, color: t.ink }}>{c.title}</span>
              </div>
            ))}
          </div>
        </div>
      </div>
    </TFPhone>
  );
}

// ─────────────────────────────────────────────────────
// Spec card
// ─────────────────────────────────────────────────────
function TFSpecCard() {
  const t = THEMES.paper;
  const rowStyle = { display: 'grid', gridTemplateColumns: '180px 1fr', gap: 16, padding: '11px 0', borderTop: `0.5px solid ${t.rule}`, alignItems: 'baseline' };
  const labelStyle = { fontSize: 11, letterSpacing: 0.8, textTransform: 'uppercase', color: t.sub, fontWeight: 600 };
  const valStyle = { fontSize: 14, color: t.ink, lineHeight: 1.5 };
  const code = { fontFamily: '"SF Mono", "JetBrains Mono", Menlo, monospace', background: 'rgba(0,0,0,0.05)', padding: '1px 5px', borderRadius: 4, fontSize: 12.5, color: '#5a3a3a' };
  return (
    <div style={{ width: '100%', height: '100%', boxSizing: 'border-box', padding: '32px 40px', background: '#fcf8f0', color: t.ink, fontFamily: '"Inter", system-ui, sans-serif', borderRadius: 18, overflow: 'auto' }}>
      <div style={{ fontFamily: '"Source Serif 4", Georgia, serif', fontSize: 26, fontWeight: 700, marginBottom: 4 }}>TOC filter field — binding contract</div>
      <div style={{ fontSize: 13, color: t.sub, marginBottom: 18 }}>
        Surface for feature <span style={code}>#94</span> (Filterable TOC), issue <span style={code}>#1517</span>. Built into <span style={code}>TOCSheet.swift</span>, cross-format. Source of truth: <span style={code}>docs/features.md</span>.
      </div>

      <div style={rowStyle}><div style={labelStyle}>Placement</div><div style={valStyle}>Pinned in the sheet header stack, <b>below</b> the Contents/Bookmarks segmented control, scoped to the Contents tab. Part of the header — does not scroll with the chapter list. Hidden on the Bookmarks tab.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Component</div><div style={valStyle}>Reuses the existing <span style={code}>SearchBar</span> view, restyled as an inline filled pill (38pt, 11pt radius). Leading magnifier, placeholder “Filter chapters”, trailing clear (✕) when non-empty, optional “Cancel” on focus.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Filter semantics</div><div style={valStyle}>Client-side over the already-loaded TOC entries. Match = <span style={code}>title.folded.contains(query.folded)</span> — case-insensitive, diacritic-folded (<span style={code}>NFD</span> strip), raw substring (no word boundaries) so it is <b>CJK-aware</b>. No network, no full-text index.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Match treatment</div><div style={valStyle}>Every matched run in a title is tinted: <span style={code}>accent @ 15%</span> background + <span style={code}>accent @ 40%</span> underline. Independent of the current-chapter weight so the two never collide. Marks all occurrences, not just the first.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Result count</div><div style={valStyle}>Below the field while filtering: “<span style={code}>N of M chapters</span>”, or “No chapters match”. Reassures the user the filter ran before they scroll.</div></div>

      <div style={rowStyle}><div style={labelStyle}>States</div><div style={valStyle}>default (empty query) · filtering-with-results · no-match (empty state + “Search full text” pivot carrying the query to #2/#63) · current-chapter-pinned · no-TOC (field suppressed, existing Open Search CTA).</div></div>

      <div style={rowStyle}><div style={labelStyle}>Current chapter</div><div style={valStyle}>Keeps its accent tint + bold (#93/#313). If the query filters it out, a compact <span style={code}>Reading</span> row pins above the results so the position is never lost and remains one tap away.</div></div>

      <div style={rowStyle}><div style={labelStyle}>No-TOC books</div><div style={valStyle}>Field <b>suppressed</b> (not disabled). The existing <span style={code}>TOCSheetV2</span> empty state + <span style={code}>Open Search</span> CTA render unchanged.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Not this</div><div style={valStyle}>Not full-text content search (#2/#63) — that stays behind the existing CTA. Not a fuzzy/ranked search — exact substring only, so results stay in chapter order and are predictable on a 500-chapter TOC.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Accessibility</div><div style={valStyle}>Field labelled “Filter chapters”. Result count is an <span style={code}>accessibilityValue</span> announced on change. Clear button labelled. Dynamic Type: field height and row type scale; match tint persists at all sizes.</div></div>

      <div style={rowStyle}><div style={labelStyle}>Performance</div><div style={valStyle}>Filter runs on the in-memory entry array; debounce not required below ~2k entries. For pathological TOCs, filter on a background actor and diff into the <span style={code}>LazyVStack</span>.</div></div>
    </div>
  );
}

Object.assign(window, { TOCFilterCanvas });
