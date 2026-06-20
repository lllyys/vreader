// Purpose: feature #116 WI-1 (#110 Phase 3) — a minimal WebDAV client over HttpURLConnection
// (no 3rd-party dep) for the backup/restore backend: PROPFIND (Depth:1) / MKCOL / PUT / GET /
// DELETE with Basic auth, timeouts, and HTTP-status → typed WebDavError mapping. The PROPFIND
// multistatus is parsed with a NAMESPACE-AWARE SAX parser (XXE disabled) — collection detection
// via <resourcetype><collection/>, hrefs URL-decoded — chosen over XmlPullParser so it's
// testable in plain JVM (no Robolectric). Redirects (301/302/307/308) are followed manually
// because HttpURLConnection does not auto-follow for non-GET methods.
package com.vreader.app.backup.net

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.xml.sax.Attributes
import org.xml.sax.InputSource
import org.xml.sax.helpers.DefaultHandler
import java.io.File
import java.io.FilterInputStream
import java.io.IOException
import java.io.InputStream
import java.net.ConnectException
import java.net.HttpURLConnection
import java.net.ProtocolException
import java.net.SocketTimeoutException
import java.net.URL
import java.net.URLDecoder
import java.net.UnknownHostException
import java.util.Base64
import javax.xml.parsers.SAXParserFactory

/** A typed WebDAV failure — mirrors the #114 WebDavError causes. */
enum class WebDavErrorKind { auth401, notFound404, offline, timeout, server }

class WebDavException(val kind: WebDavErrorKind, message: String, cause: Throwable? = null) :
    IOException(message, cause)

/** One PROPFIND multistatus entry. */
data class WebDavEntry(
    val href: String,
    val isCollection: Boolean,
    val contentLength: Long?,
)

/** The WebDAV operations the backup service needs — an interface so the service can be unit-tested
 *  against an in-memory fake (a full backup→restore round-trip) without a live server. */
interface WebDavTransport {
    suspend fun propfind(path: String): List<WebDavEntry>
    suspend fun mkcol(path: String)
    suspend fun put(path: String, bytes: ByteArray)
    /** Streams [file] as the PUT body (fixed-length) — never buffers a large book in memory. */
    suspend fun putFile(path: String, file: File)
    suspend fun get(path: String): ByteArray
    suspend fun getStream(path: String): InputStream
    suspend fun move(from: String, to: String)
    suspend fun delete(path: String)
    suspend fun exists(path: String): Boolean
}

/**
 * A WebDAV client rooted at [baseUrl] (e.g. `http://10.0.2.2:8080/`) with Basic auth. All calls
 * are `suspend` on [dispatcher]; the body is blocking HttpURLConnection. Paths are resolved
 * against [baseUrl].
 */
class WebDavClient(
    private val baseUrl: String,
    private val username: String,
    private val password: String,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 30_000,
) : WebDavTransport {
    private val authHeader: String =
        "Basic " + Base64.getEncoder().encodeToString("$username:$password".toByteArray(Charsets.UTF_8))

    /** PROPFIND Depth:1 → the entries directly under [path] (excludes [path] itself). */
    override suspend fun propfind(path: String): List<WebDavEntry> = withContext(dispatcher) {
        val body = """<?xml version="1.0" encoding="utf-8"?>
<D:propfind xmlns:D="DAV:"><D:prop><D:resourcetype/><D:getcontentlength/></D:prop></D:propfind>"""
        val (status, bytes) = request("PROPFIND", path, body.toByteArray(Charsets.UTF_8), mapOf("Depth" to "1"))
        if (status == HttpURLConnection.HTTP_NOT_FOUND) throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
        if (status != 207 && status / 100 != 2) throwForStatus(status, path)
        parseMultistatus(bytes).filterNot { samePath(it.href, path) }
    }

    /** Create a collection. Tolerates 405 (already exists). */
    override suspend fun mkcol(path: String): Unit = withContext(dispatcher) {
        val (status, _) = request("MKCOL", path, null, emptyMap())
        if (status == 405 || status == 301) return@withContext  // already exists
        if (status / 100 != 2) throwForStatus(status, path)
    }

    override suspend fun put(path: String, bytes: ByteArray): Unit = withContext(dispatcher) {
        val (status, _) = request("PUT", path, bytes, mapOf("Content-Type" to "application/octet-stream"))
        if (status / 100 != 2) throwForStatus(status, path)
    }

    override suspend fun putFile(path: String, file: File): Unit = withContext(dispatcher) {
        val url = resolve(path)
        val conn = try { url.openConnection() as HttpURLConnection } catch (e: Exception) { throw offline(e) }
        try {
            setRequestMethod(conn, "PUT")
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Authorization", authHeader)
            conn.setRequestProperty("Content-Type", "application/octet-stream")
            conn.doOutput = true
            conn.setFixedLengthStreamingMode(file.length())  // stream — no full ByteArray in heap
            file.inputStream().buffered().use { input -> conn.outputStream.use { input.copyTo(it) } }
            val status = try { conn.responseCode } catch (e: SocketTimeoutException) {
                throw WebDavException(WebDavErrorKind.timeout, "timeout PUT $path", e)
            } catch (e: IOException) { throw offline(e) }
            if (status / 100 != 2) { conn.errorStream?.use { it.readBytes() }; throwForStatus(status, path) }
        } finally {
            conn.disconnect()
        }
    }

    override suspend fun get(path: String): ByteArray = withContext(dispatcher) {
        val (status, bytes) = request("GET", path, null, emptyMap())
        if (status == HttpURLConnection.HTTP_NOT_FOUND) throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
        if (status / 100 != 2) throwForStatus(status, path)
        bytes
    }

    /**
     * Streams a GET body without buffering the whole response in memory — for large book blobs
     * (the in-memory [get] is fine for the small backup ZIPs). The returned stream OWNS the
     * connection: closing it disconnects. Errors (404 / auth / offline) are mapped before the
     * stream is returned; redirects (301/302/307/308) are followed manually.
     */
    override suspend fun getStream(path: String): InputStream = withContext(dispatcher) {
        openStream(path, redirectsLeft = 5)
    }

    private fun openStream(path: String, redirectsLeft: Int): InputStream {
        val url = resolve(path)
        val conn = try { url.openConnection() as HttpURLConnection } catch (e: Exception) { throw offline(e) }
        var handOff = false
        try {
            setRequestMethod(conn, "GET")
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Authorization", authHeader)
            val status = try { conn.responseCode } catch (e: SocketTimeoutException) {
                throw WebDavException(WebDavErrorKind.timeout, "timeout GET $path", e)
            } catch (e: IOException) { throw offline(e) }
            if (status in intArrayOf(301, 302, 307, 308)) {
                val loc = conn.getHeaderField("Location")
                if (loc != null && redirectsLeft > 0) {
                    conn.disconnect()
                    return openStream(loc, redirectsLeft - 1)
                }
            }
            if (status == HttpURLConnection.HTTP_NOT_FOUND) throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
            if (status / 100 != 2) { conn.errorStream?.use { it.readBytes() }; throwForStatus(status, path) }
            handOff = true
            return object : FilterInputStream(conn.inputStream) {
                override fun close() { try { super.close() } finally { conn.disconnect() } }
            }
        } finally {
            if (!handOff) conn.disconnect()
        }
    }

    /** WebDAV MOVE [from] → [to] (overwriting). Used to atomically publish a blob (PUT to a
     *  `.tmp` then MOVE into place) so a half-written upload is never seen as a complete blob. */
    override suspend fun move(from: String, to: String): Unit = withContext(dispatcher) {
        val destination = resolve(to).toString()
        val (status, _) = request("MOVE", from, null, mapOf("Destination" to destination, "Overwrite" to "T"))
        if (status / 100 != 2) throwForStatus(status, from)
    }

    override suspend fun delete(path: String): Unit = withContext(dispatcher) {
        val (status, _) = request("DELETE", path, null, emptyMap())
        if (status == HttpURLConnection.HTTP_NOT_FOUND) return@withContext
        if (status / 100 != 2) throwForStatus(status, path)
    }

    override suspend fun exists(path: String): Boolean = withContext(dispatcher) {
        try { propfind(path); true } catch (e: WebDavException) { if (e.kind == WebDavErrorKind.notFound404) false else throw e }
    }

    // ── transport ──────────────────────────────────────────────

    /** One request with manual redirect following (HUC doesn't auto-follow non-GET). */
    private fun request(method: String, path: String, body: ByteArray?, headers: Map<String, String>, redirectsLeft: Int = 5): Pair<Int, ByteArray> {
        val url = resolve(path)
        val conn = try { (url.openConnection() as HttpURLConnection) } catch (e: Exception) { throw offline(e) }
        try {
            setRequestMethod(conn, method)
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Authorization", authHeader)
            headers.forEach { (k, v) -> conn.setRequestProperty(k, v) }
            if (body != null) {
                conn.doOutput = true
                conn.setFixedLengthStreamingMode(body.size)
                conn.outputStream.use { it.write(body) }
            }
            val status = try { conn.responseCode } catch (e: SocketTimeoutException) {
                throw WebDavException(WebDavErrorKind.timeout, "timeout $method $path", e)
            } catch (e: IOException) { throw offline(e) }

            if (status in intArrayOf(301, 302, 307, 308)) {
                val loc = conn.getHeaderField("Location")
                if (loc != null && redirectsLeft > 0) {
                    conn.disconnect()
                    return request(method, loc, body, headers, redirectsLeft - 1)
                }
            }
            val stream = if (status / 100 == 2) conn.inputStream else conn.errorStream
            val bytes = stream?.use { it.readBytes() } ?: ByteArray(0)
            return status to bytes
        } finally {
            conn.disconnect()
        }
    }

    /**
     * Set [method] on [conn], tolerating WebDAV verbs the JDK rejects. Android's runtime is
     * OkHttp-backed and accepts PROPFIND/MKCOL via [HttpURLConnection.setRequestMethod] directly;
     * the JDK's `sun.net.www.protocol.http` impl validates against a fixed verb allow-list and
     * throws ProtocolException. In that case we set the protected `method` field reflectively
     * (the long-standing Sardine/pre-OkHttp WebDAV workaround). This fallback never runs on
     * Android — it only enables a plain-JVM transport (and unit testing without a 3rd-party dep).
     */
    private fun setRequestMethod(conn: HttpURLConnection, method: String) {
        try {
            conn.requestMethod = method
        } catch (e: ProtocolException) {
            // HttpsURLConnectionImpl wraps the real connection in a `delegate` field; the actual
            // request is issued by that delegate, so it is the REQUIRED target when present. Setting
            // only the wrapper's `method` would silently leave the delegate on the old verb.
            val delegate = runCatching {
                conn.javaClass.getDeclaredField("delegate").apply { isAccessible = true }.get(conn)
            }.getOrNull() as? HttpURLConnection
            val realTarget = delegate ?: conn
            // The real target MUST be forced; the wrapper is best-effort (some flows read its copy).
            if (!setMethodField(realTarget, method)) throw e
            if (delegate != null) setMethodField(conn, method)
        }
    }

    /** Walk [target]'s class hierarchy and reflectively set the protected `method` field. */
    private fun setMethodField(target: HttpURLConnection, method: String): Boolean {
        var c: Class<*>? = target.javaClass
        while (c != null) {
            try {
                c.getDeclaredField("method").apply { isAccessible = true }.set(target, method)
                return true
            } catch (nsf: NoSuchFieldException) {
                c = c.superclass
            } catch (other: Exception) {
                return false  // inaccessible (module encapsulation) / security — fail closed
            }
        }
        return false
    }

    /** Resolve a path/absolute-URL against the base. */
    private fun resolve(path: String): URL =
        if (path.startsWith("http://") || path.startsWith("https://")) URL(path)
        else URL(URL(baseUrl), path)

    private fun offline(cause: Throwable): WebDavException = when (cause) {
        is SocketTimeoutException -> WebDavException(WebDavErrorKind.timeout, "timeout", cause)
        is UnknownHostException, is ConnectException -> WebDavException(WebDavErrorKind.offline, "offline", cause)
        else -> WebDavException(WebDavErrorKind.offline, "offline", cause)
    }

    private fun throwForStatus(status: Int, path: String): Nothing = when (status) {
        401, 403 -> throw WebDavException(WebDavErrorKind.auth401, "$status $path")
        404 -> throw WebDavException(WebDavErrorKind.notFound404, "404 $path")
        else -> throw WebDavException(WebDavErrorKind.server, "$status $path")
    }

    private fun samePath(href: String, path: String): Boolean {
        fun norm(s: String) = URLDecoder.decode(s.substringAfter("://").substringAfter('/'), "UTF-8").trim('/')
        val a = norm(href)
        val b = norm(if (path.startsWith("http")) path else "x://x/$path")
        return a == b
    }

    /** Namespace-aware SAX parse of a DAV:multistatus body, XXE disabled. */
    private fun parseMultistatus(bytes: ByteArray): List<WebDavEntry> {
        if (bytes.isEmpty()) return emptyList()
        // Parser-INDEPENDENT, fail-closed DOCTYPE ban — the primary XXE/DoS control. A legitimate
        // WebDAV multistatus never carries a DTD; an inline internal DTD can hold a billion-laughs
        // entity-expansion bomb that opens no external URI (so the resolveEntity no-op below never
        // fires) and that disallow-doctype-decl would catch — but that flag throws on Android's
        // harmony parser. Rejecting any DOCTYPE outright before parsing closes both the
        // external-entity AND the internal-expansion vectors on every parser. (WebDAV is UTF-8.)
        if (String(bytes, Charsets.UTF_8).contains("<!DOCTYPE", ignoreCase = true)) {
            throw WebDavException(WebDavErrorKind.server, "multistatus must not contain a DOCTYPE")
        }
        val factory = SAXParserFactory.newInstance().apply {
            isNamespaceAware = true
            // XXE hardening that works on BOTH the JVM (Xerces) AND Android (harmony). The feature
            // flags are BEST-EFFORT: Android's parser throws SAXNotRecognizedException for
            // `disallow-doctype-decl` and friends, so requiring them breaks every PROPFIND on device
            // (caught by the WI-6 connected test). FEATURE_SECURE_PROCESSING is the standard JAXP
            // flag (limits entity expansion); the LOAD-BEARING, parser-agnostic defence is the
            // MultistatusHandler's resolveEntity override below, which resolves EVERY external
            // entity to nothing — so no file:// disclosure regardless of which features stuck.
            runCatching { setFeature(javax.xml.XMLConstants.FEATURE_SECURE_PROCESSING, true) }
            runCatching { setFeature("http://apache.org/xml/features/disallow-doctype-decl", true) }
            runCatching { setFeature("http://xml.org/sax/features/external-general-entities", false) }
            runCatching { setFeature("http://xml.org/sax/features/external-parameter-entities", false) }
        }
        val parser = factory.newSAXParser()
        val handler = MultistatusHandler()
        // Feed the parser a fixed UTF-8 CHARACTER stream (Reader), not the raw byte stream: SAX uses
        // the character stream and ignores the document's encoding declaration, so the parser sees
        // exactly what the UTF-8 DOCTYPE scan above saw. This closes the encoding-bypass where a
        // UTF-16 `<!DOCTYPE` slips past a UTF-8 byte scan but is still honoured by a byte-fed parser.
        parser.parse(InputSource(bytes.inputStream().reader(Charsets.UTF_8)), handler)
        return handler.entries
    }

    private class MultistatusHandler : DefaultHandler() {
        val entries = mutableListOf<WebDavEntry>()
        private val text = StringBuilder()
        private var href: String? = null
        private var isCollection = false
        private var contentLength: Long? = null
        private var inResponse = false
        private var sawStatus = false      // any <status> line seen in this response
        private var sawOkStatus = false    // at least one 2xx <status> seen

        // The parser-agnostic XXE defence: resolve EVERY external entity to an empty source, so a
        // malicious `<!ENTITY x SYSTEM "file:///etc/passwd">` expands to nothing on ANY parser
        // (Android's harmony parser doesn't honour the disallow-doctype-decl feature flag).
        override fun resolveEntity(publicId: String?, systemId: String?): InputSource =
            InputSource(java.io.StringReader(""))

        private fun local(qName: String) = qName.substringAfter(':')

        override fun startElement(uri: String?, localName: String?, qName: String, attributes: Attributes?) {
            text.setLength(0)
            when (local(qName).lowercase()) {
                "response" -> {
                    inResponse = true; href = null; isCollection = false; contentLength = null
                    sawStatus = false; sawOkStatus = false
                }
                "collection" -> if (inResponse) isCollection = true
            }
        }

        override fun characters(ch: CharArray, start: Int, length: Int) { text.append(ch, start, length) }

        override fun endElement(uri: String?, localName: String?, qName: String) {
            when (local(qName).lowercase()) {
                "href" -> if (inResponse) href = text.toString().trim()
                "getcontentlength" -> if (inResponse) contentLength = text.toString().trim().toLongOrNull()
                "status" -> if (inResponse) {
                    // "HTTP/1.1 200 OK" → the middle token is the code.
                    val code = text.toString().trim().split(' ').getOrNull(1)?.toIntOrNull()
                    if (code != null) { sawStatus = true; if (code / 100 == 2) sawOkStatus = true }
                }
                "response" -> {
                    val h = href
                    // Skip a resource whose status was reported and was never 2xx (e.g. a 404
                    // per-response/per-propstat entry); servers that omit <status> default to keep.
                    if (inResponse && h != null && (!sawStatus || sawOkStatus)) {
                        entries.add(WebDavEntry(URLDecoder.decode(h, "UTF-8"), isCollection, contentLength))
                    }
                    inResponse = false
                }
            }
            text.setLength(0)
        }
    }
}
