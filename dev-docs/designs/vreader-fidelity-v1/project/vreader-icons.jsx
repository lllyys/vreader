// Line icons — thin stroke, SF-Symbols-ish. All take {size, color, stroke}.

const Icon = ({ size = 20, color = 'currentColor', stroke = 1.6, children, style }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none"
       stroke={color} strokeWidth={stroke} strokeLinecap="round" strokeLinejoin="round"
       style={style}>{children}</svg>
);

const Icons = {
  Search:    (p) => <Icon {...p}><circle cx="11" cy="11" r="7"/><path d="M20 20l-3.5-3.5"/></Icon>,
  Grid:      (p) => <Icon {...p}><rect x="3" y="3" width="7" height="7" rx="1.5"/><rect x="14" y="3" width="7" height="7" rx="1.5"/><rect x="3" y="14" width="7" height="7" rx="1.5"/><rect x="14" y="14" width="7" height="7" rx="1.5"/></Icon>,
  List:      (p) => <Icon {...p}><path d="M4 6h16M4 12h16M4 18h16"/></Icon>,
  Plus:      (p) => <Icon {...p}><path d="M12 5v14M5 12h14"/></Icon>,
  Sort:      (p) => <Icon {...p}><path d="M7 4v16M7 4l-3 3M7 4l3 3M17 20V4M17 20l-3-3M17 20l3-3"/></Icon>,
  Filter:    (p) => <Icon {...p}><path d="M4 5h16l-6 8v6l-4-2v-4z"/></Icon>,
  Chevron:   (p) => <Icon {...p}><path d="M9 6l6 6-6 6"/></Icon>,
  ChevronL:  (p) => <Icon {...p}><path d="M15 6l-6 6 6 6"/></Icon>,
  ChevronD:  (p) => <Icon {...p}><path d="M6 9l6 6 6-6"/></Icon>,
  Close:     (p) => <Icon {...p}><path d="M6 6l12 12M18 6L6 18"/></Icon>,
  Bookmark:  (p) => <Icon {...p}><path d="M6 4h12v17l-6-4-6 4z"/></Icon>,
  BookmarkFilled: (p) => <Icon {...p}><path d="M6 4h12v17l-6-4-6 4z" fill={p?.color || 'currentColor'}/></Icon>,
  Aa:        (p) => <Icon {...p} stroke={p?.stroke || 1.8}><text x="2" y="18" fontSize="18" fontFamily="serif" fontWeight="700" fill={p?.color || 'currentColor'} stroke="none">Aa</text></Icon>,
  TOC:       (p) => <Icon {...p}><path d="M4 6h2M4 12h2M4 18h2M9 6h11M9 12h11M9 18h11"/></Icon>,
  Sparkle:   (p) => <Icon {...p}><path d="M12 3l1.7 5.3L19 10l-5.3 1.7L12 17l-1.7-5.3L5 10l5.3-1.7zM19 16l.8 2.2L22 19l-2.2.8L19 22l-.8-2.2L16 19l2.2-.8z"/></Icon>,
  Highlighter:(p) => <Icon {...p}><path d="M14 4l6 6-9 9-6-6zM5 13l-2 6 6-2"/></Icon>,
  Note:      (p) => <Icon {...p}><path d="M5 4h11l4 4v12H5z"/><path d="M9 11h7M9 15h5"/></Icon>,
  Share:     (p) => <Icon {...p}><path d="M12 3v13M8 7l4-4 4 4M5 14v5a2 2 0 002 2h10a2 2 0 002-2v-5"/></Icon>,
  More:      (p) => <Icon {...p}><circle cx="5" cy="12" r="1.3" fill={p?.color || 'currentColor'}/><circle cx="12" cy="12" r="1.3" fill={p?.color || 'currentColor'}/><circle cx="19" cy="12" r="1.3" fill={p?.color || 'currentColor'}/></Icon>,
  Cloud:     (p) => <Icon {...p}><path d="M7 18a4 4 0 010-8 6 6 0 0111.7 1.5A4 4 0 0118 18z"/></Icon>,
  Settings:  (p) => <Icon {...p}><circle cx="12" cy="12" r="3"/><path d="M12 2v3M12 19v3M4.2 4.2l2.1 2.1M17.7 17.7l2.1 2.1M2 12h3M19 12h3M4.2 19.8l2.1-2.1M17.7 6.3l2.1-2.1"/></Icon>,
  Library:   (p) => <Icon {...p}><path d="M4 4v16M8 4v16M14 6l5 1-3 14-5-1z"/></Icon>,
  Sun:       (p) => <Icon {...p}><circle cx="12" cy="12" r="4"/><path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4"/></Icon>,
  Timer:     (p) => <Icon {...p}><circle cx="12" cy="13" r="8"/><path d="M12 9v4l2.5 2.5M9 2h6M12 5V2"/></Icon>,
  Info:      (p) => <Icon {...p}><circle cx="12" cy="12" r="9"/><path d="M12 16v-5M12 8v.01"/></Icon>,
  Download:  (p) => <Icon {...p}><path d="M12 3v13M7 11l5 5 5-5M5 20h14"/></Icon>,
  Moon:      (p) => <Icon {...p}><path d="M20 14A8 8 0 1110 4a7 7 0 0010 10z"/></Icon>,
  Volume:    (p) => <Icon {...p}><path d="M4 9v6h4l5 4V5L8 9zM17 8a5 5 0 010 8M20 5a9 9 0 010 14"/></Icon>,
  Translate: (p) => <Icon {...p}><path d="M3 6h11M9 3v3M5 6c0 4 2 8 6 9M14 9c-2 5-6 7-10 7M14 21l4-10 4 10M16 17h4"/></Icon>,
  Send:      (p) => <Icon {...p}><path d="M4 12l16-8-6 18-3-7z"/></Icon>,
  Dot:       (p) => <Icon {...p}><circle cx="12" cy="12" r="3" fill={p?.color || 'currentColor'} stroke="none"/></Icon>,
  Brightness:(p) => <Icon {...p}><circle cx="12" cy="12" r="4" fill={p?.color || 'currentColor'} stroke="none"/><path d="M12 2v3M12 19v2M3 12h3M18 12h3M5 5l2 2M17 17l2 2M5 19l2-2M17 7l2-2"/></Icon>,
  Pause:     (p) => <Icon {...p}><rect x="6" y="5" width="4" height="14" rx="1" fill={p?.color || 'currentColor'}/><rect x="14" y="5" width="4" height="14" rx="1" fill={p?.color || 'currentColor'}/></Icon>,
  Play:      (p) => <Icon {...p}><path d="M6 4l14 8-14 8z" fill={p?.color || 'currentColor'}/></Icon>,
  Check:     (p) => <Icon {...p}><path d="M5 12l5 5L20 7"/></Icon>,
  Wifi:      (p) => <Icon {...p}><path d="M2 9a15 15 0 0120 0M5.5 12.5a10 10 0 0113 0M9 16a5 5 0 016 0"/><circle cx="12" cy="19" r="1" fill={p?.color || 'currentColor'} stroke="none"/></Icon>,
  Image:     (p) => <Icon {...p}><rect x="3" y="4" width="18" height="16" rx="2"/><circle cx="9" cy="10" r="2"/><path d="M21 16l-5-5-9 9"/></Icon>,
  Folder:    (p) => <Icon {...p}><path d="M3 6a2 2 0 012-2h4l2 2h8a2 2 0 012 2v9a2 2 0 01-2 2H5a2 2 0 01-2-2z"/></Icon>,
};

Object.assign(window, { Icons });
