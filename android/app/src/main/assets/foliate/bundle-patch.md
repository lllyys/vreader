# foliate-spike bundle provenance (WI-0)

`foliate-bundle.js` here is the iOS-vendored bundle **with a security patch**.

- **Source**: `vreader/Services/Foliate/JS/foliate-bundle.js`
  SHA-256 `3463a2ee41168f1549f5ed49fdcfe9eb521dbb5adab3702c63c429838480503d`
- **Patched** SHA-256 `aa4327f1aac8b4c65a4ca653e53118ca84650887a35e51b0bf7592c4d12aa807`
- **Patch** (exactly 2 occurrences — paginator + fixed-layout section iframes):
  ```
  sed 's/allow-same-origin allow-scripts/allow-same-origin/g'
  ```
  i.e. strip `allow-scripts` from EVERY foliate section-iframe sandbox so
  book-embedded JavaScript cannot execute (and therefore cannot reach the native
  bridge via `parent.*`). Reflowable path = `paginator.js:277`; fixed-layout path =
  `fixed-layout.js:86`.

The source comments say `allow-scripts` is "needed for events because of a **WebKit**
bug" — WI-0's spike empirically determines whether removing it breaks foliate's
rendering/event handling on **Android Chromium WebView** (where that WebKit bug
should not apply). If it does break, the fallback is CSP `script-src 'none'` on
section blobs and/or HTML sanitization (see the plan's R9).
