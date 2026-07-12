// Purpose: feature #131 WI-AIP — the NEW reader-scoped AI-Providers LIST presentation (the "(b)"
// half of the folded-in Variant-A entry, round-4 High-4). A faithful reproduction of
// `vreader-ai-provider-entry.jsx`'s `NavSheet` (‹ Bilingual back + centered "AI Providers" title)
// + `AIProvidersSheetBody` (the why-you're-here bilingual context strip; the empty "No providers
// yet" onboarding; the populated card with a CHECKED-ACTIVE row (`selected = row.active`) and a
// trailing "Add provider" row) + `ProviderRow` (brand tile + name + model + "IN USE"+check when
// selected, chevron otherwise). Tap on a row = SELECT (fires `onSelect(id)` → the host's
// `vm.setActive(id)`), NOT edit. Reproduces ONLY the depicted surface (rule 51); it deliberately
// does NOT reuse AiProviderListScreen's NavScreen chrome / generic AiEmptyState / tap-to-EDIT rows.
//
// Rendered inside a BackupSurface so it shares the LocalBackupTokens palette with the reused
// AiProviderEditSheet ((a)). Stateless: a pure function of the shared AiProviderListState + callbacks.
//
// @coordinates-with: ReaderAiProvidersSheet.kt, ai/AiSettingsViewModel.kt (listState), ai/AiSettingsUiState.kt,
//   backup/BackupScaffold.kt (LocalBackupTokens/BackupFonts), backup/BackupTokens.kt,
//   dev-docs/designs/vreader-fidelity-v1/project/vreader-ai-provider-entry.jsx
package com.vreader.app.bilingual

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBackIos
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Translate
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.vreader.app.ai.AiProviderListState
import com.vreader.app.ai.AiProviderRow
import com.vreader.app.backup.BackupFonts
import com.vreader.app.backup.GroupHeader
import com.vreader.app.backup.LocalBackupTokens
import com.vreader.app.backup.VSpace

/** The design's fixed brand color for the AI provider tile (theme-independent — jsx `AIPE_BRAND`). */
private val AipeBrand = Color(0xFF8C2F2F)

/**
 * The scoped in-reader AI-Providers list. [state] is the SHARED [AiProviderListState] from
 * `AiSettingsViewModel.listState` (each row already carries `active`). [onBack] returns to the
 * bilingual sheet (‹ Bilingual). [onAdd] opens the reused editor. [onSelect] fires with a row id when
 * a provider row is tapped (the host runs `vm.setActive(id)`).
 */
@Composable
fun ReaderAiProvidersList(
    state: AiProviderListState,
    onBack: () -> Unit,
    onAdd: () -> Unit,
    onSelect: (String) -> Unit,
) {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxWidth()
            .background(t.sheetBg)
            .systemBarsPadding()
            .testTag("reader-ai-providers-list"),
    ) {
        // NavSheet nav bar: ‹ Bilingual back (leading, accent) + absolutely-centered serif title.
        Box(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 12.dp)) {
            Row(
                Modifier.align(Alignment.CenterStart)
                    .clip(RoundedCornerShape(8.dp))
                    .clickable(onClickLabel = "Bilingual", onClick = onBack)
                    .testTag("reader-ai-back")
                    .padding(4.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBackIos, contentDescription = null, tint = t.tint, modifier = Modifier.size(15.dp))
                Text("Bilingual", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium)
            }
            Text(
                "AI Providers",
                Modifier.align(Alignment.Center),
                color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
            )
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep))

        Column(
            Modifier.fillMaxWidth().verticalScroll(rememberScrollState())
                .padding(horizontal = 18.dp).padding(top = 14.dp, bottom = 28.dp),
        ) {
            // The why-you're-here context — the bilingual thread, kept visible (jsx:167–183).
            ContextStrip()

            VSpace(18)

            if (state.unconfigured) {
                EmptyState(onAdd = onAdd)
            } else {
                GroupHeader("Providers")
                Column(
                    Modifier.fillMaxWidth().padding(top = 8.dp).clip(RoundedCornerShape(14.dp)).background(t.card),
                ) {
                    state.providers.forEach { p ->
                        ProviderRow(p, onSelect = onSelect)
                    }
                    AddProviderRow(onAdd = onAdd)
                }
                Text(
                    "Tap a provider to use it for translating this book.",
                    color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, lineHeight = 17.sp,
                    modifier = Modifier.padding(horizontal = 4.dp).padding(top = 10.dp),
                )
            }
        }
    }
}

/** The bilingual-context strip (jsx:167–183): translate glyph + "Choose the provider bilingual mode…". */
@Composable
private fun ContextStrip() {
    val t = LocalBackupTokens.current
    Row(
        Modifier.fillMaxWidth()
            .clip(RoundedCornerShape(10.dp))
            .background(t.chipBg)
            .padding(horizontal = 12.dp, vertical = 10.dp)
            .testTag("reader-ai-context"),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(22.dp).clip(CircleShape).background(t.tagBg),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Translate, contentDescription = null, tint = t.tint, modifier = Modifier.size(13.dp)) }
        Text(
            "Choose the provider bilingual mode will use to translate this book.",
            color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 11.5.sp, lineHeight = 16.sp,
            modifier = Modifier.padding(start = 10.dp),
        )
    }
}

/** The empty "No providers yet" onboarding (jsx:185–210) — bilingual-context copy + Add provider CTA. */
@Composable
private fun EmptyState(onAdd: () -> Unit) {
    val t = LocalBackupTokens.current
    Column(
        Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 8.dp).testTag("reader-ai-empty"),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Box(Modifier.size(54.dp).clip(CircleShape).background(t.tint), contentAlignment = Alignment.Center) {
            Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        }
        VSpace(14)
        Text("No providers yet", color = t.ink, fontFamily = BackupFonts.Serif, fontSize = 18.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center)
        VSpace(6)
        Text(
            "Add Claude, OpenAI, or any OpenAI-compatible endpoint. Your API key is stored in the device keychain — never synced.",
            color = t.sec, fontFamily = BackupFonts.Sans, fontSize = 12.5.sp, lineHeight = 19.sp, textAlign = TextAlign.Center,
        )
        VSpace(20)
        Row(
            Modifier.clip(RoundedCornerShape(100.dp)).background(t.tint)
                .clickable(onClickLabel = "Add provider", onClick = onAdd)
                .testTag("reader-ai-add").padding(horizontal = 20.dp, vertical = 11.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp))
            Text("Add provider", color = Color.White, fontFamily = BackupFonts.Sans, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.padding(start = 7.dp))
        }
    }
}

/** One provider row (jsx `ProviderRow`): brand tile + name + model + selected("IN USE"+check) / chevron. */
@Composable
private fun ProviderRow(p: AiProviderRow, onSelect: (String) -> Unit) {
    val t = LocalBackupTokens.current
    Box {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 60.dp)
                .clickable(onClickLabel = "Use ${p.name}", onClick = { onSelect(p.id) })
                .testTag("reader-provider-${p.id}").padding(horizontal = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(AipeBrand),
                contentAlignment = Alignment.Center,
            ) { Icon(Icons.Filled.AutoAwesome, contentDescription = null, tint = Color.White, modifier = Modifier.size(17.dp)) }
            Column(Modifier.weight(1f).padding(start = 12.dp)) {
                Text(p.name, color = t.ink, fontFamily = BackupFonts.Sans, fontSize = 15.sp)
                Text(p.detail, color = t.sec, fontFamily = BackupFonts.Mono, fontSize = 11.sp, modifier = Modifier.padding(top = 1.dp))
            }
            if (p.active) {
                Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.testTag("reader-provider-${p.id}-active")) {
                    Text("In use", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold)
                    Icon(Icons.Filled.Check, contentDescription = "In use", tint = t.tint, modifier = Modifier.padding(start = 6.dp).size(16.dp))
                }
            } else {
                Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null, tint = t.sec, modifier = Modifier.size(15.dp))
            }
        }
        Box(Modifier.fillMaxWidth().height(0.5.dp).background(t.sep).align(Alignment.BottomStart))
    }
}

/** The trailing "Add provider" row inside the populated card (jsx:223–234). */
@Composable
private fun AddProviderRow(onAdd: () -> Unit) {
    val t = LocalBackupTokens.current
    Row(
        Modifier.fillMaxWidth().heightIn(min = 56.dp)
            .clickable(onClickLabel = "Add provider", onClick = onAdd)
            .testTag("reader-ai-add").padding(horizontal = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            Modifier.size(30.dp).clip(RoundedCornerShape(8.dp)).background(t.codeBg),
            contentAlignment = Alignment.Center,
        ) { Icon(Icons.Filled.Add, contentDescription = null, tint = t.tint, modifier = Modifier.size(18.dp)) }
        Text("Add provider", color = t.tint, fontFamily = BackupFonts.Sans, fontSize = 15.sp, fontWeight = FontWeight.Medium, modifier = Modifier.padding(start = 12.dp))
    }
}
