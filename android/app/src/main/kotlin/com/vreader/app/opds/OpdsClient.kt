// Purpose: feature #117 WI-2 (#110 Phase 3) — fetches an OPDS feed and downloads an acquisition
// blob over HttpURLConnection (the #116 WebDavClient transport precedent): manual redirect follow,
// bounded reads (a feed/download can't OOM the process), typed OpdsError, and `Accept-Encoding:
// identity` (do NOT request gzip — avoids a decompression-bomb surface; a server that sends gzip
// anyway is bounded-decompressed). The fetched feed's baseUrl = the POST-redirect final URL so
// relative links resolve correctly. v1 = no auth.
package com.vreader.app.opds

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import java.util.zip.GZIPInputStream

/** A downloaded resource: its bytes, the response Content-Type, and the final (post-redirect) URL. */
data class OpdsDownload(val bytes: ByteArray, val contentType: String?, val finalUrl: String)

class OpdsClient(
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 30_000,
    private val maxFeedBytes: Long = 8L * 1024 * 1024,
    private val maxDownloadBytes: Long = 256L * 1024 * 1024,
    // feature #120 — optional Basic auth for a saved catalog. The credential is sent ONLY on a
    // request whose origin (scheme+host+port) matches the catalog's [authOrigin] — so a cross-origin
    // redirect or a cross-origin acquisition download never leaks it. And Basic is allowed only over
    // https OR a local/private host (a public-http catalog with auth is refused — no cleartext leak).
    private val username: String? = null,
    private val password: String? = null,
    private val authOrigin: String? = null,
) {
    /** GET + parse an OPDS feed. baseUrl = the final URL after redirects. */
    suspend fun fetchFeed(url: String): OpdsFeed = withContext(dispatcher) {
        guardCleartextAuth()
        val dl = request(url, redirectsLeft = 5, maxBytes = maxFeedBytes)
        OpdsParser.parse(dl.bytes, dl.finalUrl)
    }

    /** GET an acquisition blob (bytes + content-type), bounded for large books. */
    suspend fun download(url: String): OpdsDownload = withContext(dispatcher) {
        guardCleartextAuth()
        request(url, redirectsLeft = 5, maxBytes = maxDownloadBytes)
    }

    /** Refuse to send a configured Basic credential over cleartext to a public host. */
    private fun guardCleartextAuth() {
        if (username != null && authOrigin != null && !isSecureOrLocal(authOrigin)) throw OpdsError.InsecureAuth
    }

    /** Same-origin (scheme+host+port) as the catalog → send Basic; else (cross-origin redirect /
     *  acquisition) send nothing. */
    private fun applyAuth(conn: HttpURLConnection, url: String) {
        val user = username ?: return
        if (authOrigin == null || originOf(url) != authOrigin) return
        val token = java.util.Base64.getEncoder().encodeToString("$user:${password.orEmpty()}".toByteArray(Charsets.UTF_8))
        conn.setRequestProperty("Authorization", "Basic $token")
    }

    private fun originOf(url: String): String? = runCatching {
        val u = URL(url)
        val port = if (u.port == -1) u.defaultPort else u.port
        "${u.protocol.lowercase()}://${u.host.lowercase()}:$port"
    }.getOrNull()

    private fun isSecureOrLocal(origin: String): Boolean {
        val u = runCatching { URL(origin) }.getOrNull() ?: return false
        if (u.protocol.equals("https", true)) return true
        val h = u.host.lowercase().trim('[', ']')  // strip IPv6 brackets
        if (h == "localhost" || h == "::1") return true
        return isPrivateIpv4(h)
    }

    /** True ONLY for a numeric IPv4 LITERAL in a loopback/private range — never a hostname like
     *  "10.evil.com" or "192.168.1.1.evil.com" (a `startsWith("10.")` test would wrongly accept
     *  those and leak the Basic credential cleartext to an attacker-controlled host). */
    private fun isPrivateIpv4(host: String): Boolean {
        val parts = host.split('.')
        if (parts.size != 4) return false
        val o = parts.map { p -> canonicalOctet(p) ?: return false }
        return when {
            o[0] == 127 -> true                    // 127.0.0.0/8 loopback
            o[0] == 10 -> true                     // 10.0.0.0/8 (incl. the emulator host 10.0.2.2)
            o[0] == 192 && o[1] == 168 -> true     // 192.168.0.0/16
            o[0] == 172 && o[1] in 16..31 -> true  // 172.16.0.0/12
            else -> false
        }
    }

    /** A canonical-decimal IPv4 octet (ASCII digits only, no sign, no leading zero except "0") in
     *  0..255, else null. Rejects octal-ambiguous forms like "010" / "+10" that some resolvers read
     *  differently than `toInt()` does — a textual-origin-vs-actual-address mismatch leaks auth. */
    private fun canonicalOctet(p: String): Int? {
        if (p.isEmpty() || p.length > 3) return null
        if (!p.all { it in '0'..'9' }) return null
        if (p.length > 1 && p[0] == '0') return null  // no leading zeros
        return p.toInt().takeIf { it in 0..255 }
    }

    private fun request(url: String, redirectsLeft: Int, maxBytes: Long): OpdsDownload {
        val u = runCatching { URL(url) }.getOrNull() ?: throw OpdsError.InvalidUrl(url)
        if (u.protocol != "http" && u.protocol != "https") throw OpdsError.InvalidUrl(url)
        val conn = try { u.openConnection() as HttpURLConnection } catch (e: Exception) { throw OpdsError.Network(e.message ?: "connect failed") }
        try {
            conn.requestMethod = "GET"
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false
            conn.setRequestProperty("Accept", "application/atom+xml, application/xml;q=0.9, */*;q=0.8")
            conn.setRequestProperty("Accept-Encoding", "identity")  // no gzip (decompression-bomb surface)
            applyAuth(conn, url)  // origin-scoped Basic; never logged
            val status = try {
                conn.responseCode
            } catch (e: SocketTimeoutException) {
                throw OpdsError.Network("timeout")
            } catch (e: IOException) {
                throw OpdsError.Network(e.message ?: "offline")
            }
            if (status in REDIRECTS) {
                val loc = conn.getHeaderField("Location")
                val next = loc?.let { resolveAgainst(it, url) }
                if (next != null && redirectsLeft > 0) {
                    conn.disconnect()
                    return request(next, redirectsLeft - 1, maxBytes)
                }
            }
            if (status == HttpURLConnection.HTTP_NOT_FOUND) throw OpdsError.Http(404)
            // Do NOT read the error body — a hostile server could send an unbounded one (the
            // success path is capped, but errorStream.readBytes() isn't); disconnect() in finally
            // tears the connection down regardless (we never reuse it).
            if (status / 100 != 2) throw OpdsError.Http(status)
            val gzip = conn.getHeaderField("Content-Encoding")?.contains("gzip", ignoreCase = true) == true
            val raw = conn.inputStream
            val stream = if (gzip) GZIPInputStream(raw) else raw
            val bytes = readBounded(stream, maxBytes, url)
            return OpdsDownload(bytes, conn.contentType, url)
        } finally {
            conn.disconnect()
        }
    }

    /** Read with a hard cap so a hostile/huge response can't OOM the process. */
    private fun readBounded(stream: InputStream, max: Long, url: String): ByteArray {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(64 * 1024)
        var total = 0L
        stream.use {
            while (true) {
                val n = it.read(buf)
                if (n < 0) break
                total += n
                if (total > max) throw OpdsError.Network("response from $url exceeds the size limit")
                out.write(buf, 0, n)
            }
        }
        return out.toByteArray()
    }

    private companion object {
        val REDIRECTS = intArrayOf(301, 302, 303, 307, 308)
    }
}
