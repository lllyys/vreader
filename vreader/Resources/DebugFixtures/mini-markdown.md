# VReader Mini Markdown Fixture

A small synthetic Markdown document used by VReader's DebugBridge
`vreader-debug://seed?fixture=mini-markdown` command for automated
verification of the `.md` reader path.

## Chapter 1

This is the first paragraph of the first chapter. It contains enough
prose to exercise reflow and the Markdown attributed-string renderer
without being so large that fixture loading dominates a test run.

Second paragraph with *emphasized* text and **strong** text to exercise
inline Markdown rendering. It also has a [link](https://example.com) so
the renderer's link styling is covered.

## Chapter 2

Third paragraph in the second chapter. The two `##` headings give the
auto-TOC a non-trivial structure to extract.

- A list item.
- Another list item.

> A blockquote, so the renderer's blockquote background is exercised.

`A code span` and a fenced block follow:

```
plain code block
```

The end.
