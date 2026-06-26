package com.vreader.app.opds

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * Feature #120 WI-1 — OpdsClient origin-scoped Basic auth + the cleartext-auth guard. Mirrors the
 * #117 OpdsClientTest ServerSocket fake, additionally recording the Authorization header per path.
 */
class OpdsClientAuthTest {
    private class FakeServer {
        private val socket = ServerSocket(0)
        val port get() = socket.localPort
        /** path -> Authorization header value seen (null = none sent). */
        val seenAuth = ConcurrentHashMap<String, String>()
        val NONE = "<none>"
        @Volatile private var running = true
        init {
            thread(isDaemon = true) {
                while (running) {
                    val conn = try { socket.accept() } catch (e: Exception) { break }
                    thread(isDaemon = true) { handle(conn) }
                }
            }
        }
        private fun handle(conn: java.net.Socket): Unit = conn.use {
            val input = BufferedInputStream(conn.getInputStream())
            val requestLine = readLine(input) ?: return
            val path = requestLine.split(" ").getOrElse(1) { "/" }.substringBefore('?')
            var auth: String? = null
            while (true) {
                val h = readLine(input) ?: break
                if (h.isEmpty()) break
                if (h.lowercase().startsWith("authorization:")) auth = h.substringAfter(':').trim()
            }
            seenAuth[path] = auth ?: NONE
            write(conn.getOutputStream(), FEED.toByteArray())
        }
        private fun readLine(input: BufferedInputStream): String? {
            val sb = StringBuilder(); var prev = -1
            while (true) {
                val b = input.read(); if (b == -1) return if (sb.isEmpty()) null else sb.toString()
                if (prev == '\r'.code && b == '\n'.code) { sb.setLength(sb.length - 1); return sb.toString() }
                sb.append(b.toChar()); prev = b
            }
        }
        private fun write(out: OutputStream, body: ByteArray) {
            out.write("HTTP/1.1 200 X\r\nContent-Type: application/atom+xml\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n".toByteArray())
            out.write(body); out.flush()
        }
        fun stop() { running = false; socket.close() }
    }

    private lateinit var server: FakeServer
    @Before fun setUp() { server = FakeServer() }
    @After fun tearDown() = server.stop()

    private fun base() = "http://127.0.0.1:${server.port}"  // 127.0.0.1 = local → Basic allowed over http

    @Test fun sendsBasicAuth_whenSameOrigin() = runBlocking {
        val origin = "http://127.0.0.1:${server.port}"
        OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = origin)
            .fetchFeed("${base()}/opds/root.xml")
        assertTrue("Basic auth sent same-origin", server.seenAuth["/opds/root.xml"]?.startsWith("Basic ") == true)
    }

    @Test fun dropsAuth_onCrossOrigin() = runBlocking {
        // A DIFFERENT local origin (different port) → still passes the cleartext guard, but auth is
        // dropped because the request origin does not match the catalog's authOrigin.
        OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = "http://127.0.0.1:1")
            .fetchFeed("${base()}/opds/root.xml")
        assertNull("no auth to a non-matching origin", basicSeen("/opds/root.xml"))
    }

    @Test fun noAuth_whenNotConfigured() = runBlocking {
        OpdsClient(Dispatchers.Unconfined).fetchFeed("${base()}/opds/root.xml")
        assertNull(basicSeen("/opds/root.xml"))
    }

    @Test fun refusesBasicOverPublicHttp() = runBlocking {
        // A public http host with auth configured → InsecureAuth, never sends the password.
        val client = OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = "http://catalog.public.example")
        val ex = runCatching { client.fetchFeed("http://catalog.public.example/opds") }.exceptionOrNull()
        assertTrue(ex is OpdsError.InsecureAuth)
    }

    @Test fun dropsAuth_onCrossOriginDownload() = runBlocking {
        // The download path is origin-scoped too — a cross-origin acquisition must not carry Basic.
        OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = "http://127.0.0.1:1")
            .download("${base()}/files/book.epub")
        assertNull(basicSeen("/files/book.epub"))
    }

    @Test fun refusesBasic_overSpoofedPrivateHostname() = runBlocking {
        // "10.evil.com" / "192.168.x.evil.com" are PUBLIC hostnames, not private IPs — must be
        // refused (a startsWith("10.") classifier would wrongly leak the credential to them).
        for (host in listOf("http://10.evil.com", "http://192.168.1.1.evil.com", "http://172.16.evil.com")) {
            val ex = runCatching {
                OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = host).fetchFeed("$host/opds")
            }.exceptionOrNull()
            assertTrue("$host must be InsecureAuth", ex is OpdsError.InsecureAuth)
        }
    }

    @Test fun refusesBasic_overOctalAmbiguousOctets() = runBlocking {
        // "010.0.0.1" / "+10.0.0.1" are NOT canonical-decimal private literals — a resolver may read
        // leading-zero octets as octal and route to a public address while the textual origin still
        // looks private. Must be refused.
        for (host in listOf("http://010.0.0.1", "http://10.0.0.01", "http://192.0168.1.1")) {
            val ex = runCatching {
                OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = host).fetchFeed("$host/opds")
            }.exceptionOrNull()
            assertTrue("$host must be InsecureAuth", ex is OpdsError.InsecureAuth)
        }
    }

    @Test fun allowsBasic_overPrivateIpLiterals() = runBlocking {
        // Real private/loopback IPv4 literals (incl. the emulator host 10.0.2.2) pass the cleartext
        // guard. Pointed at the live test server (a different origin) → no InsecureAuth, request runs;
        // auth is simply dropped because the request origin differs.
        for (origin in listOf("http://10.0.2.2:8080", "http://192.168.1.20:8080", "http://172.16.0.5", "http://127.0.0.1:1")) {
            OpdsClient(Dispatchers.Unconfined, username = "reader", password = "pw", authOrigin = origin)
                .fetchFeed("${base()}/opds/root.xml")  // no throw = guard allowed it
        }
        assertNull(basicSeen("/opds/root.xml"))
    }

    /** The Authorization header for [path], or null if none was sent. */
    private fun basicSeen(path: String): String? = server.seenAuth[path].takeUnless { it == server.NONE }

    private companion object {
        const val FEED = """<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom"><title>T</title><id>i</id></feed>"""
    }
}
