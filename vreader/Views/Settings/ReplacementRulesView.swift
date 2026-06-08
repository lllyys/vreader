// Purpose: Settings UI for managing content replacement rules.
// List view with add/edit/delete, enable/disable toggles.
//
// Key decisions:
// - Uses SwiftData @Query for live updates.
// - Drag-to-reorder via .onMove modifier.
// - Inline toggle for enable/disable.
// - Sheet for add/edit form.
//
// @coordinates-with: ContentReplacementRule.swift, ReplacementTransform.swift

import SwiftUI
import SwiftData

struct ReplacementRulesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ContentReplacementRule.order) private var rules: [ContentReplacementRule]
    @State private var showingAddSheet = false
    @State private var editingRule: ContentReplacementRule?

    /// Bug #231 / GH #957 (post-feature-#54 rewrite). Feature #54 (WI-4)
    /// removed the Native/Unified Reading Mode picker entirely, and (WI-7)
    /// wired content replacement rules into the native Markdown reader via
    /// `MDFileLoader`'s transform chain. The previous banner ("Switch from
    /// the reader's Settings → Reading Mode") pointed users at a deleted
    /// control and its "only when reading in Unified mode" premise was
    /// stale for MD. The rewritten copy states the post-#54 reality: rules
    /// apply automatically when reading Markdown and EPUB today (feature #54
    /// Phase D-1 wired EPUB via `EPUBReplacementJS` on both the Readium and the
    /// legacy WKWebView engines); AZW3 / TXT support is pending; PDF is not
    /// supported. Pinned as a static constant so
    /// `ReplacementRulesViewBannerTests` can regression-guard the copy
    /// without inspecting the view tree. Update the test in lockstep with
    /// any copy change.
    static let nativeModeBannerText =
        "Rules apply automatically when reading Markdown and EPUB files. Support for AZW3 and TXT is coming in a later update; PDF is not supported."

    var body: some View {
        List {
            // Bug #128 (original) + bug #231 (post-#54 rewrite): surface
            // where replacement rules apply so users don't silently
            // configure rules that won't take effect. Post-feature-#54,
            // native Markdown applies rules automatically (WI-7 wired
            // `MDFileLoader` through `ReplacementTransform`); EPUB / AZW3 /
            // TXT support is pending Phase D / feature #42; PDF is not
            // supported.
            Section {
                Label {
                    Text(Self.nativeModeBannerText)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                }
            }

            if rules.isEmpty {
                ContentUnavailableView(
                    "No Replacement Rules",
                    systemImage: "text.magnifyingglass",
                    description: Text("Add rules to fix OCR errors or customize display text.")
                )
            } else {
                ForEach(rules) { rule in
                    ReplacementRuleRow(rule: rule)
                        .onTapGesture { editingRule = rule }
                }
                .onDelete(perform: deleteRules)
                .onMove(perform: moveRules)
            }
        }
        .navigationTitle("Replacement Rules")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("replacementRulesAddButton")
            }
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
        .sheet(isPresented: $showingAddSheet) {
            ReplacementRuleEditSheet(rule: nil) { newRule in
                modelContext.insert(newRule)
            }
        }
        .sheet(item: $editingRule) { rule in
            ReplacementRuleEditSheet(rule: rule) { _ in
                // Updates happen in-place via SwiftData
            }
        }
    }

    private func deleteRules(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(rules[index])
        }
    }

    private func moveRules(from source: IndexSet, to destination: Int) {
        var mutableRules = rules
        mutableRules.move(fromOffsets: source, toOffset: destination)
        for (index, rule) in mutableRules.enumerated() {
            rule.order = index
        }
    }
}

// MARK: - Row View

private struct ReplacementRuleRow: View {
    @Bindable var rule: ContentReplacementRule

    var body: some View {
        HStack {
            Toggle("", isOn: $rule.enabled)
                .labelsHidden()
                .toggleStyle(.switch)

            VStack(alignment: .leading, spacing: 2) {
                Text(rule.label.isEmpty ? rule.pattern : rule.label)
                    .font(.body)
                    .lineLimit(1)

                HStack(spacing: 4) {
                    if rule.isRegex {
                        Text("regex")
                            .font(.caption2)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15))
                            .cornerRadius(3)
                    }
                    Text("\"\(rule.pattern)\" → \"\(rule.replacement)\"")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if rule.isGlobal {
                Text("Global")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Edit Sheet

private struct ReplacementRuleEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let rule: ContentReplacementRule?
    let onSave: (ContentReplacementRule) -> Void

    @State private var pattern: String
    @State private var replacement: String
    @State private var isRegex: Bool
    @State private var label: String
    @State private var scopeKey: String
    @State private var enabled: Bool

    init(rule: ContentReplacementRule?, onSave: @escaping (ContentReplacementRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _pattern = State(initialValue: rule?.pattern ?? "")
        _replacement = State(initialValue: rule?.replacement ?? "")
        _isRegex = State(initialValue: rule?.isRegex ?? false)
        _label = State(initialValue: rule?.label ?? "")
        _scopeKey = State(initialValue: rule?.scopeKey ?? "")
        _enabled = State(initialValue: rule?.enabled ?? true)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Pattern") {
                    TextField("Search pattern", text: $pattern)
                        .font(.system(.body, design: .monospaced))
                    Toggle("Regular Expression", isOn: $isRegex)
                }

                Section("Replacement") {
                    TextField("Replace with", text: $replacement)
                        .font(.system(.body, design: .monospaced))
                }

                Section("Options") {
                    TextField("Label (optional)", text: $label)
                    Toggle("Enabled", isOn: $enabled)
                }
            }
            .navigationTitle(rule == nil ? "Add Rule" : "Edit Rule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(pattern.isEmpty)
                }
            }
        }
    }

    private func save() {
        if let existing = rule {
            existing.pattern = pattern
            existing.replacement = replacement
            existing.isRegex = isRegex
            existing.label = label
            existing.scopeKey = scopeKey
            existing.enabled = enabled
        } else {
            let newRule = ContentReplacementRule(
                pattern: pattern,
                replacement: replacement,
                isRegex: isRegex,
                scopeKey: scopeKey,
                enabled: enabled,
                label: label
            )
            onSave(newRule)
        }
    }
}
