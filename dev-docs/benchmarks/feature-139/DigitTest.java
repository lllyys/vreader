import java.util.regex.*;
public class DigitTest {
  public static void main(String[] x){
    String fw = "第１２章　全角数字";
    System.out.println("java \\d on fullwidth: " + Pattern.compile("第[\\d]+章").matcher(fw).find());
    System.out.println("java \\d +U flag     : " + Pattern.compile("(?U)第[\\d]+章").matcher(fw).find());
    System.out.println("explicit 0-9０-９    : " + Pattern.compile("第[0-9０-９]+章").matcher(fw).find());
    StringBuilder sb = new StringBuilder("第");
    for (int i = 0; i < 2000; i++) sb.append("一");
    sb.append("的故事没有章字");
    String p = "^[ 　\t]{0,4}(?:第\\s{0,4}[\\d一二三十百千万]+?\\s{0,4}(?:章|节)).{0,30}$";
    long t0 = System.nanoTime();
    boolean f = Pattern.compile(p, Pattern.MULTILINE).matcher(sb).find();
    System.out.println("ReDoS probe(2000 numerals) found=" + f + " ms=" + (System.nanoTime()-t0)/1_000_000);
  }
}
