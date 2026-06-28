// Purpose: feature #123 — the engine-precise anchor for a highlight/note, serialized into the
// entity's `anchorJSON` (the canonical `Locator` lives in `locatorJSON`). Mirrors the iOS
// `AnnotationAnchor` field shape for cross-platform durability: a Text anchor (TXT/MD, #124) carries
// `sourceUnitId` + UTF-16 range; an Epub anchor carries `href` + Readium `cfi` + an optional
// serialized DOM range. `anchorHash` (SHA-256 of the canonical JSON) is the dedupe discriminant
// (`anchorKey = anchorHash ?: "__nil_anchor__"`).
package com.vreader.app.annotations

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import java.security.MessageDigest

/** A serialized DOM range for an EPUB anchor (mirrors iOS `EPUBSerializedRange`). Null when Readium
 *  exposes only a CFI (the CFI is then the durable anchor). */
@Serializable
data class EpubSerializedRange(
    val startContainerPath: String,
    val startOffset: Int,
    val endContainerPath: String,
    val endOffset: Int,
)

@Serializable
sealed interface AnnotationAnchor {
    @Serializable
    @SerialName("text")
    data class Text(val sourceUnitId: String, val startUTF16: Int, val endUTF16: Int) : AnnotationAnchor

    @Serializable
    @SerialName("epub")
    data class Epub(val href: String, val cfi: String, val serializedRange: EpubSerializedRange? = null) : AnnotationAnchor

    /** SHA-256 (hex) of the canonical JSON — the dedupe discriminant. Locally deterministic
     *  (kotlinx fixed field order), the same basis as `VReaderLocator.canonicalHash`. */
    val anchorHash: String
        get() = AnnotationHashing.sha256Hex(CANONICAL_JSON.encodeToString(this))

    companion object {
        private val CANONICAL_JSON = Json { encodeDefaults = true; classDiscriminator = "kind" }

        fun encode(anchor: AnnotationAnchor): String = CANONICAL_JSON.encodeToString(anchor)
        fun decodeOrNull(json: String?): AnnotationAnchor? =
            json?.let { runCatching { CANONICAL_JSON.decodeFromString<AnnotationAnchor>(it) }.getOrNull() }
    }
}

/** Small SHA-256 hex helper shared by the annotation domain (profileKey + anchorKey derivation). */
object AnnotationHashing {
    fun sha256Hex(input: String): String =
        MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it) }
}
