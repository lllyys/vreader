// Purpose: Feature #61 WI-2 — extracts the library cover-replace flow
// (PhotosPicker presentation + CustomCoverStore persist + a coverVersion
// refresh counter) out of LibraryView / LibraryViewSheets into a reusable
// @Observable coordinator, so the reader Book Details sheet (feature #61
// WI-4) can drive the same flow without duplicating it.
//
// Behavior is preserved verbatim from the pre-extraction LibraryView
// cover-swap: present(for:) sets the target book (the picker is shown via
// an onChange so it waits for the triggering context menu to dismiss —
// bug #80), the picked image is persisted through CustomCoverStore, and
// coverVersion is bumped so card / row / rail views reload the cover.
//
// @coordinates-with: LibraryView.swift, LibraryViewSheets.swift,
//   LibraryView+Body.swift, CustomCoverStore.swift

import SwiftUI
import PhotosUI
import UIKit
import OSLog

private let log = Logger(subsystem: "com.vreader.app", category: "CoverPickCoordinator")

/// Owns the custom-cover PhotosPicker flow: which book is being
/// re-covered, the picker presentation state, the picked item, and a
/// `coverVersion` counter that cover-rendering views observe so they
/// reload the cover image after a cover change.
@Observable
@MainActor
final class CoverPickCoordinator {
    /// The book whose cover is being replaced; `nil` when idle.
    var bookForCover: LibraryBookItem?
    /// Whether the system PhotosPicker is presented.
    var isPickerPresented: Bool = false
    /// The item the user picked; transient — cleared by `reset()` once
    /// the picked image has been persisted.
    var pickedItem: PhotosPickerItem?
    /// Bumped on every cover change so views observing it (BookCardView,
    /// BookRowView, ContinueReadingRail) reload the cover image.
    private(set) var coverVersion: Int = 0

    /// Starts the cover-replace flow for `book`. The picker itself is
    /// presented by `CoverPickerModifier`'s `onChange(of: bookForCover)`
    /// — setting the book first lets the presentation wait for the
    /// triggering context menu to dismiss (bug #80).
    func present(for book: LibraryBookItem) {
        bookForCover = book
    }

    /// Bumps `coverVersion` without persisting — for callers that change
    /// a cover out of band, e.g. the "Remove Cover" menu action that
    /// calls `CustomCoverStore.removeCover` directly.
    func bumpCoverVersion() {
        coverVersion += 1
    }

    /// Persists `image` as `book`'s custom cover and bumps `coverVersion`.
    /// `book` is passed explicitly — not read from `bookForCover` — so a
    /// pick already in flight always saves onto the book it was started
    /// for, even if `present(for:)` retargets the coordinator before the
    /// async image load finishes (matches the pre-extraction behavior).
    /// `baseDirectory` is injectable for tests; production passes `nil`
    /// (CustomCoverStore's App Support default).
    func applyCover(_ image: UIImage, for book: LibraryBookItem,
                    baseDirectory: URL? = nil) {
        do {
            try CustomCoverStore.saveCover(
                image, for: book.fingerprintKey, baseDirectory: baseDirectory
            )
        } catch {
            // Logged, not silently swallowed (rule 50 §6): a failed save
            // leaves the previous cover in place; the version bump below
            // still refreshes the observing views.
            log.error("cover save failed for \(book.fingerprintKey, privacy: .public): \(String(describing: error), privacy: .public)")
        }
        coverVersion += 1
    }

    /// Clears the transient pick state (picked item, target book,
    /// presentation flag) — called once the picked image is handled.
    func reset() {
        pickedItem = nil
        bookForCover = nil
        isPickerPresented = false
    }
}

/// Attaches the system PhotosPicker for the custom-cover flow and wires
/// it to a `CoverPickCoordinator`. Apply via `.coverPicker(_:)`.
struct CoverPickerModifier: ViewModifier {
    @Bindable var coordinator: CoverPickCoordinator

    func body(content: Content) -> some View {
        content
            .photosPicker(
                isPresented: $coordinator.isPickerPresented,
                selection: $coordinator.pickedItem,
                matching: .images
            )
            // Present the picker once a book is targeted — deferred via
            // onChange so it waits for the triggering context menu to
            // dismiss (bug #80).
            .onChange(of: coordinator.bookForCover) { _, newBook in
                if newBook != nil { coordinator.isPickerPresented = true }
            }
            .onChange(of: coordinator.pickedItem) { _, newItem in
                // Snapshot the target book before the async load so a
                // retarget mid-flight cannot redirect the save — matches
                // the pre-extraction inline behavior.
                guard let item = newItem,
                      let book = coordinator.bookForCover else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        coordinator.applyCover(image, for: book)
                    }
                    coordinator.reset()
                }
            }
    }
}

extension View {
    /// Drives the custom-cover PhotosPicker flow from a shared
    /// `CoverPickCoordinator`.
    func coverPicker(_ coordinator: CoverPickCoordinator) -> some View {
        modifier(CoverPickerModifier(coordinator: coordinator))
    }
}
