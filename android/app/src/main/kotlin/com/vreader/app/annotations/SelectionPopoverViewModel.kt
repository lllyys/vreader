// Purpose: feature #123 WI-3 — state holder for the in-reader selection popover (design
// vreader-android-annotations.jsx `SelectionPopover`). Three modes: SELECT (just-selected:
// Highlight/Note/Copy/Translate/Share + color row), NOTE (inline compose), EDIT (an existing
// highlight: Note/Copy/Share/Remove — wired in WI-4). Plain StateFlow holder (JVM-testable); the
// Activity owns it and performs the side effects (persist, decorate, copy, share).
package com.vreader.app.annotations

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

enum class PopoverMode { SELECT, NOTE, EDIT }

data class SelectionPopoverState(
    val visible: Boolean = false,
    val mode: PopoverMode = PopoverMode.SELECT,
    val activeColor: AnnotationColor = AnnotationColor.DEFAULT,
    val noteDraft: String = "",
    // anchor in the reader's content coordinates (px); the host positions the popover near it.
    val anchorX: Float = 0f,
    val anchorY: Float = 0f,
)

class SelectionPopoverViewModel {
    private val _state = MutableStateFlow(SelectionPopoverState())
    val state: StateFlow<SelectionPopoverState> = _state.asStateFlow()

    /** Show for a fresh selection (SELECT mode), anchored near the selection rect. */
    fun showForSelection(anchorX: Float, anchorY: Float) {
        _state.value = SelectionPopoverState(
            visible = true, mode = PopoverMode.SELECT, activeColor = AnnotationColor.DEFAULT,
            noteDraft = "", anchorX = anchorX, anchorY = anchorY,
        )
    }

    /** Show for an existing highlight (EDIT mode), seeding its current color/note. */
    fun showForExisting(color: AnnotationColor, note: String?, anchorX: Float, anchorY: Float) {
        _state.value = SelectionPopoverState(
            visible = true, mode = PopoverMode.EDIT, activeColor = color,
            noteDraft = note.orEmpty(), anchorX = anchorX, anchorY = anchorY,
        )
    }

    fun selectColor(color: AnnotationColor) {
        _state.value = _state.value.copy(activeColor = color)
    }

    /** Switch to the inline note-compose row (from SELECT or EDIT). */
    fun beginNote() {
        _state.value = _state.value.copy(mode = PopoverMode.NOTE)
    }

    fun updateNoteDraft(text: String) {
        _state.value = _state.value.copy(noteDraft = text)
    }

    fun dismiss() {
        _state.value = _state.value.copy(visible = false)
    }
}
