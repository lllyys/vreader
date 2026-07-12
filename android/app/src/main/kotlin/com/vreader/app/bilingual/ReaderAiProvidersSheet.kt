// Purpose: feature #131 WI-AIP — the scoped in-reader "AI Providers" sheet PUSHED inside the
// bilingual flow (the Variant-A entry, round-4 High-4; the Android analog of iOS ReaderAIProvidersView),
// reached from the bilingual setup sheet's engine-strip "Set up"/"Change…" CTA. It stitches the
// three folded-in pieces:
//   (a) the reused #118 `AiProviderEditSheet` — presented VERBATIM (Kind/Name/Endpoint/Sampling/
//       API Key/Test Connection), driven by the SHARED `AiSettingsViewModel`.
//   (b) the NEW reader-scoped `ReaderAiProvidersList` — over `AiSettingsViewModel.listState`, with
//       the ‹ Bilingual nav, the bilingual-context empty state, the checked-active row, and
//       tap-to-SELECT (→ `vm.setActive(id)`). (rule 51 — reproduces vreader-ai-provider-entry.jsx.)
//   (c) the SAVE-RESULT seam — on first Save the saved id (from `AiSettingsViewModel.saveResult`)
//       drives `vm.setActive(savedId)` then pops the WHOLE stack back to the bilingual sheet
//       (via [onDone]), DETERMINISTICALLY, AFTER the upsert commits (no race).
//
// Navigation model (jsx / reader-ai-provider-entry.md): the list is the root of this pushed stack;
// "Add provider" / an active-row edit push the editor; the editor's Cancel pops to the list; a Save
// pops the WHOLE stack (setActive + onDone). ‹ Bilingual from the list (with nothing added) pops the
// stack with NO state mutation. Nothing here is composed until WI-9 wires the engine-strip CTA.
//
// This composable is rendered inside a BackupSurface so both the list and the reused editor share the
// LocalBackupTokens palette. Stateful host (owns the list/editor navigation); the leaf presentations
// are pure functions of state + callbacks (rule 50 §12).
//
// @coordinates-with: ReaderAiProvidersList.kt, BilingualSetupSheet.kt (the ‹ Bilingual host),
//   ai/AiSettingsViewModel.kt (listState/editState/saveResult/setActive), ai/AiProviderEditSheet.kt,
//   backup/BackupScaffold.kt (BackupSurface), dev-docs/designs/…/vreader-ai-provider-entry.jsx
package com.vreader.app.bilingual

import androidx.activity.compose.BackHandler
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberUpdatedState
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.vreader.app.ai.AiProviderEditSheet
import com.vreader.app.ai.AiSettingsViewModel

/**
 * The stateful in-reader AI-Providers sheet. [vm] is the SHARED [AiSettingsViewModel] (its
 * `listState`/`editState`/`saveResult` drive the surfaces). [onDone] pops the WHOLE pushed stack back
 * to the bilingual sheet — called on ‹ Bilingual (from the list, no mutation) and on a successful Save
 * (after `setActive(savedId)`). When [vm.editState] is non-null the reused editor is shown over the
 * list; otherwise the scoped list is the visible surface.
 */
@Composable
fun ReaderAiProvidersSheet(
    vm: AiSettingsViewModel,
    onDone: () -> Unit,
) {
    val listState by vm.listState.collectAsStateWithLifecycle()
    val editState by vm.editState.collectAsStateWithLifecycle()

    // (c) The save-result seam: first Save → the saved id arrives AFTER the upsert commits → make it
    // the active engine, then pop the whole stack back to bilingual. `rememberUpdatedState` keeps the
    // effect keyed on `Unit` (one long-lived collector) while always calling the latest onDone.
    val currentOnDone by rememberUpdatedState(onDone)
    LaunchedEffect(Unit) {
        vm.saveResult.collect { savedId ->
            vm.setActive(savedId)
            currentOnDone()
        }
    }

    if (editState != null) {
        // (a) The reused editor, presented VERBATIM. Cancel pops back to the list; Save is handled by
        // the ViewModel (upsert → close editState → emit saveResult, consumed by the effect above).
        AiProviderEditSheet(
            state = editState!!,
            onKind = { k -> vm.update { it.copy(kind = k) } },
            onName = { n -> vm.update { it.copy(name = n) } },
            onBaseUrl = { b -> vm.update { it.copy(baseUrl = b) } },
            onModel = { m -> vm.update { it.copy(model = m) } },
            onTemperature = { temp -> vm.update { it.copy(temperature = temp) } },
            onMaxTokens = { mt -> vm.update { it.copy(maxTokens = mt) } },
            onApiKey = { key -> vm.update { it.copy(apiKey = key) } },
            onDeleteKey = { vm.update { it.copy(apiKey = "", keyAlreadySaved = false) } },
            onTest = vm::test,
            onSave = vm::save,
            onCancel = vm::close,
        )
        // Android system-back from the editor = the editor's Cancel (pop to the list, not the whole stack).
        BackHandler(enabled = true) { vm.close() }
    } else {
        // (b) The scoped list — tap a row to SELECT it (setActive), Add opens the editor, ‹ Bilingual
        // pops the whole stack with NO mutation.
        ReaderAiProvidersList(
            state = listState,
            onBack = onDone,
            onAdd = vm::openAdd,
            onSelect = { id -> vm.setActive(id) },
        )
        // Android system-back from the list = ‹ Bilingual (pop the whole stack, no mutation).
        BackHandler(enabled = true) { onDone() }
    }
}
