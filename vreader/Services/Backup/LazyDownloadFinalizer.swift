// Purpose: Promotes a downloaded staged file into the user's library at
// the end of the lazy-download path. Feature #47 WI-4b — the integration
// step that wires `BookFileImportFinalizer`'s SHA verification into the
// `LazyDownloadCoordinator.didFinishDownload` flow and updates SwiftData
// state so the row flips from `.remoteOnly` to `.local` and the file
// lives at the canonical sandbox path that the reader resolves against.
//
// Bug #115: this wiring was deferred when feature #47's row-tap path
// shipped (WI-6 part 4) and never landed, so downloads completed but
// Book rows stayed `.remoteOnly` forever.
//
// Why this lives outside `BookFileImportFinalizer`:
//
// - `BookFileImportFinalizer` operates on a brand-new file via
//   `BookImporter.importFile(.restore)`. For an existing `.remoteOnly`
//   row, BookImporter hits the dedupe branch (step 7), updates only
//   provenance, and returns isDuplicate=true — it never moves the file
//   to the canonical sandbox path or touches `fileState`. That's the
//   right semantics for the materialize-all path (which deletes its
//   temp file after) but useless for the lazy-download path (which
//   needs the file to land at the canonical path so the reader can
//   open it). So the lazy-download path operates on the existing row
//   directly: SHA verify → move staged → canonical → flip fileState.
//
// - The two flavours share `BookFileImportFinalizer.localFileSHA256`
//   for hash semantics, so verification is identical across paths.
//
// @coordinates-with: BookFileImportFinalizer.swift,
//   BookFileMaterializer.swift, LazyDownloadCoordinator.swift,
//   LazyDownloadTaskMeta.swift, PersistenceActor+RemoteOnly.swift,
//   docs/bugs.md (bug #115)

import Foundation
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "LazyDownloadFinalizer")

/// Resolves the canonical sandbox URL for a `(fingerprintKey, originalExtension)`
/// pair. Defaults to `BookFileMaterializer.defaultSandboxResolver` so the
/// lazy-download path lands files in the same `ImportedBooks/` directory
/// that the reader and importer use.
typealias LazyDownloadSandboxURLResolver = @Sendable (_ fingerprintKey: String, _ originalExtension: String) -> URL

struct LazyDownloadFinalizer: Sendable {

    enum Failure: Error, Equatable, Sendable {
        case sha256ReadFailed(String)
        case sha256Mismatch(expected: String, actual: String)
        case moveToSandboxFailed(String)
        case persistenceUpdateFailed(String)
    }

    private let persistence: PersistenceActor
    private let canonicalURLResolver: LazyDownloadSandboxURLResolver

    init(
        persistence: PersistenceActor,
        canonicalURLResolver: @escaping LazyDownloadSandboxURLResolver = BookFileMaterializer.defaultSandboxResolver
    ) {
        self.persistence = persistence
        self.canonicalURLResolver = canonicalURLResolver
    }

    /// Promotes the staged downloaded file into the library:
    /// 1. Streaming SHA-256 of `stagedURL` must match `meta.expectedSHA256`.
    /// 2. Move `stagedURL` → canonical sandbox path (replacing any prior
    ///    file from a previous attempt).
    /// 3. Update Book row: `fileState = .local`, `blobPath = nil`.
    ///
    /// On SHA mismatch the staged file is left alone (caller decides
    /// retention/cleanup) and persistence is untouched. On move failure
    /// persistence is also untouched. On persistence failure the file
    /// has already moved — next-launch reconcile will retry the state
    /// flip rather than try to roll the move back.
    func finalize(stagedURL: URL, meta: LazyDownloadTaskMeta) async throws {
        // Step 1: SHA-256 verify (streaming so very-large blobs don't spike memory).
        let actualHash: String
        do {
            actualHash = try BookFileImportFinalizer.localFileSHA256(at: stagedURL)
        } catch {
            log.error(
                "sha256 read failed for \(meta.fingerprintKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            throw Failure.sha256ReadFailed("\(error)")
        }
        guard actualHash == meta.expectedSHA256 else {
            log.error(
                "sha256 mismatch for \(meta.fingerprintKey, privacy: .private): expected=\(meta.expectedSHA256, privacy: .private) actual=\(actualHash, privacy: .private)"
            )
            throw Failure.sha256Mismatch(expected: meta.expectedSHA256, actual: actualHash)
        }

        // Step 2: move to canonical sandbox path.
        let canonical = canonicalURLResolver(meta.fingerprintKey, meta.originalExtension)
        do {
            try FileManager.default.createDirectory(
                at: canonical.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            // Replace any pre-existing file from a previous attempt — we just
            // verified the staged bytes match the expected hash, so they're
            // the bytes we want. A leftover from a prior run isn't trustworthy.
            if FileManager.default.fileExists(atPath: canonical.path) {
                try FileManager.default.removeItem(at: canonical)
            }
            try FileManager.default.moveItem(at: stagedURL, to: canonical)
        } catch {
            log.error(
                "move to canonical failed for \(meta.fingerprintKey, privacy: .private): \(String(describing: error), privacy: .private)"
            )
            throw Failure.moveToSandboxFailed("\(error)")
        }

        // Step 3: persistence — fileState=.local AND blobPath=nil in a
        // single atomic save (bug #118). The blob pointer is no longer
        // needed: the file lives in the sandbox now, and a future
        // re-upload would reconstruct the path from the canonical
        // {format}/{sha}_{bytes}.{ext} layout.
        //
        // Atomicity matters because
        // `LazyDownloadCoordinator.reattachAndReconcile` only scans
        // `.downloading` rows — a row left half-promoted to `.local`
        // with a stale `blobPath` would never be reconciled and would
        // ship inconsistent state to a future backup pass.
        do {
            try await persistence.promoteToLocalClearBlob(fingerprintKey: meta.fingerprintKey)
        } catch {
            log.error(
                "persistence update failed for \(meta.fingerprintKey, privacy: .private) (file already moved): \(String(describing: error), privacy: .private)"
            )
            throw Failure.persistenceUpdateFailed("\(error)")
        }

        log.info(
            "finalize succeeded for \(meta.fingerprintKey, privacy: .private) → \(canonical.lastPathComponent, privacy: .private)"
        )
    }

    /// Bug #118 follow-up (Codex Medium): recovery path used by
    /// `LazyDownloadCoordinator.reattachAndReconcile`. If the previous
    /// finalize attempt moved the staged file to its canonical sandbox
    /// path but failed at the persistence save, the row sits at
    /// `.downloading` even though the bytes are local with the right
    /// SHA. Without recovery, reconcile would flip the row to `.failed`
    /// and the next user tap would re-download bytes that already exist.
    ///
    /// Returns `true` if the row was successfully promoted to `.local`,
    /// `false` if the canonical file is missing, has the wrong SHA, or
    /// the persistence save fails again. The caller should fall through
    /// to its existing `.failed` reconcile path on `false`.
    func tryPromoteFromDisk(
        fingerprintKey: String,
        expectedSHA: String,
        candidateExtensions: [String]
    ) async -> URL? {
        // Bug #118 follow-up (Codex round 2): the live lazy-download path
        // computes its `originalExtension` from `BookFormat.fileExtensions.first`
        // (e.g., `azw3` for `.azw3` format), while a row's
        // `Book.originalExtension` carries the user's import-time
        // extension (e.g., `mobi` for an AZW3 book imported as .mobi).
        // For preserved-extension formats these can disagree, so the
        // canonical file might exist under either name. Try every
        // candidate the caller hands us; the first match wins.
        guard !candidateExtensions.isEmpty else { return nil }
        for ext in candidateExtensions {
            let canonical = canonicalURLResolver(fingerprintKey, ext)
            guard FileManager.default.fileExists(atPath: canonical.path) else { continue }
            guard let actualSHA = try? BookFileImportFinalizer.localFileSHA256(at: canonical),
                  actualSHA == expectedSHA
            else { continue }
            do {
                try await persistence.promoteToLocalClearBlob(fingerprintKey: fingerprintKey)
                log.info(
                    "tryPromoteFromDisk recovered \(fingerprintKey, privacy: .private) → .local (file already at canonical path: \(canonical.lastPathComponent, privacy: .private))"
                )
                return canonical
            } catch {
                log.error(
                    "tryPromoteFromDisk persistence failed for \(fingerprintKey, privacy: .private): \(String(describing: error), privacy: .private)"
                )
                return nil
            }
        }
        return nil
    }
}
