---
branch: feat/feature-116-wi-5a-server-store
threadId: 019ee58a-wi5a
rounds: 1
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-5a (WebDavServerStore + SecretCipher)

Scope: `android/app/.../backup/net/SecretCipher.kt` (interface + AndroidKeyStore AES-256-GCM impl),
`.../backup/net/WebDavServerStore.kt` (DataStore-backed server profiles, password kept only as a
cipher token), the DataStore dependency, and `WebDavServerStoreTest.kt`.

## Round 1 — NO findings

Codex verified the audit scope and found no real defects:

- **Crypto** — `AES/GCM/NoPadding` with a generated AES-256 AndroidKeyStore key; randomized 12-byte
  IV per encrypt (from `Cipher.init(ENCRYPT_MODE)`), `iv ‖ ciphertext` framing + base64, 128-bit tag
  on decrypt. The key is generated inside AndroidKeyStore → non-exportable. No IV-reuse / fixed-IV bug.
- **Store** — the read-modify-write runs inside `DataStore.edit {}`, which DataStore serializes, so
  concurrent upserts don't lose updates via stale external reads. JSON decode failures collapse to
  `emptyList()` (no crash on corrupt prefs). `password = null` keeps the existing ciphertext and
  rejects a brand-new id. Only encrypted password tokens are persisted/returned. Plaintext username
  in DataStore is acceptable per the plan (only the password requires encryption).

Verdict: **ship-as-is.** (6 JVM `WebDavServerStoreTest` with a temp DataStore + reversible fake
cipher + full `:app` suite green. `KeystoreSecretCipher` is exercised on-device in WI-6 — AndroidKeyStore
isn't available under Robolectric.)
