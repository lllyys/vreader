// Purpose: Tests that TXTReaderContainerView's attr-string rebuild key
// includes chineseConversion so setting changes trigger a rebuild
// (feature #28 WI-A — TXT native-mode Chinese conversion).
//
// Tests the static `makeAttrStringKey(...)` helper extracted for testability.
//
// @coordinates-with: vreader/Views/Reader/TXTReaderContainerView.swift,
// vreader/Services/ReaderSettingsStore.swift

import Testing
import Foundation
@testable import vreader

@Suite("TXTReaderContainerView Chinese conversion attrStringKey (feature #28 WI-A)")
struct TXTReaderContainerViewChineseConversionTests {

    private func baseKey(_ conversion: ChineseConversionDirection) -> String {
        TXTReaderContainerView.makeAttrStringKey(
            hasText: true,
            textLen: 1000,
            wordCount: 200,
            chIdx: 0,
            chCount: 0,
            config: TXTViewConfig(),
            chineseConversion: conversion
        )
    }

    @Test func key_differsOnConversionChange() {
        #expect(
            baseKey(.none) != baseKey(.simpToTrad),
            "attrStringKey must differ when chineseConversion changes from .none to .simpToTrad"
        )
    }

    @Test func key_differsOnDirectionChange() {
        #expect(
            baseKey(.simpToTrad) != baseKey(.tradToSimp),
            "attrStringKey must differ between .simpToTrad and .tradToSimp"
        )
    }

    @Test func key_stableForSameConversion() {
        #expect(
            baseKey(.simpToTrad) == baseKey(.simpToTrad),
            "attrStringKey must be deterministic for same conversion"
        )
    }

    @Test func key_noneMatchesNone() {
        #expect(
            baseKey(.none) == baseKey(.none),
            "attrStringKey(.none) must be stable"
        )
    }
}
