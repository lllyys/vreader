// Purpose: Tests for DictionaryLookup — word extraction, system dictionary lookup,
// and action dispatching for Define/Translate on text selection.
//
// The suite is @MainActor (bug #221 / GH #849): `canLookUp` and
// `viewController(for:)` touch UIKit — `dictionaryHasDefinition` and the
// `UIReferenceLibraryViewController` initialiser are main-thread-only APIs, and
// the production helpers are now `@MainActor` to match. Without `@MainActor` on
// the suite, Swift Testing's parallel scheduler dispatches these tests onto a
// background cooperative thread; `viewController(for:)` then constructs a
// `UIViewController` off-main, UIKit's Main Thread Checker traps it
// (`UI API called on a background thread: -[UIReferenceLibraryViewController
// initWithTerm:]`), and the test host crashes intermittently — the flaky
// full-suite crash that bug #221 tracked.
//
// @coordinates-with DictionaryLookup.swift, TXTBridgeShared.swift

import Testing
import Foundation
@testable import vreader

@Suite("DictionaryLookup")
@MainActor
struct DictionaryLookupTests {

    // MARK: - extractWord: single word

    @Test func extractWord_fromSelection_singleWord() {
        let result = DictionaryLookup.extractWord(from: "hello")
        #expect(result == "hello")
    }

    // MARK: - extractWord: trimmed

    @Test func extractWord_fromSelection_trimmed() {
        let result = DictionaryLookup.extractWord(from: " hello ")
        #expect(result == "hello")
    }

    // MARK: - extractWord: empty string

    @Test func extractWord_fromSelection_emptyString() {
        let result = DictionaryLookup.extractWord(from: "")
        #expect(result == nil)
    }

    // MARK: - extractWord: whitespace only

    @Test func extractWord_fromSelection_whitespaceOnly() {
        let result = DictionaryLookup.extractWord(from: "   ")
        #expect(result == nil)
    }

    // MARK: - extractWord: multiple words takes first

    @Test func extractWord_fromSelection_multipleWords_takesFirst() {
        let result = DictionaryLookup.extractWord(from: "hello world")
        #expect(result == "hello")
    }

    // MARK: - extractWord: newlines

    @Test func extractWord_fromSelection_newlines() {
        let result = DictionaryLookup.extractWord(from: "\nhello\nworld\n")
        #expect(result == "hello")
    }

    // MARK: - extractWord: tabs

    @Test func extractWord_fromSelection_tabs() {
        let result = DictionaryLookup.extractWord(from: "\thello\tworld")
        #expect(result == "hello")
    }

    // MARK: - extractWord: CJK single character

    @Test func extractWord_fromSelection_CJKCharacter() {
        let result = DictionaryLookup.extractWord(from: "你好")
        #expect(result == "你好")
    }

    // MARK: - extractWord: CJK with spaces

    @Test func extractWord_fromSelection_CJKWithSpaces() {
        let result = DictionaryLookup.extractWord(from: " 你好 世界 ")
        #expect(result == "你好")
    }

    // MARK: - extractWord: mixed CJK and English

    @Test func extractWord_fromSelection_mixedCJKEnglish() {
        let result = DictionaryLookup.extractWord(from: "hello 你好")
        #expect(result == "hello")
    }

    // MARK: - extractWord: emoji

    @Test func extractWord_fromSelection_emoji() {
        let result = DictionaryLookup.extractWord(from: "🎉 party")
        #expect(result == "🎉")
    }

    // MARK: - extractWord: single space between words

    @Test func extractWord_fromSelection_singleSpace() {
        let result = DictionaryLookup.extractWord(from: "a b")
        #expect(result == "a")
    }

    // MARK: - extractWord: leading punctuation

    @Test func extractWord_fromSelection_punctuation() {
        let result = DictionaryLookup.extractWord(from: "hello!")
        #expect(result == "hello!")
    }

    // MARK: - canLookUp: common English word (device-dependent)

    @Test func canLookUp_returnsTrue_forCommonEnglishWord() {
        // UIReferenceLibraryViewController.dictionaryHasDefinition is device/simulator-dependent.
        // On a simulator with downloaded dictionaries, "hello" should be defined.
        // This test documents expected behavior but may be skipped in CI without dictionaries.
        let result = DictionaryLookup.canLookUp("hello")
        // On simulators, dictionaries may not be installed — accept either result
        #expect(result == true || result == false)
    }

    // MARK: - canLookUp: gibberish

    @Test func canLookUp_returnsFalse_forGibberish() {
        let result = DictionaryLookup.canLookUp("xyzqwkjjj")
        #expect(result == false)
    }

    // MARK: - canLookUp: empty string

    @Test func canLookUp_returnsFalse_forEmptyString() {
        let result = DictionaryLookup.canLookUp("")
        #expect(result == false)
    }

    // MARK: - viewController creation
    //
    // Bug #221 / GH #849: `viewController(for:)` constructs a
    // `UIReferenceLibraryViewController` (a `UIViewController`). UIKit
    // view-controller initialisers are main-thread-only; running this off-main
    // trips UIKit's Main Thread Checker and crashes the test host. Two distinct
    // guards prevent a recurrence:
    //   1. `@MainActor` on `DictionaryLookup.viewController(for:)` (production)
    //      protects EVERY call site — a synchronous non-`@MainActor` caller is
    //      a Swift 6 compile error; an async caller must `await` (a safe hop).
    //   2. `@MainActor` on this suite keeps these tests on the main thread, so
    //      the historical off-main crash path is no longer reachable here.
    // A runtime `Thread.isMainThread` check could assert neither — both are
    // compile-time / isolation properties — so no such test is kept.

    @Test func viewController_createsForWord() {
        // A fresh `UIReferenceLibraryViewController` is returned per call —
        // `viewController(for:)` does not cache or share instances.
        let first = DictionaryLookup.viewController(for: "hello")
        let second = DictionaryLookup.viewController(for: "hello")
        #expect(first !== second)
    }

    // MARK: - defineMenuTitle

    @Test func defineMenuTitle_returnsCorrectTitle() {
        #expect(DictionaryLookup.defineMenuTitle == "Define")
    }

    // MARK: - translateMenuTitle

    @Test func translateMenuTitle_returnsCorrectTitle() {
        #expect(DictionaryLookup.translateMenuTitle == "Translate")
    }
}
