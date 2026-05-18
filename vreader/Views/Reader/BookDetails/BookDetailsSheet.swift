// Purpose: Feature #61 — the reader Book Details sheet (stacked
// layout). A half-sheet reached from the reader More-menu's "Book
// details" row, replacing the feature-#60 WI-6c settings-panel interim.
// Renders the book's cover, title, author, collection tags, a metadata
// card (format / size / pages / fingerprint / location) and an actions
// card (replace cover / share book / export annotations).
//
// Layout pinned to the committed design bundle:
// `dev-docs/designs/vreader-fidelity-v1/project/vreader-book-details.jsx`
// (`DetailsStacked`). Out of scope (plan §2):
//  - the "split" (cover-left) layout — a Tweak, not the canonical surface;
//  - the "remoteOnly" state — the reader only opens local readable books;
//  - the "missing cover" dashed placeholder — `BookCoverArtView` always
//    renders a generative typographic fallback, so a coverless state is
//    unreachable here. `hasCover` only switches the cover action's label.
//
// WI-3 shipped the rendered surface + the More-menu route. WI-4 wires
// the actions: the cover pencil + "Replace/Add cover…" row drive the
// shared `CoverPickCoordinator`; the title-bar Share button + "Share
// book…" row + the Location row's reveal mini-action present the system
// share sheet for the book file; the Fingerprint row's copy mini-action
// writes the full key to the pasteboard; "Export annotations…" routes
// to the annotations panel (via `onExportAnnotations`, the same
// destination the More-menu's Export row uses).
//
// @coordinates-with: BookDetailsViewModel.swift, BookDetailsMetadataRow.swift,
//   BookDetailsActionRow.swift, BookDetailsTagFlow.swift, ReaderSheetChrome.swift,
//   ReaderThemeV2.swift, BookCoverArtView.swift, CustomCoverStore.swift,
//   CoverPickCoordinator.swift, ShareSheet.swift, ReaderTypography.swift

#if canImport(UIKit)
import SwiftUI

/// The reader Book Details half-sheet — stacked layout.
struct BookDetailsSheet: View {
    let book: LibraryBookItem
    /// Visual-identity-v2 theme tokens for the sheet surface.
    let theme: ReaderThemeV2
    /// Drives the cover-replace PhotosPicker flow (feature #61 WI-2).
    /// Owned by `ReaderContainerView` so the pick survives sheet
    /// dismiss / re-present, and its `coverVersion` refreshes the cover.
    let coverPickCoordinator: CoverPickCoordinator
    /// Routes "Export annotations…" to the host — the reader opens the
    /// annotations panel on its Highlights tab (the export affordance
    /// lives there; no separate export sheet — same as the More-menu).
    let onExportAnnotations: () -> Void

    /// Presents the system share sheet for the book file — driven by
    /// the title-bar Share button, the "Share book…" action row, and
    /// the Location row's reveal mini-action. `internal` so the
    /// `+Actions.swift` action router can drive it.
    @State var showShareSheet = false

    /// Display projection of the book — a cheap pure struct (WI-1).
    /// `internal` so `+Actions.swift` can read `fingerprintFull`.
    var viewModel: BookDetailsViewModel { BookDetailsViewModel(book: book) }

    // MARK: - Composed rows (testing surface)

    /// The Metadata card's rows, in design order. The Pages row is
    /// omitted when the book has no usable page count (plan Risk 1).
    /// Exposed (not `private`) so `BookDetailsRouteTests` can pin the
    /// composition without a SwiftUI render path.
    var metadataRows: [BookDetailsMetadataRow.Model] {
        var rows: [BookDetailsMetadataRow.Model] = [
            .init(label: "Format", value: viewModel.formatDisplay, accessory: nil),
            .init(label: "Size", value: viewModel.fileSizeDisplay, accessory: nil),
        ]
        if let pages = viewModel.pagesDisplay {
            rows.append(.init(label: "Pages", value: pages, accessory: nil))
        }
        rows.append(.init(
            label: "Fingerprint", value: viewModel.fingerprintDisplay, accessory: .copy))
        rows.append(.init(
            label: "Location", value: viewModel.locationDisplay, accessory: .reveal))
        return rows
    }

    /// The Actions card's rows, in design order. The cover row's label
    /// tracks `hasCover`. Exposed for `BookDetailsActionsTests`.
    var actionRows: [BookDetailsActionRow.Model] {
        [
            .init(
                kind: .cover, systemImage: "pencil",
                label: viewModel.hasCover ? "Replace cover\u{2026}" : "Add cover\u{2026}",
                sublabel: nil),
            .init(
                kind: .share, systemImage: "square.and.arrow.up",
                label: "Share book\u{2026}", sublabel: nil),
            .init(
                kind: .exportAnnotations, systemImage: "arrow.down.doc",
                label: "Export annotations\u{2026}",
                sublabel: "Markdown \u{00b7} JSON \u{00b7} VReader JSON"),
        ]
    }

    // MARK: - Body

    var body: some View {
        ReaderSheetChrome(theme: theme, title: "Book details", trailing: { shareButton }) {
            ScrollView {
                VStack(spacing: 22) {
                    header
                    section(label: "Metadata") { metadataCard }
                    section(label: "Actions") { actionCard }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 32)
            }
        }
        .accessibilityIdentifier("bookDetailsSheet")
        .coverPicker(coverPickCoordinator)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(book: book)
        }
    }

    // MARK: - Header

    /// Cover + title + author + tag chips, centered.
    private var header: some View {
        VStack(spacing: 16) {
            cover
            VStack(spacing: 6) {
                Text(viewModel.title)
                    .font(Font(ReaderTypography.body(for: .sourceSerif4, size: 22)))
                    .fontWeight(.semibold)
                    .italic()
                    .foregroundStyle(Color(theme.inkColor))
                    .multilineTextAlignment(.center)
                Text(viewModel.author)
                    .font(.system(size: 13))
                    .foregroundStyle(Color(theme.subColor))
                    .lineLimit(1)
            }
            if !viewModel.tags.isEmpty {
                tagRow
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// The 120×180 cover with the cover-swap affordance. Reads
    /// `coverVersion` so a successful swap re-renders the artwork.
    private var cover: some View {
        _ = coverPickCoordinator.coverVersion
        return BookCoverArtView(
            image: CustomCoverStore.loadCover(for: book.fingerprintKey),
            fingerprintKey: book.fingerprintKey,
            title: book.title,
            author: book.author,
            cornerRadius: 4
        )
        .frame(width: 120, height: 180)
        .overlay(alignment: .bottomTrailing) { coverSwapButton }
    }

    /// The accent pencil disc — design `CoverWithSwap`. Starts the
    /// shared cover-replace PhotosPicker flow.
    private var coverSwapButton: some View {
        Button { coverPickCoordinator.present(for: book) } label: {
            Image(systemName: "pencil")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color(theme.accentColor)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .padding(6)
        .accessibilityLabel(viewModel.hasCover ? "Replace cover" : "Add cover")
        .accessibilityIdentifier("bookDetailsCoverSwap")
    }

    /// The title-bar Share button — design `Sheet`'s `trailing` slot.
    /// Presents the system share sheet for the book file. The design's
    /// `Sheet` shows this in place of the default close button, so the
    /// sheet dismisses via swipe-down.
    private var shareButton: some View {
        Button { showShareSheet = true } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Color(theme.inkColor))
                .frame(width: 28, height: 28)
                .background(
                    Circle().fill(theme.isDark
                        ? Color.white.opacity(0.08)
                        : Color.black.opacity(0.06))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Share book")
        .accessibilityIdentifier("bookDetailsShareButton")
    }

    /// Centered, wrapping collection-tag chips.
    private var tagRow: some View {
        BookDetailsTagFlow(spacing: 6, lineSpacing: 6) {
            ForEach(viewModel.tags, id: \.self) { tag in
                Text(tag)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(theme.inkColor))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(theme.isDark
                            ? Color.white.opacity(0.06)
                            : Color.black.opacity(0.05))
                    )
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Cards

    /// The Metadata card body — rows separated by hairline dividers.
    private var metadataCard: some View {
        let rows = metadataRows
        return ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            BookDetailsMetadataRow(model: row, theme: theme, onAccessory: {
                if let accessory = row.accessory { handleAccessory(accessory) }
            })
            if index < rows.count - 1 {
                rowDivider
            }
        }
    }

    /// The Actions card body — rows separated by hairline dividers.
    private var actionCard: some View {
        let rows = actionRows
        return ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
            BookDetailsActionRow(model: row, theme: theme, onTap: {
                handleAction(row.kind)
            })
            if index < rows.count - 1 {
                rowDivider
            }
        }
    }

    // MARK: - Section scaffolding

    /// A labelled section: an uppercase tracked label above a rounded
    /// card. Mirrors the design's `SectionLabel` + 14pt-radius card.
    private func section(
        label: String, @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(Color(theme.subColor))
            VStack(spacing: 0) { content() }
                .background(cardBackground)
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Hairline row divider — design's `0.5px solid t.rule` borderBottom.
    private var rowDivider: some View {
        Color(theme.ruleColor).frame(height: 0.5)
    }

    /// Card surface fill — design `t.isDark ? rgba(255,255,255,0.04) : #fff`.
    private var cardBackground: Color {
        theme.isDark ? Color.white.opacity(0.04) : Color.white
    }
}
#endif
