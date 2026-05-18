// Purpose: Feature #61 WI-4 — action wiring for the reader Book Details
// sheet, split from `BookDetailsSheet.swift` to keep that file under
// the ~300-line guideline (rule 50 §9). Routes the metadata-row
// mini-actions (fingerprint copy / location reveal) and the action-row
// taps (cover swap / share book / export annotations) to their effects.
//
// @coordinates-with: BookDetailsSheet.swift, BookDetailsMetadataRow.swift,
//   BookDetailsActionRow.swift, CoverPickCoordinator.swift, ShareSheet.swift

#if canImport(UIKit)
import SwiftUI
import UIKit

extension BookDetailsSheet {

    /// Routes a metadata-row mini-action.
    func handleAccessory(_ accessory: BookDetailsMetadataRow.Model.Accessory) {
        switch accessory {
        case .copy:
            copyFingerprintToPasteboard()
        case .reveal:
            // Plan Risk 2: a file location has no iOS "reveal" equivalent;
            // the system share sheet for the file is the closest "here is
            // the file" affordance.
            showShareSheet = true
        }
    }

    /// Routes an action-row tap.
    func handleAction(_ kind: BookDetailsActionRow.Model.Kind) {
        switch kind {
        case .cover:
            coverPickCoordinator.present(for: book)
        case .share:
            showShareSheet = true
        case .exportAnnotations:
            onExportAnnotations()
        }
    }

    /// Writes the full fingerprint key to the system pasteboard — the
    /// Fingerprint row's copy mini-action. Exposed so
    /// `BookDetailsActionsTests` can pin the copy contract.
    func copyFingerprintToPasteboard() {
        UIPasteboard.general.string = viewModel.fingerprintFull
    }
}
#endif
