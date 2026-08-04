package com.vreader.app.diagnostics

/**
 * Purpose: Feature #164 WI-2 — scrubs credentials, tokens and filesystem paths out of a captured
 * log message before it can leave the device. Pure and idempotent.
 *
 * Threat model — on Android this is the ONLY barrier. iOS has a first line of defence in OSLog's
 * `privacy:` annotations (a `.private` interpolation reads back as `<private>`), so its redactor is
 * defence in depth. Android's logcat is PLAINTEXT: every byte the app or any library logs sits in
 * the ring buffer verbatim, so this function is load-bearing. It is written to be called at EVERY
 * egress — the export payload AND the viewer's "copy entry" clipboard write (WI-4 / WI-6a).
 *
 * Strategy — CONTEXT-ANCHORED. Nothing is redacted on shape or entropy alone; every branch is
 * anchored on a label the app actually writes (a key name, an `Authorization` header, a URL scheme,
 * a path root). Two deliberate non-strategies: it does NOT blanket-redact long hex/base64 runs
 * (that swallows content hashes, fingerprint keys and row ids — the handles every bug report is
 * filed against), and it does NOT use an entropy heuristic. One was tried and DELETED after failing
 * in BOTH directions across two audit rounds: it missed a real all-letter `OpdsClient` Basic token
 * and over-redacted `Basic SHA256withRSA2048`.
 *
 * WHY A SCANNER, NOT A REGEX (the WI-2b redesign). The keyed-value half was first built as 13
 * regex rules. Three audit rounds went 4 High → 3 High → 4 NEW High: each fix moved a boundary and
 * the next input class walked around it. The diagnosis: **a regex cannot delimit an unquoted or
 * partially-quoted credential value, because the delimiter depends on QUOTE STATE, not on a
 * character class.** The four survivors — an over-wide separator run, an escaped-JSON container, a
 * quoted value containing the other quote character, and an unquoted value containing a structural
 * character — are all instances of that one fact. [scanKeyedValues] is therefore a single
 * left-to-right pass with an explicit quote state machine; the pattern-shaped rules that were never
 * holed (`sk-`, JWT, URL userinfo, path roots) stay regexes in [SHAPE_RULES].
 *
 * Key decisions:
 * - **Separator runs are UNBOUNDED, and an escaped quote is a separator.** The regex container was
 *   `{0,8}` wide, so `Authorization:` + 10 spaces + `Bearer …` fell through every rule; and it
 *   excluded `\`, so the real `state={\"Authorization\":\"Basic …\"}` dump survived entirely. The
 *   run consumes `\"` pairs and remembers the last quote as the OPENING quote.
 * - **A quoted value runs to its MATCHING close, honouring backslash escapes, and FAILS CLOSED to
 *   end of line when there is none** (logd truncates at 4068 bytes, cutting the quote off exactly
 *   where a credential sits). Never to the first embedded quote: that produced
 *   `password=‹redacted›'BrienNeverClose`, a partial redaction STABLE under re-redaction, so the
 *   idempotency assertions could not see it.
 * - **The unquoted-value delimiter policy is a decision, not a character class.** Keys split by
 *   whether the value can contain a space. An API key / signature / bearer token travels in an HTTP
 *   header or query string where a raw space is ILLEGAL, so [Kind.TOKEN] stops at whitespace and
 *   `-> HTTP 401` survives. A password / passphrase / `authHeader` can contain anything, so
 *   [Kind.SPACED] runs to END OF LINE and stops early ONLY at a structural character that is
 *   *demonstrably a field boundary*: a `,`/`&`/`;` followed by a new `identifier[:=]`, or a bracket
 *   closing an opener seen before the key that is itself followed by the end of the dump. The trade
 *   is asymmetric ON PURPOSE — a wider delimiter set leaks less credential but destroys more
 *   same-line context, and this is the sole egress barrier, so it prefers SAFETY:
 *   `password=foo,bar` redacts whole, while `password=x, wifiOnly=true` keeps `wifiOnly=true`
 *   because the comma provably starts another field.
 * - **`Authorization` is a key in its own right** needing only a structural container (`:`, `=`,
 *   `,`, `]`, `)`) — `headers[Authorization]=Basic x` and `Pair(Authorization, Basic x)` are neither
 *   `key: value`. Every OTHER key requires a `:` or `=`, which keeps "the session token was
 *   refreshed successfully" intact. A recognised scheme (`Bearer`/`Basic`) survives as context;
 *   an unrecognised one consumes the rest of the LINE, because a Digest credential is spread across
 *   comma-separated parameters and anything less leaks `response=`.
 * - **Key names match as an identifier SUFFIX**, covering the camel-case fields this codebase
 *   persists (`encryptedApiKey`, `encryptedPassword`, `authHeader`) where the iOS `api[_-]?key`
 *   alternation misses them. `token` and `key` are QUALIFIER-GATED: ~70 non-credential
 *   `*Token`/`*Key` identifiers exist here (`activeToken`, `maxTokens`, `fingerprintKey`) whose
 *   redaction would destroy real diagnostics.
 * - Boundaries are explicit ASCII, never `\b` — Java's `\b` is Unicode-aware while `\w` is ASCII,
 *   so `\bsk-…` silently FAILS in `前sk-proj-…`. The fingerprint-key path exception is pinned to
 *   THIS app's applicationId and a terminal single segment (`filesDir/books/<fingerprintKey>`); if
 *   `applicationIdSuffix` is ever introduced, [PATH_ROOT_APP_BOOKS] must be widened with it. A space
 *   joins a path only when the next token still holds a `/`, which swallows an intermediate
 *   directory name while keeping a trailing exception class.
 *
 * Known limitations (accepted, NOT mitigated — do not read this as coverage):
 * - A BARE-VALUE opaque secret, with no key name, no `Authorization` container and no `sk-`/JWT
 *   shape, is NOT redacted. A `SecretCipher` token is `base64(iv ‖ ciphertext)` with no prefix,
 *   length field or magic — structurally identical to a hash, a row id or a thumbnail — so only one
 *   of the two non-strategies above would catch it. The complementary controls are the `VLog` seam,
 *   WI-3's `android.util.Log` containment check, and a typed secret wrapper a logging API cannot
 *   accept (named follow-up).
 * - An unquoted SPACED value whose text contains `, <identifier>=` (or the dump's closing bracket
 *   followed by end-of-line) is truncated there, leaking the remainder. Preserving `wifiOnly=true`
 *   in every `toString()` costs exactly this; no lexical rule can tell the two apart.
 * - An unrecognised `Authorization` scheme consumes the rest of the line, so same-line text after
 *   such a header is lost. A quoted value whose closing quote appears many lines later
 *   over-redacts to that quote (the safe direction).
 * - Book titles and filenames are NOT redacted (parity with iOS #96) — redacting them would gut the
 *   export's diagnostic value, since most import/reader failures name the book.
 *
 * @coordinates-with DiagnosticsLogStore.kt (export egress, WI-4), the viewer's copy-entry action
 */
object DiagnosticsRedactor {

    const val PLACEHOLDER = "‹redacted›"
    const val PATH_PLACEHOLDER = "‹path›"

    /**
     * Scrubs [message] for safe egress.
     *
     * Idempotent — `redact(redact(x)) == redact(x)` — because every replacement is either an
     * acceptable match for the branch that produced it (rewriting the placeholder to itself) or
     * cannot match any branch at all. Idempotency is NOT a completeness oracle: see the test suite's
     * `oracle_idempotencyIsNotACompletenessOracle`.
     */
    fun redact(message: String): String {
        if (message.isEmpty()) return message
        var out = scanKeyedValues(message)
        for (rule in SHAPE_RULES) out = rule.apply(out)
        return out
    }

    // ============================================================== key classification

    /** How far an unquoted value for this key class may run. */
    private enum class Kind { TOKEN, SPACED, AUTH, LINE }

    /** Keys whose value MAY contain spaces (a passphrase; an `authHeader` is `<scheme> <token>`). */
    private val SPACED_WORDS = listOf(
        "password", "passwd", "passphrase", "secret", "credential",
        "authheader", "auth_header", "auth-header",
    )

    /** Keys whose value is a single whitespace-free token. */
    private val TOKEN_WORDS = listOf("apikey", "api_key", "api-key", "signature", "sig")

    /** `*token` is a credential only behind these qualifiers — see the class doc. */
    private val TOKEN_QUALIFIERS = listOf(
        "auth", "access", "refresh", "bearer", "session", "id", "api", "sas", "csrf", "xsrf",
        "encrypted",
    )

    /** `*key` likewise — a bare `key=` is a cache handle, `fingerprintKey` is a bug-report handle. */
    private val KEY_QUALIFIERS = listOf(
        "api", "secret", "private", "access", "encrypted", "signing", "auth",
    )

    private val AUTH_SCHEMES = listOf("Bearer", "Basic")

    private fun classify(id: String): Kind? {
        val lower = id.lowercase()
        if (lower.endsWith("authorization")) return Kind.AUTH
        SPACED_WORDS.forEach { if (lower.endsWith(it)) return Kind.SPACED }
        TOKEN_WORDS.forEach { if (lower.endsWith(it)) return Kind.TOKEN }
        if (lower.endsWith("token") && qualified(id, id.length - 5, TOKEN_QUALIFIERS, true)) {
            return Kind.TOKEN
        }
        if (lower.endsWith("key") && qualified(id, id.length - 3, KEY_QUALIFIERS, false)) {
            return Kind.TOKEN
        }
        return null
    }

    /**
     * True when the identifier text before [cut] ends with one of [quals] at a word boundary —
     * position 0, after a `_`/`-`, or at a camelCase hump. The boundary check is what keeps
     * `validToken` (`val` + `id`) and `PaginationToken` out while admitting `x-auth-token`.
     */
    private fun qualified(id: String, cut: Int, quals: List<String>, allowEmpty: Boolean): Boolean {
        var p = id.substring(0, cut)
        while (p.isNotEmpty() && (p.last() == '_' || p.last() == '-')) p = p.dropLast(1)
        if (p.isEmpty()) return allowEmpty
        val lower = p.lowercase()
        for (q in quals) {
            if (!lower.endsWith(q)) continue
            val at = p.length - q.length
            if (at == 0) return true
            val before = p[at - 1]
            if (before == '_' || before == '-') return true
            if (p[at].isUpperCase() && before.isLowerCase()) return true
        }
        return false
    }

    // ============================================================== the scanner

    private fun isIdentChar(c: Char): Boolean =
        c in 'a'..'z' || c in 'A'..'Z' || c in '0'..'9' || c == '_' || c == '-'

    private fun isIdentStart(c: Char): Boolean =
        c in 'a'..'z' || c in 'A'..'Z' || c == '_' || c == '-'

    private fun opener(closer: Char): Char = when (closer) {
        ')' -> '('
        ']' -> '['
        else -> '{'
    }

    /**
     * One left-to-right pass. Every maximal ASCII identifier run is classified once; a credential
     * key hands off to [findValue], and the returned span is replaced by [PLACEHOLDER]. No
     * backtracking anywhere, so the cost is linear in the message length.
     */
    private fun scanKeyedValues(text: String): String {
        val out = StringBuilder(text.length + 16)
        val open = ArrayDeque<Char>()
        var i = 0
        while (i < text.length) {
            val c = text[i]
            if (isIdentStart(c) && (i == 0 || !isIdentChar(text[i - 1]))) {
                var j = i
                while (j < text.length && isIdentChar(text[j])) j++
                val kind = classify(text.substring(i, j))
                val span = if (kind == null) null else findValue(text, j, kind, open)
                if (span != null) {
                    for (k in i until span.first) track(text[k], open)
                    out.append(text, i, span.first).append(PLACEHOLDER)
                    i = span.second
                } else {
                    out.append(text, i, j)
                    i = j
                }
                continue
            }
            track(c, open)
            out.append(c)
            i++
        }
        return out.toString()
    }

    private fun track(c: Char, open: ArrayDeque<Char>) {
        when (c) {
            '\n' -> open.clear()
            '(', '[', '{' -> open.addLast(c)
            ')', ']', '}' -> if (open.isNotEmpty() && open.last() == opener(c)) open.removeLast()
        }
    }

    /**
     * Given a credential key ending at [pos], returns the half-open span of its VALUE, or null when
     * the text is not a credential assignment after all.
     */
    private fun findValue(text: String, pos: Int, kind: Kind, open: ArrayDeque<Char>): Pair<Int, Int>? {
        var k = pos
        var sawAssign = false
        var sawStructural = false
        var quote = '\u0000'
        var quoteEscaped = false
        loop@ while (k < text.length) {
            val c = text[k]
            when {
                c == ' ' || c == '\t' || c == '\r' -> k++
                c == ':' || c == '=' -> { sawAssign = true; sawStructural = true; quote = '\u0000'; k++ }
                // A container comma/bracket only counts BEFORE the assignment; afterwards it is the
                // start of the next field, and consuming it would redact that field's value.
                (c == ',' || c == ']' || c == ')' || c == '}') && !sawAssign ->
                    { sawStructural = true; quote = '\u0000'; k++ }
                c == '"' || c == '\'' -> { quote = c; quoteEscaped = false; k++ }
                c == '\\' && k + 1 < text.length && (text[k + 1] == '"' || text[k + 1] == '\'') ->
                    { quote = text[k + 1]; quoteEscaped = true; k += 2 }
                else -> break@loop
            }
        }
        if (k == pos) return null
        if (kind == Kind.AUTH) {
            if (!sawStructural) return null
        } else if (!sawAssign) return null

        var start = k
        var end = if (quote != '\u0000') {
            closingQuote(text, k, quote, quoteEscaped) ?: lineEnd(text, k)
        } else {
            -1
        }
        var effective = kind
        if (kind == Kind.AUTH) {
            val afterScheme = schemeEnd(text, start, if (end >= 0) end else lineEnd(text, start))
            if (afterScheme > 0) {
                start = afterScheme
                effective = Kind.TOKEN
            } else {
                effective = Kind.LINE
            }
        }
        if (end < 0) end = unquotedEnd(text, start, effective, open)
        return if (end <= start) null else start to end
    }

    /** Index just past a recognised scheme word plus its trailing spaces, or -1. */
    private fun schemeEnd(text: String, start: Int, limit: Int): Int {
        for (scheme in AUTH_SCHEMES) {
            val after = start + scheme.length
            if (after >= limit) continue
            if (!text.regionMatches(start, scheme, 0, scheme.length, ignoreCase = true)) continue
            if (text[after] != ' ' && text[after] != '\t') continue
            var k = after
            while (k < limit && (text[k] == ' ' || text[k] == '\t')) k++
            if (k < limit) return k
        }
        return -1
    }

    /** Index of the matching close quote, honouring backslash escapes; null when unbalanced. */
    private fun closingQuote(text: String, from: Int, quote: Char, escaped: Boolean): Int? {
        var k = from
        if (!escaped) {
            while (k < text.length) {
                when {
                    text[k] == '\\' -> k += 2
                    text[k] == quote -> return k
                    else -> k++
                }
            }
        } else {
            while (k + 1 < text.length) {
                if (text[k] == '\\') {
                    if (text[k + 1] == quote) return k
                    k += 2
                } else {
                    k++
                }
            }
        }
        return null
    }

    private fun lineEnd(text: String, from: Int): Int {
        val nl = text.indexOf('\n', from)
        return if (nl < 0) text.length else nl
    }

    /** The unquoted-value terminator policy — see the class doc's "delimiter policy" decision. */
    private fun unquotedEnd(text: String, start: Int, kind: Kind, open: ArrayDeque<Char>): Int {
        var k = start
        while (k < text.length) {
            val c = text[k]
            if (c == '\n') return k
            if (kind == Kind.TOKEN && (c == ' ' || c == '\t' || c == '\r')) return k
            if ((c == ')' || c == ']' || c == '}') && open.contains(opener(c)) && closesTheDump(text, k + 1)) {
                return k
            }
            // NOT for [Kind.LINE]: a Digest credential IS a comma-separated parameter list, so
            // honouring a field boundary there would leak `response=…`.
            if (kind != Kind.LINE && (c == ',' || c == '&' || c == ';') && nextKeyFollows(text, k + 1)) {
                return k
            }
            k++
        }
        return text.length
    }

    /** True when nothing but the end of the dump follows — the bracket really terminated a field. */
    private fun closesTheDump(text: String, from: Int): Boolean {
        var k = from
        while (k < text.length && (text[k] == ' ' || text[k] == '\t')) k++
        if (k >= text.length) return true
        val c = text[k]
        return c == '\n' || c == ')' || c == ']' || c == '}' || c == ',' || c == ';'
    }

    /** True when `[quote] identifier [quote] [:=]` follows — i.e. a genuinely new key/value pair. */
    private fun nextKeyFollows(text: String, from: Int): Boolean {
        var k = from
        while (k < text.length && (text[k] == ' ' || text[k] == '\t')) k++
        if (k < text.length && text[k] == '\\') k++
        if (k < text.length && (text[k] == '"' || text[k] == '\'')) k++
        if (k >= text.length || !isIdentStart(text[k])) return false
        while (k < text.length && (isIdentChar(text[k]) || text[k] == '.')) k++
        if (k < text.length && text[k] == '\\') k++
        if (k < text.length && (text[k] == '"' || text[k] == '\'')) k++
        while (k < text.length && (text[k] == ' ' || text[k] == '\t')) k++
        return k < text.length && (text[k] == ':' || text[k] == '=')
    }

    // ============================================================== shape rules (never holed)

    private class Rule(pattern: String, private val template: String) {
        private val regex = Regex(pattern, RegexOption.IGNORE_CASE)
        fun apply(text: String): String = regex.replace(text, template)
    }

    private const val HEAD = """(?<![A-Za-z0-9_])"""

    /** One character of a path body. `/` is included; whitespace and structural chars are not. */
    private const val PATH_CHAR = """[^\s"',()\[\]{}\n]"""

    /** A path body, admitting an internal space only when the next token still contains a `/`. */
    private const val PATH_BODY = """(?:$PATH_CHAR|[ ](?=$PATH_CHAR*/))*"""

    /** Either a `file://` URL prefix, or a real token start (never mid-token: `pkg/data/data/x`). */
    private const val PATH_START = """(?:file://|(?<![\w/]))"""

    private const val PATH_ROOT_ANY =
        """/(?:data/user(?:_de)?/\d+|data/data|data/media/\d+|""" +
            """storage/emulated/\d+|storage/self/primary|sdcard|mnt/sdcard|mnt/user/\d+)"""

    /** THIS app's artifact directory — `applicationId` is pinned; see the class doc. */
    private const val PATH_ROOT_APP_BOOKS =
        """/(?:data/user(?:_de)?/\d+|data/data)/com\.vreader\.app/files/books/"""

    /**
     * Applied IN ORDER, after [scanKeyedValues]. Only the app-books rule is order-dependent (it must
     * precede the generic path rules, which would swallow the fingerprint key).
     */
    private val SHAPE_RULES: List<Rule> = listOf(
        // OpenAI-style provider keys (`sk-…`, `sk-proj-…`, `sk-ant-…`) with no key name at all.
        Rule("""${HEAD}sk-[A-Za-z0-9_-]{12,}""", PLACEHOLDER),

        // JWT — three base64url segments.
        Rule("""${HEAD}eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+""", PLACEHOLDER),

        // URL credentials `scheme://user:pass@host` — user and host are diagnostic context and
        // survive. The username may be EMPTY (`https://:pw@host` is legal userinfo). The password
        // class admits `@` and relies on greedy backtracking to the last `@` WITHIN the authority:
        // `?` and `#` are excluded so a query-string `@` cannot pull the match past the host.
        // The head EXCLUDES `+.-` as well as word characters, and the scheme run is POSSESSIVE:
        // without both, `a-a-a-…` gives every `a` a viable start whose scheme run consumes the rest
        // of the input before failing — measured quadratic (15s timeout) on a 100 KB run. The class
        // cannot span `://` anyway, so possessiveness costs no real match.
        Rule("""(?<![A-Za-z0-9_+.\-])([a-z][a-z0-9+.-]*+://[^\s:/@]*:)[^\s/?#]+(@)""",
            "\$1$PLACEHOLDER\$2"),

        // THIS app's book artifact — the trailing segment is the sanitised fingerprintKey and
        // SURVIVES. The trailing `(?!$PATH_CHAR)` demands a real path END so a nested
        // `books/sub/evil.epub` cannot satisfy it by backtracking the capture.
        Rule(
            """$PATH_START$PATH_ROOT_APP_BOOKS([^/\s"',()\[\]{}\n]+)(?!$PATH_CHAR)""",
            "$PATH_PLACEHOLDER/\$1",
        ),

        // `file://` URLs — the whole URL is a path, with the same space handling as a raw path.
        Rule("""file://$PATH_BODY""", PATH_PLACEHOLDER),

        // SAF `content://` URIs — the AUTHORITY says which provider failed and is kept; the
        // document path embeds user filenames and goes.
        Rule("""(content://[^/\s"',()\[\]{}\n]+)/$PATH_BODY""", "\$1/$PATH_PLACEHOLDER"),

        // Every other app-private or shared-storage path.
        Rule("""$PATH_START$PATH_ROOT_ANY$PATH_BODY""", PATH_PLACEHOLDER),
    )
}
