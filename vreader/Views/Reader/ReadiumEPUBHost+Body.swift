// Purpose: Feature #42 — body + open/teardown lifecycle for `ReadiumEPUBHost`,
// extracted from `ReadiumEPUBHost.swift` so the host stays under the ~300-line
// budget as it accreted WIs 5–12 + the WI-7/8/10b refinements. The `@State` and
// the `body` requirement stay on the struct (SwiftUI); this file owns the
// composed `coreBody`, the `.ready` navigator builder, and the `.task`/
// `.onDisappear` lifecycle helpers.
//
// @coordinates-with: ReadiumEPUBHost.swift, ReadiumNavigatorRepresentable.swift,
//   ReadiumEPUBHost+Background.swift (backgroundComposited),
//   ReadiumEPUBHost+Bilingual.swift (bilingualSurfaces),
//   ReadiumEPUBHost+Highlights.swift (highlightObservers, handleReadiumSelection),
//   ReadiumEPUBHost+TTSFollow.swift (ttsFollowObservers)

#if canImport(UIKit)
import SwiftUI
import UIKit
import ReadiumShared

extension ReadiumEPUBHost {

    @ViewBuilder
    var coreBody: some View {
        Group {
            switch viewModel?.state {
            case .ready(let publication):
                // WI-10b: wrap the navigator chain with the TTS-follow observers
                // (in `+TTSFollow`). The wrapped navigator auto-advances to track
                // the spoken position.
                ttsFollowObservers(readyNavigator(publication: publication),
                                   spineHrefs: publication.readingOrder.map(\.href))
            case .failed:
                // Reuse the existing reader's failure messaging (rule 51 — no
                // new chrome): the same copy the dispatcher shows when a book
                // cannot be opened.
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Unable to open this book.")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .accessibilityIdentifier("readiumOpenErrorView")
            case .loading, .none:
                ProgressView()
            }
        }
        .task { await openHostTask() }
        // WI-8: highlight observers (selection-popover present + create,
        // decoration clear, import re-restore) live in the `+Highlights`
        // extension's `highlightObservers` modifier (300-line budget).
        .modifier(highlightObservers)
        // Bug #303: select → Note parity — observe `.readerAnnotationRequested`
        // and present the designed `AddNoteSheet` (rule 51 reuse). Lives in the
        // `+Annotations` extension's `annotationObservers` modifier.
        .modifier(annotationObservers)
        // Bug #302: present the unified highlight-action popover (color / note /
        // copy / share / delete) when a stored highlight is TAPPED. The adapter's
        // `observeDecorationInteractions` posts `.readerHighlightTapped`; this
        // presenter (the same one legacy EPUB / TXT / MD attach) observes it and
        // opens the designed popover over `highlightCoordinator` (a
        // `HighlightMutating`). Inert until the coordinator is built / in previews
        // (the `IfAvailable` variant returns self when `mutating` is nil).
        .unifiedHighlightPopoverPresenterIfAvailable(
            modelContainer: modelContainer,
            bookFingerprintKey: fingerprint.canonicalKey,
            mutating: highlightCoordinator,
            theme: settingsStore.theme
        )
        .onDisappear { onHostDisappear() }
    }

    /// The Readium navigator view + its WI-9a nav observers for `.ready`. Extracted
    /// so `coreBody` stays compact and the WI-10b TTS-follow wrap reads as one line.
    @ViewBuilder
    func readyNavigator(publication: ReadiumShared.Publication) -> some View {
        // WI-7: read `theme` + `typography` + `epubLayout` directly here so
        // SwiftUI tracks all three as `@Observable` dependencies of this body — a
        // Display-settings change mutates one of them, re-runs the body, and
        // re-builds the representable with fresh preferences, which
        // `updateUIViewController` then re-submits.
        ReadiumNavigatorRepresentable(
            publication: publication,
            preferences: ReadiumEPUBReaderViewModel.epubPreferences(
                theme: settingsStore.theme,
                typography: settingsStore.typography,
                layout: settingsStore.epubLayout,
                // Gate-4 round-1: feed the per-format-calibrated `.epub` size (the
                // same calibration band the legacy EPUB engine renders through) so
                // perceived font size stays consistent across the two engines.
                calibratedFontSizePt: settingsStore.calibrator.calibratedSize(
                    forUnified: settingsStore.typography.fontSize, target: .epub
                ),
                // WI-7: clear the HTML body background so the composited
                // ThemeBackgroundView shows through (photo/custom-bg path).
                transparentBackground: shouldRenderTransparentBackground
            ),
            fingerprintKey: fingerprint.canonicalKey,
            readerToken: readerToken,
            initialLocation: restoredLocator,
            // Med-2: a representable can only return a placeholder controller
            // synchronously, so a navigator-init throw routes here to flip the host
            // to `.failed`. `[weak viewModel]` avoids mutating @State during render.
            onNavigatorInitFailure: { [weak viewModel] message in
                viewModel?.markNavigatorInitFailed(message)
            },
            // WI-6: forward `locationDidChange` into the VM's debounced save.
            // `@MainActor @Sendable` so the coordinator stays decoupled from the VM.
            onLocationChange: { [weak viewModel] locator in
                viewModel?.save(readiumLocator: locator)  // WI-6 save
                // Gate-4 HIGH-1: remember the live locator so a first-enable toggle
                // (no location change of its own) resolves the VISIBLE chapter.
                // Compose — the WI-6 save above still runs.
                lastKnownReadiumLocator = locator
                // WI-11b: drive the chapter-change enumerate off the same callback
                // (href change + enabled → enumerate; intra-chapter deduped). HIGH-2:
                // a persisted-on book enumerates on its FIRST locator.
                handleBilingualLocationChange(locator)
                // Bug #299: update the bottom-chrome scrubber + labels off the
                // same relocate.
                updateBottomChrome(from: locator)
                // Bug #313: the Readium host was the only format host that never
                // posted `.readerPositionDidChange`, so `currentLocator` stayed
                // nil → the TOC couldn't focus the current chapter. Post the
                // relocate's vreader locator — but only when its href resolves to
                // a known spine href (Codex Gate-4 MED), so an unresolved href
                // never overwrites a good `currentLocator` with a non-TOC-matchable
                // position.
                ReadiumPositionBroadcast.post(
                    ReadiumPositionBroadcast.spineResolved(
                        currentVReaderLocator(from: locator),
                        spineHrefs: bilingualSpineHrefs
                    )
                )
            },
            // WI-8 (new-highlight): cache the finalized selection + surface the
            // designed color-picker popover (handler in `+Highlights`).
            onSelection: { handleReadiumSelection($0) },
            // WI-8: the host-owned highlight adapter — bound to the live navigator
            // in the representable, detached on teardown.
            highlightAdapter: highlightAdapter,
            navCommander: navCommander,
            bilingualCommander: bilingualCommander,
            // WI-7: make the navigator view + spine WebViews transparent so the
            // ThemeBackgroundView composited behind shows through.
            transparentBackground: shouldRenderTransparentBackground
        )
        .ignoresSafeArea()
        // WI-9a: the jump observer resolves a (legacy, OPF-relative) vreader
        // `Locator` href against the publication's reading-order.
        .onReceive(NotificationCenter.default.publisher(for: .readerNextPage)) { _ in
            navCommander.nextPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerPreviousPage)) { _ in
            navCommander.previousPage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .readerNavigateToLocator)) { notification in
            guard let vLocator = notification.object as? Locator,
                  let readiumLocator = ReadiumEPUBReaderViewModel.readiumLocator(
                    fromVReader: vLocator,
                    spineHrefs: publication.readingOrder.map(\.href)
                  ) else { return }
            navCommander.navigate(to: readiumLocator)
        }
    }

    /// Host open lifecycle (`.task`): VM + highlight coordinator, restore saved
    /// position before mount, open bilingual parser + VM + publication, restore.
    func openHostTask() async {
        guard viewModel == nil else { return }
        let persistence = PersistenceActor(modelContainer: modelContainer)
        let vm = ReadiumEPUBReaderViewModel(
            fileURL: fileURL,
            fingerprint: fingerprint,
            persistence: persistence,
            deviceId: ReaderContainerView.deviceId
        )
        viewModel = vm
        // WI-8: build the highlight coordinator over the host-owned adapter so
        // restore-on-open + the `.readerHighlightRemoved` observer route through
        // the shared highlight lifecycle (mirrors the legacy EPUB container). The
        // adapter binds to the navigator separately (in the representable) once
        // `state == .ready`.
        highlightCoordinator = HighlightCoordinator(
            renderer: highlightAdapter,
            persistence: persistence,
            bookFingerprintKey: fingerprint.canonicalKey
        )
        // WI-6: load the saved position BEFORE the navigator mounts (the
        // representable is only built once `state == .ready`) so the navigator
        // opens directly at the restored locator instead of the start. nil →
        // open at the start (first-open / nothing saved).
        restoredLocator = await vm.restoredReadiumLocator()
        // WI-11b Gate-4 round-3 HIGH-1 (persisted-on open race): build the
        // bilingual parser + VM BEFORE `vm.open()` flips `state = .ready` and
        // mounts the navigator, so the navigator's initial `locationDidChange`
        // sees a non-nil VM and a persisted-on book's only initial enumerate
        // isn't dropped. Neither call depends on the Readium publication.
        await openBilingualParser()
        ensureBilingualViewModel()
        await vm.open()
        // WI-8: restore stored highlights once the publication is open. The
        // adapter tracks the set even before the navigator attaches, so the
        // decorations submit as soon as `attach(navigator:)` runs in the
        // representable's `makeUIViewController`. `forHref: nil` — Readium
        // decorations are book-wide; the navigator renders only those whose
        // locators fall on visible spine items.
        await highlightCoordinator?.restoreAll()
    }

    /// Host teardown (`.onDisappear`). High (bug #252 lesson): the host owns the
    /// VM (+ its `Publication`) via @State, so close fires only on a genuine nav
    /// pop — releasing file handles deterministically. Registry + navigator
    /// teardown live in `dismantleUIViewController`. `closeAndFlush()` awaits the
    /// final position save in a background task so it survives the dismiss.
    func onHostDisappear() {
        guard let viewModel else { return }
        let bgTaskID = UIApplication.shared.beginBackgroundTask(expirationHandler: nil)
        Task {
            await viewModel.closeAndFlush()
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }
    }
}
#endif
