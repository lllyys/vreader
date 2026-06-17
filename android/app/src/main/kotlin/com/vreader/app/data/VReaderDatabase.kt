// Purpose: Room database + schema-versioned migration scaffold — feature #106 WI-3.
// Version 2 is the current schema; v1 was the initial books+positions baseline and
// MIGRATION_1_2 is the worked example of the additive-migration pattern (adds
// books.lastOpenedAt). The migration round-trip test (VReaderDatabaseMigrationTest)
// guards it. Future schema changes append a Migration(n, n+1) to ALL_MIGRATIONS and
// bump `version`.
package com.vreader.app.data

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

@Database(
    entities = [BookEntity::class, ReadingPositionEntity::class],
    version = 2,
    exportSchema = true,
)
abstract class VReaderDatabase : RoomDatabase() {
    abstract fun bookDao(): BookDao
    abstract fun readingPositionDao(): ReadingPositionDao

    companion object {
        private const val DB_NAME = "vreader.db"

        /** v1 → v2: add the nullable `lastOpenedAt` recents column to `books`. */
        val MIGRATION_1_2: Migration = object : Migration(1, 2) {
            override fun migrate(db: SupportSQLiteDatabase) {
                db.execSQL("ALTER TABLE books ADD COLUMN lastOpenedAt INTEGER")
            }
        }

        /** All registered migrations, oldest first. Append future Migration(n,n+1) here. */
        val ALL_MIGRATIONS: Array<Migration> = arrayOf(MIGRATION_1_2)

        /** The production on-disk database (app-private storage). */
        fun build(context: Context): VReaderDatabase =
            Room.databaseBuilder(context.applicationContext, VReaderDatabase::class.java, DB_NAME)
                .addMigrations(*ALL_MIGRATIONS)
                .build()
    }
}
