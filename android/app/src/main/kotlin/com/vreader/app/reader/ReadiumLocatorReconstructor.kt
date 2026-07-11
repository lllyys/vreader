// Purpose: Reconstruct a real Readium `Locator` from a vreader canonical `Locator`
// (feature #135 WI-1, EPUB bookmark jump). A persisted bookmark carries ONLY the
// engine-neutral canonical `Locator` (via `BookmarkRecord.toEntity()`), NOT a precise
// Readium JSON, so jumping to it after reopen / backup-restore needs a canonical ->
// Readium reconstruction. This is kept OUT of the pure-JVM, forward-only
// `ReadiumLocatorBridge` (which stays Readium-free by design); the object->locator
// reconstruction lives here, where Readium types already live.
//
// The faithful in-codebase reconstruction seam (mirrors `ReadiumTocProvider` /
// `ReaderActivity.scrubTo`), gated by an identity check first (a canonical locator
// whose `fingerprintKey` != this book's is rejected BEFORE the publication is touched,
// so a locator for a different book can't resolve a coincidentally-matching href):
//   canonical.fingerprintKey == expectedFingerprintKey   // else -> null (identity gate)
//   Url(canonical.href)?                    // NULLABLE - malformed href -> null
//     -> publication.linkWithHref(Url)      // NULLABLE - unresolvable/renamed -> null
//     -> publication.locatorFromLink(Link)  // NULLABLE - un-locatable -> null;
//                                           //   supplies the resolved href + a
//                                           //   NON-null MediaType for free (a manual
//                                           //   Locator.Locations build would leave
//                                           //   MediaType unspecified)
//     -> .copyWithLocations(progression = canonical.progression,
//                           fragments = cfi?)
//     -> (+ .copy(text = Locator.Text(before, highlight, after)) when a text-quote is present).
//
// @coordinates-with reader/nav/ReadiumTocProvider.kt (the same extracted-seam pattern,
//   because Publication is a `final`, unmockable class), reader/ReadiumLocatorBridge.kt
//   (the forward path this deliberately does NOT extend), reader/ResumeResolver.kt
//   (the same progression-precision-as-floor canonical-fallback posture).
package com.vreader.app.reader

import org.readium.r2.shared.publication.Link
import org.readium.r2.shared.publication.Locator as ReadiumLocator
import org.readium.r2.shared.publication.Publication
import org.readium.r2.shared.util.Url
import vreader.contracts.Locator

/**
 * The two Readium [Publication] operations [ReadiumLocatorReconstructor] consumes.
 * Extracted as a seam because [Publication] is a `final` class (unmockable) - the fake
 * seam lets the reconstruction / degrade logic be exercised directly in a unit test.
 * Production wires the real publication via [ReadiumLocatorReconstructor]'s
 * `(publication)` constructor. Both operations are NULLABLE (an unresolvable/renamed
 * resource, or a link that cannot be located, yields null -> the reconstructor returns
 * null -> the caller keeps the bookmark sheet open).
 */
interface PublicationLocatorSource {
    /** Resolves an href to a publication [Link], or null when the href is unresolvable. */
    fun linkWithHref(href: Url): Link?

    /** Resolves a [Link] to a base Readium [Locator], or null when it cannot be located. */
    fun locatorFromLink(link: Link): ReadiumLocator?
}

/** Adapts a real Readium [Publication] to the [PublicationLocatorSource] seam. */
private class RealPublicationLocatorSource(
    private val publication: Publication,
) : PublicationLocatorSource {
    override fun linkWithHref(href: Url): Link? = publication.linkWithHref(href)
    override fun locatorFromLink(link: Link): ReadiumLocator? = publication.locatorFromLink(link)
}

/**
 * Reconstructs a Readium [ReadiumLocator] from a vreader canonical [Locator] so a
 * persisted bookmark (canonical-only) can be jumped to via `navigator.go`.
 *
 * [expectedFingerprintKey] is the identity of the book this publication represents
 * (`Book.fingerprintKey`). A canonical locator whose own `fingerprintKey` differs
 * belongs to a DIFFERENT book - reconstructing it against THIS publication could
 * resolve a coincidentally-matching href and silently jump to the wrong content, so
 * a mismatch is rejected up front (before touching the publication).
 */
class ReadiumLocatorReconstructor internal constructor(
    private val expectedFingerprintKey: String,
    private val source: PublicationLocatorSource,
) {

    /** Production constructor: wraps the real [Publication] for [expectedFingerprintKey]. */
    constructor(expectedFingerprintKey: String, publication: Publication) :
        this(expectedFingerprintKey, RealPublicationLocatorSource(publication))

    /**
     * The canonical -> Readium reconstruction. Returns null on EVERY degrade so the
     * caller degrades gracefully (the bookmark sheet stays open), specifically:
     *  - the canonical locator points into a DIFFERENT book (`fingerprintKey` mismatch)
     *    - checked FIRST, before the publication is touched at all,
     *  - the canonical locator is structurally invalid ([Locator.validate] non-null),
     *  - its href is null/blank or a malformed URL ([Url] factory returns null),
     *  - the href is unresolvable in the publication ([PublicationLocatorSource.linkWithHref] null),
     *  - the resolved link cannot be located ([PublicationLocatorSource.locatorFromLink] null).
     *
     * On success the resolved position prefers `locatorFromLink`'s href + [MediaType],
     * refined with the canonical progression + cfi fragment (and the text quote when
     * present) - progression precision is the floor, matching `ResumeResolver`'s
     * canonical fallback.
     */
    fun toReadium(canonical: Locator): ReadiumLocator? {
        // Identity gate FIRST: a locator for a different book must never resolve against
        // this publication (a coincidentally-matching href would jump to wrong content).
        // No publication access happens until this passes.
        if (canonical.fingerprintKey != expectedFingerprintKey) return null

        // Reject a structurally-invalid canonical locator up front (negative page /
        // offsets, inverted range, non-finite progression) - never reconstruct from it.
        if (canonical.validate() != null) return null

        val href = canonical.href?.takeIf { it.isNotBlank() } ?: return null
        val url = Url(href) ?: return null                 // malformed href -> null
        val link = source.linkWithHref(url) ?: return null // unresolvable/renamed -> null
        val base = source.locatorFromLink(link) ?: return null // un-locatable -> null

        // Refine the resolved base position with the canonical progression + cfi. A cfi
        // rides in `fragments` (same slot the TOC seam uses); `copyWithLocations` keeps
        // the resolved href + non-null MediaType from `locatorFromLink`.
        val fragments = canonical.cfi
            ?.takeIf { it.isNotBlank() }
            ?.let { listOf(it) }
            ?: emptyList()
        val refined = base.copyWithLocations(
            progression = canonical.progression,
            fragments = fragments,
        )

        // Carry the text quote / context when present (the bookmark's anchor text).
        return if (canonical.textQuote != null ||
            canonical.textContextBefore != null ||
            canonical.textContextAfter != null
        ) {
            refined.copy(
                text = ReadiumLocator.Text(
                    before = canonical.textContextBefore,
                    highlight = canonical.textQuote,
                    after = canonical.textContextAfter,
                ),
            )
        } else {
            refined
        }
    }
}
