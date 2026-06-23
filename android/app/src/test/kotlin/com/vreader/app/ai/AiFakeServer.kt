package com.vreader.app.ai

import java.io.BufferedInputStream
import java.io.OutputStream
import java.net.ServerSocket
import java.util.concurrent.ConcurrentHashMap
import kotlin.concurrent.thread

/**
 * A hand-rolled HTTP/1.1 fake for the AI provider JVM tests (plain JVM, no Robolectric). Responds
 * to `POST <path>` with a canned status + body; captures the request body so tests can assert the
 * request shape. SSE bodies are sent with Content-Length + Connection: close (the provider reads
 * lines to EOF, which a complete body satisfies).
 */
class AiFakeServer {
    class Response(val status: Int, val body: String = "", val contentType: String = "application/json")

    private val socket = ServerSocket(0)
    val port get() = socket.localPort
    val handlers = ConcurrentHashMap<String, (String) -> Response>()  // "POST /path" -> (body)->Response
    val lastBody = ConcurrentHashMap<String, String>()
    @Volatile private var running = true

    init {
        thread(isDaemon = true) {
            while (running) {
                val conn = try { socket.accept() } catch (e: Exception) { break }
                thread(isDaemon = true) { handle(conn) }
            }
        }
    }

    fun baseUrl() = "http://127.0.0.1:$port"
    fun stop() { running = false; socket.close() }

    private fun handle(conn: java.net.Socket) = conn.use {
        val input = BufferedInputStream(conn.getInputStream())
        val requestLine = readLine(input) ?: return
        val parts = requestLine.split(" ")
        val method = parts[0]; val path = parts.getOrElse(1) { "/" }
        var len = 0
        while (true) {
            val h = readLine(input) ?: break
            if (h.isEmpty()) break
            if (h.lowercase().startsWith("content-length:")) len = h.substringAfter(":").trim().toInt()
        }
        val body = if (len > 0) ByteArray(len).also { readFully(input, it) }.toString(Charsets.UTF_8) else ""
        val key = "$method ${path.substringBefore('?')}"
        lastBody[key] = body
        val resp = (handlers[key] ?: handlers["$method *"])?.invoke(body) ?: Response(404)
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
        val bytes = r.body.toByteArray(Charsets.UTF_8)
        val sb = StringBuilder("HTTP/1.1 ${r.status} X\r\n")
        sb.append("Content-Type: ${r.contentType}\r\n")
        sb.append("Content-Length: ${bytes.size}\r\n")
        sb.append("Connection: close\r\n\r\n")
        out.write(sb.toString().toByteArray()); out.write(bytes); out.flush()
    }
}
