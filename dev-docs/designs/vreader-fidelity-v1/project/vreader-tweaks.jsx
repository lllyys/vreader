// AppTweaksPanel — wires the prototype's tweakable knobs into the host's Tweaks toggle.
// Built on the starter TweaksPanel + Tweak* controls from tweaks-panel.jsx.

function AppTweaksPanel({ tw, setTweak, onOpenBookDetails, onOpenBilingualSetup }) {
  return (
    <TweaksPanel title="Tweaks">
      <TweakSection label="Theme">
        <TweakSelect
          label="Reader theme"
          value={tw.themeOverride}
          onChange={(v) => setTweak('themeOverride', v)}
          options={[
            { value: 'auto',  label: 'Follow reader settings' },
            { value: 'paper', label: 'Paper' },
            { value: 'sepia', label: 'Sepia' },
            { value: 'dark',  label: 'Dark' },
            { value: 'oled',  label: 'OLED' },
            { value: 'image', label: 'Photo' },
          ]}
        />
      </TweakSection>

      <TweakSection label="Book details · #789">
        <TweakSelect
          label="Book in reader"
          value={tw.selectedBookId}
          onChange={(v) => setTweak('selectedBookId', v)}
          options={BOOKS.map(b => ({ value: b.id, label: `${b.title} — ${b.author}` }))}
        />
        <TweakSelect
          label="File state"
          value={tw.fileState}
          onChange={(v) => setTweak('fileState', v)}
          options={[
            { value: 'default',     label: 'Default' },
            { value: 'longTitle',   label: 'Long title' },
            { value: 'missingCover', label: 'No cover' },
            { value: 'remoteOnly',  label: 'Remote-only' },
          ]}
        />
        <TweakRadio
          label="Sheet layout"
          value={tw.detailsLayout}
          onChange={(v) => setTweak('detailsLayout', v)}
          options={[
            { value: 'stacked', label: 'Stacked' },
            { value: 'split',   label: 'Compact' },
          ]}
        />
        <TweakButton label="Open Book Details sheet" onClick={onOpenBookDetails}/>
      </TweakSection>

      <TweakSection label="Bilingual · #790">
        <TweakSelect
          label="Target language"
          value={tw.bilingualLang}
          onChange={(v) => setTweak('bilingualLang', v)}
          options={[
            'Chinese', 'Japanese', 'Korean', 'Spanish',
            'French', 'German', 'Italian', 'Arabic', 'Russian',
          ].map(k => ({ value: k, label: k }))}
        />
        <TweakToggle
          label="Simulate: no AI provider"
          value={!!tw.aiUnavailable}
          onChange={(v) => setTweak('aiUnavailable', v)}
        />
        <TweakButton label="Open Bilingual setup sheet" onClick={onOpenBilingualSetup}/>
      </TweakSection>

      <TweakSection label="Annotations · #793">
        <TweakSelect
          label="Highlights filter on open"
          value={tw.annotationsTab}
          onChange={(v) => setTweak('annotationsTab', v)}
          options={[
            { value: 'all',        label: 'All' },
            { value: 'highlights', label: 'Highlights' },
            { value: 'notes',      label: 'Notes' },
            { value: 'bookmarks',  label: 'Bookmarks' },
          ]}
        />
        <div className="twk-row" style={{
          fontSize: 11, opacity: 0.65, lineHeight: 1.45,
        }}>
          Routing: <b>Contents</b> button → TOCSheet · <b>Notes</b> button → HighlightsSheet.
        </div>
      </TweakSection>
    </TweaksPanel>
  );
}

Object.assign(window, { AppTweaksPanel });
