package com.vreader.app.diagnostics

import androidx.core.content.FileProvider

/**
 * Purpose: Feature #164 WI-7 — the FileProvider that grants read access to the diagnostics export,
 * and to nothing else. Declared in the manifest as `${applicationId}.diagnosticsprovider`
 * (`exported=false`, `grantUriPermissions=true`) backed by `@xml/diagnostics_paths`, whose only
 * root is `filesDir/diagnostics`.
 *
 * **Why a SECOND provider rather than a second root on `@xml/file_paths`** (plan section 6.4): the
 * book provider's paths file grants `filesDir/books` and says so in a comment that would become
 * false; more concretely, `BookFileProvider` resolves its DISPLAY_NAME override from a GLOBAL,
 * un-scoped registration map keyed by trailing filename segment, so a diagnostics file sharing that
 * provider would be one name collision away from a mislabelled attachment. Neither is an imminent
 * vulnerability — the failure mode is cosmetic and the registrations are only populated from the
 * book-share path — but a second provider costs one manifest element and one three-line xml file,
 * and in exchange each provider grants exactly one directory and neither feature can widen the
 * other's scope. `BookFileProvider`, `file_paths.xml` and `BookShareIntent` are untouched.
 *
 * No `query` override on purpose: the export's on-disk name (`vreader-log-YYYY-MM-DD.txt`) is
 * already the name a receiver should show, so the platform's default cursor is correct — the whole
 * reason `BookFileProvider` needs an override (books are stored under an extension-less fingerprint
 * key) does not apply here.
 *
 * @coordinates-with DiagnosticsExportWriter.kt (writes what this grants), DiagnosticsShareIntent.kt
 *   (requests the URI), AndroidManifest.xml, `res/xml/diagnostics_paths.xml`
 */
class DiagnosticsFileProvider : FileProvider()
