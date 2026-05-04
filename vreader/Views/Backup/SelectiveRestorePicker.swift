// Purpose: Picker view for the selective-restore flow (#47 WI-6).
// Lists every book in the backup's manifest and lets the user tick
// the subset to materialize immediately. Unticked entries land as
// `.remoteOnly` rows the lazy-download coordinator (#47 WI-3) fetches
// on later tap.
//
// @coordinates-with: BackupViewModel.swift,
//   SelectiveRestoreCoordinator.swift,
//   WebDAVProvider.restoreSelectively (v3.11.29),
//   dev-docs/plans/20260503-feature-47-selective-picker-lazy-load.md

import SwiftUI

struct SelectiveRestorePicker: View {
    let backup: BackupMetadata
    let viewModel: BackupViewModel
    let persistence: PersistenceActor
    let dismiss: () -> Void

    @State private var selectedKeys: Set<String> = []
    @State private var hasLoaded = false

    var body: some View {
        Group {
            if viewModel.isLoadingManifest {
                ProgressView("Loading manifest…")
                    .padding()
            } else if let manifest = viewModel.loadedManifest {
                manifestList(manifest: manifest)
            } else if let message = viewModel.errorMessage {
                ContentUnavailableView(
                    "Cannot load picker",
                    systemImage: "exclamationmark.icloud",
                    description: Text(message)
                )
            } else {
                ContentUnavailableView(
                    "No manifest",
                    systemImage: "questionmark.folder",
                    description: Text("This backup doesn't carry a recoverable book list.")
                )
            }
        }
        .navigationTitle("Restore Selectively")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Restore (\(selectedKeys.count))") {
                    Task {
                        await viewModel.performSelectiveRestore(
                            backupId: backup.id,
                            selectedKeys: selectedKeys,
                            persistence: persistence
                        )
                        dismiss()
                    }
                }
                .disabled(viewModel.isRestoringSelectively || !hasLoaded)
            }
        }
        .task {
            if !hasLoaded {
                await viewModel.loadManifest(for: backup.id)
                hasLoaded = true
            }
        }
        .overlay {
            if viewModel.isRestoringSelectively {
                restoreOverlay
            }
        }
    }

    private func manifestList(manifest: [BackupLibraryEntry]) -> some View {
        List {
            Section {
                HStack {
                    Button("Select All") {
                        selectedKeys = Set(manifest.map(\.fingerprintKey))
                    }
                    Spacer()
                    Button("Clear") {
                        selectedKeys = []
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            Section {
                ForEach(manifest, id: \.fingerprintKey) { entry in
                    row(entry: entry)
                }
            } header: {
                Text("\(manifest.count) books in backup · ticked = download now, unticked = lazy-load on tap")
                    .font(.caption)
            }
        }
    }

    private func row(entry: BackupLibraryEntry) -> some View {
        let isOn = Binding<Bool>(
            get: { selectedKeys.contains(entry.fingerprintKey) },
            set: { newValue in
                if newValue {
                    selectedKeys.insert(entry.fingerprintKey)
                } else {
                    selectedKeys.remove(entry.fingerprintKey)
                }
            }
        )
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title ?? "Untitled")
                    .font(.body)
                    .lineLimit(1)
                if let author = entry.author {
                    Text(author)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(entry.format.uppercased()) · \(byteCountFormatter.string(fromByteCount: entry.byteCount))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private var restoreOverlay: some View {
        ZStack {
            Color.black.opacity(0.3).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView(value: viewModel.restoreProgress)
                    .frame(width: 220)
                Text("Restoring \(selectedKeys.count) book(s) and \((viewModel.loadedManifest?.count ?? 0) - selectedKeys.count) row(s) marked for later…")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .padding(20)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useKB, .useMB]
        f.countStyle = .file
        return f
    }
}
