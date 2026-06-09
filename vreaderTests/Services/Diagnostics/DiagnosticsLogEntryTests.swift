// Purpose: Feature #96 WI-1 — DiagnosticsLevel mirrors OSLogEntryLog.Level. Pins
// the mapping (and the documented absence of a recoverable `warning` level).

import Testing
import OSLog
@testable import vreader

@Suite("DiagnosticsLevel")
struct DiagnosticsLogEntryTests {

    @Test(arguments: [
        (OSLogEntryLog.Level.undefined, DiagnosticsLevel.undefined),
        (.debug,  .debug),
        (.info,   .info),
        (.notice, .notice),
        (.error,  .error),
        (.fault,  .fault),
    ])
    func mapsOSLevelToMirror(_ os: OSLogEntryLog.Level, _ expected: DiagnosticsLevel) {
        #expect(DiagnosticsLevel(os) == expected)
    }

    // There is no `warning` case — `Logger.warning()` reads back as `.error`.
    @Test func hasNoWarningCase() {
        #expect(!DiagnosticsLevel.allCases.contains { $0.rawValue == "warning" })
        #expect(DiagnosticsLevel.allCases.count == 6)
    }

    @Test func exportTagIsUppercased() {
        #expect(DiagnosticsLevel.error.exportTag == "ERROR")
        #expect(DiagnosticsLevel.fault.exportTag == "FAULT")
    }
}
