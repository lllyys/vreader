import java.nio.file.*; import java.nio.charset.*;

public class HeadScan {
    static boolean isCjkNum(char c) { return "零〇一二三四五六七八九十百千万两".indexOf(c) >= 0; }
    static boolean isAsciiDigit(char c) { return c >= '0' && c <= '9'; }
    static boolean isFullWidthDigit(char c) { return c >= '０' && c <= '９'; }

    public static void main(String[] args) throws Exception {
        String text = new String(Files.readAllBytes(Paths.get(args[0])), "UTF-16");
        int n = text.length();
        int[] starts = new int[1024]; int count = 0; starts[count++] = 0;
        for (int i = 0; i < n; ) {
            char c = text.charAt(i);
            if (c == '\n') { i++; if (i < n) { if (count == starts.length) starts = java.util.Arrays.copyOf(starts, starts.length*2); starts[count++] = i; } }
            else if (c == '\r') { i++; if (i < n && text.charAt(i)=='\n') i++;
                if (i < n) { if (count == starts.length) starts = java.util.Arrays.copyOf(starts, starts.length*2); starts[count++] = i; } }
            else i++;
        }
        System.out.println("line starts = " + count);
        for (int rep = 0; rep < 3; rep++) {
            long s0 = System.nanoTime(); int hits = 0; final int PREFIX = 64;
            for (int li = 0; li < count; li++) {
                int st = starts[li], end = (li + 1 < count) ? starts[li+1] : n, p = st;
                while (p < end && (text.charAt(p)==' '||text.charAt(p)=='\t'||text.charAt(p)=='　')) p++;
                if (p >= end) continue;
                char c0 = text.charAt(p);
                if (c0 != '第' && c0 != '#') continue;
                int lineEnd = Math.min(end, p + PREFIX);
                if (c0 == '第') {
                    int q = p + 1, numLen = 0;
                    while (q < lineEnd && (isCjkNum(text.charAt(q)) || isAsciiDigit(text.charAt(q)) || isFullWidthDigit(text.charAt(q)))) { q++; numLen++; }
                    if (numLen > 0 && q < lineEnd) { char u = text.charAt(q);
                        if (u=='章'||u=='节'||u=='卷'||u=='回'||u=='部'||u=='篇') hits++; }
                } else hits++;
            }
            System.out.println("rep " + rep + ": headings = " + hits + "  scan ms = " + (System.nanoTime()-s0)/1_000_000);
        }
    }
}
