package com.vreader.app.opds

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Feature #117 WI-2 — OpdsClient against a hand-rolled ServerSocket HTTP fake (plain JVM): feed
 * fetch + parse, redirect follow with baseUrl = the final URL, typed errors, oversized-response
 * rejection.
 */
class OpdsClientTest {
    private class Response(val status: Int, val body: ByteArray = ByteArray(0), val headers: Map<String, String> = emptyMap())
    private class FakeServer {
        private val socket = ServerSocket(0)
        val port get() = socket.localPort
        val handlers = ConcurrentHashMap<String, (ByteArray) -> Response>()
        @Volatile private var running = true
        init {
            thread(isDaemon = true) {
                while (running) {
                    val conn = try { socket.accept() } catch (e: Exception) { break }
                    thread(isDaemon = true) { handle(conn) }
                }
            }
        }
        private fun handle(conn: java.net.Socket) = conn.use {
            val input = BufferedInputStream(conn.getInputStream())
            val requestLine = readLine(input) ?: return
            val parts = requestLine.split(" ")
            val method = parts[0]; val path = parts.getOrElse(1) { "/" }
            while (true) { val h = readLine(input) ?: break; if (h.isEmpty()) break }
            val resp = (handlers["$method ${path.substringBefore('?')}"] ?: handlers["$method *"])?.invoke(ByteArray(0))
                ?: Response(404)
            write(conn.getOutputStream(), resp)
        }
        private fun readLine(input: BufferedInputStream): String? {
            val sb = StringBuilder(); var prev = -1
            while (true) {
                val b = input.read(); if (b == -1) return if (sb.isEmpty()) null else sb.toString()
                if (prev == '\r'.code && b == '\n'.code) { sb.setLength(sb.length - 1); return sb.toString() }
                sb.append(b.toChar()); prev = b
            }
        }
        private fun write(out: OutputStream, r: Response) {
            val sb = StringBuilder("HTTP/1.1 ${r.status} X\r\nContent-Length: ${r.body.size}\r\nConnection: close\r\n")
            r.headers.forEach { (k, v) -> sb.append("$k: $v\r\n") }
            sb.append("\r\n")
            out.write(sb.toString().toByteArray()); out.write(r.body); out.flush()
        }
        fun stop() { running = false; socket.close() }
    }

    private lateinit var server: FakeServer
    private fun base() = "http://127.0.0.1:${server.port}"
    private fun client() = OpdsClient(Dispatchers.Unconfined, 2000, 2000, maxFeedBytes = 4096)

    @Before fun setUp() { server = FakeServer() }
    @After fun tearDown() = server.stop()

    private val feedXml = """<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom"><title>Cat</title><id>i</id>
  <entry><title>Book</title><id>b</id>
    <link rel="http://opds-spec.org/acquisition/open-access" href="files/book.epub" type="application/epub+zip"/>
  </entry></feed>"""

    @Test fun fetchFeed_parses() = runBlocking {
        server.handlers["GET /opds/root.xml"] = { Response(200, feedXml.toByteArray()) }
        val feed = client().fetchFeed("${base()}/opds/root.xml")
        assertEquals("Cat", feed.title)
        // baseUrl = the fetched URL → relative acquisition href resolves under /opds/.
        assertEquals("${base()}/opds/files/book.epub", feed.entries.single().acquisitionLinks.single().resolvedHref(feed.baseUrl))
    }

    @Test fun fetchFeed_followsRedirect_baseUrlIsFinal() = runBlocking {
        server.handlers["GET /old"] = { Response(301, headers = mapOf("Location" to "${base()}/opds/root.xml")) }
        server.handlers["GET /opds/root.xml"] = { Response(200, feedXml.toByteArray()) }
        val feed = client().fetchFeed("${base()}/old")
        // The final (post-redirect) URL is the base → href resolves under /opds/, NOT /.
        assertEquals("${base()}/opds/files/book.epub", feed.entries.single().acquisitionLinks.single().resolvedHref(feed.baseUrl))
    }

    @Test fun fetchFeed_404_throwsHttp() = runBlocking {
        server.handlers["GET /nope"] = { Response(404) }
        val e = runCatching { client().fetchFeed("${base()}/nope") }.exceptionOrNull()
        assertTrue(e is OpdsError.Http && e.code == 404)
    }

    @Test fun fetchFeed_unreachable_throwsNetwork() = runBlocking {
        val e = runCatching { OpdsClient(Dispatchers.Unconfined, 500, 500).fetchFeed("http://127.0.0.1:1/x") }.exceptionOrNull()
        assertTrue(e is OpdsError.Network)
    }

    @Test fun fetchFeed_oversized_throwsNetwork() = runBlocking {
        server.handlers["GET /big"] = { Response(200, ByteArray(8192) { 'a'.code.toByte() }) }  // > 4096 cap
        val e = runCatching { client().fetchFeed("${base()}/big") }.exceptionOrNull()
        assertTrue(e is OpdsError.Network)
    }

    @Test fun download_returnsBytesAndContentType() = runBlocking {
        server.handlers["GET /files/book.epub"] = { Response(200, "PKepub".toByteArray(Charsets.ISO_8859_1), mapOf("Content-Type" to "application/epub+zip")) }
        val dl = client().download("${base()}/files/book.epub")
        assertEquals("application/epub+zip", dl.contentType?.substringBefore(';')?.trim())
        assertTrue(dl.bytes.size >= 4)
    }
}
