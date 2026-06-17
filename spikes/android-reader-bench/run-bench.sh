#!/usr/bin/env bash
# Spike B (#105) WI-2 — reproducible scroll-benchmark recipe (the
# "minimally-automatable Android verification lane" the ADR calls for).
# Instrumentation-first / NO UI automation: builds, installs, pushes the real
# 1042-chapter CJK corpus, drives a deterministic chapter sweep in-process,
# pulls metrics.json, and scans logcat for renderer crashes.
#
#   spikes/android-reader-bench/run-bench.sh                 # full 250-chapter sweep
#   CHAPTERS=12 SCROLLS=2 spikes/android-reader-bench/run-bench.sh   # quick smoke
#
# Prereqs: an android-35+ emulator booted (adb device online), Android SDK +
# JDK 17 on PATH (see /tmp/android-env.sh), and the corpus on the host at
# $CORPUS (a real 1000+-spine CJK EPUB from the gitignored test-books/).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"

PKG="vreader.spike"
RUNNER="$PKG.test/androidx.test.runner.AndroidJUnitRunner"
DEVDIR="/sdcard/Android/data/$PKG/files"
CHAPTERS="${CHAPTERS:-250}"
SCROLLS="${SCROLLS:-4}"
CORPUS="${CORPUS:-$REPO/test-books/books/epub/道诡异仙 - 狐尾的笔.epub}"
OUT="${OUT:-/tmp/spikeB-metrics.json}"

command -v adb >/dev/null || { echo "FAIL: adb not on PATH (source /tmp/android-env.sh)"; exit 1; }
adb get-state >/dev/null 2>&1 || { echo "FAIL: no adb device (boot the emulator)"; exit 1; }
[[ -f "$CORPUS" ]] || { echo "FAIL: corpus not found at $CORPUS"; exit 1; }

echo "== build + install (app + androidTest) =="
( cd "$HERE" && ./gradlew :app:assembleDebug :app:assembleDebugAndroidTest --console=plain --no-daemon ) || { echo "FAIL: build"; exit 1; }
adb install -r "$HERE/app/build/outputs/apk/debug/app-debug.apk" >/dev/null || exit 1
adb install -r "$HERE/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk" >/dev/null || exit 1

echo "== push corpus + mini-cjk anchor fixture =="
adb shell mkdir -p "$DEVDIR" >/dev/null 2>&1
adb push "$CORPUS" "$DEVDIR/corpus.epub" >/dev/null || { echo "FAIL: push corpus"; exit 1; }
[[ -f "$HERE/fixtures/mini-cjk.epub" ]] && adb push "$HERE/fixtures/mini-cjk.epub" "$DEVDIR/mini-cjk.epub" >/dev/null
adb shell rm -f "$DEVDIR/metrics.json"
adb logcat -c

# SUITE=anchor runs the WI-3 CFI/selection anchor-restore probes instead of the
# WI-2 scroll benchmark. Default = scroll.
if [[ "${SUITE:-scroll}" == "anchor" ]]; then
    echo "== run anchor-restore probes (WI-3) =="
    adb shell am instrument -w -e class "$PKG.AnchorRestoreTest" "$RUNNER" 2>&1 | tee /tmp/spikeB-instrument.log
    adb logcat -d -s AnchorRestore 2>/dev/null | tail -8
    if grep -q "OK (3 tests)" /tmp/spikeB-instrument.log; then
        echo "BENCH RESULT: PASS (anchor)"; exit 0
    else
        echo "BENCH RESULT: FAIL (anchor)"; exit 1
    fi
fi

echo "== run sweep: $CHAPTERS chapters x $SCROLLS scrolls =="
adb shell am instrument -w -e chapters "$CHAPTERS" -e scrollsPerChapter "$SCROLLS" \
    -e class "$PKG.ReaderScrollBenchmark" "$RUNNER" 2>&1 | tee /tmp/spikeB-instrument.log

echo "== pull metrics =="
adb pull "$DEVDIR/metrics.json" "$OUT" >/dev/null 2>&1 || echo "warn: no metrics.json (test may have failed early)"

echo "== renderer stability (logcat) =="
CRASHES="$(adb logcat -d 2>/dev/null | grep -ciE 'FATAL EXCEPTION|render process (gone|crash)|chromium.*fatal')"
echo "renderer-crash lines: $CRASHES"

if grep -q "OK (1 test)" /tmp/spikeB-instrument.log && [[ "$CRASHES" -eq 0 ]]; then
    echo "BENCH RESULT: PASS  (metrics: $OUT)"; exit 0
else
    echo "BENCH RESULT: FAIL"; exit 1
fi
