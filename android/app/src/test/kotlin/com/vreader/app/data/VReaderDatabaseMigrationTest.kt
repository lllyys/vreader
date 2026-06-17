package com.vreader.app.data

import android.content.Context
import androidx.room.Room
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import androidx.test.core.app.ApplicationProvider
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/**
 * Migration round-trip for [VReaderDatabase] (feature #106 WI-3). Hand-builds a v1
 * database (the books+positions baseline, WITHOUT the v2 `lastOpenedAt` column),
 * seeds a book + its position, then opens the real Room DB (version 2) with
 * [VReaderDatabase.MIGRATION_1_2] registered — proving the additive migration runs,
 * Room's structural validation passes, and the seeded data survives.
 */
@RunWith(RobolectricTestRunner::class)
class VReaderDatabaseMigrationTest {
    private val dbName = "migration-roundtrip.db"
    private val context: Context get() = ApplicationProvider.getApplicationContext()
    private val key = "epub:${"a".repeat(64)}:2048"

    @Before
    fun setUp() {
        context.deleteDatabase(dbName)
    }

    @After
    fun tearDown() {
        context.deleteDatabase(dbName)
    }

    @Test
    fun migrate1To2_preservesData_andAddsNullableColumn() {
        seedVersion1Database()

        // Open the current (v2) Room DB on the v1 file — triggers MIGRATION_1_2.
        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(VReaderDatabase.MIGRATION_1_2)
            .build()
        try {
            val book = runBlocking { db.bookDao().find(key) }
            assertNotNull("book survived the migration", book)
            assertEquals("Pre-migration Book", book!!.title)
            assertNull("new v2 column defaults to null for migrated rows", book.lastOpenedAt)

            val position = runBlocking { db.readingPositionDao().find(key) }
            assertNotNull("position survived the migration", position)
            assertTrue(
                "envelope JSON survived intact",
                position!!.vreaderLocatorJSON.contains("readium"),
            )
        } finally {
            db.close()
        }
    }

    /**
     * Creates the v1 schema directly (no Room) — exactly the v2 structure minus
     * `books.lastOpenedAt`. Room's post-migration validation is structural (PRAGMA
     * table/index/fk info), so the column names/affinities/PK/FK/index must match
     * what Room expects for v2 after MIGRATION_1_2 adds the column.
     */
    private fun seedVersion1Database() {
        val callback = object : SupportSQLiteOpenHelper.Callback(1) {
            override fun onCreate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `books` (
                        `fingerprintKey` TEXT NOT NULL,
                        `title` TEXT NOT NULL,
                        `originalFormat` TEXT NOT NULL,
                        `contentSHA256` TEXT NOT NULL,
                        `fileByteCount` INTEGER NOT NULL,
                        `localFilePath` TEXT,
                        `sourceUri` TEXT,
                        `addedAt` INTEGER NOT NULL,
                        PRIMARY KEY(`fingerprintKey`)
                    )
                    """.trimIndent(),
                )
                db.execSQL(
                    """
                    CREATE TABLE IF NOT EXISTS `reading_positions` (
                        `fingerprintKey` TEXT NOT NULL,
                        `vreaderLocatorJSON` TEXT NOT NULL,
                        `canonicalHash` TEXT NOT NULL,
                        `updatedAt` INTEGER NOT NULL,
                        PRIMARY KEY(`fingerprintKey`),
                        FOREIGN KEY(`fingerprintKey`) REFERENCES `books`(`fingerprintKey`)
                            ON UPDATE NO ACTION ON DELETE CASCADE
                    )
                    """.trimIndent(),
                )
            }

            override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
        }

        val helper = FrameworkSQLiteOpenHelperFactory().create(
            SupportSQLiteOpenHelper.Configuration.builder(context)
                .name(dbName)
                .callback(callback)
                .build(),
        )
        helper.writableDatabase.use { db ->
            db.execSQL(
                "INSERT INTO books " +
                    "(fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                    "localFilePath, sourceUri, addedAt) VALUES (?,?,?,?,?,?,?,?)",
                arrayOf<Any?>(key, "Pre-migration Book", "epub", "a".repeat(64), 2048L, null, null, 1L),
            )
            val envelopeJson =
                """{"fingerprintKey":"$key","originalFormat":"epub","engine":"readium",""" +
                    """"readiumLocatorJSON":"{}","legacyLocator":null,"schemaVersion":1}"""
            db.execSQL(
                "INSERT INTO reading_positions " +
                    "(fingerprintKey, vreaderLocatorJSON, canonicalHash, updatedAt) VALUES (?,?,?,?)",
                arrayOf<Any?>(key, envelopeJson, "deadbeef", 1L),
            )
        }
    }
}
