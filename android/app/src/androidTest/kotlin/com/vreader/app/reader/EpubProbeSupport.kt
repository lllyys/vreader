package com.vreader.app.reader

import androidx.compose.ui.graphics.toArgb
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.vreader.app.VReaderApp
import com.vreader.app.data.Book
import com.vreader.app.reader.settings.ReaderFontFamily
import com.vreader.app.reader.settings.ReaderLayout
import com.vreader.app.reader.settings.ReaderSettings
import kotlinx.coroutines.runBlocking
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.readium.r2.navigator.epub.EpubPreferences
import org.readium.r2.navigator.preferences.Color as ReadiumColor
import org.readium.r2.navigator.preferences.FontFamily as ReadiumFontFamily
import org.readium.r2.shared.ExperimentalReadiumApi
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.zip.CRC32
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

/**
 * Feature #156 — fixtures and DOM-state predicates shared by the EPUB computed-style tests
 * ([EpubDomProbe]'s callers).
 *
 * **Real books first.** [EN_FILE] / [ZH_FILE] are the genuine gitignored EPUBs pushed to the app's scoped
 * external files dir, and they carry every primary assertion. The connected task wipes that dir at run
 * END — re-push before every run; the byte-size checks refuse to label a truncated/stale file "real".
 *
 * [publisherAlignedEpubBytes] is the one synthetic input, under the stated AGENTS.md exception *"the test
 * needs a deterministic tiny structure a real book can't give cheaply"*: verifying that ReadiumCSS's
 * `text-align: inherit !important` override does not flatten a publisher's own alignment requires a
 * paragraph that carries `text-align` **on the `<p>` itself**, and a `blockquote` that carries its own.
 * The real Latin EPUB has neither — an exhaustive scan of its markup + CSS finds `text-align` only on two
 * container classes (`.chapter-intro`, `.front-epi-body`), never on a `p`, `li` or `blockquote`. It is
 * built in-memory rather than committed as a binary asset so the markup under test is readable in the
 * diff that asserts on it.
 */
object EpubFixtures {
    const val EN_FILE = "m3-en.epub"
    const val EN_BYTES = 1_302_140L
    const val ZH_FILE = "m3-zh.epub"
    const val ZH_BYTES = 19_381_838L

    private val instrumentation get() = InstrumentationRegistry.getInstrumentation()
    val app: VReaderApp get() = instrumentation.targetContext.applicationContext as VReaderApp

    /** Import the genuine pushed EPUB; fails loudly (never silently substitutes) if absent or wrong-sized. */
    fun importRealEpub(file: String, expectedBytes: Long): Book {
        val dir = requireNotNull(instrumentation.targetContext.getExternalFilesDir(null)) { "no external files dir" }
        val f = File(dir, file)
        assertTrue(
            "this test requires the REAL EPUB at ${f.absolutePath} — push it before the run " +
                "(the connected task wipes this dir at run end)",
            f.exists() && f.canRead(),
        )
        assertEquals("$file must be the genuine real book, not a truncated/stale copy", expectedBytes, f.length())
        return runBlocking { app.container.importer.importStream("content://test/$file", file, f.inputStream()) }
    }

    /** Import an in-memory EPUB under a run-unique name (the importer dedupes by content fingerprint). */
    fun importBytes(name: String, bytes: ByteArray): Book = runBlocking {
        app.container.importer.importStream("content://test/$name", name, bytes.inputStream())
    }

    private const val PROSE =
        "The half second is the interval in which a decision is still reversible, and it is also the " +
            "interval in which almost nobody is paying attention. Every sentence in this paragraph exists " +
            "only so the line boxes are long enough that inter-word justification has real slack to " +
            "distribute across several wrapped lines of Latin prose."

    /**
     * A tiny EPUB whose chapter carries **publisher alignment on the elements ReadiumCSS overrides**:
     *  • `<p>` with its own `text-align: center` (the element the advanced-gate rule forces to `inherit`);
     *  • `<blockquote>` with its own `text-align: right` wrapping a `<p>` (the container is NOT in the
     *    override list, so its prose must keep inheriting the publisher's alignment);
     *  • `<p>` with `text-align-last: justify` — the only way to discriminate the second half of that rule
     *    (`text-align-last: auto !important`), since `auto` is also the CSS initial value, so a book that
     *    never sets it would make the assertion trivially true;
     *  • the **whole** set of elements the advanced type-scale block names — `h1`–`h4`, `small`, `sub`,
     *    `sup` — plus a `<p>` at `0.75em`, each at a publisher size the block overrides.
     */
    fun publisherAlignedEpubBytes(): ByteArray {
        val chapter = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml"><head><title>Alignment</title><style>
h1{font-size:3em}h2{font-size:2em}h3{font-size:1.9em}h4{font-size:1.8em}
p.tiny{font-size:0.75em}small{font-size:1.7em}sub{font-size:1.6em}sup{font-size:1.55em}
p.pub-center{text-align:center}blockquote.pub-right{text-align:right}
p.pub-lastjustify{text-align:justify;text-align-last:justify}
</style></head>
<body><h1>Publisher alignment of a heading long enough to wrap onto a second line</h1><h2>Second level</h2>
<h3>Third level</h3><h4>Fourth level</h4>
<p class="plain">$PROSE</p>
<p class="pub-center">$PROSE</p>
<blockquote class="pub-right"><p>$PROSE</p></blockquote>
<p class="pub-lastjustify">$PROSE</p>
<p class="tiny">$PROSE</p>
<p class="marks"><small>small text</small> <sub>subscript</sub> <sup>superscript</sup></p>
</body></html>"""
        val opf = """<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:vreader-156-wi2-publisher-aligned</dc:identifier>
    <dc:title>Publisher Alignment Fixture</dc:title>
    <dc:language>en</dc:language>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine><itemref idref="ch1"/></spine>
</package>"""
        val nav = """<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops"><head><title>nav</title></head>
<body><nav epub:type="toc"><ol><li><a href="ch1.xhtml">Alignment</a></li></ol></nav></body></html>"""

        val out = ByteArrayOutputStream()
        ZipOutputStream(out).use { zip ->
            // `mimetype` must be the FIRST entry and STORED (uncompressed) or the container is not an EPUB.
            val mime = "application/epub+zip".toByteArray()
            zip.putNextEntry(
                ZipEntry("mimetype").apply {
                    method = ZipEntry.STORED
                    size = mime.size.toLong()
                    compressedSize = mime.size.toLong()
                    crc = CRC32().apply { update(mime) }.value
                },
            )
            zip.write(mime)
            zip.closeEntry()
            fun add(path: String, text: String) {
                zip.putNextEntry(ZipEntry(path))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
            add(
                "META-INF/container.xml",
                """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/></rootfiles>
</container>""",
            )
            add("OEBPS/content.opf", opf)
            add("OEBPS/nav.xhtml", nav)
            add("OEBPS/ch1.xhtml", chapter)
        }
        return out.toByteArray()
    }
}

/**
 * Restores the global display settings around each test, and pins the open-time state the "production"
 * readings are taken under — the reader applies `current().toEpubPreferences()` via its initialPrefs, so a
 * test that did not pin these would be measuring whatever a previous class left behind.
 */
abstract class ReaderSettingsIsolatedTest {
    private lateinit var original: ReaderSettings

    @Before fun captureReaderSettings() = runBlocking<Unit> {
        val store = EpubFixtures.app.container.readerSettingsStore
        original = store.current()
        store.setLayout(ReaderLayout.Scroll)
        store.setLineSpacing(ReaderSettings.DEFAULT_LINE_SPACING)
        store.setFontSize(ReaderSettings.DEFAULT_FONT_SIZE)
    }

    @After fun restoreReaderSettings() = runBlocking<Unit> {
        val store = EpubFixtures.app.container.readerSettingsStore
        store.setTheme(original.theme)
        store.setFontFamily(original.fontFamily)
        store.setFontSize(original.fontSizeSp)
        store.setLineSpacing(original.lineSpacing)
        store.setMargin(original.marginDp)
        store.setLayout(original.layout)
    }

    protected fun currentSettings(): ReaderSettings =
        runBlocking { EpubFixtures.app.container.readerSettingsStore.current() }

    protected fun launchReader(book: Book): ActivityScenario<ReaderActivity> =
        ActivityScenario.launch(
            ReaderActivity.intent(InstrumentationRegistry.getInstrumentation().targetContext, book.fingerprintKey),
        )
}

private const val REFERENCE_FONT_SIZE_SP = 18.0
private const val REFERENCE_MARGIN_DP = 20.0

/**
 * The **pre-#156 production mapping**, reconstructed field for field — every property `toEpubPreferences`
 * set before feature #156 WI-2, and only those. This is the control arm of every with/without pair: if a
 * reading under these preferences already showed `justify`, the with-flag reading would prove nothing.
 * It is spelled out rather than derived from the production mapper so a future change to the mapper cannot
 * silently move the control along with the subject.
 */
@OptIn(ExperimentalReadiumApi::class)
fun legacyPreferences(s: ReaderSettings): EpubPreferences = EpubPreferences(
    fontSize = s.fontSizeSp / REFERENCE_FONT_SIZE_SP,
    fontFamily = when (s.fontFamily) {
        ReaderFontFamily.Serif -> ReadiumFontFamily.SERIF
        ReaderFontFamily.Sans -> ReadiumFontFamily.SANS_SERIF
    },
    lineHeight = s.lineSpacing.toDouble(),
    pageMargins = s.marginDp / REFERENCE_MARGIN_DP,
    backgroundColor = ReadiumColor(s.theme.background.toArgb()),
    textColor = ReadiumColor(s.theme.ink.toArgb()),
)

/** The probe's `<p>` computed-alignment census as a Kotlin map (alignment → count). */
fun censusOf(p: JSONObject): Map<String, Int> {
    val o = p.optJSONObject("census") ?: return emptyMap()
    return o.keys().asSequence().associateWith { o.optInt(it) }
}

/** True when ReadiumCSS's advanced-settings gate (`publisherStyles = false`) is on in the live DOM. */
fun advancedOn(p: JSONObject) = p.optString("rootStyle").contains("readium-advanced-on")

/** True when [decl] (e.g. `--USER__textAlign: justify`) is present in the live `<html>` inline style. */
fun hasDecl(p: JSONObject, decl: String) = p.optString("rootStyle").contains(decl)

/**
 * The resource + element identity a multi-state comparison must hold constant. The probe is deliberately
 * read-only (minting an id would mutate the DOM under measurement), so identity is the resource path plus
 * the measured element's tag, text prefix and text length — the tag matters because the probe falls back
 * from `p` to a block element, and a fallback with the same text prefix would otherwise read as "the same
 * element" while being a different one.
 */
fun sameContent(states: List<JSONObject>) =
    listOf("docHref", "textHead", "tag").all { key -> states.map { it.optString(key) }.distinct().size == 1 } &&
        states.map { it.optInt("textLen") }.distinct().size == 1

/** A CSS `<length>px` reading, or null when the DOM returned something unusable (e.g. `normal`, ""). */
fun pxOrNull(v: String): Double? = v.removeSuffix("px").toDoubleOrNull()?.takeIf { v.endsWith("px") }
