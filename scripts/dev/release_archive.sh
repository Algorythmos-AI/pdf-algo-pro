#!/bin/zsh
# Archive the App Store build on this Mac (PAP-072). 1.0 has no Xcode Cloud product for the production
# app, so this does what Xcode Cloud would have: a clean build of the Release configuration at a known
# commit, with the pinned XcodeGen and Xcode. It stops before uploading: the owner clicks Distribute App
# in Xcode's Organizer, where the archive appears.
#
#   scripts/dev/release_archive.sh <commit> <build-number> [--unsigned]
#
# <commit> is the commit expected at HEAD; the tree must be clean and on it. <build-number> becomes
# CFBundleVersion and must be higher than any uploaded for the production app. --unsigned builds without
# a Team ID or an Apple account, to check everything but the signature; it can't be uploaded.
#
# Config/Team.xcconfig (git-ignored) holds the Team ID. The Team ID is never printed (ADR-0015).
set -euo pipefail

BUNDLE_ID=com.algorythmos.pdfalgopro
MINIMUM_FREE_GIB=10

die() {
  print -u2 -- "release_archive: $1"
  exit 1
}

[[ $# -ge 2 && $# -le 3 ]] || die "usage: scripts/dev/release_archive.sh <commit> <build-number> [--unsigned]"
expected=$1
build=$2
unsigned=0
if [[ $# -eq 3 ]]; then
  [[ $3 == --unsigned ]] || die "unknown option $3"
  unsigned=1
fi
[[ $build == <1-> ]] || die "the build number must be a whole number above 0, not '$build'"

cd "${0:A:h:h:h}"
head=$(git rev-parse HEAD)
[[ $(git rev-parse --verify "$expected^{commit}") == "$head" ]] || die "HEAD is $head, not $expected"
[[ -z $(git status --porcelain) ]] || die "the tree is not clean: commit or remove these first
$(git status --porcelain)"

pin() { sed -n "s/^  $1: \"*\([^\"]*\)\"*\$/\1/p" .github/workflows/ci.yml | head -1; }
xcode_build=$(pin XCODE27_BUILD)
xcodegen_version=$(pin XCODEGEN_VERSION)
xcodegen_sha=$(pin XCODEGEN_SHA256)
[[ -n $xcode_build && -n $xcodegen_version && -n $xcodegen_sha ]] || die "the pins were not found in ci.yml"
xcodebuild -version | grep -q "Build version $xcode_build\$" \
  || die "Xcode is not the pinned build $xcode_build: $(xcodebuild -version | tr '\n' ' ')"

team_file=Config/Team.xcconfig
team=""
if [[ $unsigned -eq 0 ]]; then
  [[ -f $team_file ]] || die "$team_file is missing; see Config/Base.xcconfig (it is git-ignored, so a new checkout needs it)"
  team=$(sed -n 's/^DEVELOPMENT_TEAM *= *//p' "$team_file" | head -1)
  [[ -n $team ]] || die "$team_file has no DEVELOPMENT_TEAM line"
fi

free_gib=$(df -g . | awk 'NR == 2 { print $4 }')
((free_gib >= MINIMUM_FREE_GIB)) || die "$free_gib GiB free, and an archive needs at least $MINIMUM_FREE_GIB"

work=$(mktemp -d "${TMPDIR:-/tmp}/pdfalgopro-archive.XXXXXX")
trap 'rm -rf "$work"' EXIT

# The Mac's own XcodeGen may be another version: this is the pinned one, checked as CI and Xcode Cloud do.
curl --fail --silent --show-error --location --output "$work/xcodegen.zip" \
  "https://github.com/yonaskolb/XcodeGen/releases/download/$xcodegen_version/xcodegen.zip"
print "$xcodegen_sha  $work/xcodegen.zip" | shasum -a 256 -c - >/dev/null
unzip -q "$work/xcodegen.zip" -d "$work"
"$work/xcodegen/bin/xcodegen" generate --quiet
python3 scripts/ci/write_testplan.py
[[ -z $(git status --porcelain) ]] || die "generating the project changed tracked files
$(git status --porcelain)"

version=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | head -1)
archive=~/Library/Developer/Xcode/Archives/$(date +%Y-%m-%d)/PDFAlgoPro-$version-$build.xcarchive
[[ ! -e $archive ]] || die "$archive already exists; each archive needs its own build number"

arguments=(
  archive -project PDFAlgoPro.xcodeproj -scheme PDFAlgoPro -configuration Release
  -destination generic/platform=iOS -archivePath "$archive"
  -derivedDataPath "$work/DerivedData" -clonedSourcePackagesDirPath "$work/SourcePackages"
  -disableAutomaticPackageResolution -skipPackageUpdates
  CURRENT_PROJECT_VERSION="$build"
)
if [[ $unsigned -eq 1 ]]; then
  arguments+=(CODE_SIGNING_ALLOWED=NO)
else
  arguments+=(-allowProvisioningUpdates)
fi

print "Archiving $head as $version ($build), about 15 minutes..."
if ! xcodebuild "${arguments[@]}" >"$work/xcodebuild.log" 2>&1; then
  redact=${team:-no-team-id}
  grep -E 'error:|\*\* ARCHIVE FAILED' "$work/xcodebuild.log" | sed "s/$redact/<team>/g" | head -20 >&2
  die "the archive failed"
fi

app="$archive/Products/Applications/PDFAlgoPro.app"
read_plist() { /usr/libexec/PlistBuddy -c "Print :$1" "$app/Info.plist"; }
check() {
  [[ $2 == "$3" ]] || die "$1 is '$2', not '$3'; don't upload $archive"
  print "  $1: $2"
}
print "Checked in the archive:"
check "bundle identifier" "$(read_plist CFBundleIdentifier)" "$BUNDLE_ID"
check "version" "$(read_plist CFBundleShortVersionString)" "$version"
check "build" "$(read_plist CFBundleVersion)" "$build"
check "export compliance" "$(read_plist ITSAppUsesNonExemptEncryption)" "false"

# The names ci.yml looks for in the Release binary (PAP-060, #267), where a Staging binary is the control.
strings=$(strings -a "$app/$(read_plist CFBundleExecutable)")
for name in 'internal\.firstRun\.build' 'Internal testing' 'EvaluationSection' 'InternalEntitlementOverride'; do
  if print -r -- "$strings" | grep -Eq -- "$name"; then
    die "the Release binary contains '$name', an internal tool that must not ship; don't upload $archive"
  fi
done
print "  internal tools: none in the binary"

if [[ $unsigned -eq 0 ]]; then
  # Key names only: the values name the Team ID.
  print "  entitlements: $(codesign -d --entitlements - --xml "$app" 2>/dev/null | plutil -convert json -o - - \
    | python3 -c 'import json, sys; print(", ".join(sorted(json.load(sys.stdin))) or "none")')"
fi

print "
Archived commit $head, version $version, build $build:
  $archive"
if [[ $unsigned -eq 1 ]]; then
  print "Unsigned: this archive can't be uploaded."
else
  print "Next, by hand: Xcode › Window › Organizer › Archives › Distribute App › App Store Connect."
fi
