# shellcheck shell=bash
# xcodebuild helpers shared by scripts/dev/ci_tests.sh (simulator) and scripts/dev/device_tests.sh
# (iPhone). Sourced from the repository root, not run. Written for macOS's own Bash 3.2: no mapfile,
# no namerefs, and an array that may be empty is expanded as ${a[@]+"${a[@]}"} so `set -u` allows it.

# Generates the Xcode project and the test plans, as ci.yml does before every build.
xcb_regenerate() {
  xcodegen generate
  python3 scripts/ci/write_testplan.py
}

# Reads stdin into XCB_LINES, one element per non-empty line (xcodebuild arguments, one per line).
xcb_read_lines() {
  XCB_LINES=()
  local line
  while IFS= read -r line; do
    if [ -n "$line" ]; then
      XCB_LINES+=("$line")
    fi
  done
}

# xcb_test_with_retry SHARD OUT NAME
#
# Runs `xcodebuild test-without-building "${XCB_TEST_ARGS[@]}" "${XCB_SELECTORS[@]}"` into
# OUT/NAME.xcresult. When it fails, runs the failed tests once more on their own into
# OUT/NAME-retry.xcresult, the way ci.yml's ios-tests job does (test_shards.py retry-args SHARD decides
# whether the shard retries, and which tests). Then names each failed and flaky test with
# xcresult_report.py, writing OUT/NAME-summary.md, and returns test_shards.py's verdict for SHARD.
#
# Sets XCB_TESTS_JSON, XCB_RETRY_JSON (empty when nothing ran again) and XCB_FAILED_IDS for the caller.
# A TEST_RUNNER_REPORTS_DIR in the environment gets a retry/ folder for the second run, as in CI.
xcb_test_with_retry() {
  local shard="$1" out="$2" name="$3" code reporter="" reports="${TEST_RUNNER_REPORTS_DIR:-}"
  local bundle="$out/$name.xcresult" again="$out/$name-retry.xcresult"
  XCB_TESTS_JSON="$out/$name-tests.json"
  XCB_RETRY_JSON=""
  XCB_FAILED_IDS="$out/$name-failed-tests.txt"
  rm -rf "$bundle" "$again" "$XCB_TESTS_JSON" "$out/$name-retry-tests.json" "$XCB_FAILED_IDS" \
    "$out/$name-summary.md"

  set +e
  xcodebuild test-without-building "${XCB_TEST_ARGS[@]}" -resultBundlePath "$bundle" \
    ${XCB_SELECTORS[@]+"${XCB_SELECTORS[@]}"} 2>&1 | tee "$out/$name.log"
  code=${PIPESTATUS[0]}
  set -e
  echo "== xcodebuild exited $code"

  if [ "$code" != 0 ] && [ -f "$bundle/Info.plist" ] \
    && xcrun xcresulttool get test-results tests --path "$bundle" > "$out/$name-first.json"; then
    python3 scripts/ci/xcresult_report.py "$out/$name-first.json" --retry-ids "$out/$name-failed.txt" \
      > /dev/null || true
    python3 scripts/ci/test_shards.py retry-args "$shard" "$out/$name-failed.txt" > "$out/$name-retry.txt"
    xcb_read_lines < "$out/$name-retry.txt"
    if [ "${#XCB_LINES[@]}" -gt 0 ]; then
      echo "== Running again: ${XCB_LINES[*]}"
      set +e
      TEST_RUNNER_REPORTS_DIR="${reports:+$reports/retry}" xcodebuild test-without-building \
        "${XCB_TEST_ARGS[@]}" -resultBundlePath "$again" "${XCB_LINES[@]}" 2>&1 | tee "$out/$name-retry.log"
      echo "== xcodebuild (failed tests again) exited ${PIPESTATUS[0]}"
      set -e
    fi
  fi

  if [ ! -f "$bundle/Info.plist" ]; then
    echo "== xcodebuild left no result bundle: see $out/$name.log" >&2
  elif xcrun xcresulttool get test-results tests --path "$bundle" > "$XCB_TESTS_JSON"; then
    local retries=()
    if [ -f "$again/Info.plist" ] \
      && xcrun xcresulttool get test-results tests --path "$again" > "$out/$name-retry-tests.json"; then
      XCB_RETRY_JSON="$out/$name-retry-tests.json"
      retries=(--retries "$XCB_RETRY_JSON")
    fi
    set +e
    python3 scripts/ci/xcresult_report.py "$XCB_TESTS_JSON" ${retries[@]+"${retries[@]}"} \
      --failed-ids "$XCB_FAILED_IDS" --summary "$out/$name-summary.md"
    reporter=$?
    set -e
  fi
  python3 scripts/ci/test_shards.py verdict "$shard" --xcodebuild-exit "$code" --reporter-exit "$reporter"
}
