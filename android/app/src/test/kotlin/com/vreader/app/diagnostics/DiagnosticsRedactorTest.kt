package com.vreader.app.diagnostics

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Feature #164 WI-2b — the feature's security gate.
 *
 * On Android logcat is plaintext with no `privacy:` barrier, so [DiagnosticsRedactor] is the ONLY
 * thing standing between a captured log entry and a share sheet / clipboard. Every vector below is
 * drawn from a real credential path in this app (`WebDavClient.authHeader`, `OpdsClient`'s Basic
 * token, `OpenAiCompatibleProvider`, `AnthropicProvider`, `SecretCipher`, `WebDavServerStore`,
 * `AiProviderStore`, `OpdsSourcesViewModel.TestSignature`, `BookImporter`).
 *
 * The oracle is deliberately strict, because a redactor test is the classic place to pass for free:
 *  - every security vector asserts the EXACT output, not just "the secret is absent" — a substring
 *    check silently accepts a surviving suffix whenever a delimiter splits the credential;
 *  - [check] asserts each secret was genuinely present BEFORE redaction, so a mistyped fixture
 *    cannot make a test pass;
 *  - multi-word secrets are additionally asserted word-by-word, and EVERY secret is asserted
 *    suffix-by-suffix — a partial redaction that eats a prefix and leaves the tail is the exact
 *    failure the previous regex design shipped, and it is stable under re-redaction, so
 *    idempotency cannot see it (pinned by [oracle_idempotencyIsNotACompletenessOracle]);
 *  - assertions are TWO-SIDED — the surrounding diagnostic context (host, scheme, HTTP status,
 *    exception class, entity id) must SURVIVE. A redactor that destroys diagnosability fails too.
 *
 * Test names carry the scanner branch or shape rule they pin, so the mutation pass (disable one
 * branch, expect a named test to go red) has an unambiguous mapping.
 */
class DiagnosticsRedactorTest {

    private val redacted = DiagnosticsRedactor.PLACEHOLDER
    private val path = DiagnosticsRedactor.PATH_PLACEHOLDER

    /**
     * Asserts the full contract for one vector: pre-redaction presence, exact output, secret
     * absence (whole, per-word AND per-suffix), context survival, and idempotency.
     */
    private fun check(
        input: String,
        expected: String,
        secrets: List<String>,
        context: List<String> = emptyList(),
    ) {
        secrets.forEach {
            assertTrue(
                "fixture bug: input does not actually contain the secret <$it>",
                input.contains(it),
            )
        }
        val out = DiagnosticsRedactor.redact(input)
        assertEquals("exact output", expected, out)
        secrets.forEach { secret ->
            assertFalse("secret <$secret> survived: $out", out.contains(secret))
            // A delimiter inside the secret must not leave a usable fragment behind.
            secret.split(' ').filter { it.length >= 4 }.forEach { word ->
                assertFalse("secret fragment <$word> survived: $out", out.contains(word))
            }
            // A partial redaction leaves a SUFFIX — the previous design's whole failure class.
            for (from in 0..(secret.length - 4)) {
                val tail = secret.substring(from)
                assertFalse("secret suffix <$tail> survived: $out", out.contains(tail))
            }
        }
        context.forEach {
            assertTrue("diagnostic context <$it> was destroyed: $out", out.contains(it))
        }
        assertEquals("redact() must be idempotent", out, DiagnosticsRedactor.redact(out))
    }

    private fun assertUnchanged(input: String) {
        assertEquals("must not be over-redacted", input, DiagnosticsRedactor.redact(input))
    }

    // ================================================================ the four regex survivors
    // Each of these was returned UNCHANGED (or partially redacted) by the 13-rule regex design on
    // `feat/164-wi-2-redactor` after three audit rounds. They are the reason the keyed-value
    // matcher is a scanner and not a pattern.

    @Test
    fun survivor1_arbitrarilyLongSeparatorRunBeforeAScheme_isRedacted() {
        // The regex container class was bounded `{0,8}` and the fallback rule DECLINED whenever it
        // saw a recognised scheme, so a wide separator run fell through BOTH rules. The scanner's
        // separator run is unbounded, so no gap width exists.
        check(
            "Authorization:" + " ".repeat(10) + "Bearer abcdefghijkl -> 401",
            "Authorization:" + " ".repeat(10) + "Bearer $redacted -> 401",
            secrets = listOf("abcdefghijkl"),
            context = listOf("Authorization:", "Bearer", "-> 401"),
        )
        check(
            "Authorization:" + "\t".repeat(40) + "Basic WEtBQTpIRXFrQVdHZFFM",
            "Authorization:" + "\t".repeat(40) + "Basic $redacted",
            secrets = listOf("WEtBQTpIRXFrQVdHZFFM"),
            context = listOf("Authorization:", "Basic"),
        )
    }

    @Test
    fun survivor2_escapedJsonAuthorizationContainer_isRedacted() {
        // The real `OpdsClient` / `WebDavClient` Basic shape inside a nested JSON dump. The regex
        // container class excluded `\`, and `Authorization` was not in the keyed-name set, so this
        // survived ENTIRELY. The scanner's separator run consumes `\"` pairs.
        check(
            """state={\"Authorization\":\"Basic WEtBQTpIRXFrQVdHZFFM\"} -> 401""",
            """state={\"Authorization\":\"Basic $redacted\"} -> 401""",
            secrets = listOf("WEtBQTpIRXFrQVdHZFFM"),
            context = listOf("state=", "Authorization", "Basic", "-> 401"),
        )
        check(
            """req={\"headers\":{\"Authorization\":\"Bearer sk-ant-api03-AbC123def456\"}}""",
            """req={\"headers\":{\"Authorization\":\"Bearer $redacted\"}}""",
            secrets = listOf("sk-ant-api03-AbC123def456"),
            context = listOf("headers", "Authorization", "Bearer"),
        )
    }

    @Test
    fun survivor3_quotedValueContainingTheOtherQuote_isFullyRedacted() {
        // The regex body `[^"'\n\\]*` stopped at the first embedded quote, producing
        // `password=‹redacted›'BrienNeverClose` — a STABLE partial redaction that idempotency
        // cannot detect. The scanner's quote state machine consumes to the MATCHING close, and
        // fails closed to end of line when there is none (logd truncates at 4068 bytes).
        check(
            """password="O'BrienNeverClose""",
            """password="$redacted""",
            secrets = listOf("O'BrienNeverClose"),
            context = listOf("password="),
        )
        check(
            """AiProviderProfile(apiKey='it"s-complicated-9988""",
            """AiProviderProfile(apiKey='$redacted""",
            secrets = listOf("""it"s-complicated-9988"""),
            context = listOf("AiProviderProfile", "apiKey="),
        )
        // Balanced, but the value contains the OTHER quote character throughout.
        check(
            """{"password": "O'Brien's passphrase"} rejected""",
            """{"password": "$redacted"} rejected""",
            secrets = listOf("O'Brien's passphrase"),
            context = listOf("\"password\"", "rejected"),
        )
    }

    @Test
    fun survivor4_unquotedValueContainingStructuralCharacters_isFullyRedacted() {
        // The regex value class excluded `,&)]}` and quotes, so `password=foo,bar` leaked `,bar`.
        // Commas, ampersands and brackets are all legal in a passphrase. The scanner terminates an
        // unquoted value at a structural character ONLY when a NEW key/value pair follows it.
        check(
            "WebDAV auth failed password=hunter2,continued&more)tail",
            "WebDAV auth failed password=$redacted",
            secrets = listOf("hunter2,continued&more)tail"),
            context = listOf("WebDAV auth failed", "password="),
        )
        // …while a genuine following field still survives, which is the whole point of the policy.
        check(
            "ServerDraft(password=hunter2,continued, wifiOnly=true)",
            "ServerDraft(password=$redacted, wifiOnly=true)",
            secrets = listOf("hunter2,continued"),
            context = listOf("ServerDraft", "wifiOnly=true"),
        )
        // A closer that does NOT terminate a field is not a delimiter either — only the one that
        // actually ends the dump is. (The secret avoids the word "word": `password` contains it,
        // and the suffix oracle would fire on the surviving KEY NAME.)
        check(
            "ServerDraft(password=p@ss)Tr0ub4dor)",
            "ServerDraft(password=$redacted)",
            secrets = listOf("p@ss)Tr0ub4dor"),
            context = listOf("ServerDraft", "password="),
        )
    }

    // ================================================================ Authorization container

    @Test
    fun auth_webDavBasicHeader_redactsTokenKeepsSchemeAndStatus() {
        check(
            "WebDAV PROPFIND /remote.php/dav/ -> 401 Unauthorized; sent " +
                "Authorization: Basic dXNlcjpwYXNzd29yZA==",
            "WebDAV PROPFIND /remote.php/dav/ -> 401 Unauthorized; sent " +
                "Authorization: Basic $redacted",
            secrets = listOf("dXNlcjpwYXNzd29yZA=="),
            context = listOf("401 Unauthorized", "/remote.php/dav/", "Authorization: Basic"),
        )
    }

    @Test
    fun auth_openAiBearerHeader_redactsKeyKeepsSchemeAndStatus() {
        check(
            "AI request failed: Authorization: Bearer sk-proj-AbC123def456GHI789jkl -> HTTP 401",
            "AI request failed: Authorization: Bearer $redacted -> HTTP 401",
            secrets = listOf("sk-proj-AbC123def456GHI789jkl"),
            context = listOf("AI request failed", "-> HTTP 401"),
        )
    }

    @Test
    fun auth_serializedJsonHeader_redactsInsideQuotes() {
        check(
            """headers {"Authorization": "Basic YWxpY2U6cHcxMjM="} -> 401""",
            """headers {"Authorization": "Basic $redacted"} -> 401""",
            secrets = listOf("YWxpY2U6cHcxMjM="),
            context = listOf("headers", "\"Authorization\"", "-> 401"),
        )
    }

    @Test
    fun auth_bracketedAndPairContainers_areCoveredByTheSameBranch() {
        // Neither shape is a `key: value` pair, so a header-name-plus-colon rule cannot see them.
        check(
            "headers[Authorization]=Basic dXNlcjpwQHNzIHdvcmQ= -> 401",
            "headers[Authorization]=Basic $redacted -> 401",
            secrets = listOf("dXNlcjpwQHNzIHdvcmQ="),
            context = listOf("headers[Authorization]", "-> 401"),
        )
        check(
            "request=(Authorization, Basic dXNlcjpwQHNzIHdvcmQ=)",
            "request=(Authorization, Basic $redacted)",
            secrets = listOf("dXNlcjpwQHNzIHdvcmQ="),
            context = listOf("Authorization"),
        )
    }

    @Test
    fun auth_allLetterAndShortCredentials_areRedactedBecauseTheBranchIsContextAnchored() {
        // `OpdsClient` base64-encodes `user:pass`, which routinely yields an ALL-LETTER token —
        // an entropy/shape heuristic ("16+ chars containing a digit") lets this real credential
        // through, and over-redacts `Basic SHA256withRSA2048`. Such a heuristic was tried, failed
        // in BOTH directions across two audit rounds, and was deleted. Anchoring on the container
        // removes the need for one.
        check(
            "request=(Authorization, Basic WEtBQTpIRXFrQVdHZFFM)",
            "request=(Authorization, Basic $redacted)",
            secrets = listOf("WEtBQTpIRXFrQVdHZFFM"),
            context = listOf("Authorization"),
        )
        check(
            "Authorization: Bearer abcdefgh -> 401",
            "Authorization: Bearer $redacted -> 401",
            secrets = listOf("abcdefgh"),
            context = listOf("Authorization: Bearer", "-> 401"),
        )
        check(
            "Authorization: Basic YWxpY2U= -> 401",
            "Authorization: Basic $redacted -> 401",
            secrets = listOf("YWxpY2U="),
            context = listOf("Authorization: Basic", "-> 401"),
        )
    }

    @Test
    fun auth_proxyAuthorizationIsTreatedAsTheSameHeaderFamily() {
        check(
            "Proxy-Authorization: Basic cHJveHk6c2VjcmV0OTk5 -> 407",
            "Proxy-Authorization: Basic $redacted -> 407",
            secrets = listOf("cHJveHk6c2VjcmV0OTk5"),
            context = listOf("Proxy-Authorization: Basic", "-> 407"),
        )
    }

    @Test
    fun auth_unknownScheme_redactsWholeHeaderValueToEndOfLine() {
        // A Digest credential is spread across quoted, comma-separated parameters, so anything
        // less than "to end of line" leaks `response=`. Same-line context after such a header is
        // therefore lost BY DESIGN (documented in the class header); adjacent lines survive.
        check(
            "proxy auth failed\n" +
                "Authorization: Digest username=\"alice\", response=deadbeefcafe1234, nonce=abc99\n" +
                "retrying in 2s",
            "proxy auth failed\nAuthorization: $redacted\nretrying in 2s",
            secrets = listOf("deadbeefcafe1234", "nonce=abc99"),
            context = listOf("proxy auth failed", "retrying in 2s"),
        )
    }

    // ================================================================ quoted keyed values

    @Test
    fun quoted_multiWordSecret_consumesToClosingQuote() {
        check(
            """request body {"password": "correct horse battery staple"} rejected""",
            """request body {"password": "$redacted"} rejected""",
            secrets = listOf("correct horse battery staple"),
            context = listOf("request body", "\"password\"", "rejected"),
        )
    }

    @Test
    fun quoted_singleQuotedValue_isRedacted() {
        // Kotlin/Room/OkHttp dumps quote with either character; handling only `"` leaked this.
        check(
            "OPDS test password='p@ss phrase' -> 401",
            "OPDS test password='$redacted' -> 401",
            secrets = listOf("p@ss phrase"),
            context = listOf("OPDS test", "password=", "-> 401"),
        )
    }

    @Test
    fun quoted_escapedQuoteInsideValue_doesNotTerminateEarly() {
        check(
            """ServerDraft(password="p@ss\"Tr0ub4dor", wifiOnly=true)""",
            """ServerDraft(password="$redacted", wifiOnly=true)""",
            secrets = listOf("""p@ss\"Tr0ub4dor"""),
            context = listOf("ServerDraft", "wifiOnly=true"),
        )
    }

    @Test
    fun quoted_secretSpanningNewlines_isFullyRedacted() {
        check(
            "cfg {\"client_secret\": \"line one\nline two\"} loaded",
            """cfg {"client_secret": "$redacted"} loaded""",
            secrets = listOf("line one", "line two"),
            context = listOf("cfg", "client_secret", "loaded"),
        )
    }

    @Test
    fun quoted_truncatedClosingQuote_failsClosedToEndOfLine() {
        // logd truncates a line at 4068 bytes; a balanced-quote rule alone fails OPEN on the
        // truncated remainder, which is exactly the tail a credential sits in.
        check(
            """AiProviderProfile(apiKey="azureOpaqueSecret123""",
            """AiProviderProfile(apiKey="$redacted""",
            secrets = listOf("azureOpaqueSecret123"),
            context = listOf("AiProviderProfile", "apiKey="),
        )
        // …and only to the END OF LINE — a later line is not swallowed.
        check(
            "AiProviderProfile(apiKey=\"azureOpaqueSecret123\nretrying in 2s",
            "AiProviderProfile(apiKey=\"$redacted\nretrying in 2s",
            secrets = listOf("azureOpaqueSecret123"),
            context = listOf("retrying in 2s"),
        )
    }

    @Test
    fun quoted_nestedJsonDumpWithEscapedStructuralQuotes_isRedacted() {
        check(
            """state={\"encryptedApiKey\":\"AAAAFGhlbGxvd29ybGQxMjM0\"}""",
            """state={\"encryptedApiKey\":\"$redacted\"}""",
            secrets = listOf("AAAAFGhlbGxvd29ybGQxMjM0"),
            context = listOf("state=", "encryptedApiKey"),
        )
    }

    // ================================================================ unquoted keyed values

    @Test
    fun unquoted_spacedValueRunsPastWhitespaceToTheNextFieldOnly() {
        // OpdsSourceStore.upsert / WebDavServerStore.upsert take PLAINTEXT passwords and
        // OpdsSourcesViewModel.TestSignature is a data class that prints one unquoted, so a
        // space-containing password in a toString() is real. Whitespace termination would have
        // leaked "horse battery staple".
        check(
            "WebDAV failed password=correct horse battery staple, wifiOnly=true",
            "WebDAV failed password=$redacted, wifiOnly=true",
            secrets = listOf("correct horse battery staple"),
            context = listOf("WebDAV failed", "wifiOnly=true"),
        )
    }

    @Test
    fun unquoted_webDavAuthHeaderProperty_isRedactedIncludingItsScheme() {
        // `authHeader` is the real property name at WebDavClient.kt:71, and its value is
        // `<scheme> <credential>` — it contains a space, so it belongs to the space-bearing class.
        check(
            "WebDavClient authHeader=Basic dXNlcjpwQHNzIHdvcmQ=",
            "WebDavClient authHeader=$redacted",
            secrets = listOf("dXNlcjpwQHNzIHdvcmQ="),
            context = listOf("WebDavClient", "authHeader"),
        )
    }

    @Test
    fun unquoted_camelCaseEncryptedPasswordWithColon_isRedacted() {
        check(
            "WebDavServerStore not decodable encryptedPassword: AAAAFGhlbGxvd29ybGQ5OTk=",
            "WebDavServerStore not decodable encryptedPassword: $redacted",
            secrets = listOf("AAAAFGhlbGxvd29ybGQ5OTk="),
            context = listOf("WebDavServerStore", "not decodable", "encryptedPassword"),
        )
    }

    @Test
    fun unquoted_serializedEntityDump_redactsBlobAndKeepsIdUrlUsername() {
        check(
            "upsert WebDavServerProfile(id=3, url=https://dav.example.com/remote.php/dav/, " +
                "username=alice, encryptedPassword=AAAAFGhlbGxvd29ybGQxMjM=, wifiOnly=true)",
            "upsert WebDavServerProfile(id=3, url=https://dav.example.com/remote.php/dav/, " +
                "username=alice, encryptedPassword=$redacted, wifiOnly=true)",
            secrets = listOf("AAAAFGhlbGxvd29ybGQxMjM="),
            context = listOf("id=3", "dav.example.com", "username=alice", "wifiOnly=true"),
        )
    }

    @Test
    fun unquoted_tokenValueStopsAtWhitespaceSoSameLineContextSurvives() {
        // The class split exists for this: an API key / signature / bearer token has no space in
        // its grammar (it travels in an HTTP header or a query string, where a raw space is
        // illegal), so terminating at a structural delimiter would needlessly destroy the line.
        check(
            "paging token = WEtBQTpIRXFrQVdHZFFM HTTP 401 retrying",
            "paging token = $redacted HTTP 401 retrying",
            secrets = listOf("WEtBQTpIRXFrQVdHZFFM"),
            context = listOf("paging token", "HTTP 401 retrying"),
        )
    }

    @Test
    fun unquoted_anthropicXApiKeyHeader_redactsKeyKeepsHeaderNameAndStatus() {
        check(
            "AnthropicProvider POST /v1/messages header " +
                "x-api-key: sk-ant-api03-AbC123def456 -> HTTP 401",
            "AnthropicProvider POST /v1/messages header x-api-key: $redacted -> HTTP 401",
            secrets = listOf("sk-ant-api03-AbC123def456"),
            context = listOf("x-api-key", "/v1/messages", "-> HTTP 401"),
        )
    }

    @Test
    fun unquoted_queryStringApiKey_redactsValueKeepsHostAndOtherParams() {
        check(
            "at OpenAiCompatibleProvider.post(https://api.example.com/v1/chat" +
                "?api_key=abc123secret&model=gpt-4o) HTTP 401",
            "at OpenAiCompatibleProvider.post(https://api.example.com/v1/chat" +
                "?api_key=$redacted&model=gpt-4o) HTTP 401",
            secrets = listOf("abc123secret"),
            context = listOf("api.example.com", "/v1/chat", "model=gpt-4o", "HTTP 401"),
        )
    }

    @Test
    fun unquoted_signedRedirectUrl_redactsSignatureKeepsHostAndStatus() {
        // WebDavClient follows absolute redirect Locations and embeds the path in exceptions.
        check(
            "WebDavException: 403 https://blob.example/vreader.zip" +
                "?sv=2024-11-04&sig=QWxhZGRpbjpvcGVuIHNlc2FtZQ== retrying",
            "WebDavException: 403 https://blob.example/vreader.zip" +
                "?sv=2024-11-04&sig=$redacted retrying",
            secrets = listOf("QWxhZGRpbjpvcGVuIHNlc2FtZQ=="),
            context = listOf("WebDavException: 403", "blob.example", "sv=2024-11-04", "retrying"),
        )
    }

    @Test
    fun unquoted_camelCaseEncryptedApiKey_isRedacted() {
        // The iOS `api[_-]?key` alternation does NOT match `encryptedApiKey` (its separator-or-
        // word-start requirement fails mid-token). This is the coverage iOS lacks.
        check(
            "AiProviderStore decrypt failed encryptedApiKey=AAAAFGhlbGxvd29ybGQxMjM0NTY3ODkw " +
                "javax.crypto.AEADBadTagException",
            "AiProviderStore decrypt failed encryptedApiKey=$redacted " +
                "javax.crypto.AEADBadTagException",
            secrets = listOf("AAAAFGhlbGxvd29ybGQxMjM0NTY3ODkw"),
            context = listOf("AiProviderStore", "AEADBadTagException", "encryptedApiKey"),
        )
    }

    @Test
    fun unquoted_entityDumpWithPlainAndEncryptedCredential_redactsBothKeepsTuning() {
        check(
            "AiProviderProfile(id=p1, baseUrl=https://openrouter.ai/api/v1, " +
                "apiKey=sk-or-v1-abc123def456, encryptedApiKey=AAAAFGhlbGxvMTIz, maxTokens=4096)",
            "AiProviderProfile(id=p1, baseUrl=https://openrouter.ai/api/v1, " +
                "apiKey=$redacted, encryptedApiKey=$redacted, maxTokens=4096)",
            secrets = listOf("sk-or-v1-abc123def456", "AAAAFGhlbGxvMTIz"),
            // maxTokens must SURVIVE — the over-redaction pin for the camel-case key rule.
            context = listOf("id=p1", "openrouter.ai", "maxTokens=4096"),
        )
    }

    @Test
    fun unquoted_commandLineStyleDoubleDashKey_isRedacted() {
        check(
            "spawn rclone --password=hunter2secret999 serve",
            "spawn rclone --password=$redacted",
            secrets = listOf("hunter2secret999"),
            context = listOf("spawn rclone", "--password="),
        )
    }

    @Test
    fun unquoted_secretAndAccessKeyFamilies_areRedacted() {
        check(
            "S3 upload denied accessKey=AKIAIOSFODNN7EXAMPLE region=eu-west-1",
            "S3 upload denied accessKey=$redacted region=eu-west-1",
            secrets = listOf("AKIAIOSFODNN7EXAMPLE"),
            context = listOf("S3 upload denied", "region=eu-west-1"),
        )
        check(
            "signer init secretKey=wJalrXUtnFEMIK7MDENGbPxRfiCY status=ready",
            "signer init secretKey=$redacted status=ready",
            secrets = listOf("wJalrXUtnFEMIK7MDENGbPxRfiCY"),
            context = listOf("signer init", "status=ready"),
        )
    }

    @Test
    fun unquoted_allKeyedSecretSpellings_areRedacted() {
        // (key + separator, secret value) — the expected output is the separator plus the
        // placeholder, so a branch that ate the key name or the separator fails here too.
        listOf(
            "apiKey=" to "SUPERSECRETVALUE123",
            "api_key=" to "SUPERSECRETVALUE123",
            "api-key=" to "SUPERSECRETVALUE123",
            "x-api-key: " to "xk9988776655",
            "access_token: " to "aaaaaaaaaaaaaaaa",
            "refresh_token=" to "rrrrrrrrrrrr",
            "refreshToken=" to "rrrrrrrrrrrr",
            "x-auth-token=" to "xa9988776655",
            "client_secret: " to "csXYZ987654",
            "password=" to "hunter2hunter2",
            "passwd=" to "pw9988776655",
            "passphrase=" to "pp9988776655",
            "authToken=" to "tk9988776655",
            "sessionToken=" to "st9988776655",
            "idToken=" to "id9988776655",
            "token=" to "bare9988776655",
            "credential=" to "cr9988776655",
            "X-Amz-Signature=" to "sg9988776655",
        ).forEach { (keyWithSeparator, secret) ->
            check(
                "provider probe -> HTTP 401 for $keyWithSeparator$secret",
                "provider probe -> HTTP 401 for $keyWithSeparator$redacted",
                secrets = listOf(secret),
                context = listOf("provider probe -> HTTP 401 for", keyWithSeparator.trimEnd()),
            )
        }
    }

    // ================================================================ shapes with no key name

    @Test
    fun shape_bareOpenAiKeyWithNoKeyName_isRedacted() {
        // `value` is not a secret word, so ONLY the sk- rule can fire here.
        check(
            "provider probe rejected value sk-proj-AbCdEf1234567890XyZqrs at OpenAiCompatibleProvider",
            "provider probe rejected value $redacted at OpenAiCompatibleProvider",
            secrets = listOf("sk-proj-AbCdEf1234567890XyZqrs"),
            context = listOf("provider probe rejected", "OpenAiCompatibleProvider"),
        )
    }

    @Test
    fun shape_cjkAdjacentKeyIsStillRedacted() {
        // Java's `\b` is Unicode-aware, so `\bsk-` FAILS after a CJK character. The rule uses an
        // explicit ASCII lookbehind instead; this vector is the regression pin.
        check(
            "密钥sk-proj-AbCdEf123456后 rejected",
            "密钥${redacted}后 rejected",
            secrets = listOf("sk-proj-AbCdEf123456"),
            context = listOf("密钥", "后 rejected"),
        )
    }

    @Test
    fun shape_bareJwt_isRedacted() {
        val jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NSJ9.SflKxwRJSMeKKF2QT4f"
        check(
            "OIDC session $jwt expired at AuthInterceptor",
            "OIDC session $redacted expired at AuthInterceptor",
            secrets = listOf(jwt),
            context = listOf("OIDC session", "expired at AuthInterceptor"),
        )
    }

    // ================================================================ URL credentials

    @Test
    fun url_credentials_redactPasswordKeepUserAndHost() {
        check(
            "WebDAV connect https://alice:hunter2secret@dav.example.com/remote.php/dav/ -> 401",
            "WebDAV connect https://alice:$redacted@dav.example.com/remote.php/dav/ -> 401",
            secrets = listOf("hunter2secret"),
            context = listOf("alice", "dav.example.com", "/remote.php/dav/", "-> 401"),
        )
    }

    @Test
    fun url_passwordContainingAtSign_isFullyRedactedWithoutCrossingTheQuery() {
        check(
            "invalid URL: https://alice:p@ss@catalog.example/feed",
            "invalid URL: https://alice:$redacted@catalog.example/feed",
            secrets = listOf("p@ss"),
            context = listOf("alice", "catalog.example/feed"),
        )
        // A query-string `@` must not pull the match past the host.
        check(
            "invalid URL: https://alice:p@ss@catalog.example?next=a@b",
            "invalid URL: https://alice:$redacted@catalog.example?next=a@b",
            secrets = listOf("p@ss"),
            context = listOf("alice", "catalog.example", "next=a@b"),
        )
    }

    @Test
    fun url_emptyUsernameUserinfo_isStillRedacted() {
        // `https://:password@host` is legal userinfo; requiring a non-empty username leaked it.
        check(
            "network error: response from https://:hunter2@catalog.example/feed exceeds the limit",
            "network error: response from https://:$redacted@catalog.example/feed exceeds the limit",
            secrets = listOf("hunter2"),
            context = listOf("network error", "catalog.example/feed", "exceeds the limit"),
        )
    }

    @Test
    fun url_rtlAdjacentCredentials_areStillRedacted() {
        check(
            "فشلhttps://alice:hunter2@dav.example/dav",
            "فشلhttps://alice:$redacted@dav.example/dav",
            secrets = listOf("hunter2"),
            context = listOf("فشل", "alice", "dav.example/dav"),
        )
    }

    // ================================================================ paths and URIs

    @Test
    fun path_appBooksPath_redactsContainerButKeepsFingerprintKeyFilename() {
        // Book artifacts live at filesDir/books/<sanitised fingerprintKey>, and that key is the
        // handle every import/reader bug is filed against — it must SURVIVE.
        check(
            "java.io.FileNotFoundException: " +
                "/data/user/0/com.vreader.app/files/books/epub_984f8611bb2842e0_2956 " +
                "(No such file)",
            "java.io.FileNotFoundException: $path/epub_984f8611bb2842e0_2956 (No such file)",
            secrets = listOf("/data/user/0", "com.vreader.app/files"),
            context = listOf("epub_984f8611bb2842e0_2956", "FileNotFoundException", "(No such file)"),
        )
    }

    @Test
    fun path_fileUrlToAnAppBookAlsoKeepsTheFingerprintKey() {
        check(
            "loaded file:///data/user/0/com.vreader.app/files/books/epub_984f_1 ok",
            "loaded $path/epub_984f_1 ok",
            secrets = listOf("/data/user/0", "com.vreader.app"),
            context = listOf("epub_984f_1", "loaded", "ok"),
        )
    }

    @Test
    fun path_theFingerprintExceptionIsScopedToThisAppsArtifactDirectory() {
        // A nested tail under the app's books dir must NOT satisfy the terminal-segment guard.
        check(
            "open /data/user/0/com.vreader.app/files/books/sub/evil.epub gone",
            "open $path gone",
            secrets = listOf("sub/evil.epub", "/data/user/0"),
            context = listOf("open", "gone"),
        )
        // Another app's private books dir gets NO exception — the applicationId is pinned.
        check(
            "open /data/user/0/com.other.app/files/books/private_customer_name gone",
            "open $path gone",
            secrets = listOf("com.other.app", "private_customer_name"),
            context = listOf("open", "gone"),
        )
        // A user's own "Books" folder on shared storage is not the app artifact dir either.
        check(
            "import /storage/emulated/0/Books/Alice/Tax Return.pdf failed",
            // A terminal filename containing a space keeps its last word — filenames are outside
            // redaction policy (parity with iOS #96); the DIRECTORY name is not, and it goes.
            "import $path Return.pdf failed",
            secrets = listOf("/storage/emulated/0/Books", "Alice"),
            context = listOf("import", "failed"),
        )
    }

    @Test
    fun path_genericFileUrl_isRedactedWithTheSameSpaceHandling() {
        check(
            "loaded file:///data/user/0/com.vreader.app/files/x.epub ok",
            "loaded $path ok",
            secrets = listOf("/data/user/0/com.vreader.app/files/x.epub"),
            context = listOf("loaded", "ok"),
        )
        // A file URL OUTSIDE every known Android root — a removable SD card carries the volume id
        // and the user's own folder names, and no path-root rule matches it.
        check(
            "loaded file:///storage/1A2B-3C4D/Books/Alice Smith/tax.pdf failed",
            "loaded $path failed",
            secrets = listOf("1A2B-3C4D", "Alice Smith", "tax.pdf"),
            context = listOf("loaded", "failed"),
        )
    }

    @Test
    fun path_safContentUri_keepsAuthorityRedactsDocumentPath() {
        check(
            "import content://com.android.providers.downloads.documents/document/msf%3A1000 " +
                "failed SecurityException",
            "import content://com.android.providers.downloads.documents/$path " +
                "failed SecurityException",
            secrets = listOf("document/msf%3A1000"),
            context = listOf("com.android.providers.downloads.documents", "SecurityException"),
        )
    }

    @Test
    fun path_multiUserAppPrivatePath_isRedacted() {
        // The user id is NOT hard-coded to 0 — a work profile / secondary user must redact too.
        check(
            "Room open failed android.database.sqlite.SQLiteException at " +
                "/data/user/11/com.vreader.app/databases/vreader.db",
            "Room open failed android.database.sqlite.SQLiteException at $path",
            secrets = listOf("/data/user/11/com.vreader.app"),
            context = listOf("SQLiteException"),
        )
        check(
            "prefs /data/user_de/10/com.vreader.app/shared_prefs/settings.xml unreadable",
            "prefs $path unreadable",
            secrets = listOf("/data/user_de/10/com.vreader.app"),
            context = listOf("prefs", "unreadable"),
        )
    }

    @Test
    fun path_legacyDataDataPath_isRedacted() {
        check(
            "prefs /data/data/com.vreader.app/shared_prefs/settings.xml unreadable",
            "prefs $path unreadable",
            secrets = listOf("/data/data/com.vreader.app"),
            context = listOf("prefs", "unreadable"),
        )
    }

    @Test
    fun path_sharedStoragePaths_areRedacted() {
        check(
            "import from /storage/emulated/0/Download/foo.epub denied SecurityException",
            "import from $path denied SecurityException",
            secrets = listOf("/storage/emulated/0/Download"),
            context = listOf("import from", "denied SecurityException"),
        )
        check(
            "import from /sdcard/Download/foo.epub denied SecurityException",
            "import from $path denied SecurityException",
            secrets = listOf("/sdcard/Download"),
            context = listOf("import from", "denied SecurityException"),
        )
    }

    @Test
    fun path_directoryNameWithASpace_doesNotLeakTheRestOfThePath() {
        // Whitespace termination leaked "Smith/tax.pdf" — a real name plus a document title.
        check(
            "import /storage/emulated/0/Download/Alice Smith/tax.pdf failed",
            "import $path failed",
            secrets = listOf("Alice Smith", "tax.pdf"),
            context = listOf("import", "failed"),
        )
    }

    @Test
    fun path_spaceHeuristicResidualImperfectionsArePinnedNotImplicit() {
        // No lexical rule separates "a directory name containing a space" from "trailing prose",
        // so the heuristic ("a space joins the path only if the next token holds a `/`") has two
        // known residuals. They are asserted so a future change to the rule is a visible decision
        // rather than a silent regression.

        // (a) A TERMINAL directory containing a space keeps its last word.
        check(
            "cannot create /storage/emulated/0/Download/Alice Smith",
            "cannot create $path Smith",
            secrets = listOf("/storage/emulated/0/Download", "Alice"),
            context = listOf("cannot create"),
        )
        // (b) Prose containing a `/` right after a path is over-redacted (the safe direction).
        check(
            "open /storage/emulated/0/Download/x read/write failed",
            "open $path failed",
            secrets = listOf("/storage/emulated/0/Download"),
            context = listOf("open", "failed"),
        )
    }

    // ================================================================ negatives: no over-redaction

    @Test
    fun negative_nonCredentialTokenIdentifiersSurvive() {
        // This codebase has ~70 `*Token` identifiers that are NOT credentials; redacting them
        // would destroy exactly the pagination/session diagnostics an export exists to carry.
        assertUnchanged("paging startToken=abc123 activeToken=def456 maxTokens=4096")
        assertUnchanged("PaginationToken=p9 iteratorToken=t7 finalToken=f1 rawTokens=12")
        assertUnchanged("validToken=true uuidToken=u1 nextToken=n2")
        assertUnchanged("the session token was refreshed successfully")
    }

    @Test
    fun negative_nonCredentialKeyIdentifiersSurvive() {
        // The `*Key` family is qualifier-gated for the same reason: `fingerprintKey` is the handle
        // every import/reader bug is filed against, and a bare `key=` is a cache/map handle.
        assertUnchanged("book fingerprintKey=epub_984f8611bb2842e0bc3a7b90cef7ffed37e4cc23_2956 opened")
        assertUnchanged("cache key=chapter-12 sortKey=title primaryKey=42 publicKey=short")
    }

    @Test
    fun negative_proseAfterAnAuthSchemeWordSurvives() {
        // An entropy-shaped bare rule redacted `Basic SHA256withRSA2048`; the scanner is anchored
        // on a real container instead, so prose is untouched.
        assertUnchanged("Basic authentication required by the server")
        assertUnchanged("Basic SHA256withRSA2048 unsupported")
        assertUnchanged("Bearer tokens rejected")
        // No `:`/`=`/`,`/`]`/`)` after the header name — not a container, so not a credential.
        assertUnchanged("Authorization is required for this endpoint")
    }

    @Test
    fun negative_keyWordWithoutAnAssignmentSeparatorSurvives() {
        // `password` here is a KEYSTORE ALIAS, not a `key=value` pair. Requiring a `:` or `=` in
        // the separator run is what keeps "the session token was refreshed" intact too.
        assertUnchanged("keystore alias vreader.webdav.password rotated")
        assertUnchanged("TestSignature(probe) completed in 12ms")
    }

    @Test
    fun negative_identifiersHashesAndVersionsAreUnchanged() {
        assertUnchanged("content sha256 984f8611bb2842e0bc3a7b90cef7ffed37e4cc23 verified")
        assertUnchanged("deleted books row id=42 in 12ms")
        assertUnchanged("versionName=0.13.4 versionCode=134")
        assertUnchanged("design=material config=default assign=true")
    }

    @Test
    fun negative_messageWithNoSecretIsByteIdentical() {
        val msg = "loaded 12 books in 0.34s"
        assertEquals(msg, DiagnosticsRedactor.redact(msg))
    }

    // ================================================================ oracle self-check

    @Test
    fun oracle_idempotencyIsNotACompletenessOracle() {
        // Survivor 3's partial output (`password=‹redacted›'BrienNeverClose`) was STABLE under
        // re-redaction, so the idempotency assertion could not see it. This test pins that
        // idempotency proves nothing about completeness — using the ACCEPTED non-goal as the
        // demonstration: a bare `SecretCipher` blob with no key name and no `sk-`/JWT shape is a
        // fixed point of redact() AND still contains the secret.
        val leaking = "SecretCipher decrypt failed for AAAAFGhlbGxvd29ybGQxMjM0"
        val once = DiagnosticsRedactor.redact(leaking)
        assertEquals("idempotent…", once, DiagnosticsRedactor.redact(once))
        assertTrue(
            "…yet the secret survives — idempotency is not a completeness oracle",
            once.contains("AAAAFGhlbGxvd29ybGQxMjM0"),
        )
        // The controls for this class are the `VLog` seam and the `android.util.Log` containment
        // check, NOT this function. A blanket base64 rule would swallow every hash, row id and
        // fingerprint key — see negative_identifiersHashesAndVersionsAreUnchanged.
    }

    @Test
    fun oracle_aPartialRedactionIsRejectedByTheExactAndSuffixAssertions() {
        // The shape the previous design produced. It must NOT be what redact() returns.
        val partial = """password="$redacted'BrienNeverClose"""
        val actual = DiagnosticsRedactor.redact("""password="O'BrienNeverClose""")
        assertFalse("a partial redaction must not be the output", actual == partial)
        assertFalse("no suffix of the secret may survive", actual.contains("BrienNeverClose"))
    }

    // ================================================================ robustness

    @Test
    fun robustness_emptyCjkAndRtlMessagesAreUnchanged() {
        assertEquals("", DiagnosticsRedactor.redact(""))
        assertUnchanged("已加载 12 本书，用时 0.34 秒")
        assertUnchanged("فشل تحميل الكتاب بعد 3 محاولات")
        assertUnchanged("مرحبا 已加载 mixed ‏RTL‏ 12")
    }

    @Test
    fun robustness_cjkMessageStillRedactsAnEmbeddedSecret() {
        check(
            "同步失败 Authorization: Basic dXNlcjpwYXNzd29yZA== 请重试",
            "同步失败 Authorization: Basic $redacted 请重试",
            secrets = listOf("dXNlcjpwYXNzd29yZA=="),
            context = listOf("同步失败", "请重试"),
        )
    }

    @Test
    fun robustness_oneMegabyteMessageDoesNotThrowAndStillRedacts() {
        val line = "loaded 12 books in 0.34s and reopened the library index cleanly\n"
        val bulk = StringBuilder(1_100_000)
        while (bulk.length < 1_000_000) bulk.append(line)
        bulk.append("Authorization: Bearer sk-proj-OneMegabyteTailSecret999\n")
        val input = bulk.toString()
        assertTrue("fixture must exceed 1 MB", input.length > 1_000_000)
        val out = DiagnosticsRedactor.redact(input)
        assertFalse(out.contains("sk-proj-OneMegabyteTailSecret999"))
        assertTrue(out.contains("Authorization: Bearer $redacted"))
    }

    @Test
    fun robustness_pathologicalInputsDoNotThrow() {
        listOf(
            " ", "\n", "\t", "=", ":", "\"", "'", "{}", "://", "content://",
            "Authorization:", "Authorization: Bearer", "Authorization: Bearer ", "password=",
            "sk-", "eyJ", "/data/user/", "/sdcard", "file://", "  nul", "password=\"unterminated",
            "password='", """state={\"apiKey\":\"""", "https://:@", "Authorization]=",
            "--", "--password=", "-", "key=", "a-b-c-key=", "token", "token=", "\\\"", "\\",
            "Authorization" + " ".repeat(40), "password" + "=".repeat(40),
        ).forEach { DiagnosticsRedactor.redact(it) }
    }

    // ================================================================ ReDoS / linearity bounds
    // Each of these was measured super-linear against the previous regex design. The scanner is a
    // single left-to-right pass with no backtracking, so the timeout is the assertion.

    @Test(timeout = 15_000)
    fun linear_longWhitespaceRunAfterAuthorization() {
        DiagnosticsRedactor.redact("Authorization:" + " ".repeat(100_000) + "Bearer $redacted")
    }

    @Test(timeout = 15_000)
    fun linear_longSingleIdentifier() {
        DiagnosticsRedactor.redact("a".repeat(100_000))
    }

    @Test(timeout = 15_000)
    fun linear_repeatedKeyWord() {
        DiagnosticsRedactor.redact("password".repeat(12_000))
    }

    @Test(timeout = 15_000)
    fun linear_longHyphenatedRun() {
        // Measured QUADRATIC before the fix: the URL-credential rule's `[a-z][a-z0-9+.-]*` gave
        // every `a` in `a-a-a-…` a viable start whose scheme run consumed the rest of the input
        // before failing. Fixed by a head that also excludes `+.-` plus a possessive scheme run.
        DiagnosticsRedactor.redact("a-".repeat(50_000))
    }

    @Test(timeout = 15_000)
    fun linear_repeatedKeyAssignment() {
        DiagnosticsRedactor.redact("api-key=".repeat(12_000))
        DiagnosticsRedactor.redact("Authorization:".repeat(12_000))
    }

    @Test(timeout = 15_000)
    fun linear_unterminatedQuotedValueWithBackslashRun() {
        DiagnosticsRedactor.redact("password=\"" + "\\".repeat(4_000))
        DiagnosticsRedactor.redact("""state={\"apiKey\":\"""" + "\\".repeat(4_000))
    }

    // ================================================================ idempotency, combined

    @Test
    fun idempotency_holdsForACombinedMultiSecretMessage() {
        val msg = "Authorization: Bearer sk-abc123def456ghijk, " +
            "at /data/user/0/com.vreader.app/files/books/epub_a1b2_4, " +
            "via https://alice:pw123456@dav.example.com/dav/, " +
            "uri content://com.android.providers.media.documents/document/x%3A9, " +
            "apiKey=ZZTOP1234567"
        val once = DiagnosticsRedactor.redact(msg)
        assertEquals(once, DiagnosticsRedactor.redact(once))
        assertEquals(once, DiagnosticsRedactor.redact(DiagnosticsRedactor.redact(once)))
        listOf("sk-abc123def456ghijk", "/data/user/0", "ZZTOP1234567", "pw123456", "document/x%3A9")
            .forEach { assertFalse("<$it> survived: $once", once.contains(it)) }
        listOf("epub_a1b2_4", "alice", "dav.example.com",
            "content://com.android.providers.media.documents")
            .forEach { assertTrue("<$it> destroyed: $once", once.contains(it)) }
    }
}
