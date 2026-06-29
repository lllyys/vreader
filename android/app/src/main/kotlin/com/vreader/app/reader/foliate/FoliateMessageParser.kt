// Purpose: parse the `{name, detail}` wire JSON the foliate-js bundle posts over the WebView bridge
// into a typed [FoliateMessage]. Pure + side-effect-free so it is fully JVM-unit-testable (no WebView).
// Uses kotlinx.serialization (the module convention, cf. ReadiumLocatorBridge) — NOT org.json, which
// is a throwing stub under JVM unit tests. Feature #126 WI-2.
package com.vreader.app.reader.foliate

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject

object FoliateMessageParser {

    private val json = Json { ignoreUnknownKeys = true; isLenient = true }

    /**
     * Parse one bridge message. Returns `null` for input that isn't a usable message — non-JSON,
     * not an object, or missing/empty `name` — so a malformed/hostile payload degrades to "ignored"
     * rather than throwing into the WebView callback. Unknown-but-valid names map to [FoliateMessage.Other].
     */
    fun parse(raw: String): FoliateMessage? {
        val root = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return null
        val name = root.str("name") ?: return null
        val detail = (root["detail"] as? JsonObject) ?: JsonObject(emptyMap())
        return when (name) {
            "bridge-ready" -> FoliateMessage.BridgeReady
            "book-ready" -> FoliateMessage.BookReady(
                title = detail.str("title"),
                sectionTotal = detail.int("sections") ?: detail.int("sectionTotal") ?: 0,
            )
            "relocate" -> FoliateMessage.Relocate(
                cfi = detail.str("cfi"),
                fraction = detail.dbl("fraction"),
                sectionIndex = detail.int("sectionIndex") ?: 0,
                sectionTotal = detail.int("sectionTotal") ?: 1,
            )
            "error" -> FoliateMessage.Error(
                message = detail.str("message") ?: "unknown",
                type = detail.str("type"),
            )
            else -> FoliateMessage.Other(name)
        }
    }

    private fun JsonObject.prim(key: String): JsonPrimitive? = this[key] as? JsonPrimitive

    /** Non-blank string content, or null (treats JSON null / blank / non-string as absent). */
    private fun JsonObject.str(key: String): String? =
        prim(key)?.takeIf { it.isString }?.content?.takeIf { it.isNotBlank() }

    /** Integer from a JSON number, or null. A quoted numeric STRING ("3") is NOT accepted. */
    private fun JsonObject.int(key: String): Int? =
        prim(key)?.takeUnless { it.isString }?.intOrNull

    /** FINITE double from a JSON number, or null. Quoted strings ("0.5", "NaN", "Infinity") and
     *  non-finite values are rejected — a hostile book must not corrupt the fraction resume anchor. */
    private fun JsonObject.dbl(key: String): Double? =
        prim(key)?.takeUnless { it.isString }?.doubleOrNull?.takeIf { it.isFinite() }
}
