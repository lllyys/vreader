---
branch: feat/feature-116-wi-6-roundtrip
threadId: 019ee5be-wi6
rounds: 3
final_verdict: ship-as-is
date: 2026-06-20
---

# Codex audit — feature #116 WI-6 (live round-trip + the XXE parser fix it caught)

Scope: `android/app/.../backup/net/WebDavClient.kt` (multistatus XXE hardening, reworked after the
live connected test caught an Android-runtime break), `scripts/run-webdav-roundtrip.sh`, and
`app/src/androidTest/.../WebDavRoundTripConnectedTest.kt`.

## What the live test caught

The WI-1 XXE hardening made `setFeature("disallow-doctype-decl", true)` REQUIRED (fail-closed).
The WI-6 **live connected test** (real `WebDavClient` against `rclone serve webdav` on the emulator)
failed with `SAXNotRecognizedException` — Android's `org.apache.harmony` SAX parser doesn't
recognise that feature, so **every PROPFIND threw on device**. The Robolectric/JVM unit tests (Xerces)
never saw this — a textbook case for the device gate.

## The fix, audited over 3 rounds

| round | finding | severity | resolution |
|---|---|---|---|
| 1 | `resolveEntity` no-op stops external-entity disclosure but NOT internal entity expansion (billion-laughs in an inline DTD opens no external URI). | High | Added a parser-independent **fail-closed DOCTYPE ban** before parsing (WebDAV multistatus never carries a DTD); kept `resolveEntity` as defence-in-depth + best-effort feature flags (no longer required → no Android break). |
| 2 | The DOCTYPE ban scanned UTF-8 bytes, but the byte-fed parser honours the XML encoding → a UTF-16 `<!DOCTYPE` could slip past the UTF-8 scan and still be parsed. | High | Feed the parser a fixed **UTF-8 `Reader`** (`InputSource(bytes.inputStream().reader(UTF_8))`) — SAX uses the character stream and ignores the encoding declaration, so the parser's view == the scan's view. A non-UTF-8 body becomes unparseable, not a bypass. |
| 3 | — | — | Codex confirmed: external entities need a DTD (banned), internal expansion needs a DTD (banned), `resolveEntity` is secondary defence, UTF-8 character-stream parsing removes the encoding desync. **No new issues; fully resolved.** |

Tests added: `internalEntityExpansion_isRejected`, `utf16Doctype_cannotBypassTheScan` (JVM); the
`xxe_doctype_doesNotLeak` test now asserts the DTD is rejected outright.

Verdict: **ship-as-is.** The live round-trip (`scripts/run-webdav-roundtrip.sh`) passes on
emulator-5554 against rclone after the fix; 11 `WebDavClientTest` (JVM) green.
