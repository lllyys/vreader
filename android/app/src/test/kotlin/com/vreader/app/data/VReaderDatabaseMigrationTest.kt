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

        // Open the current Room DB on the v1 file — runs the full migration chain (1→2→3).
        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
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

    /**
     * Feature #122 — the FULL migration chain 1→2→3 through [VReaderDatabase.ALL_MIGRATIONS]: a v1
     * file opens as v3, the seeded book/position survive (Room's structural validation passes), and
     * the new `daily_reading` table (added by MIGRATION_2_3) is created + usable.
     */
    @Test
    fun migrate1To3_throughAllMigrations_preservesData_andAddsDailyReading() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            val book = runBlocking { db.bookDao().find(key) }
            assertNotNull("book survived 1→3", book)
            assertNull("v2 lastOpenedAt is null for the migrated row", book!!.lastOpenedAt)
            assertNotNull("position survived 1→3", runBlocking { db.readingPositionDao().find(key) })

            // the v3 daily_reading table is structurally valid + works
            runBlocking {
                db.readingStatsDao().addMinutes("2026-06-27", key, 9)
                db.readingStatsDao().addMinutes("2026-06-27", key, 3)
                assertEquals(12, db.readingStatsDao().rowsSince("2026-06-27").single().minutes)
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #123 — the FULL migration chain 1→2→3→4 through [VReaderDatabase.ALL_MIGRATIONS]: a v1
     * file opens as v4, the seeded book/position survive (Room's structural validation passes), and the
     * new annotation tables (added by MIGRATION_3_4) are created + usable, incl. the unique
     * (profileKey, anchorKey) dedupe index on `highlights`.
     */
    @Test
    fun migrate1To4_throughAllMigrations_preservesData_andAddsAnnotations() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→4", runBlocking { db.bookDao().find(key) })
            assertNotNull("position survived 1→4", runBlocking { db.readingPositionDao().find(key) })

            // the v4 annotation tables are structurally valid + work; the unique dedupe index holds.
            runBlocking {
                val dao = db.annotationDao()
                val h = HighlightEntity(
                    highlightId = "h1", bookKey = key, profileKey = "$key:abc", anchorKey = "anchor1",
                    color = "yellow", selectedText = "hello", note = null,
                    locatorJSON = "{}", anchorJSON = null, createdAt = 1L, updatedAt = 1L,
                )
                dao.upsertHighlight(h)
                // same (profileKey, anchorKey), different id + color → UPDATE in place, not a duplicate.
                dao.upsertHighlight(h.copy(highlightId = "h2", color = "pink", updatedAt = 2L))
                val all = dao.highlightsForBook(key)
                assertEquals("dedupe collapsed to one row", 1, all.size)
                assertEquals("update-in-place changed the color", "pink", all.single().color)
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #127 WI-1 — the FULL migration chain 1→2→3→4→5 through [VReaderDatabase.ALL_MIGRATIONS]:
     * a v1 file opens as v5 (Room's structural PRAGMA validation passes, so MIGRATION_4_5's DDL matches
     * the generated v5 schema exactly), the new `collections` + `book_collection` tables work, the
     * `book_collection` FK CASCADES when its book is deleted, and the unique `nameKey` index holds.
     */
    @Test
    fun migrate1To5_throughAllMigrations_addsCollections_cascades_andEnforcesUniqueName() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→5", runBlocking { db.bookDao().find(key) })
            val dao = db.collectionDao()
            runBlocking {
                // create a collection + add the seeded book → membership works.
                val c = CollectionEntity(id = "c1", name = "Fiction", nameKey = "fiction", createdAt = 1L)
                dao.insertCollection(c)
                dao.addMembership(key, "c1")
                assertEquals("the book is in the collection", listOf(key), dao.bookKeysInCollection("c1"))

                // the unique nameKey index rejects a second collection with the SAME nameKey (diff id).
                var threw = false
                try {
                    dao.insertCollection(CollectionEntity(id = "c2", name = "FICTION", nameKey = "fiction", createdAt = 2L))
                } catch (e: android.database.sqlite.SQLiteConstraintException) {
                    threw = true
                }
                assertTrue("the unique nameKey index rejects a case-folded duplicate", threw)

                // deleting the book CASCADES the cross-ref (FK ON DELETE CASCADE), not the collection.
                db.bookDao().delete(key)
                assertTrue("the membership cascaded away with the book", dao.bookKeysInCollection("c1").isEmpty())
                assertEquals("the collection itself survives the book delete", 1, dao.getAllCollections().size)
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #128 WI-1 — MIGRATION_5_6 adds the nullable `books.author` column. Seed a v5-shaped
     * `books` row (WITHOUT `author`), then open the current Room DB (v6) with the full migration chain
     * registered: the additive column is created, Room's structural PRAGMA validation passes, and the
     * pre-existing row reads back with `author = null` (a migrated legacy book has no author yet).
     */
    @Test
    fun migrate5To6_addsNullableAuthor_andExistingRowReadsNull() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            val book = runBlocking { db.bookDao().find(key) }
            assertNotNull("book survived 1→6", book)
            assertNull("the new v6 author column defaults to null for migrated rows", book!!.author)

            // The column is writable + reads back — round-trip an author onto the migrated row.
            runBlocking {
                db.bookDao().backfillAuthorIfNull(key, "Herman Melville")
                assertEquals("Herman Melville", db.bookDao().find(key)?.author)
            }
        } finally {
            db.close()
        }
    }
}
