// Purpose: Tests for TestLaunchConfig.parse — new launch args added for the
// verification harness (feature #45 WI-4c) and existing seed/feature flags.
// The new --reader-default-layout=<value> arg lets XCUITest seed the EPUB
// layout default without driving the SwiftUI segmented Picker (which doesn't
// transition state under XCUITest as of iOS 26.5).

import Testing
import Foundation
@testable import vreader

#if DEBUG

@Suite("TestLaunchConfig parsing")
struct LaunchArgParsingTests {

    @Test func defaultEPUBLayoutIsNilWithoutFlag() {
        let config = TestLaunchConfig.parse(["--uitesting"])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func parsesPagedLayout() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=paged"
        ])
        #expect(config.defaultEPUBLayout == .paged)
    }

    @Test func parsesScrollLayout() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=scroll"
        ])
        #expect(config.defaultEPUBLayout == .scroll)
    }

    @Test func invalidLayoutValueFallsThroughToNil() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout=garbage"
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func emptyLayoutValueFallsThroughToNil() {
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout="
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func bareFlagWithoutEqualsValueFallsThroughToNil() {
        // `--reader-default-layout` without an `=value` suffix is not a match —
        // the parser only recognises the `<arg>=<rawValue>` form.
        let config = TestLaunchConfig.parse([
            "--uitesting", "--reader-default-layout"
        ])
        #expect(config.defaultEPUBLayout == nil)
    }

    @Test func laterLayoutFlagWinsOverEarlier() {
        // If the test harness or CI script accidentally passes the flag twice,
        // the LAST occurrence wins — matches the user's mental model of
        // command-line overrides.
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--reader-default-layout=scroll",
            "--reader-default-layout=paged"
        ])
        #expect(config.defaultEPUBLayout == .paged)
    }

    @Test func layoutFlagCoexistsWithOtherSeedFlags() {
        let config = TestLaunchConfig.parse([
            "--uitesting",
            "--seed-md-toc",
            "--reset-preferences",
            "--reader-default-layout=paged"
        ])
        #expect(config.isUITesting == true)
        #expect(config.seedMDTOC == true)
        #expect(config.seedResetPreferences == true)
        #expect(config.defaultEPUBLayout == .paged)
    }
}

#endif
