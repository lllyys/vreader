// Purpose: Tests for AnnotationListViewModel — load, add, remove, edit, edge cases.
//
// @coordinates-with: AnnotationListViewModel.swift, MockAnnotationStore.swift

import Testing
import Foundation
@testable import vreader

// MARK: - Loading

@Suite("AnnotationListViewModel - Loading")
@MainActor
struct AnnotationListViewModelLoadingTests {

    @Test("loads annotations for a book")
    func loadAnnotationsPopulatesList() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeAnnotationRecord(content: "My note")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        #expect(vm.annotations.count == 1)
        #expect(vm.annotations.first?.content == "My note")
    }

    @Test("empty list shows empty state")
    func emptyAnnotationList() async {
        let store = MockAnnotationStore()
        let vm = AnnotationListViewModel(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            store: store
        )
        await vm.loadAnnotations()

        #expect(vm.annotations.isEmpty)
        #expect(vm.isEmpty)
    }

    @Test("load error sets error message")
    func loadErrorSetsMessage() async {
        let store = MockAnnotationStore()
        await store.setFetchError(WI9TestError.mockFailure)

        let vm = AnnotationListViewModel(
            bookFingerprintKey: wi9EPUBFingerprint.canonicalKey,
            store: store
        )
        await vm.loadAnnotations()

        #expect(vm.annotations.isEmpty)
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Add / Remove

@Suite("AnnotationListViewModel - Add/Remove")
@MainActor
struct AnnotationListViewModelMutationTests {

    @Test("add annotation appends to list")
    func addAnnotation() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let locator = makeEPUBLocator()

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addAnnotation(locator: locator, content: "New annotation")

        #expect(vm.annotations.count == 1)
        #expect(vm.annotations.first?.content == "New annotation")
    }

    @Test("remove annotation removes from list")
    func removeAnnotation() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeAnnotationRecord(content: "To Delete")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()
        #expect(vm.annotations.count == 1)

        await vm.removeAnnotation(annotationId: record.annotationId)

        #expect(vm.annotations.isEmpty)
    }

    @Test("remove nonexistent annotation is no-op")
    func removeNonexistentAnnotation() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        await store.seed(makeAnnotationRecord(), forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        await vm.removeAnnotation(annotationId: UUID())

        #expect(vm.annotations.count == 1)
    }
}

// MARK: - Edit

@Suite("AnnotationListViewModel - Edit")
@MainActor
struct AnnotationListViewModelEditTests {

    @Test("update annotation content")
    func updateContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeAnnotationRecord(content: "Original")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        await vm.updateAnnotation(annotationId: record.annotationId, content: "Updated")

        #expect(vm.annotations.first?.content == "Updated")
    }

    @Test("update with empty content is rejected")
    func updateEmptyContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeAnnotationRecord(content: "Original")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        await vm.updateAnnotation(annotationId: record.annotationId, content: "")

        // Empty content should be rejected; original content preserved
        #expect(vm.annotations.first?.content == "Original")
        #expect(vm.errorMessage != nil)
    }

    @Test("update with whitespace-only content is rejected")
    func updateWhitespaceContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let record = makeAnnotationRecord(content: "Original")
        await store.seed(record, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        await vm.updateAnnotation(annotationId: record.annotationId, content: "   \n  ")

        #expect(vm.annotations.first?.content == "Original")
        #expect(vm.errorMessage != nil)
    }
}

// MARK: - Edge Cases

@Suite("AnnotationListViewModel - Edge Cases")
@MainActor
struct AnnotationListViewModelEdgeCaseTests {

    @Test("add annotation error surfaces error message")
    func addAnnotationError() async {
        let store = MockAnnotationStore()
        await store.setAddError(WI9TestError.mockFailure)
        let bookKey = wi9EPUBFingerprint.canonicalKey

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addAnnotation(locator: makeEPUBLocator(), content: "Fails")

        #expect(vm.annotations.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("add annotation with empty content is rejected")
    func addEmptyContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addAnnotation(locator: makeEPUBLocator(), content: "")

        #expect(vm.annotations.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("add annotation with whitespace-only content is rejected")
    func addWhitespaceContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addAnnotation(locator: makeEPUBLocator(), content: "   \t\n  ")

        #expect(vm.annotations.isEmpty)
        #expect(vm.errorMessage != nil)
    }

    @Test("annotation with Unicode/CJK content")
    func unicodeContent() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.addAnnotation(
            locator: makeEPUBLocator(),
            content: "这是一个注释 📝 テスト"
        )

        #expect(vm.annotations.count == 1)
        #expect(vm.annotations.first?.content == "这是一个注释 📝 テスト")
    }

    @Test("multiple annotations ordered newest first")
    func newestFirstOrder() async {
        let store = MockAnnotationStore()
        let bookKey = wi9EPUBFingerprint.canonicalKey
        let now = Date()

        let older = makeAnnotationRecord(content: "Older", createdAt: now.addingTimeInterval(-100))
        let newer = makeAnnotationRecord(content: "Newer", createdAt: now)
        await store.seed(older, forBookWithKey: bookKey)
        await store.seed(newer, forBookWithKey: bookKey)

        let vm = AnnotationListViewModel(bookFingerprintKey: bookKey, store: store)
        await vm.loadAnnotations()

        #expect(vm.annotations.count == 2)
        #expect(vm.annotations.first?.content == "Newer")
    }
}
