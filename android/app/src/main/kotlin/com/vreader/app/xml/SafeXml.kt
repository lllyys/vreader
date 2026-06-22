// Purpose: feature #117 (#110 Phase 3) — a hardened SAX-parse helper for UNTRUSTED external XML
// (OPDS feeds; the WebDAV multistatus precedent). Encapsulates the #116 WI-6 XXE defence that the
// live connected gate forced us to get right on Android: a parser-INDEPENDENT fail-closed DOCTYPE
// ban (a billion-laughs/external-entity bomb needs a DTD; banning it closes both vectors on every
// parser — Android's harmony parser throws SAXNotRecognizedException for the disallow-doctype-decl
// feature, so the flag alone can't be relied on) + a fixed-UTF-8 character stream (so a UTF-16
// `<!DOCTYPE` can't slip past the UTF-8 byte scan while the byte-fed parser still honours it) +
// best-effort hardening flags. A legitimate OPDS/Atom feed never carries a DTD.
package com.vreader.app.xml

import org.xml.sax.InputSource
import org.xml.sax.SAXException
import org.xml.sax.helpers.DefaultHandler
import javax.xml.parsers.SAXParserFactory

object SafeXml {
    /**
     * Namespace-aware SAX-parse [bytes] into [handler], XXE/DoS-hardened. Throws [SAXException] on
     * a DOCTYPE (rejected outright) or any parse error.
     */
    fun parse(bytes: ByteArray, handler: DefaultHandler) {
        // Fail-closed DOCTYPE ban — the primary, parser-independent control. WebDAV/Atom/OPDS never
        // legitimately carry a DTD; rejecting one closes both the external-entity and the
        // internal-expansion (billion-laughs) vectors regardless of which feature flags stuck.
        if (String(bytes, Charsets.UTF_8).contains("<!DOCTYPE", ignoreCase = true)) {
            throw SAXException("XML must not contain a DOCTYPE")
        }
        val factory = SAXParserFactory.newInstance().apply {
            isNamespaceAware = true
            // Best-effort: Android's harmony parser throws SAXNotRecognizedException for these, so
            // none of them may be REQUIRED — the DOCTYPE ban above is what actually protects us.
            runCatching { setFeature(javax.xml.XMLConstants.FEATURE_SECURE_PROCESSING, true) }
            runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        }
        // Feed a fixed UTF-8 CHARACTER stream so the parser's view == the DOCTYPE scan's view (the
        // parser ignores the document's encoding declaration when given a Reader) — closes the
        // UTF-16-smuggles-a-DOCTYPE-past-the-UTF-8-scan bypass.
        factory.newSAXParser().parse(InputSource(bytes.inputStream().reader(Charsets.UTF_8)), handler)
    }
}
