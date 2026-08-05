// Purpose: feature #155 WI-2 — a fast STRUCTURAL check of the inbound-document
// manifest surface. It parses `src/main/AndroidManifest.xml` as XML and asserts the
// shape the plan's §4 specifies: FOUR separate <intent-filter> elements on
// ImportActivity, their actions/categories/schemes/mimeTypes/pathPatterns, the
// translucent (never NoDisplay) theme, and that MainActivity's own filter block is
// byte-identical.
//
// It deliberately does NOT run through Robolectric's resolver: Robolectric's intent
// resolution is a SHADOW PackageManager whose PatternMatcher need not reproduce the
// platform's pathPattern behaviour (Gate-2 round 2, M4). Real matching is proven by
// `ImportFilterResolutionConnectedTest` on a device; this file only proves the
// manifest says what we think it says.
package com.vreader.app.imports

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.w3c.dom.Element
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

class ImportIntentFilterTest {

    private data class ParsedFilter(
        val actions: Set<String>,
        val categories: Set<String>,
        val schemes: Set<String>,
        val hosts: Set<String>,
        val mimeTypes: List<String>,
        val pathPatterns: List<String>,
    )

    private fun manifestFile(): File {
        // Gradle runs unit tests with workingDir = the module dir (android/app).
        val file = File("src/main/AndroidManifest.xml")
        assertTrue("manifest not found at ${file.absolutePath}", file.exists())
        return file
    }

    private fun activityElement(name: String): Element {
        val doc = DocumentBuilderFactory.newInstance()
            .apply { isNamespaceAware = true }
            .newDocumentBuilder()
            .parse(manifestFile())
        val activities = doc.getElementsByTagName("activity")
        val matches = (0 until activities.length)
            .map { activities.item(it) as Element }
            .filter { it.getAttributeNS(ANDROID_NS, "name") == name }
        assertEquals("exactly one <activity> named $name", 1, matches.size)
        return matches.single()
    }

    private fun filtersOf(activity: Element): List<ParsedFilter> {
        val nodes = activity.getElementsByTagName("intent-filter")
        return (0 until nodes.length).map { i ->
            val f = nodes.item(i) as Element
            fun values(tag: String, attr: String): List<String> {
                val n = f.getElementsByTagName(tag)
                return (0 until n.length)
                    .map { (n.item(it) as Element).getAttributeNS(ANDROID_NS, attr) }
                    .filter { it.isNotEmpty() }
            }
            ParsedFilter(
                actions = values("action", "name").toSet(),
                categories = values("category", "name").toSet(),
                schemes = values("data", "scheme").toSet(),
                hosts = values("data", "host").toSet(),
                mimeTypes = values("data", "mimeType"),
                pathPatterns = values("data", "pathPattern"),
            )
        }
    }

    private fun importFilters(): List<ParsedFilter> = filtersOf(activityElement(IMPORT_ACTIVITY))

    @Test
    fun importActivityDeclaresExactlyFourSeparateFilters() {
        // <data> elements MERGE into a cross-product WITHIN one filter, so MIME
        // matching and pathPattern matching must never share a filter.
        assertEquals(4, importFilters().size)
    }

    @Test
    fun mimeAndPathNeverShareAFilter() {
        importFilters().forEach { f ->
            assertFalse(
                "a filter carries both mimeType and pathPattern (they would cross-product)",
                f.mimeTypes.isNotEmpty() && f.pathPatterns.isNotEmpty(),
            )
        }
    }

    @Test
    fun filterA_viewByMime_hasBothSchemesAndTheFullMimeList() {
        val a = importFilters().single { VIEW in it.actions && it.mimeTypes.isNotEmpty() }
        assertEquals(setOf(VIEW), a.actions)
        assertEquals(setOf(DEFAULT, BROWSABLE), a.categories)
        assertEquals(setOf("content", "file"), a.schemes)
        assertEquals(MIME_TYPES, a.mimeTypes)
        assertTrue("filter A must not path-match", a.pathPatterns.isEmpty())
        assertTrue("filter A must not constrain host", a.hosts.isEmpty())
    }

    @Test
    fun filterB_viewByExtension_isContentOnly_typeless_andEnumeratesEveryPathPattern() {
        val b = importFilters().single { VIEW in it.actions && it.pathPatterns.isNotEmpty() }
        assertEquals(setOf(VIEW), b.actions)
        assertEquals(setOf(DEFAULT, BROWSABLE), b.categories)
        // file:// has an EMPTY authority, so host="*" can never match it — content only.
        assertEquals(setOf("content"), b.schemes)
        assertEquals(setOf("*"), b.hosts)
        assertTrue("filter B must carry no mimeType (a typeless VIEW is its only job)", b.mimeTypes.isEmpty())
        assertEquals(expectedPathPatterns(), b.pathPatterns.toSet())
        assertEquals("no duplicate pathPatterns", b.pathPatterns.size, b.pathPatterns.toSet().size)
    }

    @Test
    fun filterC_send_matchesOnTypeAlone_andIsNotBrowsable() {
        val c = importFilters().single { SEND in it.actions }
        assertEquals(setOf(SEND), c.actions)
        assertEquals(setOf(DEFAULT), c.categories)
        assertEquals(MIME_TYPES, c.mimeTypes)
        // SEND's payload is EXTRA_STREAM/ClipData, never intent.data.
        assertTrue(c.schemes.isEmpty() && c.hosts.isEmpty() && c.pathPatterns.isEmpty())
    }

    @Test
    fun filterD_sendMultiple_mirrorsSend() {
        val d = importFilters().single { SEND_MULTIPLE in it.actions }
        assertEquals(setOf(SEND_MULTIPLE), d.actions)
        assertEquals(setOf(DEFAULT), d.categories)
        assertEquals(MIME_TYPES, d.mimeTypes)
        assertTrue(d.schemes.isEmpty() && d.hosts.isEmpty() && d.pathPatterns.isEmpty())
    }

    @Test
    fun importActivityIsExportedWithAnIsolatedTaskModel() {
        val a = activityElement(IMPORT_ACTIVITY)
        assertEquals("true", a.getAttributeNS(ANDROID_NS, "exported"))
        assertEquals("", a.getAttributeNS(ANDROID_NS, "taskAffinity"))
        assertTrue("taskAffinity must be DECLARED (empty), not absent", a.hasAttributeNS(ANDROID_NS, "taskAffinity"))
        assertEquals("true", a.getAttributeNS(ANDROID_NS, "noHistory"))
        assertEquals("true", a.getAttributeNS(ANDROID_NS, "excludeFromRecents"))
        assertEquals("@style/Theme.VReader.Import", a.getAttributeNS(ANDROID_NS, "theme"))
        // Rule 51: no user-visible copy is invented — the chooser inherits the app label.
        assertFalse("ImportActivity must not declare its own label", a.hasAttributeNS(ANDROID_NS, "label"))
    }

    @Test
    fun importThemeIsTranslucentAndNotNoDisplay() {
        val file = File("src/main/res/values/themes.xml")
        assertTrue("themes.xml not found at ${file.absolutePath}", file.exists())
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val styles = doc.getElementsByTagName("style")
        val theme = (0 until styles.length)
            .map { styles.item(it) as Element }
            .single { it.getAttribute("name") == "Theme.VReader.Import" }
        val items = theme.getElementsByTagName("item")
        val declared = (0 until items.length).associate { i ->
            val item = items.item(i) as Element
            item.getAttribute("name") to item.textContent.trim()
        }
        assertEquals("true", declared["android:windowIsTranslucent"])
        assertEquals("@android:color/transparent", declared["android:windowBackground"])
        assertEquals("true", declared["android:windowNoTitle"])
        assertEquals("false", declared["android:windowIsFloating"])
        assertEquals("false", declared["android:backgroundDimEnabled"])
        // A NoDisplay activity must finish before it would become visible; this one must
        // stay alive long enough to open the incoming streams (plan D2/D6).
        assertFalse("windowNoDisplay is forbidden", declared.containsKey("android:windowNoDisplay"))
        assertFalse("NoDisplay parent is forbidden", theme.getAttribute("parent").contains("NoDisplay"))
    }

    @Test
    fun mainActivityFilterBlockIsByteIdentical() {
        val raw = manifestFile().readText()
        assertTrue(
            "MainActivity's declaration changed — WI-2 must leave it byte-identical",
            raw.contains(MAIN_ACTIVITY_BLOCK),
        )
        assertEquals(1, filtersOf(activityElement(".MainActivity")).size)
    }

    /**
     * The pathPatterns the manifest SOURCE must spell out.
     *
     * Note the escaping level: this test reads the un-compiled `AndroidManifest.xml`, so a
     * literal dot is written `\\.` there (aapt collapses it to `\.` in the binary manifest
     * the platform's PatternMatcher actually sees). Hence the Kotlin literal below is
     * `".*\\\\."` — four source backslashes ⇒ two real ones ⇒ one after aapt.
     */
    private fun expectedPathPatterns(): Set<String> =
        EXTENSIONS.flatMap { ext ->
            listOf(ext, ext.uppercase()).flatMap { cased ->
                // PATTERN_SIMPLE_GLOB has no reliable backtracking: `.*\.epub` stops at the
                // FIRST dot, so a path with earlier dots needs extra `.*\.` repeats.
                (0..2).map { extra -> ".*\\\\.".repeat(extra + 1) + cased }
            }
        }.toSet()

    private companion object {
        const val ANDROID_NS = "http://schemas.android.com/apk/res/android"
        const val IMPORT_ACTIVITY = ".imports.ImportActivity"
        const val VIEW = "android.intent.action.VIEW"
        const val SEND = "android.intent.action.SEND"
        const val SEND_MULTIPLE = "android.intent.action.SEND_MULTIPLE"
        const val DEFAULT = "android.intent.category.DEFAULT"
        const val BROWSABLE = "android.intent.category.BROWSABLE"

        val EXTENSIONS = listOf("epub", "pdf", "txt", "md", "markdown", "azw3", "azw", "mobi", "prc")

        val MIME_TYPES = listOf(
            "application/epub+zip",
            "application/x-epub+zip",
            "application/epub",
            "application/pdf",
            "application/x-pdf",
            "text/plain",
            "text/markdown",
            "text/x-markdown",
            "application/vnd.amazon.ebook",
            "application/vnd.amazon.mobi8-ebook",
            "application/x-mobipocket-ebook",
            "application/octet-stream",
        )

        val MAIN_ACTIVITY_BLOCK = """
            |        <activity
            |            android:name=".MainActivity"
            |            android:exported="true">
            |            <intent-filter>
            |                <action android:name="android.intent.action.MAIN" />
            |                <category android:name="android.intent.category.LAUNCHER" />
            |            </intent-filter>
            |        </activity>
        """.trimMargin()
    }
}
