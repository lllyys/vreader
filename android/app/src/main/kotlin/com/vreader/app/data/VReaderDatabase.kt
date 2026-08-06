// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
// Version 10 is the current schema; v1 was the initial books+positions baseline and
// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search),
// 6→7 the FTS search index (search_sections + search_sections_fts + search_index_state
// + search_sections_staging, all #128 WI-4), 7→8 the composite UNIQUE (bookKey, profileKey)
// index on `bookmarks` — preceded by an in-migration dedupe of pre-existing duplicate rows so
// the unique index can't fail on a legacy duplicate (feature #135 WI-3), 8→9 the additive
// `chapter_translations` bilingual translation cache (+ bookKey index, FK→books CASCADE;
// feature #131 WI-2), 9→10 the additive nullable `books.coverPath` + `books.coverExtractorVersion`
// cover-state pair (feature #152 WI-2). The migration round-trip test
// (VReaderDatabaseMigrationTest) guards them.
// Future schema changes append a Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
package com.vreader.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [
        BookEntity::class, ReadingPositionEntity::class, DailyReadingEntity::class,
        HighlightEntity::class, AnnotationNoteEntity::class, BookmarkEntity::class,
        CollectionEntity::class, BookCollectionCrossRef::class,
        SearchSectionEntity::class, SearchSectionFtsEntity::class,
        SearchIndexStateEntity::class, SearchStagingEntity::class,
        ChapterTranslationEntity::class,
    ],
    version = 10,
    exportSchema = true,
)
abstract class VReaderDatabase : RoomDatabase() {
    abstract fun bookDao(): BookDao
    abstract fun readingPositionDao(): ReadingPositionDao
    abstract fun readingStatsDao(): ReadingStatsDao
    abstract fun annotationDao(): AnnotationDao
    abstract fun collectionDao(): CollectionDao
    abstract fun searchDao(): SearchDao
    abstract fun chapterTranslationDao(): ChapterTranslationDao

    companion object {
        private const val DB_NAME = "vreader.db"

        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN lastOpenedAt INTEGER")
            }
        }

        /** v2 → v3: feature #122 — add the additive `daily_reading` per-day/per-book stats table +
         *  its bookKey index. No data transform. DDL matches Room's generated schema exactly. */
        val MIGRATION_2_3: Migration = object : Migration(2, 3) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `daily_reading` (`date` TEXT NOT NULL, `bookKey` TEXT NOT NULL, " +
                        "`minutes` INTEGER NOT NULL, PRIMARY KEY(`date`, `bookKey`))",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_daily_reading_bookKey` ON `daily_reading` (`bookKey`)")
            }
        }

        /** v3 → v4: feature #123 — add the additive `highlights`, `annotation_notes`, and `bookmarks`
         *  annotation tables (each FK→books ON DELETE CASCADE; highlights has the unique
         *  `(profileKey, anchorKey)` dedupe index). No data transform. DDL matches Room's generated
         *  schema for v4 exactly (the migration test opens the real Room DB, whose structural PRAGMA
         *  validation catches any drift). */
        val MIGRATION_3_4: Migration = object : Migration(3, 4) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `highlights` (`highlightId` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `anchorKey` TEXT NOT NULL, " +
                        "`color` TEXT NOT NULL, `selectedText` TEXT NOT NULL, `note` TEXT, " +
                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`highlightId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_highlights_bookKey` ON `highlights` (`bookKey`)")
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_highlights_profileKey_anchorKey` " +
                        "ON `highlights` (`profileKey`, `anchorKey`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `annotation_notes` (`noteId` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `profileKey` TEXT NOT NULL, `content` TEXT NOT NULL, " +
                        "`locatorJSON` TEXT NOT NULL, `anchorJSON` TEXT, `createdAt` INTEGER NOT NULL, " +
                        "`updatedAt` INTEGER NOT NULL, PRIMARY KEY(`noteId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_annotation_notes_bookKey` " +
                        "ON `annotation_notes` (`bookKey`)",
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
        }

        /** v4 → v5: feature #127 — add the additive `collections` table (unique `nameKey` index) +
         *  the `book_collection` many-to-many join (composite PK, both FKs ON DELETE CASCADE, a
         *  `collectionId` index for the reverse lookup). No data transform. DDL matches Room's generated
         *  v5 schema exactly (the migration test opens the real Room DB, whose structural PRAGMA
         *  validation catches any drift). */
        val MIGRATION_4_5: Migration = object : Migration(4, 5) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `collections` (`id` TEXT NOT NULL, `name` TEXT NOT NULL, " +
                        "`nameKey` TEXT NOT NULL, `createdAt` INTEGER NOT NULL, PRIMARY KEY(`id`))",
                )
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_collections_nameKey` ON `collections` (`nameKey`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `book_collection` (`bookKey` TEXT NOT NULL, " +
                        "`collectionId` TEXT NOT NULL, PRIMARY KEY(`bookKey`, `collectionId`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE , " +
                        "FOREIGN KEY(`collectionId`) REFERENCES `collections`(`id`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_book_collection_collectionId` " +
                        "ON `book_collection` (`collectionId`)",
                )
            }
        }

        /** v5 → v6: feature #128 — add the nullable `author` column to `books` (library search).
         *  Purely additive; migrated rows read `author = null` until a backfill or restore sets it. */
        val MIGRATION_5_6: Migration = object : Migration(5, 6) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN author TEXT")
            }
        }

        /** v6 → v7: feature #128 WI-4 — add the cross-book search index (all in the one `vreader.db`):
         *  `search_sections` (+ bookKey index + FK→books CASCADE), its FTS4/unicode61 content-table
         *  shadow `search_sections_fts`, `search_index_state` (+ FK→books CASCADE), and the transient
         *  `search_sections_staging` buffer (+ bookKey index + FK→books CASCADE). The migration ships
         *  the base + FTS VIRTUAL tables only; Room recreates the FTS content-table sync triggers when
         *  it opens the DB. DDL matches Room's generated v7 schema exactly (the migration test opens the
         *  real Room DB, whose structural PRAGMA validation catches any drift). No data transform. */
        val MIGRATION_6_7: Migration = object : Migration(6, 7) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_sections` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL("CREATE INDEX IF NOT EXISTS `index_search_sections_bookKey` ON `search_sections` (`bookKey`)")
                db.execSQL(
                    "CREATE VIRTUAL TABLE IF NOT EXISTS `search_sections_fts` USING FTS4(" +
                        "`indexedText` TEXT NOT NULL, tokenize=unicode61, content=`search_sections`)",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_index_state` (`bookKey` TEXT NOT NULL, " +
                        "`indexerVersion` INTEGER NOT NULL, `indexedAt` INTEGER NOT NULL, `status` TEXT NOT NULL, " +
                        "PRIMARY KEY(`bookKey`), FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `search_sections_staging` (`id` INTEGER PRIMARY KEY AUTOINCREMENT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, `sectionIndex` INTEGER NOT NULL, `chunkOrdinal` INTEGER NOT NULL, " +
                        "`sectionTitle` TEXT, `text` TEXT NOT NULL, `indexedText` TEXT NOT NULL, " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_search_sections_staging_bookKey` " +
                        "ON `search_sections_staging` (`bookKey`)",
                )
            }
        }

        /** v7 → v8: feature #135 WI-3 — make re-bookmarking the same position idempotent by adding a
         *  composite UNIQUE index on `bookmarks (bookKey, profileKey)` (the atomic-toggle enforcer,
         *  mirroring the highlights `(profileKey, anchorKey)` dedupe precedent).
         *
         *  A pre-#135 create path (`upsertBookmark`, UUID-keyed) could have produced DUPLICATE rows at
         *  the same `(bookKey, profileKey)`; `CREATE UNIQUE INDEX` would FAIL on such a duplicate. So
         *  the migration first DEDUPES — deleting every duplicate LOSER, keeping a DETERMINISTIC winner
         *  per `(bookKey, profileKey)`: the row with the greatest `updatedAt`, tie-broken by the
         *  greatest `createdAt`, then the LOWEST `bookmarkId` (a total, stable order). This is a
         *  targeted dedupe — a non-duplicate row (unique `(bookKey, profileKey)`) is never deleted, and
         *  no other table is touched. THEN the unique index is created, matching Room's generated name
         *  + columns (`index_bookmarks_bookKey_profileKey` on `(bookKey, profileKey)`) exactly, so
         *  Room's structural PRAGMA validation passes. DDL is idempotent (`IF NOT EXISTS`). */
        val MIGRATION_7_8: Migration = object : Migration(7, 8) {
            override fun migrate(db: SupportSQLiteDatabase) {
                // 1) Dedupe: delete every row that is NOT the deterministic winner within its
                //    (bookKey, profileKey) group. The winner is the row whose (updatedAt, createdAt,
                //    -rowid-preference-on-bookmarkId) is greatest — expressed as: a row is a loser iff
                //    another row in the same group ranks strictly higher by (updatedAt DESC,
                //    createdAt DESC, bookmarkId ASC).
                db.execSQL(
                    "DELETE FROM `bookmarks` WHERE `bookmarkId` IN (" +
                        "SELECT b.`bookmarkId` FROM `bookmarks` b JOIN `bookmarks` w " +
                        "ON b.`bookKey` = w.`bookKey` AND b.`profileKey` = w.`profileKey` " +
                        "AND b.`bookmarkId` <> w.`bookmarkId` " +
                        "WHERE (w.`updatedAt` > b.`updatedAt`) " +
                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` > b.`createdAt`) " +
                        "OR (w.`updatedAt` = b.`updatedAt` AND w.`createdAt` = b.`createdAt` " +
                        "AND w.`bookmarkId` < b.`bookmarkId`))",
                )
                // 2) Now that each (bookKey, profileKey) is unique, create the unique index.
                db.execSQL(
                    "CREATE UNIQUE INDEX IF NOT EXISTS `index_bookmarks_bookKey_profileKey` " +
                        "ON `bookmarks` (`bookKey`, `profileKey`)",
                )
            }
        }

        /** v8 → v9: feature #131 WI-2 — add the additive `chapter_translations` bilingual
         *  translation cache (PK `lookupKey`; all columns NOT NULL; a `bookKey` index; FK→books
         *  ON DELETE CASCADE so a book's cached translations drop with the book). Purely additive,
         *  no data transform. DDL matches Room's generated v9 schema exactly (the migration test
         *  opens the real Room DB, whose structural PRAGMA validation catches any drift). Modeled on
         *  the `search_index_state` shape (MIGRATION_6_7). */
        val MIGRATION_8_9: Migration = object : Migration(8, 9) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL(
                    "CREATE TABLE IF NOT EXISTS `chapter_translations` (" +
                        "`lookupKey` TEXT NOT NULL, " +
                        "`bookKey` TEXT NOT NULL, " +
                        "`unitStorageKey` TEXT NOT NULL, " +
                        "`targetLanguage` TEXT NOT NULL, " +
                        "`promptVersion` TEXT NOT NULL, " +
                        "`translatedJson` TEXT NOT NULL, " +
                        "`sourceParagraphCount` INTEGER NOT NULL, " +
                        "`createdAt` INTEGER NOT NULL, " +
                        "PRIMARY KEY(`lookupKey`), " +
                        "FOREIGN KEY(`bookKey`) REFERENCES `books`(`fingerprintKey`) " +
                        "ON UPDATE NO ACTION ON DELETE CASCADE )",
                )
                db.execSQL(
                    "CREATE INDEX IF NOT EXISTS `index_chapter_translations_bookKey` " +
                        "ON `chapter_translations` (`bookKey`)",
                )
            }
        }

        /** v9 → v10: feature #152 WI-2 — add the additive nullable cover-state pair to `books`:
         *  `coverPath` (TEXT, the extracted cover file's path — present for reactivity, since the
         *  library grid repaints off `observeAll()`) and `coverExtractorVersion` (INTEGER, the
         *  negative memo that keeps a backfill from re-parsing every art-less book on every app
         *  start — the `search_index_state.indexerVersion` precedent).
         *
         *  Purely additive, two `ALTER TABLE ADD COLUMN`s, NO data transform: every pre-existing row
         *  reads `NULL`/`NULL`, which is exactly the "never attempted → eligible" tri-state corner, so
         *  a migrated library backfills normally. Nothing else in the row is read or rewritten, so a
         *  migrated book's `author`, `lastOpenedAt` and reading position are untouched. Affinities
         *  match Room's generated v10 schema (`String?` → TEXT, `Int?` → INTEGER); the migration test
         *  opens the real Room DB, whose structural PRAGMA validation catches any drift. */
        val MIGRATION_9_10: Migration = object : Migration(9, 10) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN coverPath TEXT")
                db.execSQL("ALTER TABLE books ADD COLUMN coverExtractorVersion INTEGER")
            }
        }

        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
        val ALL_MIGRATIONS: Array<Migration> =
            arrayOf(
                MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5,
                MIGRATION_5_6, MIGRATION_6_7, MIGRATION_7_8, MIGRATION_8_9,
                MIGRATION_9_10,
            )

        /** The production on-disk database (app-private storage). */
        fun build(context: Context): VReaderDatabase =
            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
                .addMigrations(*ALL_MIGRATIONS)
                .build()
    }
}
