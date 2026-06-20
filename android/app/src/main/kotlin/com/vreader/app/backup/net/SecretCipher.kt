// Purpose: feature #116 WI-5 (#110 Phase 3) — symmetric encryption for WebDAV passwords at rest.
// The store keeps a password only as a SecretCipher token (never plaintext); the production
// impl wraps an AndroidKeyStore AES-GCM key (hardware-backed where available, non-exportable),
// chosen over EncryptedSharedPreferences (deprecated AndroidX Security-Crypto — Gate-2 Low-2).
// The interface lets WebDavServerStore be unit-tested with a fake (AndroidKeyStore isn't
// available under Robolectric/JVM).
package com.vreader.app.backup.net

import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyStore
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** Reversibly protects a secret string. [encrypt]/[decrypt] round-trip; the token is opaque. */
interface SecretCipher {
    fun encrypt(plaintext: String): String
    fun decrypt(token: String): String
}

/**
 * AES-256-GCM via a non-exportable AndroidKeyStore key. The token is base64( iv ‖ ciphertext ),
 * a fresh random IV per encryption (GCM requirement). Not unit-testable under Robolectric (no
 * AndroidKeyStore); exercised on-device in WI-6.
 */
class KeystoreSecretCipher(private val alias: String = DEFAULT_ALIAS) : SecretCipher {
    override fun encrypt(plaintext: String): String {
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val iv = cipher.iv
        val ct = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return Base64.getEncoder().encodeToString(iv + ct)
    }

    override fun decrypt(token: String): String {
        val blob = Base64.getDecoder().decode(token)
        val iv = blob.copyOfRange(0, IV_BYTES)
        val ct = blob.copyOfRange(IV_BYTES, blob.size)
        val cipher = Cipher.getInstance(TRANSFORMATION)
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(TAG_BITS, iv))
        return String(cipher.doFinal(ct), Charsets.UTF_8)
    }

    private fun key(): SecretKey {
        val ks = KeyStore.getInstance(KEYSTORE).apply { load(null) }
        (ks.getEntry(alias, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, KEYSTORE)
        gen.init(
            KeyGenParameterSpec.Builder(
                alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return gen.generateKey()
    }

    companion object {
        const val DEFAULT_ALIAS = "vreader.webdav.password"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val TRANSFORMATION = "AES/GCM/NoPadding"
        private const val IV_BYTES = 12
        private const val TAG_BITS = 128
    }
}
