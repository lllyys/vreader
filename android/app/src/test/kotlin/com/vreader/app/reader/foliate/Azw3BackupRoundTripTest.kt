package com.vreader.app.reader.foliate

import org.junit.Assert.assertEquals
import org.junit.Test
import vreader.contracts.Locator
import vreader.contracts.backup.BackupJson
import vreader.contracts.backup.BackupPosition
import vreader.contracts.backup.BackupPositionsEnvelope
import java.time.Instant

/**
 * Feature #126 WI-7 — an AZW3/foliate reading position survives the BACKUP round-trip. Backup
 * serializes a PLAIN `Locator` (not the `VReaderLocator` envelope) into `BackupPosition.locatorJSON`
 * (Gate-2 H2): `BackupCollector` does `BackupJson.encode(legacyLocator)`, `RestoreImporter` does
 * `BackupJson.decode<Locator>(...)`. This proves the foliate `cfi` + `progression` round-trip through
 * that plain-Locator path — including inside a full positions section.
 */
class Azw3BackupRoundTripTest {

    private val sha = "a".repeat(64)
    private val bytes = 6_291_456L

    @Test
    fun foliatePosition_survivesPlainLocatorBackupRoundTrip() {
        val relocate = FoliateMessage.Relocate(cfi = "/6/4!/2[ch5]", fraction = 0.63, sectionIndex = 5, sectionTotal = 85)
        val plain: Locator = Azw3LocatorBridge.toEnvelope(relocate, sha, bytes).legacyLocator!!

        // Exactly the production path (BackupCollector encode → RestoreImporter decode).
        val locatorJSON = BackupJson.encode(plain)
        val restored = BackupJson.decode<Locator>(locatorJSON)

        assertEquals("azw3", restored.format)
        assertEquals("/6/4!/2[ch5]", restored.cfi)
        assertEquals(0.63, restored.progression!!, 0.0)
        assertEquals(plain.fingerprintKey, restored.fingerprintKey)
        assertEquals(plain, restored)
    }

    @Test
    fun foliatePosition_survivesFullPositionsSectionRoundTrip() {
        val plain = Azw3LocatorBridge.toEnvelope(
            FoliateMessage.Relocate(cfi = "/6/4!/2[caféch]", fraction = 0.5, sectionIndex = 3, sectionTotal = 9),
            sha, bytes,
        ).legacyLocator!!

        val env = BackupPositionsEnvelope(
            schemaVersion = 3,
            positions = listOf(
                BackupPosition(plain.fingerprintKey, BackupJson.encode(plain), Instant.parse("2026-06-29T00:00:00Z"), null),
            ),
        )
        val sectionJson = BackupJson.encode(env)
        val back = BackupJson.decode<BackupPositionsEnvelope>(sectionJson)
        val backLocator = BackupJson.decode<Locator>(back.positions.single().locatorJSON)

        assertEquals(plain, backLocator)
        assertEquals("azw3", backLocator.format)
        assertEquals(0.5, backLocator.progression!!, 0.0)
    }

    @Test
    fun progressionOnlyPosition_roundTrips() {
        // A position with no CFI (cross-platform progression anchor) must also survive.
        val plain = Azw3LocatorBridge.toEnvelope(
            FoliateMessage.Relocate(cfi = null, fraction = 0.12, sectionIndex = 1, sectionTotal = 9),
            sha, bytes,
        ).legacyLocator!!
        val restored = BackupJson.decode<Locator>(BackupJson.encode(plain))
        assertEquals(plain, restored)
        assertEquals(null, restored.cfi)
        assertEquals(0.12, restored.progression!!, 0.0)
    }
}
