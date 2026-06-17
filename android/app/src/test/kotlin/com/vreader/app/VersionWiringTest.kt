// Purpose: feature #106 WI-1 smoke test — proves the version-plumbing CHAIN
// (`android/version.properties` → defaultConfig → BuildConfig) actually wires
// through, by reading version.properties at test time and comparing to the
// generated BuildConfig (Codex Gate-4: a hardcoded expectation is a version pin,
// not a wiring proof). Runs on the JVM via Robolectric (no emulator) through
// `scripts/run-android-tests.sh`.
package com.vreader.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import vreader.contracts.Identity
import java.io.File
import java.util.Properties

@RunWith(RobolectricTestRunner::class)
class VersionWiringTest {

    // Gradle runs unit tests with workingDir = the module dir (android/app), so
    // `../version.properties` resolves to the root android/version.properties —
    // the SAME file the build reads into defaultConfig.
    private fun versionProperties(): Properties {
        val file = File("../version.properties")
        assertTrue("version.properties not found at ${file.absolutePath}", file.exists())
        return Properties().apply { file.inputStream().use { load(it) } }
    }

    @Test
    fun buildConfigMatchesVersionProperties() {
        val props = versionProperties()
        // Whatever version.properties declares MUST be what BuildConfig carries —
        // proves the chain wires, and survives legitimate version bumps.
        assertEquals(props.getProperty("versionName"), BuildConfig.VERSION_NAME)
        assertEquals(props.getProperty("versionCode").toInt(), BuildConfig.VERSION_CODE)
    }

    @Test
    fun applicationIdIsTheVreaderNamespace() {
        assertEquals("com.vreader.app", BuildConfig.APPLICATION_ID)
        assertTrue(BuildConfig.VERSION_CODE >= 1)
    }

    @Test
    fun appLinksTheSharedIdentityModule() {
        // Proves :app depends on :identity (WI-2) — the same module the
        // conformance lane tests, so cross-platform identity is the app's code.
        val key = Identity.canonicalKey("epub", "a".repeat(64), 1024)
        assertEquals("epub:${"a".repeat(64)}:1024", key)
    }
}
