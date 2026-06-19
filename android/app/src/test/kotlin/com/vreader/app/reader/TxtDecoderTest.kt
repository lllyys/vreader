package com.vreader.app.reader

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.charset.Charset

/**
 * TxtDecoder charset detection (feature #111 WI-1). BOM-first is deterministic; the
 * real fixture is UTF-16LE+BOM CJK, exercised here synthetically (CI can't read the
 * gitignored test-books/, so a constructed UTF-16LE CJK byte array stands in).
 */
class TxtDecoderTest {
    private val cjk = "测试文本\n第二行"

    @Test fun utf8_noBom_isConfident() {
        val r = TxtDecoder.decode("Hello, world\nsecond".toByteArray(Charsets.UTF_8))
        assertEquals("UTF-8", r.charsetName)
        assertTrue(r.confident)
        assertEquals("Hello, world\nsecond", r.text)
    }

    @Test fun utf8_withBom_stripsBom() {
        val bom = byteArrayOf(0xEF.toByte(), 0xBB.toByte(), 0xBF.toByte())
        val r = TxtDecoder.decode(bom + cjk.toByteArray(Charsets.UTF_8))
        assertEquals("UTF-8", r.charsetName)
        assertTrue(r.confident)
        assertEquals(cjk, r.text)                      // BOM removed
        assertFalse("no U+FEFF leftover", r.text.startsWith("﻿"))
    }

    @Test fun utf16le_withBom_decodesCjk() {
        val bom = byteArrayOf(0xFF.toByte(), 0xFE.toByte())
        val r = TxtDecoder.decode(bom + cjk.toByteArray(Charsets.UTF_16LE))
        assertEquals("UTF-16LE", r.charsetName)
        assertTrue(r.confident)
        assertEquals(cjk, r.text)
    }

    @Test fun utf16be_withBom_decodesCjk() {
        val bom = byteArrayOf(0xFE.toByte(), 0xFF.toByte())
        val r = TxtDecoder.decode(bom + cjk.toByteArray(Charsets.UTF_16BE))
        assertEquals("UTF-16BE", r.charsetName)
        assertTrue(r.confident)
        assertEquals(cjk, r.text)
    }

    @Test fun gbk_bomlessCjk_fallsBackLowConfidence() {
        val gbk = Charset.forName("GBK")
        val bytes = cjk.toByteArray(gbk)               // valid GBK, NOT valid UTF-8
        val r = TxtDecoder.decode(bytes)
        assertEquals("GBK", r.charsetName)
        assertFalse("heuristic guess is not confident", r.confident)
        assertEquals(cjk, r.text)
    }

    @Test fun emptyFile_decodesToEmpty_notConfident() {
        val r = TxtDecoder.decode(ByteArray(0))
        assertEquals("", r.text)
        assertFalse("empty input has no charset evidence", r.confident)
    }

    @Test fun decode_neverThrows_onArbitraryBytes() {
        // 0xFF 0xFF isn't a UTF-16 BOM, fails strict UTF-8; the replacement fallback
        // must still produce a (lossy) string rather than throw.
        val r = TxtDecoder.decode(byteArrayOf(0xFF.toByte(), 0xFF.toByte(), 0x41))
        assertTrue(r.text.isNotEmpty())
    }
}
