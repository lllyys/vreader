// Canvas for issue #1363 / feature #79 — AI provider editor Base URL + Model
// pre-fill / placeholder interaction.
//
// The editor (AIProviderEditSheet) seeds Base URL + Model with the kind's real
// default text in add-mode, so the declared placeholders are shadowed and the
// user must delete the defaults to type their own. This canvas explores three
// ways to make the defaults read as placeholders that clear on focus, while
// keeping the zero-config "add a key and Save" path working — which forces the
// save-empty-vs-default decision the issue calls out.

const L = UI.light;
const D = UI.dark;

function Pane({ ui, children, w = 384, h = 300 }) {
  // grouped-bg artboard host for the close-up cards
  return <div style={{ width: w, minHeight: h, background: ui.grouped }}>{children}</div>;
}

function CanvasRoot() {
  return (
    <DesignCanvas>

      {/* ─────────────────────────────────────────────────────────
          The problem — today's prefill
      ───────────────────────────────────────────────────────── */}
      <DCSection id="today" title="The problem — today’s prefill"
        subtitle="Add-mode seeds Base URL + Model with the kind’s real default text (AIProviderEditSheet.swift init). It reads as a value you must delete, the declared placeholders never show, and there’s no signal that leaving it alone is fine.">
        <DCArtboard id="today-sheet" label="Add Provider — as shipped" width={402} height={880}>
          <EditorSheet ui={L} variant="today" state="rest" mode="add" />
        </DCArtboard>
        <DCArtboard id="today-rest" label="Endpoint · default seeded as a value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="today" state="rest" caption="ADD MODE · default = editable value (ink)" />
        </DCArtboard>
        <DCArtboard id="today-focus" label="Endpoint · focused (must backspace)" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="today" state="focus" caption="FOCUSED · caret lands after the default — delete to replace" />
        </DCArtboard>
        <DCPostIt top={-34} right={28} rotate={2} width={258}>
          <strong>Why design is needed (rule 51):</strong> the placeholders in <em>+Sections.swift</em> are shadowed because the binding is non-empty, so SwiftUI never clears on focus. The fix has to keep the zero-config Save path: an empty Base URL fails <em>canSave</em> validation today.
        </DCPostIt>
      </DCSection>

      {/* ─────────────────────────────────────────────────────────
          A — Placeholder + save-time fallback  (recommended)
      ───────────────────────────────────────────────────────── */}
      <DCSection id="vA" title="A · Placeholder + save-time fallback  ·  recommended"
        subtitle="Bind the fields empty. Show the kind default as a real muted placeholder with a small “Default” tag. Nothing to delete on focus. Leaving a field blank stores the kind default at Save, so the zero-config flow still works.">
        <DCArtboard id="A-sheet" label="Add Provider — blank, Save enabled" width={402} height={880}>
          <EditorSheet ui={L} variant="A" state="rest" mode="add" />
        </DCArtboard>
        <DCArtboard id="A-rest" label="① rest · placeholder + Default tag" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="rest" caption="① UNFOCUSED · muted default, tagged as a fallback" />
        </DCArtboard>
        <DCArtboard id="A-focus" label="② focused · empty, caret at start" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="focus" caption="② FOCUSED · nothing to clear; type or leave blank" />
        </DCArtboard>
        <DCArtboard id="A-typed" label="③ user-typed · ink value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="typed" caption="③ TYPED · custom value in ink, tag gone" />
        </DCArtboard>
        <DCArtboard id="A-edit" label="④ edit existing · saved value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="edit" caption="④ EDIT EXISTING · committed value, no placeholder" />
        </DCArtboard>
        <DCArtboard id="A-dark" label="Dark · add, blank" width={402} height={880}>
          <EditorSheet ui={D} variant="A" state="rest" mode="add" />
        </DCArtboard>
        <DCArtboard id="A-edit-sheet" label="Edit existing — Test Connection" width={402} height={880}>
          <EditorSheet ui={L} variant="A" mode="edit" test="ok" />
        </DCArtboard>
        <DCArtboard id="A-nokey" label="Add · no key yet — Test disabled" width={402} height={880}>
          <EditorSheet ui={L} variant="A" state="rest" mode="add" keyEntered={false} test="disabled" />
        </DCArtboard>
        <DCArtboard id="A-testok" label="Add · tested OK before saving" width={402} height={880}>
          <EditorSheet ui={L} variant="A" state="rest" mode="add" test="ok" />
        </DCArtboard>
        <DCPostIt top={-30} left={40} rotate={2} width={262}>
          <strong>Test before Save:</strong> the Test button lights up the moment a key is entered — no Save-and-reopen. It runs against the live form state + the typed key (the VM already builds the candidate from form fields; pass the in-memory key instead of reading the keychain).
        </DCPostIt>
        <DCPostIt top={-36} right={24} rotate={-2} width={272}>
          <strong>The save decision:</strong> empty field → store the kind default. <em>canSave</em> changes from “baseURL must be non-empty &amp; valid” to validating the <em>effective</em> URL (typed value, else kind default) — so blank + a key still Saves. Matches the literal “placeholder” ask; one small VM change.
        </DCPostIt>
      </DCSection>

      {/* ─────────────────────────────────────────────────────────
          B — Prefilled, select-all on focus
      ───────────────────────────────────────────────────────── */}
      <DCSection id="vB" title="B · Prefilled, select-all on focus"
        subtitle="Keep the real default as an ink value so it reads as a live config. On focus the field selects all, so one keystroke replaces it — “clears on focus” without ever being empty. Save path is untouched; a “Reset to default” link returns the value.">
        <DCArtboard id="B-rest" label="① rest · ink value (looks filled)" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="B" state="rest" caption="① UNFOCUSED · real default value, not a placeholder" />
        </DCArtboard>
        <DCArtboard id="B-focus" label="② focused · whole value selected" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="B" state="focus" caption="② FOCUSED · select-all → next keystroke replaces" />
        </DCArtboard>
        <DCArtboard id="B-typed" label="③ user-typed · Reset to default" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="B" state="typed" caption="③ TYPED · custom value + reset affordance" />
        </DCArtboard>
        <DCArtboard id="B-edit" label="④ edit existing · saved value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="B" state="edit" caption="④ EDIT EXISTING · same select-all on focus" />
        </DCArtboard>
        <DCArtboard id="B-sheet" label="Add Provider — Base URL focused" width={402} height={880}>
          <EditorSheet ui={L} variant="B" state="focus" mode="add" />
        </DCArtboard>
        <DCPostIt top={-34} right={24} rotate={2} width={258}>
          <strong>Trade-off:</strong> zero change to <em>canSave</em> (field is never empty), but default vs. user-typed look identical, and select-all is a quieter signal than a real placeholder. Safest to ship, weakest affordance.
        </DCPostIt>
      </DCSection>

      {/* ─────────────────────────────────────────────────────────
          C — Empty field + tap-to-fill suggestion
      ───────────────────────────────────────────────────────── */}
      <DCSection id="vC" title="C · Empty field + tap-to-fill suggestion"
        subtitle="Honest empty fields with the generic placeholder, plus a tappable chip that seeds the kind defaults. Most discoverable about what the default is and that it’s optional. Still needs the blank → default save fallback (same as A).">
        <DCArtboard id="C-rest" label="① empty · suggestion chip" width={430} height={324} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="C" state="rest" caption="① UNFOCUSED · empty + “Use defaults” chip" />
        </DCArtboard>
        <DCArtboard id="C-typed" label="② filled via chip · ink value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="C" state="typed" caption="② FILLED · chip seeded the defaults; editable" />
        </DCArtboard>
        <DCArtboard id="C-edit" label="③ edit existing · saved value" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="C" state="edit" caption="③ EDIT EXISTING · committed value, no chip" />
        </DCArtboard>
        <DCArtboard id="C-sheet" label="Add Provider — empty + chip" width={402} height={880}>
          <EditorSheet ui={L} variant="C" state="rest" mode="add" />
        </DCArtboard>
        <DCPostIt top={-34} right={24} rotate={-2} width={258}>
          <strong>Trade-off:</strong> clearest about the default and that it’s optional, but it’s the most chrome and an extra control to localize. Good if discoverability of the default value (not just the behaviour) matters.
        </DCPostIt>
      </DCSection>

      {/* ─────────────────────────────────────────────────────────
          Kind switch — placeholder follows the picker (A)
      ───────────────────────────────────────────────────────── */}
      <DCSection id="kind" title="Kind switch updates the default (variant A)"
        subtitle="The segmented Provider Type picker drives which default the placeholder shows — OpenAI-compatible → gpt-4o-mini · api.openai.com/v1, Anthropic → claude-sonnet-4-6 · api.anthropic.com. KindResetPolicy already resets only untouched fields.">
        <DCArtboard id="kind-openai" label="OpenAI-compatible" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="rest" kind="openai" caption="PICKER = OPENAI-COMPATIBLE" />
        </DCArtboard>
        <DCArtboard id="kind-anthropic" label="Anthropic" width={430} height={300} style={{ background: L.grouped }}>
          <EndpointCard ui={L} variant="A" state="rest" kind="anthropic" caption="PICKER = ANTHROPIC" />
        </DCArtboard>
      </DCSection>

      {/* ─────────────────────────────────────────────────────────
          Live specimen — interactive
      ───────────────────────────────────────────────────────── */}
      <DCSection id="live" title="Live — focus & type"
        subtitle="Real inputs. A: leave a field blank and the muted default still saves (see “What Save would store”). B: focusing selects all, so one keystroke replaces the prefilled default.">
        <DCArtboard id="live-A" label="A · placeholder + fallback (interactive)" width={430} height={420} style={{ background: L.grouped }}>
          <LiveField ui={L} variant="A" />
        </DCArtboard>
        <DCArtboard id="live-B" label="B · select-all on focus (interactive)" width={430} height={420} style={{ background: L.grouped }}>
          <LiveField ui={L} variant="B" />
        </DCArtboard>
        <DCArtboard id="live-A-dark" label="A · dark (interactive)" width={430} height={420} style={{ background: D.grouped }}>
          <LiveField ui={D} variant="A" />
        </DCArtboard>
      </DCSection>

    </DesignCanvas>
  );
}

Object.assign(window, { CanvasRoot });
