package com.vreader.app.backup

import org.junit.Assert.assertEquals
import org.junit.Test

/** Feature #114 WI-3 — the status→color mapping is a pure function, JVM-unit-tested across all
 *  three branches (the instrumented test can't assert pixel color). */
class BackupColorTest {
    @Test fun statusColor_mapsEachBranch() {
        val t = BackupTokens.Light
        assertEquals(t.green, serverStatusColor(ServerStatus.ok, t))
        assertEquals(t.red, serverStatusColor(ServerStatus.error, t))
        assertEquals(t.sec, serverStatusColor(ServerStatus.unknown, t))
    }

    @Test fun statusColor_usesDarkPalette() {
        val t = BackupTokens.Dark
        assertEquals(t.green, serverStatusColor(ServerStatus.ok, t))
        assertEquals(t.red, serverStatusColor(ServerStatus.error, t))
    }
}
