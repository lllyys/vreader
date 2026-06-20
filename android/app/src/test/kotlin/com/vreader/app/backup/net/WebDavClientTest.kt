package com.vreader.app.backup.net

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Feature #116 WI-1 — the WebDavClient against a hand-rolled ServerSocket HTTP fake (plain JVM;
 * `com.sun.net.httpserver` isn't on the Android unit-test classpath). Exercises the multistatus
 * parse (namespace prefix, resourcetype/collection, URL-decoded href, a non-2xx per-resource
 * entry skipped), PUT/GET round-trip, a 307 redirect, typed error mapping, MKCOL/DELETE
 * idempotency, and XXE inertness.
 */
class WebDavClientTest {
    /** A minimal HTTP/1.1 responder: handlers keyed by "METHOD path" → (body bytes) -> Response. */
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
            var contentLength = 0
            while (true) {
                val h = readLine(input) ?: break
                if (h.isEmpty()) break
                if (h.lowercase().startsWith("content-length:")) contentLength = h.substringAfter(":").trim().toInt()
            }
            val body = if (contentLength > 0) ByteArray(contentLength).also { readFully(input, it) } else ByteArray(0)
            val key = "$method ${path.substringBefore('?')}"
            val handler = handlers[key] ?: handlers["$method *"]
            val resp = handler?.invoke(body) ?: Response(404)
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
        private fun readFully(input: BufferedInputStream, buf: ByteArray) {
            var off = 0; while (off < buf.size) { val n = input.read(buf, off, buf.size - off); if (n < 0) break; off += n }
        }
        private fun write(out: OutputStream, r: Response) {
            val sb = StringBuilder("HTTP/1.1 ${r.status} X\r\n")
            sb.append("Content-Length: ${r.body.size}\r\n")
            // One request per socket — advertise close so the JDK client doesn't try to reuse the
            // (already-closed) keep-alive connection for the next request and fail with an IOException.
            sb.append("Connection: close\r\n")
            r.headers.forEach { (k, v) -> sb.append("$k: $v\r\n") }
            sb.append("\r\n")
            out.write(sb.toString().toByteArray()); out.write(r.body); out.flush()
        }
        fun stop() { running = false; socket.close() }
    }

    private lateinit var server: FakeServer
    private lateinit var base: String

    @Before fun setUp() { server = FakeServer(); base = "http://127.0.0.1:${server.port}/" }
    @After fun tearDown() = server.stop()

    private fun client() = WebDavClient(base, "u", "p", Dispatchers.Unconfined, 2000, 2000)

    @Test fun propfind_parsesMultistatus_namespaces_collection_urlDecoded() = runBlocking {
        val xml = """<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/My%20Book.epub</d:href><d:propstat><d:prop><d:resourcetype/><d:getcontentlength>1234</d:getcontentlength></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
  <d:response><d:href>/dav/missing</d:href><d:propstat><d:status>HTTP/1.1 404 Not Found</d:status></d:propstat></d:response>
</d:multistatus>"""
        server.handlers["PROPFIND /dav/"] = { Response(207, xml.toByteArray()) }
        val entries = client().propfind("dav/")
        val file = entries.firstOrNull { it.href.endsWith("My Book.epub") }
        assertTrue("href URL-decoded + collection self-entry filtered", file != null)
        assertEquals(1234L, file!!.contentLength)
        assertFalse(file.isCollection)
        // The 404 per-response entry must be skipped, and the request-path self-entry filtered out.
        assertTrue("404 sub-entry skipped", entries.none { it.href.endsWith("/missing") })
        assertEquals("only the one real file remains", 1, entries.size)
    }

    @Test fun put_then_get_roundTripsBytes() = runBlocking {
        val store = ConcurrentHashMap<String, ByteArray>()
        server.handlers["PUT *"] = { body -> store["last"] = body; Response(201) }
        server.handlers["GET *"] = { Response(200, store["last"] ?: ByteArray(0)) }
        val bytes = "hello 世界".toByteArray()
        client().put("dav/x.txt", bytes)
        assertTrue(bytes.contentEquals(client().get("dav/x.txt")))
    }

    @Test fun get_followsRedirect_307() = runBlocking {
        server.handlers["GET /a"] = { Response(307, headers = mapOf("Location" to "${base}b")) }
        server.handlers["GET /b"] = { Response(200, "redirected".toByteArray()) }
        assertEquals("redirected", String(client().get("a")))
    }

    @Test fun mapsStatusCodes() = runBlocking {
        server.handlers["GET /401"] = { Response(401) }
        server.handlers["PROPFIND /404"] = { Response(404) }
        assertEquals(WebDavErrorKind.auth401, (runCatching { client().get("401") }.exceptionOrNull() as WebDavException).kind)
        assertEquals(WebDavErrorKind.notFound404, (runCatching { client().propfind("404") }.exceptionOrNull() as WebDavException).kind)
    }

    @Test fun offline_whenServerUnreachable() = runBlocking {
        val dead = WebDavClient("http://127.0.0.1:1/", "u", "p", Dispatchers.Unconfined, 500, 500)
        val kind = (runCatching { dead.get("x") }.exceptionOrNull() as WebDavException).kind
        assertTrue(kind == WebDavErrorKind.offline || kind == WebDavErrorKind.timeout)
    }

    @Test fun mkcol_tolerates405() = runBlocking {
        server.handlers["MKCOL /dav/"] = { Response(405) }
        client().mkcol("dav/")
    }

    @Test fun delete_tolerates404() = runBlocking {
        server.handlers["DELETE /gone"] = { Response(404) }
        client().delete("gone")
    }

    @Test fun xxe_doctype_doesNotLeak() = runBlocking {
        val xml = """<?xml version="1.0"?><!DOCTYPE m [<!ENTITY x SYSTEM "file:///etc/passwd">]>
<d:multistatus xmlns:d="DAV:"><d:response><d:href>/x/safe</d:href><d:propstat><d:prop><d:resourcetype/></d:prop></d:propstat></d:response></d:multistatus>"""
        server.handlers["PROPFIND /x/"] = { Response(207, xml.toByteArray()) }
        val result = runCatching { client().propfind("x/") }
        // disallow-doctype-decl → parse throws; OR (if a parser ignores it) no entity content leaks.
        assertTrue(result.isFailure || result.getOrNull()?.none { it.href.contains("root:") } == true)
    }
}
