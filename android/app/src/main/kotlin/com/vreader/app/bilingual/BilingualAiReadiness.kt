// Purpose: feature #131 WI-4a — the Android bilingual AI-readiness gate. Drives the
// setup-sheet engine strip's configured/unconfigured state. Readiness = an ACTIVE
// provider profile exists AND its API key decrypts to a NON-EMPTY string. Deriving
// from `profiles.isEmpty()` alone is WRONG: the store keeps a separate `activeId`
// that can be null WITH profiles present (AiProviderSnapshot.active), and key
// usability depends on decrypting the active profile's cipher token
// (AiProviderStore.apiKey). A cipher/keystore failure maps to NOT-ready, never a
// crash (the decrypt is wrapped in runCatching → false).
//
// This is EXACTLY the #118 gate — provider (active) + key (decrypts non-empty).
// Android has NO consent manager and NO feature flag (unlike iOS #82's 4-gate
// readiness), so this gate is provider+key only; no consent/flag component.
//
// @coordinates-with: com.vreader.app.ai.AiProviderStore / AiProviderSnapshot,
//   dev-docs/plans/20260710-feature-131-android-bilingual-interlinear.md (WI-4a)
package com.vreader.app.bilingual

import com.vreader.app.ai.AiProviderSnapshot
import com.vreader.app.ai.AiProviderStore
import kotlinx.coroutines.CancellationException

/**
 * Resolves whether bilingual translation can run given a provider [snapshot]. Holds
 * the [store] only to decrypt the active profile's key; the snapshot is passed in so
 * the caller controls when it was read (snapshot-consistency with the prefetcher).
 */
class BilingualAiReadiness(private val store: AiProviderStore) {

    /**
     * True iff [snapshot] has an active profile whose API key decrypts to a non-empty
     * string. No active profile → false; empty decrypted key → false; a cipher/decrypt
     * throw → false (never propagated). Pure w.r.t. the snapshot — no live store read.
     */
    fun resolve(snapshot: AiProviderSnapshot): Boolean {
        val active = snapshot.active ?: return false
        // Explicit try/catch (not a bare runCatching) so a CancellationException is never
        // swallowed as "not ready" — the decrypt is synchronous today, but the discipline
        // is the gate. Any other cipher/keystore failure → not-ready, never a crash.
        return try {
            store.apiKey(active).isNotEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (_: Throwable) {
            false
        }
    }
}
