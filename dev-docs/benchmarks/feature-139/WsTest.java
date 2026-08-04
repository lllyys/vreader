import java.util.regex.*;

/**
 * D1b probe - does java.util.regex `\s` accept the separators ICU's `\s` accepts?
 *
 * DELIBERATE DEVIATION from the plan's Appendix A.4 listing, which mandates unicode-escaped
 * literals: every CJK character and separator here is built from its CODE POINT instead.
 * Same guarantee, strictly stronger. The plan's clause exists because a literal NBSP is
 * fragile - Gate-2 rounds 3 and 4 each caught one that copy-paste had silently normalized to an
 * ASCII space, which makes the probe's output a lie. Committing this file hit that failure
 * twice more (the authoring pipeline rewrote each unicode escape back into a literal, then
 * flattened the NBSP literal to a plain space), so nothing load-bearing is written literally
 * here and no re-encoding can mangle it. The closing `separators tested:` line prints the code
 * points actually exercised, so the output proves its own provenance.
 *
 *   U+7B2C chapter-ordinal head   U+4E00 numeral one   U+7AE0 chapter unit
 *   U+3000 IDEOGRAPHIC SPACE      U+00A0 NO-BREAK SPACE
 */
public class WsTest {
  static final String WS = "[\\s\\p{Z}\\x{0085}]";

  static String cp(int c) { return new String(Character.toChars(c)); }

  static final String DI = cp(0x7B2C);
  static final String YI = cp(0x4E00);
  static final String ZHANG = cp(0x7AE0);
  static final String IDEO = cp(0x3000);
  static final String NBSP = cp(0x00A0);

  static void t(String label, String pat, String s){
    System.out.println(label + " -> " + Pattern.compile(pat).matcher(s).find());
  }

  public static void main(String[] a){
    String ideo = DI + IDEO + YI + IDEO + ZHANG;
    String nbsp = DI + NBSP + YI + NBSP + ZHANG;
    String rx   = DI + "\\s{0,4}[" + YI + "]\\s{0,4}" + ZHANG;
    String rxWs = DI + WS + "{0,4}[" + YI + "]" + WS + "{0,4}" + ZHANG;
    t("java \\s  + U+3000", rx,   ideo);
    t("java \\s  + U+00A0", rx,   nbsp);
    t("WS class + U+3000 ", rxWs, ideo);
    t("WS class + U+00A0 ", rxWs, nbsp);
    System.out.println("separators tested: U+" + String.format("%04X", (int) ideo.charAt(1))
        + " and U+" + String.format("%04X", (int) nbsp.charAt(1)));
  }
}
