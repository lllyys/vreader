// Purpose: Shared test-only DebugReaderProbe stub for the bug #141 settle
// test suites (DebugReaderRegistrySettle{Core,Cleanup,EdgeCase}Tests). The
// settle suites were split out of one 443-line file for the <300-line
// convention; this stub is the single shared dependency they all need.
//
// DEBUG-only — DebugReaderProbe and the settle machinery are #if DEBUG.

#if DEBUG

import Foundation
@testable import vreader

/// Minimal `DebugReaderProbe` conformer used by the settle suites for the
/// `register` / `unregister` lifecycle cases. Behaviour-free: the settle
/// signal under test lives entirely in `DebugReaderRegistry`, not the probe.
@MainActor
final class SettleStubProbe: DebugReaderProbe {
    let fingerprintKey: String
    let format: String
    var currentPositionString: String? = nil

    init(key: String, fmt: String) {
        self.fingerprintKey = key
        self.format = fmt
    }

    func awaitSettle(timeout: TimeInterval) async throws {}
    func evaluateJavaScript(_ script: String) async throws -> Data {
        throw DebugReaderProbeError.evalUnsupported(format: format)
    }
}

#endif
