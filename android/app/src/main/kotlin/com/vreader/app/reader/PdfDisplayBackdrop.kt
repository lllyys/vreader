// Purpose: feature #129 WI-7 (#110 Phase 3) — the pure `ReaderSettings → PDF viewer backdrop Color`
// the PDF reader host paints behind its page bitmaps. PDF is RASTERIZED (it can't reflow), so it
// inherits ONLY the theme background from the global ReaderSettingsStore — font family/size/spacing/
// margin don't apply, and PDF has NO Display sheet / NO Aa slot (a theme-only reduced sheet would be
// undesigned — rule 51). Mirrors iOS, where PDFKit gets no reader typography either (only the page
// backdrop tracks the theme). Deterministic value type (JVM-unit-testable, PdfDisplayBackdropTest) —
// no Android runtime beyond Compose Color.
//
// @coordinates-with: PdfReaderActivity.kt (collects ReaderSettings, applies pdfBackdrop() to the
//   viewer backdrop live), ReaderSettings.kt / ReaderTheme.kt (the value type + theme colors).
package com.vreader.app.reader

import androidx.compose.ui.graphics.Color
import com.vreader.app.reader.settings.ReaderSettings

/**
 * The viewer-backdrop [Color] the PDF reader paints behind its page bitmaps for these display
 * [ReaderSettings]. PDF applies the theme background ONLY (it can't reflow, so typography is inert);
 * the mapping is intentionally the theme's [background] so the surround matches the reflowable readers.
 */
fun ReaderSettings.pdfBackdrop(): Color = theme.background
