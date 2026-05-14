// Purpose: Tests for AIEditorContext — the Identifiable wrapper that
// drives `.sheet(item:)` in AIProviderListView. Bug #174 fix: the prior
// `.sheet(isPresented:)` + separate `editingProfile` pair could race on
// rapid swap of edit targets; this wrapper makes the presentation state
// atomic. Tests verify the Identifiable id discriminates add-vs-edit
// and distinguishes individual profiles so SwiftUI's sheet-item diffing
// re-creates the sheet body on target change.

import Testing
import Foundation
@testable import vreader

@Suite("AIEditorContext")
struct AIEditorContextTests {

    // MARK: - Helpers

    private func makeProfile(id: UUID = UUID(), name: String = "Test") -> ProviderProfile {
        ProviderProfile(
            id: id,
            name: name,
            kind: .openAICompatible,
            baseURL: URL(string: "https://example.com/v1")!,
            model: "gpt-4o-mini",
            temperature: 0.7,
            maxTokens: 1024
        )
    }

    // MARK: - id behavior

    @Test func addContextHasStableNewID() {
        let a = AIEditorContext.add()
        let b = AIEditorContext.add()
        #expect(a.id == "new")
        #expect(b.id == "new")
        // Two add-contexts share the same id, which is correct for
        // .sheet(item:) — opening Add twice is the same logical state.
        #expect(a.id == b.id)
    }

    @Test func editContextIDMatchesProfileUUID() {
        let id = UUID()
        let profile = makeProfile(id: id)
        let context = AIEditorContext.edit(profile)
        #expect(context.id == id.uuidString)
    }

    @Test func editContextsForDifferentProfilesHaveDifferentIDs() {
        let p1 = makeProfile(id: UUID())
        let p2 = makeProfile(id: UUID())
        let c1 = AIEditorContext.edit(p1)
        let c2 = AIEditorContext.edit(p2)
        #expect(c1.id != c2.id, "Different profiles must produce different sheet ids so SwiftUI recreates the sheet body on swap (the bug #174 race fix).")
    }

    @Test func addAndEditHaveDistinctIDs() {
        let profile = makeProfile()
        let add = AIEditorContext.add()
        let edit = AIEditorContext.edit(profile)
        #expect(add.id != edit.id, "Add and edit contexts must be distinguishable by id so SwiftUI can switch between them without reusing the prior sheet body.")
    }

    // MARK: - profile payload

    @Test func addContextHasNilProfile() {
        let context = AIEditorContext.add()
        #expect(context.profile == nil)
    }

    @Test func editContextCarriesProfileByValue() {
        let profile = makeProfile(name: "OriginalName")
        let context = AIEditorContext.edit(profile)
        #expect(context.profile?.id == profile.id)
        #expect(context.profile?.name == "OriginalName")
    }

    @Test func editContextSnapshotsProfileAtCreation() {
        // ProviderProfile is a value type; mutating the original after
        // wrapping must not affect the context's payload. Important for
        // bug #174: if the user starts editing, then the underlying list
        // reloads with a renamed profile, the open sheet still shows the
        // form state from when it was opened.
        var profile = makeProfile(name: "Before")
        let context = AIEditorContext.edit(profile)
        profile.name = "After"
        #expect(context.profile?.name == "Before")
    }

    // MARK: - Equatable

    @Test func equatable_sameProfileEditsAreEqual() {
        let profile = makeProfile()
        let a = AIEditorContext.edit(profile)
        let b = AIEditorContext.edit(profile)
        #expect(a == b)
    }

    @Test func equatable_addContextsAreEqual() {
        let a = AIEditorContext.add()
        let b = AIEditorContext.add()
        #expect(a == b)
    }

    @Test func equatable_addAndEditAreNotEqual() {
        let a = AIEditorContext.add()
        let b = AIEditorContext.edit(makeProfile())
        #expect(a != b)
    }

    @Test func equatable_differentProfilesAreNotEqual() {
        let a = AIEditorContext.edit(makeProfile(id: UUID()))
        let b = AIEditorContext.edit(makeProfile(id: UUID()))
        #expect(a != b)
    }
}
