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

    /**
     * Feature #128 WI-4 — the FULL migration chain 1→…→7 through [VReaderDatabase.ALL_MIGRATIONS]: a
     * v1 file opens as v7 (Room's structural PRAGMA validation passes, so MIGRATION_6_7's DDL matches
     * the generated v7 schema exactly, incl. the FTS4 content-table + Room-recreated sync triggers), the
     * seeded book/position survive, the four search tables work, an FTS insert is MATCHable (proving the
     * content-table triggers were recreated at open), and deleting the book CASCADES its search rows.
     */
    @Test
    fun migrate1To7_throughAllMigrations_addsSearchIndex_ftsWorks_andCascades() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→7", runBlocking { db.bookDao().find(key) })
            assertNotNull("position survived 1→7", runBlocking { db.readingPositionDao().find(key) })

            runBlocking {
                val dao = db.searchDao()
                // A published section (via staging → copy) is MATCHable — proves Room recreated the FTS
                // content-table sync triggers when it opened the migrated DB.
                dao.insertStagingBatch(
                    listOf(
                        SearchStagingEntity(
                            bookKey = key, sectionIndex = 0, chunkOrdinal = 0, sectionTitle = null,
                            text = "migrated search corpus text", indexedText = "migrated search corpus text",
                        ),
                    ),
                )
                dao.copyStagingToSections(key)
                dao.clearStaging(key)
                assertNotNull("FTS MATCH works after migration", dao.firstMatchingSection(key, "corpus"))
                dao.markIndexed(SearchIndexStateEntity(key, 1, 1L, "indexed"))

                // deleting the book CASCADES all four search tables.
                db.bookDao().delete(key)
                assertTrue("search_sections cascaded on book delete", dao.sectionsFor(key).isEmpty())
                assertNull("search_index_state cascaded on book delete", dao.indexState(key))
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #128 WI-4 — MIGRATION_6_7 in ISOLATION against an AUTHENTIC v6 database. Hand-builds the
     * v6 `books` shape (has `author`), seeds a book, applies ONLY the 6→7 DDL via a raw SupportSQLite
     * helper, and asserts the four search tables + the bookKey indexes + the FTS4 virtual table now
     * exist and are writable — validating the migration's SQL directly, not just its full-chain
     * registration.
     */
    @Test
    fun migrate6To7_inIsolation_addsSearchTables_andFtsVirtualTable() {
        val isoDbName = "iso-6-to-7.db"
        context.deleteDatabase(isoDbName)
        try {
            // Build the v6 `books` table directly (v6 shape: …addedAt + lastOpenedAt + author).
            val v6Callback = object : SupportSQLiteOpenHelper.Callback(6) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v6Callback).build(),
            ).writableDatabase.use { db ->
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("k1", "Book", "epub", "a".repeat(64), 100L, "/p", null, 1L, null, "Author"),
                )
            }

            // Apply ONLY MIGRATION_6_7 through a raw helper whose onUpgrade runs the real migration.
            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(7) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit  // never — the file already exists at v6
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    assertEquals(6, oldVersion)
                    assertEquals(7, newVersion)
                    VReaderDatabase.MIGRATION_6_7.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                // All four search tables now exist + are writable (else these throw).
                db.execSQL(
                    "INSERT INTO search_sections (bookKey, sectionIndex, chunkOrdinal, sectionTitle, text, indexedText) " +
                        "VALUES ('k1', 0, 0, NULL, 'raw', 'indexed')",
                )
                db.execSQL(
                    "INSERT INTO search_index_state (bookKey, indexerVersion, indexedAt, status) " +
                        "VALUES ('k1', 1, 1, 'indexed')",
                )
                db.execSQL(
                    "INSERT INTO search_sections_staging (bookKey, sectionIndex, chunkOrdinal, sectionTitle, text, indexedText) " +
                        "VALUES ('k1', 0, 0, NULL, 'raw', 'indexed')",
                )
                // The FTS4 virtual table exists (querying it does not throw "no such table").
                db.query("SELECT COUNT(*) FROM search_sections_fts").use { c ->
                    assertTrue(c.moveToFirst())
                }
                db.query("SELECT bookKey, indexedText FROM search_sections WHERE bookKey = 'k1'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("k1", c.getString(0))
                    assertEquals("indexed", c.getString(1))
                }
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #128 WI-1 (audit follow-up) — MIGRATION_5_6 in ISOLATION against an AUTHENTIC v5 `books`
     * table (has `lastOpenedAt`, has NO `author`). Hand-builds exactly the v5 `books` shape, seeds a
     * legacy row + an already-set-lastOpenedAt row, applies ONLY the 5→6 DDL via a raw SupportSQLite
     * helper, and asserts: (a) the `author` column now exists and is nullable, (b) every pre-existing
     * value survives, (c) migrated rows read `author = NULL`, (d) an author is writable onto the new
     * column. This validates the migration's SQL directly, not just its registration in the full chain.
     */
    @Test
    fun migrate5To6_inIsolation_onAuthenticV5Books_addsNullableAuthor_preservesData() {
        val isoDbName = "iso-5-to-6.db"
        context.deleteDatabase(isoDbName)
        try {
            // Build the v5 `books` table directly (v5 shape: fingerprintKey..addedAt + lastOpenedAt, NO author).
            val v5Callback = object : SupportSQLiteOpenHelper.Callback(5) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, PRIMARY KEY(`fingerprintKey`))",
                    )
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v5Callback).build(),
            ).writableDatabase.use { db ->
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt) VALUES (?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("k-legacy", "Legacy", "epub", "a".repeat(64), 100L, "/p", "content://s", 1L, null),
                )
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt) VALUES (?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("k-opened", "Opened", "txt", "b".repeat(64), 200L, null, null, 2L, 4242L),
                )
            }

            // Apply ONLY MIGRATION_5_6 through a raw helper whose onUpgrade runs the real migration.
            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(6) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit  // never called — the file already exists at v5
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    assertEquals(5, oldVersion)
                    assertEquals(6, newVersion)
                    VReaderDatabase.MIGRATION_5_6.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                // The `author` column now exists (else this SELECT throws).
                db.query("SELECT fingerprintKey, title, lastOpenedAt, author FROM books ORDER BY addedAt").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("k-legacy", c.getString(0))
                    assertEquals("Legacy", c.getString(1))
                    assertTrue("legacy lastOpenedAt preserved (null)", c.isNull(2))
                    assertTrue("migrated legacy row has NULL author", c.isNull(3))

                    assertTrue(c.moveToNext())
                    assertEquals("k-opened", c.getString(0))
                    assertEquals("data survived: lastOpenedAt", 4242L, c.getLong(2))
                    assertTrue("migrated opened row has NULL author", c.isNull(3))
                }
                // The new column is writable.
                db.execSQL("UPDATE books SET author = ? WHERE fingerprintKey = ?", arrayOf<Any?>("Herman Melville", "k-legacy"))
                db.query("SELECT author FROM books WHERE fingerprintKey = 'k-legacy'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("Herman Melville", c.getString(0))
                }
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #135 WI-3 — the FULL migration chain 1→…→8 through [VReaderDatabase.ALL_MIGRATIONS]: a
     * v1 file opens as v8 (Room's structural PRAGMA validation passes, so MIGRATION_7_8's DDL — the
     * new composite UNIQUE index on `bookmarks (bookKey, profileKey)` — matches the generated v8
     * schema exactly), the seeded book/position survive, and the new unique index is enforced: an
     * insert-if-absent of a second bookmark at the SAME (bookKey, profileKey) is rejected (IGNOREd),
     * collapsing to one row.
     */
    @Test
    fun migrate1To8_throughAllMigrations_addsBookmarkUniqueIndex_andEnforcesIt() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→8", runBlocking { db.bookDao().find(key) })
            assertNotNull("position survived 1→8", runBlocking { db.readingPositionDao().find(key) })

            runBlocking {
                val dao = db.annotationDao()
                val b1 = BookmarkEntity(
                    bookmarkId = "b1", bookKey = key, profileKey = "$key:pos1",
                    title = "Chapter 1", locatorJSON = "{}", createdAt = 1L, updatedAt = 1L,
                )
                // A second bookmark at the SAME (bookKey, profileKey) but a different id → rejected
                // by the new unique index (insert-if-absent returns -1), collapsing to one row.
                val b2 = b1.copy(bookmarkId = "b2", title = "Chapter 1 (again)", updatedAt = 2L)
                assertTrue("first insert-if-absent applied", dao.insertBookmarkIfAbsent(b1) != -1L)
                assertEquals("second insert at same (bookKey, profileKey) rejected", -1L, dao.insertBookmarkIfAbsent(b2))
                assertEquals("unique index collapsed to one row", 1, dao.bookmarksForBook(key).size)
                assertEquals("the surviving row is the first", "b1", dao.bookmarksForBook(key).single().bookmarkId)
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #135 WI-3 — MIGRATION_7_8 in ISOLATION against an AUTHENTIC v7 database that already
     * holds DUPLICATE bookmarks at the same (bookKey, profileKey) (rows created before the unique
     * index existed). The migration must DEDUPE the duplicate losers BEFORE creating the unique index
     * (else CREATE UNIQUE INDEX would fail on the pre-existing duplicate), keeping a DETERMINISTIC
     * winner (highest updatedAt, then highest createdAt, then lowest bookmarkId). Asserts: (a) the
     * winner survives + the losers are deleted, (b) a NON-duplicate bookmark at a different profileKey
     * is untouched, (c) other tables' data (the seeded book) is preserved, (d) the unique index now
     * rejects a subsequent duplicate insert.
     */
    @Test
    fun migrate7To8_inIsolation_dedupesDuplicateBookmarks_thenEnforcesUniqueIndex() {
        val isoDbName = "iso-7-to-8.db"
        context.deleteDatabase(isoDbName)
        try {
            // Build the v7 `books` + `bookmarks` shape directly (v7 bookmarks has ONLY the non-unique
            // bookKey index — the state before this migration adds the composite unique index).
            val v7Callback = object : SupportSQLiteOpenHelper.Callback(7) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `bookmarks` (`bookmarkId` TEXT NOT NULL, " +
                            "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `title` TEXT, " +
                            "`locatorJSON` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
                            "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`bookmarkId`), " +
                            "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                            "ON UPDATE NO ACTION ON DELETE CASCADE )",
                    )
                    db.execSQL("CREATE INDEX IF NOT EXISTS `index_bookmarks_bookKey` ON `bookmarks` (`bookKey`)")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v7Callback).build(),
            ).writableDatabase.use { db ->
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("bk", "Book", "epub", "a".repeat(64), 100L, "/p", null, 1L, null, "Author"),
                )
                // THREE bookmarks at the SAME (bookKey='bk', profileKey='bk:posA') — duplicates that a
                // pre-index create path could produce. The winner is the highest (updatedAt, createdAt),
                // tie-broken by the LOWEST bookmarkId. Here 'dup-c' has updatedAt=30 → winner.
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('dup-a','bk','bk:posA','A', '{}', 5, 10)",
                )
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('dup-b','bk','bk:posA','B', '{}', 8, 20)",
                )
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('dup-c','bk','bk:posA','C', '{}', 3, 30)",
                )
                // A distinct (different profileKey) bookmark that must be left untouched.
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('solo','bk','bk:posB','Solo', '{}', 1, 1)",
                )
            }

            // Apply ONLY MIGRATION_7_8 through a raw helper whose onUpgrade runs the real migration.
            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(8) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit  // never — the file already exists at v7
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    assertEquals(7, oldVersion)
                    assertEquals(8, newVersion)
                    VReaderDatabase.MIGRATION_7_8.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                // (a) the deterministic winner ('dup-c', highest updatedAt) survives; the losers are gone.
                db.query("SELECT bookmarkId FROM bookmarks WHERE profileKey = 'bk:posA'").use { c ->
                    assertTrue("exactly one duplicate survived", c.moveToFirst())
                    assertEquals("the deterministic winner survived", "dup-c", c.getString(0))
                    assertTrue("no other duplicate row remains", !c.moveToNext())
                }
                // (b) the distinct non-duplicate bookmark is untouched.
                db.query("SELECT bookmarkId FROM bookmarks WHERE profileKey = 'bk:posB'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("solo", c.getString(0))
                }
                // (c) other tables' data preserved (the seeded book still exists).
                db.query("SELECT title FROM books WHERE fingerprintKey = 'bk'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("Book", c.getString(0))
                }
                // (d) the new unique index rejects a subsequent duplicate insert.
                var threw = false
                try {
                    db.execSQL(
                        "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                            "VALUES ('new-dup','bk','bk:posA','New', '{}', 99, 99)",
                    )
                } catch (e: android.database.sqlite.SQLiteConstraintException) {
                    threw = true
                }
                assertTrue("the new unique index rejects a duplicate (bookKey, profileKey) insert", threw)
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #135 WI-3 — MIGRATION_7_8 in ISOLATION on a CLEAN v7 database (no duplicates): the
     * migration succeeds (the dedupe DELETE is a harmless no-op) and the unique index is created +
     * enforced. Guards against a dedupe SQL that accidentally deletes non-duplicate rows.
     */
    @Test
    fun migrate7To8_inIsolation_noDuplicates_succeeds_andCreatesUniqueIndex() {
        val isoDbName = "iso-7-to-8-clean.db"
        context.deleteDatabase(isoDbName)
        try {
            val v7Callback = object : SupportSQLiteOpenHelper.Callback(7) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `bookmarks` (`bookmarkId` TEXT NOT NULL, " +
                            "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `title` TEXT, " +
                            "`locatorJSON` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, " +
                            "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`bookmarkId`), " +
                            "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                            "ON UPDATE NO ACTION ON DELETE CASCADE )",
                    )
                    db.execSQL("CREATE INDEX IF NOT EXISTS `index_bookmarks_bookKey` ON `bookmarks` (`bookKey`)")
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v7Callback).build(),
            ).writableDatabase.use { db ->
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("bk", "Book", "epub", "a".repeat(64), 100L, "/p", null, 1L, null, "Author"),
                )
                // Two DISTINCT bookmarks (different profileKeys) — no duplicates.
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('one','bk','bk:posA','One', '{}', 1, 1)",
                )
                db.execSQL(
                    "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                        "VALUES ('two','bk','bk:posB','Two', '{}', 2, 2)",
                )
            }

            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(8) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    VReaderDatabase.MIGRATION_7_8.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                // Both distinct rows survive (the dedupe deleted nothing).
                db.query("SELECT COUNT(*) FROM bookmarks").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("both distinct bookmarks survive a clean migration", 2, c.getInt(0))
                }
                // The unique index exists + is enforced.
                var threw = false
                try {
                    db.execSQL(
                        "INSERT INTO bookmarks (bookmarkId, bookKey, profileKey, title, locatorJSON, createdAt, updatedAt) " +
                            "VALUES ('dup','bk','bk:posA','Dup', '{}', 9, 9)",
                    )
                } catch (e: android.database.sqlite.SQLiteConstraintException) {
                    threw = true
                }
                assertTrue("the unique index rejects a duplicate after a clean migration", threw)
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #131 WI-2 — the FULL migration chain 1→…→9 through [VReaderDatabase.ALL_MIGRATIONS]: a
     * v1 file opens as v9. Opening the REAL Room DB after the v8→v9 migration is the exact-DDL GUARD —
     * Room's structural PRAGMA validation runs on open and would THROW if MIGRATION_8_9's hand-written
     * `chapter_translations` DDL diverged from Room's GENERATED 9.json schema (the recurring Android
     * migration failure mode; cf. #135's stale-version finding). It then asserts: the seeded
     * book/position survive, a cached translation ROUND-TRIPS through the DAO, and deleting the book
     * CASCADES the cached translation (FK ON DELETE CASCADE).
     */
    @Test
    fun migrate1To9_throughAllMigrations_addsChapterTranslations_roundTrips_andCascades() {
        seedVersion1Database()

        // Opening the real Room DB (declared version 9) validates MIGRATION_8_9's DDL against the
        // generated 9.json schema — a mismatch throws IllegalStateException here.
        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→9", runBlocking { db.bookDao().find(key) })
            assertNotNull("position survived 1→9", runBlocking { db.readingPositionDao().find(key) })

            runBlocking {
                val dao = db.chapterTranslationDao()
                val row = ChapterTranslationEntity(
                    lookupKey = "$key|epubHref:ch1|zh-Hans|bilingual-v1|g=paragraph",
                    bookKey = key, unitStorageKey = "epubHref:ch1", targetLanguage = "zh-Hans",
                    promptVersion = "bilingual-v1|g=paragraph", translatedJson = """["你好","世界"]""",
                    sourceParagraphCount = 2, createdAt = 100L,
                )
                dao.upsert(row)
                assertEquals("cached translation round-trips after migration", row, dao.getByLookupKey(row.lookupKey))

                // deleting the book CASCADES its cached translations.
                db.bookDao().delete(key)
                assertNull("chapter_translations cascaded on book delete", dao.getByLookupKey(row.lookupKey))
                assertEquals("no orphan translations remain", 0, dao.count())
            }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #131 WI-2 — MIGRATION_8_9 in ISOLATION against an AUTHENTIC v8 database. Hand-builds the
     * v8 `books` shape, seeds a book, applies ONLY the 8→9 DDL via a raw SupportSQLite helper, and
     * asserts the new `chapter_translations` table + its bookKey index now exist and are writable,
     * that the FK→books CASCADES on book delete, and that the PK rejects a duplicate `lookupKey` —
     * validating the migration's SQL directly, not just its full-chain registration.
     */
    @Test
    fun migrate8To9_inIsolation_addsChapterTranslations_cascades_andEnforcesPk() {
        val isoDbName = "iso-8-to-9.db"
        context.deleteDatabase(isoDbName)
        try {
            // Build the v8 `books` shape directly (v8: …addedAt + lastOpenedAt + author).
            val v8Callback = object : SupportSQLiteOpenHelper.Callback(8) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v8Callback).build(),
            ).writableDatabase.use { db ->
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("bk", "Book", "epub", "a".repeat(64), 100L, "/p", null, 1L, null, "Author"),
                )
            }

            // Apply ONLY MIGRATION_8_9 through a raw helper whose onUpgrade runs the real migration.
            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(9) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit  // never — the file already exists at v8
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    assertEquals(8, oldVersion)
                    assertEquals(9, newVersion)
                    // FK enforcement is off by default on a raw helper; turn it on so the CASCADE below runs.
                    db.execSQL("PRAGMA foreign_keys=ON")
                    VReaderDatabase.MIGRATION_8_9.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                db.execSQL("PRAGMA foreign_keys=ON")
                // The new table + its bookKey index exist and are writable (else these throw).
                db.execSQL(
                    "INSERT INTO chapter_translations (lookupKey, bookKey, unitStorageKey, targetLanguage, " +
                        "promptVersion, translatedJson, sourceParagraphCount, createdAt) " +
                        "VALUES ('bk|epubHref:ch1|zh-Hans|p', 'bk', 'epubHref:ch1', 'zh-Hans', 'p', '[\"你好\"]', 1, 1)",
                )
                db.query("SELECT translatedJson, sourceParagraphCount FROM chapter_translations WHERE bookKey = 'bk'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("[\"你好\"]", c.getString(0))
                    assertEquals(1, c.getInt(1))
                }
                // The bookKey index exists (named per Room's generated schema).
                db.query(
                    "SELECT name FROM sqlite_master WHERE type='index' AND name='index_chapter_translations_bookKey'",
                ).use { c ->
                    assertTrue("the bookKey index was created with the Room-generated name", c.moveToFirst())
                }
                // The PK rejects a duplicate lookupKey.
                var pkThrew = false
                try {
                    db.execSQL(
                        "INSERT INTO chapter_translations (lookupKey, bookKey, unitStorageKey, targetLanguage, " +
                            "promptVersion, translatedJson, sourceParagraphCount, createdAt) " +
                            "VALUES ('bk|epubHref:ch1|zh-Hans|p', 'bk', 'u2', 'zh-Hans', 'p', '[]', 0, 2)",
                    )
                } catch (e: android.database.sqlite.SQLiteConstraintException) {
                    pkThrew = true
                }
                assertTrue("the PK rejects a duplicate lookupKey", pkThrew)
                // Deleting the book CASCADES its cached translations (FK ON DELETE CASCADE).
                db.execSQL("DELETE FROM books WHERE fingerprintKey = 'bk'")
                db.query("SELECT COUNT(*) FROM chapter_translations").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("chapter_translations cascaded on book delete", 0, c.getInt(0))
                }
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #152 WI-2 — the FULL migration chain 1→…→10 through [VReaderDatabase.ALL_MIGRATIONS]: a
     * v1 file opens as v10. Opening the REAL Room DB after the v9→v10 migration is the exact-DDL GUARD
     * — Room's structural PRAGMA validation runs on open and would THROW if MIGRATION_9_10's
     * hand-written `ALTER TABLE` DDL diverged from Room's GENERATED 10.json schema (affinity, nullability
     * or column name). It then asserts the seeded book/position survive and that BOTH new cover columns
     * read NULL for a pre-existing row — the "never attempted" tri-state corner that makes the backfill
     * eligible rather than permanently skipped.
     *
     * The columns are read through a raw `SELECT` rather than the entity so this test fails on the
     * MIGRATION, not on an unrelated entity-mapping regression.
     */
    @Test
    fun migrate1To10_throughAllMigrations_addsCoverColumns_nullForExistingRows() {
        seedVersion1Database()

        val db = Room.databaseBuilder(context, VReaderDatabase::class.java, dbName)
            .addMigrations(*VReaderDatabase.ALL_MIGRATIONS)
            .build()
        try {
            assertNotNull("book survived 1→10", runBlocking { db.bookDao().find(key) })
            assertNotNull("position survived 1→10", runBlocking { db.readingPositionDao().find(key) })

            db.openHelper.writableDatabase
                .query("SELECT coverPath, coverExtractorVersion FROM books WHERE fingerprintKey = ?", arrayOf<Any?>(key))
                .use { c ->
                    assertTrue("the migrated book row is present", c.moveToFirst())
                    assertTrue("coverPath is NULL for a pre-existing row", c.isNull(0))
                    assertTrue("coverExtractorVersion is NULL for a pre-existing row", c.isNull(1))
                }
        } finally {
            db.close()
        }
    }

    /**
     * Feature #152 WI-2 — MIGRATION_9_10 in ISOLATION against an AUTHENTIC v9 database, and the one
     * people forget: the migration must be NON-DESTRUCTIVE. Two `ALTER TABLE ADD COLUMN`s should be
     * incapable of losing data, but a migration written as a table-rebuild (the shape SQLite forces
     * for a column DROP or a type change) silently would — so every other column of a seeded book is
     * asserted individually, along with the book's reading position in the child table.
     *
     * Also asserts the new columns are WRITABLE and round-trip: the art case (path + version), the
     * memoised no-art case (NULL path WITH a version — the state that stops a re-parse), and the
     * reset-to-eligible case (both NULL again).
     */
    @Test
    fun migrate9To10_inIsolation_addsCoverColumns_isNonDestructive_andRoundTrips() {
        val isoDbName = "iso-9-to-10.db"
        context.deleteDatabase(isoDbName)
        try {
            // Build the v9 `books` + `reading_positions` shape directly (v9 books: …lastOpenedAt + author).
            val v9Callback = object : SupportSQLiteOpenHelper.Callback(9) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `reading_positions` (`fingerprintKey` TEXT NOT NULL, " +
                            "`vreaderLocatorJSON` TEXT NOT NULL, `canonicalHash` TEXT NOT NULL, " +
                            "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`fingerprintKey`), " +
                            "FOREIGN KEY(`fingerprintKey`) REFERENCES `books`(`fingerprintKey`) " +
                            "ON UPDATE NO ACTION ON DELETE CASCADE )",
                    )
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v9Callback).build(),
            ).writableDatabase.use { db ->
                // A fully-populated row — every column non-default, so a rebuild-style migration that
                // dropped or re-defaulted any of them is caught.
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>(
                        "bk-full", "白鲸", "azw3", "c".repeat(64), 6_288_371L,
                        "/data/user/0/com.vreader.app/files/books/bk-full.azw3", "content://saf/doc/42",
                        1_700_000_000_000L, 1_700_000_999_000L, "Herman Melville",
                    ),
                )
                // A minimally-populated row — the nullable columns must stay NULL, not become "".
                db.execSQL(
                    "INSERT INTO books (fingerprintKey, title, originalFormat, contentSHA256, fileByteCount, " +
                        "localFilePath, sourceUri, addedAt, lastOpenedAt, author) VALUES (?,?,?,?,?,?,?,?,?,?)",
                    arrayOf<Any?>("bk-bare", "Bare", "txt", "d".repeat(64), 10L, null, null, 5L, null, null),
                )
                db.execSQL(
                    "INSERT INTO reading_positions (fingerprintKey, vreaderLocatorJSON, canonicalHash, updatedAt) " +
                        "VALUES (?,?,?,?)",
                    arrayOf<Any?>("bk-full", """{"engine":"readium"}""", "cafebabe", 1_700_000_500_000L),
                )
            }

            // Apply ONLY MIGRATION_9_10 through a raw helper whose onUpgrade runs the real migration.
            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(10) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit  // never — the file already exists at v9
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    assertEquals(9, oldVersion)
                    assertEquals(10, newVersion)
                    VReaderDatabase.MIGRATION_9_10.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                // NON-DESTRUCTIVE: every pre-existing column of the populated row is byte-identical.
                db.query(
                    "SELECT title, originalFormat, contentSHA256, fileByteCount, localFilePath, sourceUri, " +
                        "addedAt, lastOpenedAt, author, coverPath, coverExtractorVersion " +
                        "FROM books WHERE fingerprintKey = 'bk-full'",
                ).use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("title survived", "白鲸", c.getString(0))
                    assertEquals("originalFormat survived", "azw3", c.getString(1))
                    assertEquals("contentSHA256 survived", "c".repeat(64), c.getString(2))
                    assertEquals("fileByteCount survived", 6_288_371L, c.getLong(3))
                    assertEquals(
                        "localFilePath survived",
                        "/data/user/0/com.vreader.app/files/books/bk-full.azw3",
                        c.getString(4),
                    )
                    assertEquals("sourceUri survived", "content://saf/doc/42", c.getString(5))
                    assertEquals("addedAt survived", 1_700_000_000_000L, c.getLong(6))
                    assertEquals("lastOpenedAt survived", 1_700_000_999_000L, c.getLong(7))
                    assertEquals("author survived", "Herman Melville", c.getString(8))
                    assertTrue("coverPath starts NULL", c.isNull(9))
                    assertTrue("coverExtractorVersion starts NULL", c.isNull(10))
                }
                // The sparse row's nullable columns are still NULL (not defaulted to a sentinel).
                db.query(
                    "SELECT localFilePath, sourceUri, lastOpenedAt, author, coverPath, coverExtractorVersion " +
                        "FROM books WHERE fingerprintKey = 'bk-bare'",
                ).use { c ->
                    assertTrue(c.moveToFirst())
                    for (i in 0..5) assertTrue("column $i stayed NULL on the sparse row", c.isNull(i))
                }
                // The CHILD table survived too — a table-rebuild migration that dropped and recreated
                // `books` would have cascaded these away.
                db.query("SELECT canonicalHash, updatedAt FROM reading_positions WHERE fingerprintKey = 'bk-full'")
                    .use { c ->
                        assertTrue("the reading position survived the books migration", c.moveToFirst())
                        assertEquals("cafebabe", c.getString(0))
                        assertEquals(1_700_000_500_000L, c.getLong(1))
                    }

                // WRITABLE — the art case.
                db.execSQL(
                    "UPDATE books SET coverPath = ?, coverExtractorVersion = ? WHERE fingerprintKey = 'bk-full'",
                    arrayOf<Any?>("/data/user/0/com.vreader.app/files/covers/白鲸.jpg", 1),
                )
                db.query("SELECT coverPath, coverExtractorVersion FROM books WHERE fingerprintKey = 'bk-full'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertEquals("/data/user/0/com.vreader.app/files/covers/白鲸.jpg", c.getString(0))
                    assertEquals("INTEGER affinity round-trips the version", 1, c.getInt(1))
                }
                // The MEMOISED NO-ART state: NULL path WITH a version — the row that must be
                // distinguishable from "never attempted", or the backfill re-parses it forever.
                db.execSQL(
                    "UPDATE books SET coverPath = NULL, coverExtractorVersion = ? WHERE fingerprintKey = 'bk-bare'",
                    arrayOf<Any?>(1),
                )
                db.query("SELECT coverPath, coverExtractorVersion FROM books WHERE fingerprintKey = 'bk-bare'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertTrue("no-art keeps a NULL path", c.isNull(0))
                    assertEquals("…while still carrying the version memo", 1, c.getInt(1))
                }
                // Reset to eligible — both NULL again.
                db.execSQL("UPDATE books SET coverPath = NULL, coverExtractorVersion = NULL WHERE fingerprintKey = 'bk-full'")
                db.query("SELECT coverPath, coverExtractorVersion FROM books WHERE fingerprintKey = 'bk-full'").use { c ->
                    assertTrue(c.moveToFirst())
                    assertTrue(c.isNull(0))
                    assertTrue("the memo can be cleared to make a book eligible again", c.isNull(1))
                }
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }

    /**
     * Feature #152 WI-2 — the zero-row edge: a fresh-ish install whose library is empty still migrates
     * 9→10 cleanly (an `ALTER TABLE` on an empty table is trivial, but a migration that tried to
     * backfill values row-by-row could divide-by-zero or leave the columns absent).
     */
    @Test
    fun migrate9To10_onEmptyBooksTable_succeeds_andColumnsExist() {
        val isoDbName = "iso-9-to-10-empty.db"
        context.deleteDatabase(isoDbName)
        try {
            val v9Callback = object : SupportSQLiteOpenHelper.Callback(9) {
                override fun onCreate(db: SupportSQLiteDatabase) {
                    db.execSQL(
                        "CREATE TABLE IF NOT EXISTS `books` (`fingerprintKey` TEXT NOT NULL, " +
                            "`title` TEXT NOT NULL, `originalFormat` TEXT NOT NULL, `contentSHA256` TEXT NOT NULL, " +
                            "`fileByteCount` INTEGER NOT NULL, `localFilePath` TEXT, `sourceUri` TEXT, " +
                            "`addedAt` INTEGER NOT NULL, `lastOpenedAt` INTEGER, `author` TEXT, " +
                            "PRIMARY KEY(`fingerprintKey`))",
                    )
                }
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) = Unit
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(v9Callback).build(),
            ).writableDatabase.use { /* create only — no rows */ }

            val migrateCallback = object : SupportSQLiteOpenHelper.Callback(10) {
                override fun onCreate(db: SupportSQLiteDatabase) = Unit
                override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
                    VReaderDatabase.MIGRATION_9_10.migrate(db)
                }
            }
            FrameworkSQLiteOpenHelperFactory().create(
                SupportSQLiteOpenHelper.Configuration.builder(context).name(isoDbName).callback(migrateCallback).build(),
            ).writableDatabase.use { db ->
                db.query("SELECT coverPath, coverExtractorVersion FROM books").use { c ->
                    assertEquals("still empty, and both columns exist", 0, c.count)
                }
            }
        } finally {
            context.deleteDatabase(isoDbName)
        }
    }
}
