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
) {
    /** GET + parse an OPDS feed. baseUrl = the final URL after redirects. */
    suspend fun fetchFeed(url: String): OpdsFeed = withContext(dispatcher) {
        val dl = request(url, redirectsLeft = 5, maxBytes = maxFeedBytes)
        OpdsParser.parse(dl.bytes, dl.finalUrl)
    }

    /** GET an acquisition blob (bytes + content-type), bounded for large books. */
    suspend fun download(url: String): OpdsDownload = withContext(dispatcher) {
        request(url, redirectsLeft = 5, maxBytes = maxDownloadBytes)
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
