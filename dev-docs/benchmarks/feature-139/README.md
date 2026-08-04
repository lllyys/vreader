# Feature #139 — Gate-1 measurement probes (TXT/MD auto-generated Contents)

The four standalone Java programs behind every number in
`dev-docs/plans/20260804-feature-139-android-txt-md-toc.md` §5 and §3.5, committed by WI-1 so the
plan's evidence is reproducible instead of merely quoted. They are **historical evidence, not
build inputs** — nothing in `android/` compiles or runs them, and no Gradle source set includes
this directory.

| File | Plan appendix | Answers |
| --- | --- | --- |
| `RuleScan.java` | A.1 | Port-fidelity + cost: runs the 14 iOS-enabled rules over the real 14 MB CJK book — detection over the 512 K sample, extraction over the full text. |
| `HeadScan.java` | A.2 | Independent cross-validation of the entry count by a regex-free prefix scanner. |
| `DigitTest.java` | A.3 | The **D1** divergence (Java `\d` vs ICU `\d`) and the R4 ReDoS bound. |
| `WsTest.java` | A.4 | The **D1b** divergence (Java `\s` vs ICU `\s`) on U+3000 and NBSP. |

## Running them

JDK 17 (`/opt/homebrew/opt/openjdk@17` on this machine). Compile out-of-tree so no `.class`
files land in the repo:

```bash
javac -encoding UTF-8 -d /tmp/f139 dev-docs/benchmarks/feature-139/*.java

java -cp /tmp/f139 DigitTest
java -cp /tmp/f139 WsTest
java -Xmx1g -cp /tmp/f139 RuleScan test-books/books/txt/黑暗血时代.txt
java -Xmx1g -cp /tmp/f139 HeadScan test-books/books/txt/黑暗血时代.txt
```

`test-books/` is gitignored and local-only, so the two book-scale probes only run on a machine
that has the fixture; `DigitTest` and `WsTest` are self-contained and run anywhere.

## Output reproduced by WI-1 (2026-08-04, JDK 17, Apple silicon)

```
$ java -cp /tmp/f139 DigitTest
java \d on fullwidth: false      <- the D1 divergence
java \d +U flag     : true       <- ICU semantics
explicit 0-9０-９    : true       <- the D1 fix, shipped as TxtTocRules.DIGIT
ReDoS probe(2000 numerals) found=false ms=1   <- the R4 bound

$ java -cp /tmp/f139 WsTest
java \s  + U+3000 -> false       <- the D1b divergence (CJK-critical)
java \s  + U+00A0 -> false
WS class + U+3000  -> true       <- the D1b fix, shipped as TxtTocRules.WS
WS class + U+00A0  -> true
separators tested: U+3000 and U+00A0

$ java -Xmx1g -cp /tmp/f139 RuleScan test-books/books/txt/黑暗血时代.txt
decoded as UTF-16
chars = 7029609
rep0 DETECT best=1 matches=171 ms=80
  EXTRACT entries=1859 ms=23 firstOffset=20 first='　　第一章　太阳消失' last='　　第一千八百六十章 左旋封锁'
rep1 DETECT best=1 matches=171 ms=24
  EXTRACT entries=1859 ms=22 …
rep2 DETECT best=1 matches=171 ms=24
  EXTRACT entries=1859 ms=22 …

$ java -Xmx1g -cp /tmp/f139 HeadScan test-books/books/txt/黑暗血时代.txt
line starts = 254109
rep 0: headings = 1860  scan ms = 12
rep 1: headings = 1860  scan ms = 3
rep 2: headings = 1860  scan ms = 5
```

`DigitTest`, `WsTest` and `RuleScan` reproduce the plan's appendices **exactly**. Two deltas are
recorded below rather than papered over.

## Recorded deltas between these listings and the plan / iOS

1. **`HeadScan` counts 1 860, not the 1 859 claimed in Appendix A.2.** The plan reads this probe
   as agreeing exactly with `RuleScan`'s 1 859; it is off by one. The extra hit is the *loose*
   match Appendix A.5's own Python probe already isolates (`loose: 1860  strict: 1859` — a line
   such as `第一回合，…` that a boundary refinement rejects). So the cross-validation still holds
   in substance — two unrelated algorithms agree to within that single known loose match — but
   the number in A.2 is wrong and the plan should be corrected. **No effect on shipped code:**
   `HeadScan` is the rejected hand-rolled alternative (plan §3.4), not the algorithm being ported.

2. **`RuleScan`'s rule 5 uses U+534D where iOS uses U+5350** (two variants of the same symbol;
   both are `e5 8d …` in UTF-8, differing in the last byte). The listing is committed verbatim as
   the plan requires, so the discrepancy is preserved here; **the production port follows iOS**
   (`TxtTocRules` rule 5 carries U+5350, matching `TXTTocRuleEngine.swift:182`). The benchmark
   numbers are unaffected — rule 1 wins detection on this book with 171 sample matches, and rule
   5 never becomes the extraction rule.

3. **`WsTest` deviates from A.4's mandated form.** A.4 binds WI-1 to write every CJK character and
   separator as a unicode escape, because Gate-2 rounds 3 and 4 each caught a literal NBSP that
   copy-paste had silently normalized to an ASCII space. Committing it hit that exact failure
   twice more (the authoring pipeline rewrote each escape back into a literal, then flattened the
   NBSP to a space), so the committed probe builds each character from its **code point** — a
   strictly stronger version of the same guarantee, with no non-ASCII byte in the file at all.
   The added `separators tested:` line prints the code points actually exercised, so the output
   proves it really tested U+00A0 and not a space.

The same code-point discipline is used in `TxtTocRulesTest.kt` for the D1b samples, for the same
reason.
