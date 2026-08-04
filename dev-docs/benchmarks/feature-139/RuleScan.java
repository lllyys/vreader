import java.nio.file.*; import java.nio.charset.*; import java.util.*; import java.util.regex.*;

public class RuleScan {
    static final String CJKNUM = "\\d〇零一二两三四五六七八九十百千万壹贰叁肆伍陆柒捌玖拾佰仟";
    static final String[][] RULES = {
        {"1","^[ 　\t]{0,4}(?:序章|楔子|正文(?!完|结)|终章|后记|尾声|番外|第\\s{0,4}["+CJKNUM+"]+?\\s{0,4}(?:章|节(?!课)|卷|集(?![合和])|部(?![分赛游])|篇(?!张))).{0,30}$"},
        {"2","^[ 　\t]{0,4}[第（(]?\\s{0,4}["+CJKNUM+"]+?\\s{0,4}[章节卷集部篇回话]\\s?.{0,30}$"},
        {"3","^[ 　\t]{0,4}(?:[Cc]hapter|[Ss]ection|[Pp]art|[Ee]pisode)\\s{0,4}\\d{1,4}.{0,30}$"},
        {"4","^[ 　\t]{0,4}\\d{1,5}[：:,.， 、_—\\-].{1,30}$"},
        {"5","^[ 　\t]{0,4}[【\\[☆★●◆◇○◎□■△▲※卍].{1,30}$"},
        {"6","^[ 　\t]{0,4}正文\\s.{0,20}$"},
        {"7","^[ 　\t]{0,4}(?:卷|篇|部|集)\\s{0,4}["+CJKNUM+"]+.{0,30}$"},
        {"8","^[ 　\t]{0,4}[☆★].{1,30}$"},
        {"9","^[ 　\t]{0,4}[Vv]ol(?:ume)?\\s{0,4}\\d{1,4}.{0,30}$"},
        {"10","^[ 　\t]{0,4}[Bb]ook\\s{0,4}\\d{1,4}.{0,30}$"},
        {"13","^[ 　\t]{0,4}[\\(（]\\d{1,5}[\\)）].{1,30}$"},
        {"14","^[ 　\t]{0,4}\\d{1,5}\\..{1,30}$"},
        {"20","^[ 　\t]{0,4}(?:[Pp]rologue|[Ee]pilogue|[Ii]nterlude|[Pp]reface|[Ff]oreword|[Aa]fterword|[Ii]ntroduction|[Cc]onclusion).{0,30}$"},
        {"23","^[ 　\t]{0,4}第\\s{0,4}["+CJKNUM+"]+?\\s{0,4}[回话].{0,30}$"},
    };

    public static void main(String[] a) throws Exception {
        byte[] raw = Files.readAllBytes(Paths.get(a[0]));
        String text = null;
        for (String cs : new String[]{"UTF-16","UTF-8","GBK","GB18030"}) {
            CharsetDecoder d = Charset.forName(cs).newDecoder()
                .onMalformedInput(CodingErrorAction.REPORT)
                .onUnmappableCharacter(CodingErrorAction.REPORT);
            try { text = d.decode(java.nio.ByteBuffer.wrap(raw)).toString();
                  System.out.println("decoded as " + cs); break; } catch (Exception e) { }
        }
        if (text == null) { System.out.println("undecodable"); return; }
        System.out.println("chars = " + text.length());
        int SAMPLE = 512 * 1024;
        String sample = text.length() > SAMPLE ? text.substring(0, SAMPLE) : text;

        for (int rep = 0; rep < 3; rep++) {
            long t0 = System.nanoTime();
            String bestId = null, bestPat = null; int best = 0;
            for (String[] r : RULES) {
                Matcher m = Pattern.compile(r[1], Pattern.MULTILINE).matcher(sample);
                int c = 0; while (m.find()) c++;
                if (c > best) { best = c; bestId = r[0]; bestPat = r[1]; }
            }
            long t1 = System.nanoTime();
            System.out.println("rep"+rep+" DETECT best=" + bestId + " matches=" + best
                + " ms=" + (t1-t0)/1_000_000);
            if (best < 2) { System.out.println("  below threshold, no TOC"); continue; }
            long t2 = System.nanoTime();
            Matcher m = Pattern.compile(bestPat, Pattern.MULTILINE).matcher(text);
            int n = 0; String first = null, last = null; int firstOff = -1;
            while (m.find()) { n++; if (first == null) { first = m.group().trim(); firstOff = m.start(); }
                               last = m.group().trim(); }
            long t3 = System.nanoTime();
            System.out.println("  EXTRACT entries=" + n + " ms=" + (t3-t2)/1_000_000
                + " firstOffset=" + firstOff + " first='" + first + "' last='" + last + "'");
        }
    }
}
