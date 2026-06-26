---
branch: feat/feature-120-wi-1-opds-source-store
threadId: 019f0405-1291-7682-a91b-ee9441609400
rounds: 2
final_verdict: ship-as-is
date: 2026-06-26
---

# Feature #120 WI-1 — Codex audit (OPDS optional Basic auth + saved-source store)

Changed files audited:
- `android/app/src/main/kotlin/com/vreader/app/opds/OpdsClient.kt` — origin-scoped Basic auth.
- `android/app/src/main/kotlin/com/vreader/app/opds/OpdsModels.kt` — `OpdsError.InsecureAuth`.
- `android/app/src/main/kotlin/com/vreader/app/opds/OpdsSourceStore.kt` — NEW DataStore source store.
- `android/app/src/test/kotlin/com/vreader/app/opds/OpdsClientAuthTest.kt`
- `android/app/src/test/kotlin/com/vreader/app/opds/OpdsSourceStoreTest.kt`

Security contract: a Basic credential is sent ONLY same-origin (scheme+host+port) with the
catalog's `authOrigin` (so a cross-origin redirect/acquisition never leaks it); Basic is refused
over cleartext http to a public host (allowed only over https OR a private/loopback IPv4 literal);
the password is kept at rest ONLY as a `SecretCipher` token under a distinct alias and is never
logged.

## Round 1

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsClient.kt (isSecureOrLocal) | Medium | `startsWith("10.")` / `startsWith("192.168.")` matched HOSTNAMES like `10.evil.com` → Basic leaked cleartext to an attacker host | FIXED — replaced with `isPrivateIpv4()` requiring exactly 4 numeric octets in canonical range; hostnames no longer classify as local; IPv6 brackets stripped; `localhost`/`::1` explicit |
| OpdsClientAuthTest.kt | Medium | tests missed spoofed-private-hostname + cross-origin download paths | FIXED — added `dropsAuth_onCrossOriginDownload`, `refusesBasic_overSpoofedPrivateHostname`, `allowsBasic_overPrivateIpLiterals` |
| OpdsSourceStore.kt:80 (clientFor) | Low | decrypted `encryptedPassword` before confirming a usable username → a corrupt/stale token on a username-less source would throw | FIXED — decrypt only when `user != null` |

Confirmed clean in round 1: no plaintext-at-rest (`upsert` writes only the cipher token; auth-off
clears username+token); origin scoping on redirects/downloads structurally correct
(`instanceFollowRedirects=false` + `applyAuth()` runs per manually-followed request).

## Round 2

| file:line | severity | issue | resolution |
|---|---|---|---|
| OpdsClient.kt (isPrivateIpv4) | Medium | `toIntOrNull()` accepted octal-ambiguous/​signed octets (`010.0.0.1`, `+10.0.0.1`) → a resolver reading leading-zero octets as octal could route to a public address while the textual origin still looked private, carrying Basic | FIXED — added `canonicalOctet()`: ASCII digits only, length ≤3, no leading zero except `"0"`, no sign; added `refusesBasic_overOctalAmbiguousOctets` test |

Round-2 verdict: round-1 issues otherwise resolved (spoofed private hostnames refused, cross-origin
downloads drop auth, `clientFor` no longer decrypts without a username). The octal-octet finding was
the only new issue; it is fixed + covered by a test.

## Summary

All Critical/High/Medium/Low findings across 2 rounds are resolved and covered by tests. The
origin-scoped Basic-auth credential never escapes the catalog origin (verified for fetch + download +
redirect) and is refused over cleartext to anything but a canonical private/loopback IPv4 literal or
https. **Verdict: ship-as-is.**
