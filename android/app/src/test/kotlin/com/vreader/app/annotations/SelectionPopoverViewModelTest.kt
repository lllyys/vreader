package com.vreader.app.annotations

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** Feature #123 WI-3 — [SelectionPopoverViewModel] mode/state transitions. */
class SelectionPopoverViewModelTest {
    private val vm = SelectionPopoverViewModel()

    @Test fun showForSelection_entersSelectMode_visibleWithDefaults() {
        vm.showForSelection(120f, 340f)
        val s = vm.state.value
        assertTrue(s.visible)
        assertEquals(PopoverMode.SELECT, s.mode)
        assertEquals(AnnotationColor.DEFAULT, s.activeColor)
        assertEquals(120f, s.anchorX)
        assertEquals(340f, s.anchorY)
        assertEquals("", s.noteDraft)
    }

    @Test fun showForExisting_entersEditMode_seedsColorAndNote() {
        vm.showForExisting(AnnotationColor.blue, "a thought", 10f, 20f)
        val s = vm.state.value
        assertTrue(s.visible)
        assertEquals(PopoverMode.EDIT, s.mode)
        assertEquals(AnnotationColor.blue, s.activeColor)
        assertEquals("a thought", s.noteDraft)
    }

    @Test fun showForExisting_nullNote_seedsEmptyDraft() {
        vm.showForExisting(AnnotationColor.green, null, 0f, 0f)
        assertEquals("", vm.state.value.noteDraft)
    }

    @Test fun selectColor_updatesActiveColor() {
        vm.showForSelection(0f, 0f)
        vm.selectColor(AnnotationColor.pink)
        assertEquals(AnnotationColor.pink, vm.state.value.activeColor)
    }

    @Test fun beginNote_switchesToNoteMode_keepingColor() {
        vm.showForSelection(0f, 0f)
        vm.selectColor(AnnotationColor.red)
        vm.beginNote()
        assertEquals(PopoverMode.NOTE, vm.state.value.mode)
        assertEquals(AnnotationColor.red, vm.state.value.activeColor)
    }

    @Test fun updateNoteDraft_accumulates_andLongNoteRetained() {
        vm.showForSelection(0f, 0f)
        vm.beginNote()
        val long = "x".repeat(5000)
        vm.updateNoteDraft(long)
        assertEquals(long, vm.state.value.noteDraft)
    }

    @Test fun dismiss_hides() {
        vm.showForSelection(0f, 0f)
        vm.dismiss()
        assertFalse(vm.state.value.visible)
    }
}
