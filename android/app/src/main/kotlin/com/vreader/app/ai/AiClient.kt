// Purpose: feature #118 WI-2 (#110 Phase 3) — the AI client seam + the shared HTTP/SSE plumbing.
// `AiClient` mirrors iOS `AIProvider` (stream + one-shot + test-connection); `BaseHttpAiClient` owns
// the POST-over-HttpURLConnection transport (the #116/#117 precedent), the typed-error mapping, the
// bounded streaming loop (cancellation disconnects), and a bounded one-shot read. The provider
// concretes supply only the endpoint path, auth headers, request body, and the per-wire payload
// parse (OpenAI vs Anthropic). The API key + auth headers are NEVER logged.
package com.vreader.app.ai

import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.job
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream
import java.net.HttpURLConnection
import java.net.SocketTimeoutException
import java.net.URL
import kotlin.coroutines.coroutineContext

interface AiClient {
    /** Streamed assistant text deltas. Cancelling the collector disconnects the HTTP stream. */
    fun streamChat(request: AiRequest): Flow<AiChunk>
    /** One-shot (non-streamed) completion. */
    suspend fun chat(request: AiRequest): AiResponse
    /** A tiny ping → Ok / typed Fail (the editor's Connection section). */
    suspend fun testConnection(): AiTestResult
}

/** A parsed SSE delta: incremental [text] (or null if this event carries none) + a [done] sentinel. */
data class DeltaParse(val text: String?, val done: Boolean)

abstract class BaseHttpAiClient(
    protected val baseUrl: String,
    protected val apiKey: String,
    protected val model: String,
    protected val temperature: Double,
    protected val maxTokens: Int,
    private val dispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val connectTimeoutMs: Int = 15_000,
    private val readTimeoutMs: Int = 60_000,
) : AiClient {

    protected abstract val endpointPath: String
    protected abstract fun applyAuth(conn: HttpURLConnection)
    protected abstract fun requestBody(request: AiRequest, stream: Boolean): String
    protected abstract fun parseDelta(event: SseEvent): DeltaParse
    protected abstract fun parseOneShot(json: String): String

    final override fun streamChat(request: AiRequest): Flow<AiChunk> = flow {
        val conn = openPost(requestBody(request, stream = true))
        // Disconnect PROMPTLY on cancellation — otherwise a blocking reader.read() inside the
        // Sequence wouldn't honour cancel until readTimeout (up to 60s). Closing the socket makes
        // the blocked read throw, unwinding immediately.
        val onCancel = coroutineContext.job.invokeOnCompletion { runCatching { conn.disconnect() } }
        try {
            checkStatus(conn)
            var emitted = 0
            var sawTerminal = false
            for (ev in SseEventReader.events(conn.inputStream)) {
                coroutineContext.ensureActive()
                val d = parseDelta(ev)
                if (d.done) { sawTerminal = true; break }
                val text = d.text ?: continue
                emitted += text.length
                if (emitted > MAX_ANSWER_CHARS) throw AiError.Stream("answer exceeds the length limit")
                emit(AiChunk(text))
            }
            // EOF before the terminal sentinel ([DONE] / message_stop) = a dropped/truncated stream,
            // not a clean finish — surface it rather than returning a silent partial answer.
            if (!sawTerminal) { coroutineContext.ensureActive(); throw AiError.Stream("stream ended before its terminal event") }
        } finally {
            onCancel.dispose()
            conn.disconnect()
        }
    }.flowOn(dispatcher)

    final override suspend fun chat(request: AiRequest): AiResponse = withContext(dispatcher) {
        val conn = openPost(requestBody(request, stream = false))
        // Same prompt-cancellation guard as streamChat — a blocking one-shot read shouldn't hang to
        // readTimeout if the caller cancels.
        val onCancel = coroutineContext.job.invokeOnCompletion { runCatching { conn.disconnect() } }
        try {
            checkStatus(conn)
            AiResponse(parseOneShot(conn.inputStream.readBoundedText(MAX_ONESHOT_BYTES)))
        } finally {
            onCancel.dispose()
            conn.disconnect()
        }
    }

    final override suspend fun testConnection(): AiTestResult = try {
        chat(AiRequest(model, listOf(AiMessage(AiRole.user, "ping")), temperature, maxTokens = 8))
        AiTestResult.Ok
    } catch (e: AiError) {
        AiTestResult.Fail(e, e.message ?: "connection failed")
    }

    // ── transport ─────────────────────────────────────────────

    private fun openPost(body: String): HttpURLConnection {
        // Path-dedup (iOS Bug #185): if the base already ends with the endpoint, don't append again.
        val base = baseUrl.trim().trimEnd('/')
        val full = if (base.endsWith(endpointPath)) base else base + endpointPath
        val url = runCatching { URL(full) }.getOrNull() ?: throw AiError.Config("invalid base URL")
        requireSafeScheme(url)  // never send the key over cleartext to a remote host
        val conn = try { url.openConnection() as HttpURLConnection } catch (e: Exception) { throw AiError.Offline }
        try {
            conn.requestMethod = "POST"
            conn.connectTimeout = connectTimeoutMs
            conn.readTimeout = readTimeoutMs
            conn.instanceFollowRedirects = false  // never let HUC silently re-POST/forward the key on a 3xx
            conn.setRequestProperty("Content-Type", "application/json")
            conn.setRequestProperty("Accept", "text/event-stream")
            applyAuth(conn)  // NEVER logged
            conn.doOutput = true
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            return conn
        } catch (e: SocketTimeoutException) {
            conn.disconnect(); throw AiError.Timeout
        } catch (e: IOException) {
            conn.disconnect(); throw AiError.Offline
        }
    }

    /** Map the response status; a 2xx returns, anything else throws a typed error (error body is
     *  bounded-discarded, never fully read). */
    private fun checkStatus(conn: HttpURLConnection) {
        val status = try {
            conn.responseCode
        } catch (e: SocketTimeoutException) {
            throw AiError.Timeout
        } catch (e: IOException) {
            throw AiError.Offline
        }
        if (status / 100 == 2) return
        // Do NOT read the error body — it could block/throw and mask the known status; disconnect
        // (in the caller's finally) tears the connection down.
        throw when (status) {
            401, 403 -> AiError.Auth401
            429 -> AiError.RateLimited429
            else -> AiError.Http(status)
        }
    }

    /** Refuse to send the API key over cleartext http:// to a non-local host (https required;
     *  loopback / the emulator host alias are allowed for local dev + tests). */
    private fun requireSafeScheme(url: URL) {
        if (url.protocol.equals("https", ignoreCase = true)) return
        val host = url.host
        val local = host == "127.0.0.1" || host == "::1" || host.equals("localhost", true) || host == "10.0.2.2"
        if (url.protocol.equals("http", ignoreCase = true) && local) return
        throw AiError.InsecureUrl
    }

    /** Accumulate the bounded body as BYTES, then decode UTF-8 ONCE — so a multibyte (CJK)
     *  character split across a read boundary isn't corrupted. */
    private fun InputStream.readBoundedText(max: Long): String {
        val out = ByteArrayOutputStream()
        val buf = ByteArray(16 * 1024)
        var total = 0L
        use {
            while (true) {
                val n = read(buf)
                if (n < 0) break
                total += n
                if (total > max) throw AiError.Decode("response exceeds the size limit")
                out.write(buf, 0, n)
            }
        }
        return out.toString("UTF-8")
    }

    protected companion object {
        const val MAX_ANSWER_CHARS = 200_000
        const val MAX_ONESHOT_BYTES = 4L * 1024 * 1024
    }
}
