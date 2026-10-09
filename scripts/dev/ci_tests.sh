#!/usr/bin/env bash
# Runs one shard of the iOS tests on a Mac the way CI does (ci.yml: ios-build, then ios-tests): the
# same build for testing, signed ad hoc, on the pinned simulator, then the same shard's selectors and
# retry flags from scripts/ci/test_shards.py, against that build.
#
#   scripts/dev/ci_tests.sh                          # the unit shard
#   scripts/dev/ci_tests.sh --shard ui-1             # unit, ui-1, ui-2 or ui-3
#   scripts/dev/ci_tests.sh --only PDFAlgoProUITests/ReaderUITests   # a focused run, as only_testing
#
# The simulator is ci.yml's (SIMULATOR_NAME and SIMULATOR_RUNTIME, which may be overridden). The build
# goes to .build/ci-tests (ignored by git); the result bundle to .build/ci-tests/<shard>.xcresult.
# Needs XcodeGen and the pinned Xcode, selected with xcode-select.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"

shard=unit
only=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    --shard) shard="${2:?--shard needs unit, ui-1, ui-2 or ui-3}"; shift 2 ;;
    --only) only="${2:?--only needs Target, Target/Class or Target/Class/method}"; shift 2 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done
if [ -n "$only" ]; then
  shard=focused
fi

# The simulator ci.yml pins, read from its env block so the two never drift apart.
pinned() { sed -n "s/^  $1: *//p" .github/workflows/ci.yml | head -1; }
SIMULATOR_NAME="${SIMULATOR_NAME:-$(pinned SIMULATOR_NAME)}"
SIMULATOR_RUNTIME="${SIMULATOR_RUNTIME:-$(pinned SIMULATOR_RUNTIME)}"
export SIMULATOR_NAME SIMULATOR_RUNTIME

# The selectors first, so a malformed --only or shard fails before the build.
selectors="$(python3 scripts/ci/test_shards.py args "$shard" --only-testing "$only")" || {
  echo "$selectors" >&2
  exit 2
}
args=()
while IFS= read -r arg; do
  args+=("$arg")
done <<< "$selectors"

out="$root/.build/ci-tests"
mkdir -p "$out"
xcodegen generate
python3 scripts/ci/write_testplan.py
device="$(scripts/ci/pinned_simulator.sh)"
echo "== $SIMULATOR_NAME ($SIMULATOR_RUNTIME): $device"

xcodebuild build-for-testing -scheme PDFAlgoPro -testPlan PDFAlgoPro -destination "id=$device" \
  -derivedDataPath "$out/DD" CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=

rm -rf "$out/$shard.xcresult"
echo "== $shard: ${args[*]}"
TEST_RUNNER_SNAPSHOT_TESTING_RECORD=never TEST_RUNNER_REPORTS_DIR="$out/reports" \
  xcodebuild test-without-building -scheme PDFAlgoPro -testPlan PDFAlgoPro -derivedDataPath "$out/DD" \
  -destination "id=$device" -enableCodeCoverage YES -resultBundlePath "$out/$shard.xcresult" "${args[@]}"
