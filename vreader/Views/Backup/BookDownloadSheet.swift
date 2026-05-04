// Purpose: Sheet that LibraryView presents when the user taps a
// non-`.local` row. Shows the lazy-download coordinator's live
// progress for the tapped book and surfaces the outcome (success →
// auto-dismiss; failure → retry CTA). Feature #47 WI-6.
//
// @coordinates-with: LibraryView.swift, LazyDownloadCoordinator.swift,
//   LibraryBookItem.swift,
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import SwiftUI

/// Modal sheet bound to one fingerprintKey's lazy-download progress.
/// Drives the UI from the `@Observable` `LazyDownloadCoordinator`'s
/// `progressByKey` + `outcomes` dictionaries. Auto-dismisses on
/// completion; offers "Retry" on failure (re-posts the same
/// `libraryRowTappedWhileNotLocal` notification so LibraryView's
/// existing observer kicks off the next attempt).
struct BookDownloadSheet: View {
    let book: LibraryBookItem
    /// Bound to LibraryView's @State sheet item — set to nil to dismiss.
    @Binding var presentedBook: LibraryBookItem?
    @Environment(\.lazyDownloadCoordinator) private var coordinator

    var body: some View {
        VStack(spacing: 16) {
            headerSection
            progressSection
            footerSection
        }
        .padding(24)
        .presentationDetents([.medium])
        .onChange(of: outcome) { _, newOutcome in
            // Auto-dismiss on success after a short delay so the user
            // sees the "Done" state for a frame.
            if case .completed = newOutcome {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    presentedBook = nil
                    coordinator?.clearOutcome(for: book.fingerprintKey)
                }
            }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 8) {
            Image(systemName: outcomeIcon)
                .font(.system(size: 36))
                .foregroundStyle(outcomeTint)
            Text(book.title)
                .font(.headline)
                .multilineTextAlignment(.center)
            if let author = book.author {
                Text(author)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        if let progress = currentProgress {
            if let total = progress.totalBytes, total > 0 {
                ProgressView(
                    value: Double(progress.bytesWritten),
                    total: Double(total)
                ) {
                    Text("Downloading…")
                        .font(.caption)
                } currentValueLabel: {
                    Text("\(formatBytes(progress.bytesWritten)) / \(formatBytes(total))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView()
                Text("Downloading… (\(formatBytes(progress.bytesWritten)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if case .completed = outcome {
            Text("Downloaded")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } else if case .failed(_, let reason) = outcome {
            VStack(spacing: 4) {
                Text("Download failed")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                Text(reason)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }
        } else {
            ProgressView()
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        if case .failed = outcome {
            HStack(spacing: 12) {
                Button("Cancel", role: .cancel) {
                    coordinator?.clearOutcome(for: book.fingerprintKey)
                    presentedBook = nil
                }
                .buttonStyle(.bordered)
                Button("Retry") {
                    NotificationCenter.default.post(
                        name: .libraryRowTappedWhileNotLocal,
                        object: nil,
                        userInfo: [
                            "fingerprintKey": book.fingerprintKey,
                            "fileState": book.fileState.rawValue
                        ]
                    )
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            Button("Hide") {
                presentedBook = nil
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Coordinator state derivations

    private var currentProgress: LazyDownloadProgress? {
        coordinator?.progressByKey[book.fingerprintKey]
    }

    private var outcome: LazyDownloadOutcome? {
        coordinator?.outcomes[book.fingerprintKey]
    }

    private var outcomeIcon: String {
        switch outcome {
        case .completed: return "checkmark.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .none: return "arrow.down.circle"
        }
    }

    private var outcomeTint: Color {
        switch outcome {
        case .completed: return .green
        case .failed: return .red
        case .none: return .accentColor
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(
            fromByteCount: bytes,
            countStyle: .file
        )
    }
}
