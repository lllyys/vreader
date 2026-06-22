---
branch: feat/feature-118-wi-1-ai-provider-store
threadId: 019eeb6c-f118wi1
rounds: 1
final_verdict: ship-as-is
date: 2026-06-22
---

# Codex audit — feature #118 WI-1 (AiProviderKind + AiProviderProfile + AiProviderStore)

Scope: `android/app/.../ai/AiProviderKind.kt`, `.../ai/AiProviderStore.kt`, and tests. AI provider
config + active selection, API key kept only as a `SecretCipher` token (reuses the #116
DataStore + `KeystoreSecretCipher` pattern).

## Round 1 — 2 findings (1 Medium / 1 Low)

| file:line | severity | issue | resolution |
|---|---|---|---|
| AiProviderStore.kt (apiKey) | Medium | `apiKey(id)` re-read live DataStore, so a request that captured `snapshot()` at start could pair snapshot metadata with a later-edited/deleted key — violating the request-start consistency contract. | FIXED — added `apiKey(profile: AiProviderProfile)` that decrypts from the CAPTURED profile's token (no live read); the chat/test request path uses this with a single snapshot. The id-based live read remains for non-request UI flows, documented as such. |
| AiProviderKind.kt | Low | The serialized enum name was `openAiCompatible`, but iOS `ProviderKind`'s raw value is `openAICompatible` — breaking the stated persisted parity (the enum is serialized inside the store JSON). | FIXED — `@Serializable` + `@SerialName("openAICompatible")` on the case (Kotlin identifier stays camelCase; the persisted value matches iOS). Test now asserts the serialized form. |

Both fixes are mechanical and match Codex's prescribed remedy exactly; 9 JVM tests
(`AiProviderStoreTest` 6 + `AiProviderKindTest` 3) green after.

Verdict: **ship-as-is.** Active-id semantics (first→active, delete-active→reselect, setActive
no-op on absent), edit-with-null-key, new-id-requires-key, plaintext-never-persisted, and
corrupt-JSON resilience all verified.
