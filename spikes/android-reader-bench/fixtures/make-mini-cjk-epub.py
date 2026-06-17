#!/usr/bin/env python3
"""Spike B (#105) WI-3 — generate a tiny, deterministic CJK EPUB for anchor /
selection-restore probes. Real-books-first exception (AGENTS.md): the
1042-chapter 道诡异仙 book is used for the WI-2 perf/memory legs, but exact
anchor assertions need a controlled tiny structure (known chapters, known
paragraphs, known char offsets) a 19MB book can't give cheaply. 4 chapters x 4
paragraphs, each paragraph a UNIQUE CJK sentence so a restored locator's
paragraph is identifiable. Mirrors the iOS `mini-cjk` fixture intent.

Run:  python3 make-mini-cjk-epub.py   ->  mini-cjk.epub  (committed, ~few KB)
"""
import os
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "mini-cjk.epub")

# 4 chapters x 24 paragraphs. Chapters are deliberately TALLER than the viewport
# (multi-screen) so a saved scroll position is a non-trivial within-chapter
# anchor, not just "chapter start" — that's what makes the restore probe
# meaningful. Each paragraph is a UNIQUE CJK sentence (a rotated 24-char Han
# string, doubled to ~48 chars for height) so char offsets are deterministic and
# the text identifies the exact paragraph on restore. id = c{chap}p{para}.
PARAS_PER_CHAPTER = 24
CHAPTERS = []
HAN = "甲乙丙丁戊己庚辛壬癸子丑寅卯辰巳午未申酉戌亥天地"  # 24 distinct Han chars
for c in range(1, 5):
    paras = []
    for p in range(1, PARAS_PER_CHAPTER + 1):
        # rotate the 24-char string by a per-(chap,para) shift -> unique sentence
        shift = (c * 7 + p) % len(HAN)
        text = (HAN[shift:] + HAN[:shift]) * 2
        paras.append((f"c{c}p{p}", f"第{c}章第{p}段{text}"))
    CHAPTERS.append(paras)

CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

def chapter_xhtml(idx, paras):
    body = "\n".join(
        f'    <p id="{pid}">{text}</p>' for pid, text in paras
    )
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xml:lang="zh" lang="zh">
<head><title>第{idx}章</title><meta charset="utf-8"/></head>
<body>
    <h1 id="ch{idx}">第{idx}章</h1>
{body}
</body>
</html>
"""

manifest_items = ['<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>']
spine_items = []
for c in range(1, 5):
    manifest_items.append(f'<item id="ch{c}" href="chapter{c}.xhtml" media-type="application/xhtml+xml"/>')
    spine_items.append(f'<itemref idref="ch{c}"/>')

OPF = f"""<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">urn:uuid:vreader-spike-mini-cjk-0001</dc:identifier>
    <dc:title>迷你测试书 mini-cjk</dc:title>
    <dc:language>zh</dc:language>
  </metadata>
  <manifest>
    {"".join(chr(10) + "    " + m for m in manifest_items)}
  </manifest>
  <spine>
    {"".join(chr(10) + "    " + s for s in spine_items)}
  </spine>
</package>
"""

nav_links = "\n".join(
    f'      <li><a href="chapter{c}.xhtml">第{c}章</a></li>' for c in range(1, 5)
)
NAV = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE html>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" xml:lang="zh" lang="zh">
<head><title>目录</title><meta charset="utf-8"/></head>
<body>
  <nav epub:type="toc" id="toc">
    <h1>目录</h1>
    <ol>
{nav_links}
    </ol>
  </nav>
</body>
</html>
"""

FIXED_DATE = (1980, 1, 1, 0, 0, 0)  # deterministic: no local wall-clock in the binary

def _zi(name, stored=False):
    info = zipfile.ZipInfo(name, date_time=FIXED_DATE)
    info.compress_type = zipfile.ZIP_STORED if stored else zipfile.ZIP_DEFLATED
    return info

def main():
    if os.path.exists(OUT):
        os.remove(OUT)
    # Fixed entry order + fixed timestamps -> byte-identical on regeneration.
    with zipfile.ZipFile(OUT, "w") as z:
        # mimetype MUST be first and STORED (uncompressed) per EPUB OCF.
        z.writestr(_zi("mimetype", stored=True), "application/epub+zip")
        z.writestr(_zi("META-INF/container.xml"), CONTAINER)
        z.writestr(_zi("OEBPS/content.opf"), OPF)
        z.writestr(_zi("OEBPS/nav.xhtml"), NAV)
        for c in range(1, 5):
            z.writestr(_zi(f"OEBPS/chapter{c}.xhtml"), chapter_xhtml(c, CHAPTERS[c - 1]))
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes), 4 chapters x {PARAS_PER_CHAPTER} paragraphs")

if __name__ == "__main__":
    main()
