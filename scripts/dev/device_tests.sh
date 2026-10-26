#!/usr/bin/env bash
# Runs Device.xctestplan (the app's unit and UI tests) on a connected iPhone, then records the run and
# prints the manual checklist (docs/process/device-test-run.md).
#
#   scripts/dev/device_tests.sh --device ID          # ID: the phone's Identifier in `xcrun devicectl list devices`
#   DEVICE_ID=ID scripts/dev/device_tests.sh         # the same
#   scripts/dev/device_tests.sh --device ID --only PDFAlgoProUITests/ReaderUITests   # only these
#   scripts/dev/device_tests.sh --device ID --check  # the preconditions only
#
#   --purchases   also PurchaseDeviceUITests, when it exists (a sandbox account signed in on the phone)
#   --live-model  also LiveIntelligenceDeviceUITests, when it exists (Apple Intelligence on)
#   --keep-dd     keep the build's intermediates (deleted after the run otherwise)
#   --no-record   do not add a row to docs/process/device-test-run.md
#
# The build goes to DEVICE_TESTS_DERIVED_DATA (default: PDFAlgoPro-device-tests in Xcode's DerivedData
# folder, outside the repository); the results to DEVICE_TESTS_RESULTS/<date>-<time>-<commit> (default:
# .build/device-tests). Needs Xcode 27, XcodeGen and Config/Team.xcconfig. The device's id is never
# printed or written to a file: the repository is public.
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root"
# shellcheck source=scripts/dev/lib/xcodebuild.sh
. scripts/dev/lib/xcodebuild.sh

device_id="${DEVICE_ID:-}"
only=""
purchases=0
live_model=0
keep_dd=0
record=1
check_only=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --device) device_id="${2:?--device needs the Identifier of the phone from xcrun devicectl list devices}"; shift 2 ;;
    --only) only="${2:?--only needs Target, Target/Class or Target/Class/method}"; shift 2 ;;
    --purchases) purchases=1; shift ;;
    --live-model) live_model=1; shift ;;
    --keep-dd) keep_dd=1; shift ;;
    --no-record) record=0; shift ;;
    --check) check_only=1; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)" >&2; exit 2 ;;
  esac
done

dd="${DEVICE_TESTS_DERIVED_DATA:-$HOME/Library/Developer/Xcode/DerivedData/PDFAlgoPro-device-tests}"
results="${DEVICE_TESTS_RESULTS:-$root/.build/device-tests}"
min_free_gib=8
team_file=Config/Team.xcconfig
ui_target=PDFAlgoProUITests

# The commit as it is before anything is generated or built (a build with Xcode 27 can rewrite
# Package.resolved, which is not a change of the tests): <sha>-dirty when a tracked file is changed or
# an untracked one would be built (device_run_record.py commit), so the row never claims a clean commit.
sha="$(git rev-parse --short HEAD)"
full_sha="$(git rev-parse HEAD)"
commit="$(git status --porcelain --untracked-files=normal | python3 scripts/dev/device_run_record.py commit "$sha")"
if [ "$commit" != "$sha" ]; then
  echo "warning: the tree differs from $sha (see git status); the run is recorded as $commit" >&2
fi

# The selectors first, so a malformed --only fails before anything else.
selectors=()
if [ -n "$only" ]; then
  focused="$(python3 scripts/ci/test_shards.py args focused --only-testing "$only")" || {
    echo "$focused" >&2
    exit 2
  }
  xcb_read_lines <<< "$focused"
  selectors=(${XCB_LINES[@]+"${XCB_LINES[@]}"})
fi
# The opt-in device classes, skipped unless their flag is given (only once they exist: xcodebuild is
# not asked to skip a class it does not have).
flags="Device"
[ -z "$only" ] || flags="$flags --only $only"
opt_in() { # CLASS WANTED FLAG
  if [ "$2" = 1 ]; then
    flags="$flags $3"
  elif grep -rqE "class[[:space:]]+$1([^A-Za-z0-9_]|$)" App/UITests; then
    selectors+=("-skip-testing:$ui_target/$1")
  fi
}
opt_in PurchaseDeviceUITests "$purchases" --purchases
opt_in LiveIntelligenceDeviceUITests "$live_model" --live-model

# 1. Preconditions: every problem at once, each with its fix.
problems=()
problem() { problems+=("$1"); }

xcode_info="$(xcodebuild -version 2>/dev/null || true)"
xcode_version="$(printf '%s\n' "$xcode_info" | sed -n 's/^Xcode //p')"
xcode_build="$(printf '%s\n' "$xcode_info" | sed -n 's/^Build version //p')"
case "$xcode_version" in
  27|27.*) ;;
  "") problem "xcodebuild does not run. Install Xcode 27 and select it: sudo xcode-select -s /Applications/Xcode.app (or set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)." ;;
  *) problem "Xcode $xcode_version is selected; the device run needs Xcode 27 (ADR-0023). Select it: sudo xcode-select -s /Applications/Xcode.app (or set DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer)." ;;
esac

# The Team ID itself is never printed: only whether the line is there.
if [ ! -f "$team_file" ]; then
  main_checkout="$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")"
  if [ "$main_checkout" != "$root" ] && [ -f "$main_checkout/$team_file" ]; then
    problem "$team_file is missing in this worktree. Copy it from the main checkout: cp \"$main_checkout/$team_file\" $team_file"
  else
    problem "$team_file is missing. Create it with one line, DEVELOPMENT_TEAM = <your Team ID> (Xcode > Settings > Accounts shows the team; the file is git-ignored, ADR-0015)."
  fi
elif ! grep -Eq '^[[:space:]]*DEVELOPMENT_TEAM[[:space:]]*=[[:space:]]*[A-Za-z0-9]+[[:space:]]*(//.*)?$' "$team_file"; then
  problem "$team_file has no DEVELOPMENT_TEAM = <your Team ID> line. Add it (Xcode > Settings > Accounts shows the team)."
fi

if ! command -v xcodegen > /dev/null; then
  problem "XcodeGen is not installed: brew install xcodegen (CI pins its version as XCODEGEN_VERSION in .github/workflows/ci.yml)."
fi

volume="$dd"
while [ ! -d "$volume" ]; do volume="$(dirname "$volume")"; done
free_kib="$(df -Pk "$volume" | awk 'NR == 2 { print $4 }')"
free_gib=$((free_kib / 1024 / 1024))
if [ "$free_gib" -lt "$min_free_gib" ]; then
  problem "Only $free_gib GiB free where the build goes ($volume); the build and the result bundle need $min_free_gib GiB. Free space: old folders in ~/Library/Developer/Xcode/DerivedData, unused simulators (xcrun simctl delete unavailable), or set DEVICE_TESTS_DERIVED_DATA to a roomier volume."
fi

udid=""
model=""
ios=""
if [ -z "$device_id" ]; then
  problem "No phone named. Pass --device <Identifier> or set DEVICE_ID; xcrun devicectl list devices shows each phone's Identifier."
else
  listing="$(mktemp -t device-tests)"
  trap 'rm -f "$listing"' EXIT
  if ! xcrun devicectl list devices --json-output "$listing" > /dev/null 2>&1; then
    problem "devicectl cannot list the devices. Run xcodebuild -runFirstLaunch (or open Xcode once) to finish installing its components, then run again."
  elif ! facts="$(python3 scripts/dev/device_run_record.py device "$listing" --id "$device_id")"; then
    problem "The phone is not ready: see the errors above."
  else
    while IFS='=' read -r key value; do
      case "$key" in
        udid) udid="$value" ;;
        model) model="$value" ;;
        ios) ios="$value" ;;
      esac
    done <<< "$facts"
  fi
fi

if [ "${#problems[@]}" -gt 0 ]; then
  echo "Not ready to run the tests on the phone:" >&2
  for p in "${problems[@]}"; do
    echo "  - $p" >&2
  done
  exit 1
fi
echo "== Ready: Xcode $xcode_version ($xcode_build), $model on iOS $ios, $free_gib GiB free"
echo "== On the phone, before the tests start:"
echo "   - keep it unlocked, with Settings > Display & Brightness > Auto-Lock set to Never"
echo "   - turn on a Focus (Do Not Disturb), so no notification covers the app"
echo "   - keep the cable connected"
if [ "$purchases" = 1 ]; then
  echo "   - sign in to a sandbox account: Settings > Developer > Sandbox Apple Account"
fi
if [ "$live_model" = 1 ]; then
  echo "   - turn on Apple Intelligence and let its model finish downloading"
fi
if [ "$check_only" = 1 ]; then
  exit 0
fi

# 2. The project and the test plans, as CI generates them.
out="$results/$(date +%Y%m%d-%H%M%S)-$sha"
mkdir -p "$out" "$dd"
xcb_regenerate

# 3. Build for testing: Debug, automatic signing with the team in Config/Team.xcconfig.
destination="platform=iOS,id=$udid"
echo "== Building for testing (Device plan, Debug) into $dd"
set +e
xcodebuild build-for-testing -scheme PDFAlgoPro -testPlan Device -configuration Debug \
  -destination "$destination" -derivedDataPath "$dd" \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration 2>&1 | tee "$out/build.log"
build=${PIPESTATUS[0]}
set -e
if [ "$build" != 0 ]; then
  echo "The build for testing failed ($build). Its errors (all of it in $out/build.log):" >&2
  grep -E 'error:' "$out/build.log" | sort -u | head -20 >&2 || true
  echo "A signing error: check that Xcode > Settings > Accounts is signed in to the team in $team_file." >&2
  exit 1
fi

# 4. The tests, then the failed ones once more on their own, as CI's UI shards do.
echo "== Device tests: ${selectors[*]:-the whole plan}"
XCB_TEST_ARGS=(-scheme PDFAlgoPro -testPlan Device -destination "$destination" -derivedDataPath "$dd"
  -disableAutomaticPackageResolution -skipPackageUpdates)
XCB_SELECTORS=(${selectors[@]+"${selectors[@]}"})
if xcb_test_with_retry device "$out" Device; then
  verdict=0
else
  verdict=1
fi

# 5. The evidence: everything the tests kept (UI_EVIDENCE=all keeps quarantined findings too), and
# each failed test's attachments on their own, as CI's failed-attachments/.
for bundle in "$out/Device.xcresult" "$out/Device-retry.xcresult"; do
  if [ -f "$bundle/Info.plist" ]; then
    folder="$out/attachments/$(basename "$bundle" .xcresult)"
    mkdir -p "$folder"
    xcrun xcresulttool export attachments --path "$bundle" --output-path "$folder" > /dev/null 2>&1 \
      || echo "warning: could not export the attachments of $bundle" >&2
  fi
done
if [ -s "$XCB_FAILED_IDS" ]; then
  while IFS= read -r test; do
    folder="$out/failed-attachments/$(printf '%s' "$test" | tr -c 'A-Za-z0-9._-' '_')"
    mkdir -p "$folder"
    xcrun xcresulttool export attachments --path "$out/Device.xcresult" --output-path "$folder" \
      --test-id "$test" > /dev/null 2>&1 || true
  done < "$XCB_FAILED_IDS"
fi

# 6. The record: a row in docs/process/device-test-run.md, then the manual checklist.
if [ "$record" = 1 ]; then
  ci_ios="$(gh api "repos/{owner}/{repo}/commits/$full_sha/check-runs?check_name=ios" \
    --jq '.check_runs[0].conclusion // .check_runs[0].status // "not run"' 2>/dev/null || true)"
  retries=()
  if [ -n "$XCB_RETRY_JSON" ]; then
    retries=(--retries "$XCB_RETRY_JSON")
  fi
  python3 scripts/dev/device_run_record.py record --tests "$XCB_TESTS_JSON" ${retries[@]+"${retries[@]}"} \
    --commit "$commit" --xcode "$xcode_version ($xcode_build)" --device "$model" --ios "$ios" \
    --flags "$flags" --bundle "$out/Device.xcresult" --ci-ios "${ci_ios:-unknown}"
fi
echo
python3 scripts/dev/device_run_record.py checklist

# 7. Space: the products stay for a re-run, the intermediates go.
if [ "$keep_dd" = 0 ]; then
  rm -rf "$dd/Build/Intermediates.noindex"
fi
echo
echo "== Results: $out (summary: Device-summary.md; attachments: attachments/, failed-attachments/)"
exit "$verdict"
