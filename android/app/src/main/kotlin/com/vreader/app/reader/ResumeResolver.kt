// Purpose: Resolve a saved VReaderLocator envelope to a concrete restore target —
// feature #106 WI-6 (Gate-2 Critical resume). Encodes the cross-platform resume rule
// (contracts/identity/locator.md): try the PRECISE anchor first (Readium's own
// locator JSON), fall back to the CANONICAL legacy locator (progression + text-quote)
// so a position is restorable to at least progression precision even when the precise
// anchor doesn't round-trip. Pure function — the (#1745 design-blocked) reader host
// applies the target to the Readium navigator.
package com.vreader.app.reader

import vreader.contracts.Locator
import vreader.contracts.ReaderLocatorEngine
import vreader.contracts.VReaderLocator

/** Where to restore a reader to, resolved from a saved [VReaderLocator]. */
sealed interface ResumeTarget {
    /**
     * Feed [readiumLocatorJSON] to the navigator for an exact restore — and if that
     * anchor can't be reapplied on this device/Readium version, degrade to
     * [canonicalFallback] (progression/quote). The precise-FIRST-then-canonical rule
     * lives in this one target so the host never loses the fallback (Gate-4 High).
     */
    data class Precise(val readiumLocatorJSON: String, val canonicalFallback: Locator?) : ResumeTarget

    /** No precise anchor — approximate via the canonical [Locator] (progression/quote). */
    data class Canonical(val locator: Locator) : ResumeTarget

    /** No saved position — open at the beginning. */
    data object None : ResumeTarget
}

object ResumeResolver {
    /**
     * Precise-first / canonical-fallback. A `readium`-engine envelope with a non-blank
     * `readiumLocatorJSON` restores precisely, carrying its `legacyLocator` as the
     * degrade target; otherwise the canonical `legacyLocator` (progression + text-quote)
     * drives a degraded restore; a null envelope or one carrying neither anchor opens
     * at the start.
     */
    fun resolve(envelope: VReaderLocator?): ResumeTarget {
        if (envelope == null) return ResumeTarget.None
        val readium = envelope.readiumLocatorJSON
        if (envelope.engine == ReaderLocatorEngine.readium && !readium.isNullOrBlank()) {
            return ResumeTarget.Precise(readium, envelope.legacyLocator)
        }
        envelope.legacyLocator?.let { return ResumeTarget.Canonical(it) }
        return ResumeTarget.None
    }
}
