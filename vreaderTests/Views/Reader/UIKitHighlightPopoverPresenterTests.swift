// Purpose: Feature #64 WI-5 — tests for `UIKitHighlightPopoverPresenter`, the
// `UIPopoverPresentationController`-based realization of
// `HighlightPopoverPresenting` for the anchored `.card` form.
//
// The app-hosted test target lets these tests build a real `UIWindow` + root
// `UIViewController` and drive an actual present/dismiss/update cycle — so the
// suite exercises the serialized pipeline's *presented*-state contracts, not
// just the idle branches:
//   - `presentCard` anchors a hosting controller as the root VC's
//     `presentedViewController`.
//   - `presentCard` for the SAME `content.id` is idempotent — it keeps the
//     same hosting-controller instance (an in-place `updateCard`, R2-F6), NOT
//     a dismiss-and-re-present.
//   - `updateCard` keeps the same hosting-controller instance.
//   - `dismissCard(completion:)` runs the completion after dismissal — and
//     synchronously when nothing is presented.
//   - the no-host-view fallback: a detached `UIView` has no
//     `nearestViewController`, so `presentCard` surfaces nothing, fires
//     `onDismiss`, and leaves the pipeline reusable.

#if canImport(UIKit)
import Testing
import Foundation
import CoreGraphics
import UIKit
import SwiftUI
@testable import vreader

@Suite("UIKitHighlightPopoverPresenter")
@MainActor
struct UIKitHighlightPopoverPresenterTests {

    private let fingerprint = DocumentFingerprint(
        contentSHA256: "uikit_presenter_sha_0000000000000000000000000000000000",
        fileByteCount: 100, format: .epub
    )

    private func content(id: UUID = UUID()) -> HighlightPopoverContent {
        HighlightPopoverContent(
            id: id, note: "a note", highlightedText: "the passage",
            colorName: "yellow", createdAt: Date(timeIntervalSince1970: 1),
            chapter: "Ch. 1", sourceRect: CGRect(x: 1, y: 2, width: 30, height: 14),
            anchor: nil
        )
    }

    private func theme() -> ReaderThemeV2 { .paper }

    /// Builds a key `UIWindow` with a root `UIViewController` whose view hosts
    /// `anchorView` — so `anchorView.nearestViewController` resolves and the
    /// presenter can actually present. Returns both for assertion + cleanup.
    private func makeHostedAnchor() -> (window: UIWindow, root: UIViewController, anchor: UIView) {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let root = UIViewController()
        let anchor = UIView(frame: CGRect(x: 20, y: 40, width: 200, height: 30))
        root.view.addSubview(anchor)
        window.rootViewController = root
        window.makeKeyAndVisible()
        return (window, root, anchor)
    }

    // MARK: - dismissCard (idle)

    @Test func dismissCard_nothingPresented_runsCompletionSynchronously() {
        let presenter = UIKitHighlightPopoverPresenter()
        var ran = false
        presenter.dismissCard(completion: { ran = true })
        // Nothing was presented — the completion drains synchronously.
        #expect(ran)
    }

    @Test func dismissCard_multipleCompletions_allRunWhenIdle() {
        let presenter = UIKitHighlightPopoverPresenter()
        var count = 0
        presenter.dismissCard(completion: { count += 1 })
        presenter.dismissCard(completion: { count += 1 })
        #expect(count == 2)
    }

    @Test func updateCard_nothingPresented_isNoOp_pipelineStaysIdle() {
        let presenter = UIKitHighlightPopoverPresenter()
        // No card presented — updateCard must be a safe no-op (R2-F6). The
        // observable postcondition: the pipeline is still idle, so a
        // subsequent dismissCard completion drains synchronously.
        presenter.updateCard(
            content: content(), mode: .editing, noteDraft: "draft", pressedColor: .pink
        )
        var ran = false
        presenter.dismissCard(completion: { ran = true })
        #expect(ran)
    }

    // MARK: - presentCard with no host view-controller

    @Test func presentCard_detachedView_firesOnDismissAndStaysReusable() {
        let presenter = UIKitHighlightPopoverPresenter()
        let detached = UIView()  // not in any window / view-controller hierarchy
        var dismissed = false
        presenter.presentCard(
            content(), theme: theme(), mode: .reading, noteDraft: "",
            pressedColor: nil, in: detached,
            onAction: { _ in }, onDraftChange: { _ in },
            onDismiss: { dismissed = true }
        )
        // No `nearestViewController` → the presenter surfaces nothing and
        // reports the dismissal so the modifier's sheet fallback covers it.
        #expect(dismissed)
        // The pipeline is back to idle — a follow-up dismissCard drains sync.
        var ran = false
        presenter.dismissCard(completion: { ran = true })
        #expect(ran)
    }

    // MARK: - presentCard with a real hosted window

    @Test func presentCard_hostedAnchor_presentsAHostingController() {
        let (window, root, anchor) = makeHostedAnchor()
        defer { window.isHidden = true }
        let presenter = UIKitHighlightPopoverPresenter()

        presenter.presentCard(
            content(), theme: theme(), mode: .reading, noteDraft: "",
            pressedColor: nil, in: anchor,
            onAction: { _ in }, onDraftChange: { _ in }, onDismiss: {}
        )

        // The presenter anchors a UIHostingController as the root's
        // presentedViewController (set synchronously even with animated: true).
        #expect(root.presentedViewController is UIHostingController<HighlightActionCardView>)
    }

    @Test func presentCard_sameContentID_isIdempotent_keepsSameHostingController() {
        let (window, root, anchor) = makeHostedAnchor()
        defer { window.isHidden = true }
        let presenter = UIKitHighlightPopoverPresenter()
        let id = UUID()

        presenter.presentCard(
            content(id: id), theme: theme(), mode: .reading, noteDraft: "",
            pressedColor: nil, in: anchor,
            onAction: { _ in }, onDraftChange: { _ in }, onDismiss: {}
        )
        let firstHost = root.presentedViewController
        #expect(firstHost != nil)

        // A second presentCard for the SAME content.id must NOT dismiss +
        // re-present — it routes to updateCard, keeping the same hosting
        // controller instance (R2-F6 — no flicker, keyboard preserved).
        presenter.presentCard(
            content(id: id), theme: theme(), mode: .editing, noteDraft: "typed",
            pressedColor: nil, in: anchor,
            onAction: { _ in }, onDraftChange: { _ in }, onDismiss: {}
        )
        #expect(root.presentedViewController === firstHost)
    }

    @Test func updateCard_whilePresented_keepsSameHostingController() {
        let (window, root, anchor) = makeHostedAnchor()
        defer { window.isHidden = true }
        let presenter = UIKitHighlightPopoverPresenter()
        let id = UUID()

        presenter.presentCard(
            content(id: id), theme: theme(), mode: .reading, noteDraft: "",
            pressedColor: nil, in: anchor,
            onAction: { _ in }, onDraftChange: { _ in }, onDismiss: {}
        )
        let host = root.presentedViewController
        #expect(host != nil)

        // updateCard reassigns the hosting controller's rootView in place —
        // the presented controller instance is unchanged.
        presenter.updateCard(
            content: content(id: id), mode: .confirmingDelete, noteDraft: "",
            pressedColor: nil
        )
        #expect(root.presentedViewController === host)
    }

    @Test func dismissCard_whilePresented_runsCompletionAfterDismissal() async {
        let (window, root, anchor) = makeHostedAnchor()
        defer { window.isHidden = true }
        let presenter = UIKitHighlightPopoverPresenter()

        presenter.presentCard(
            content(), theme: theme(), mode: .reading, noteDraft: "",
            pressedColor: nil, in: anchor,
            onAction: { _ in }, onDraftChange: { _ in }, onDismiss: {}
        )
        #expect(root.presentedViewController != nil)

        // Wait on the completion itself — resumed from the real modal-dismiss
        // completion, NOT a fixed sleep (rule 10: no bare Task.sleep for sync).
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            presenter.dismissCard(completion: { continuation.resume() })
        }
        // The dismissal completed and the card is gone.
        #expect(root.presentedViewController == nil)
        // The presenter is reusable — a follow-up dismissCard drains sync.
        var ran = false
        presenter.dismissCard(completion: { ran = true })
        #expect(ran)
    }
}
#endif
