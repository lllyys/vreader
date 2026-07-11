// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
// Version 6 is the current schema; v1 was the initial books+positions baseline and
// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
// books.lastOpenedAt). Subsequent additive migrations: 2→3 daily_reading (#122),
// 3→4 annotations (#123), 4→5 collections (#127), 5→6 books.author (#128 search).
// The migration round-trip test (VReaderDatabaseMigrationTest) guards them. Future
// schema changes append a Migration(n, n+1) to ALL_MIGRATIONS and bump `version`.
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
    ],
    version = 6,
    exportSchema = true,
)
abstract class VReaderDatabase : RoomDatabase() {
    abstract fun bookDao(): BookDao
    abstract fun readingPositionDao(): ReadingPositionDao
    abstract fun readingStatsDao(): ReadingStatsDao
    abstract fun annotationDao(): AnnotationDao
    abstract fun collectionDao(): CollectionDao

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

        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
        val ALL_MIGRATIONS: Array<Migration> =
            arrayOf(MIGRATION_1_2, MIGRATION_2_3, MIGRATION_3_4, MIGRATION_4_5, MIGRATION_5_6)

        /** The production on-disk database (app-private storage). */
        fun build(context: Context): VReaderDatabase =
            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
                .addMigrations(*ALL_MIGRATIONS)
                .build()
    }
}
