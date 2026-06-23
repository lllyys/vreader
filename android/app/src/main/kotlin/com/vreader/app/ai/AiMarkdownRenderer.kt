// Purpose: feature #118 WI-4 (#110 Phase 3) — renders a MULTI-LINE AI answer's markdown to a
// Compose AnnotatedString. The #112 `MarkdownRenderer` is a SINGLE-LINE chunk renderer (Gate-2
// High), so this wraps it: split the answer into lines, render each line's inline markdown
// (headings / bold / italic / code / bullets) via #112, assemble with newlines, and handle
// multi-line fenced code blocks (```) as monospace verbatim. Degrades partial/streaming markdown
// (an unclosed `**` or fence) to literal text — never crashes (it re-renders on every stream delta).
package com.vreader.app.ai

import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.withStyle
import com.vreader.app.reader.MarkdownRenderer

object AiMarkdownRenderer {
    /** Render [markdown] (a full or partial multi-line answer) to a styled AnnotatedString. */
    fun render(markdown: String): AnnotatedString = buildAnnotatedString {
        if (markdown.isEmpty()) return@buildAnnotatedString
        val lines = markdown.split("\n")
        var inFence = false
        var first = true
        lines.forEach { line ->
            val isFenceMarker = line.trimStart().startsWith("```")
            if (isFenceMarker) { inFence = !inFence; return@forEach }  // the ``` marker line isn't drawn
            if (!first) append("\n")
            first = false
            if (inFence) {
                withStyle(SpanStyle(fontFamily = FontFamily.Monospace)) { append(line) }
            } else {
                append(MarkdownRenderer.render(line))  // reuse #112's inline-span logic per line
            }
        }
    }
}
