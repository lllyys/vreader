// Purpose: feature #113 WI-2 (#110 Phase 3) — the type-tagged settings value used by the
// `settings` backup section. Mirrors Swift `BackupDefaultsValue` (a `{type, value}` union)
// so a UserDefaults snapshot of mixed types round-trips faithfully. `data` is base64
// (Swift `Data` JSON encoding).
package vreader.contracts.backup

import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.JsonDecoder
import kotlinx.serialization.json.JsonEncoder
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.long
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.Base64

/** A type-tagged UserDefaults value — mirrors Swift `BackupDefaultsValue` (`{type, value}`). */
@Serializable(BackupDefaultsValueSerializer::class)
sealed class BackupDefaultsValue {
    data class Bool(val value: Boolean) : BackupDefaultsValue()
    /** 64-bit — Swift `Int` is `Int64` on iOS; a UserDefaults value can exceed 32-bit. */
    data class IntValue(val value: Long) : BackupDefaultsValue()
    data class DoubleValue(val value: Double) : BackupDefaultsValue()
    data class Str(val value: String) : BackupDefaultsValue()
    class DataValue(val value: ByteArray) : BackupDefaultsValue() {
        override fun equals(other: Any?): Boolean =
            other is DataValue && value.contentEquals(other.value)
        override fun hashCode(): Int = value.contentHashCode()
    }
}

/** Encodes/decodes the Swift `{type: "bool"|"int"|"double"|"string"|"data", value: …}` union.
 *  `data`'s value is a base64 String (Swift `Data`). JSON-only (casts to Json{En,De}coder). */
object BackupDefaultsValueSerializer : KSerializer<BackupDefaultsValue> {
    override val descriptor: SerialDescriptor =
        buildClassSerialDescriptor("vreader.backup.BackupDefaultsValue")

    override fun serialize(encoder: Encoder, value: BackupDefaultsValue) {
        val json = encoder as? JsonEncoder
            ?: error("BackupDefaultsValue is JSON-only")
        val obj = buildJsonObject {
            when (value) {
                is BackupDefaultsValue.Bool -> { put("type", "bool"); put("value", value.value) }
                is BackupDefaultsValue.IntValue -> { put("type", "int"); put("value", value.value) }
                is BackupDefaultsValue.DoubleValue -> { put("type", "double"); put("value", value.value) }
                is BackupDefaultsValue.Str -> { put("type", "string"); put("value", value.value) }
                is BackupDefaultsValue.DataValue ->
                    { put("type", "data"); put("value", Base64.getEncoder().encodeToString(value.value)) }
            }
        }
        json.encodeJsonElement(obj)
    }

    override fun deserialize(decoder: Decoder): BackupDefaultsValue {
        val json = decoder as? JsonDecoder ?: error("BackupDefaultsValue is JSON-only")
        val obj = json.decodeJsonElement().jsonObject
        val type = obj.getValue("type").jsonPrimitive.content
        val v = obj.getValue("value")
        return when (type) {
            "bool" -> BackupDefaultsValue.Bool(v.jsonPrimitive.boolean)
            "int" -> BackupDefaultsValue.IntValue(v.jsonPrimitive.long)
            "double" -> BackupDefaultsValue.DoubleValue(v.jsonPrimitive.double)
            "string" -> BackupDefaultsValue.Str(v.jsonPrimitive.content)
            "data" -> BackupDefaultsValue.DataValue(Base64.getDecoder().decode(v.jsonPrimitive.content))
            else -> error("unknown BackupDefaultsValue type: $type")
        }
    }
}
