#!/bin/zsh
# Typecheck every Swift module, test target and the app for the iOS simulator, with warnings as
# errors, without building binaries: a fast pre-push check that needs a few megabytes of disk
# instead of a full DerivedData. CI still builds and runs everything (ci.yml, `ios` job).
#
#   scripts/dev/typecheck.sh
#
# Module order follows the dependency graph in docs/ios-architecture-review.md. Package resource
# bundles are replaced by a stub, and DEBUG is defined, as in a Debug build; the app and its tests
# also get INTERNAL_TOOLS, as the Debug configuration gives the app (project.yml).
set -u
ROOT=${0:A:h:h:h}
OUT=$(mktemp -d "${TMPDIR:-/tmp}/pdfalgopro-typecheck.XXXXXX")
trap 'rm -rf "$OUT"' EXIT
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
PLAT=$(xcrun --sdk iphonesimulator --show-sdk-platform-path)
TOOLCHAIN=$(dirname "$(dirname "$(xcrun --find swiftc)")")
BUNDLE=$OUT/BundleStub.swift
print 'import Foundation\nextension Foundation.Bundle { static let module = Bundle.main }' > $BUNDLE
common=(-sdk $SDK -target arm64-apple-ios26.0-simulator -swift-version 6 -enable-upcoming-feature NonisolatedNonsendingByDefault
  -warnings-as-errors -D DEBUG -I $OUT -F $PLAT/Developer/Library/Frameworks -I $PLAT/Developer/usr/lib -enable-testing
  # StoreKitTest, for the app's store tests: its header uses a symbol Apple deprecated (see project.yml).
  -F $SDK/Developer/Library/Frameworks -Xcc -Wno-error=deprecated-declarations)
[[ -d $TOOLCHAIN/lib/swift/host/plugins/testing ]] && common+=(-plugin-path $TOOLCHAIN/lib/swift/host/plugins/testing)
fail=0

run() { # emit|check module isolation dir [bundle] [file to leave out]
  local mode=$1 m=$2 iso=$3 dir=$4 extra=()
  [[ $dir == App/* ]] && extra+=(-D INTERNAL_TOOLS)
  [[ $iso == main ]] && extra+=(-default-isolation MainActor)
  [[ ${5:-} == bundle ]] && extra+=($BUNDLE)
  local action=(-typecheck)
  [[ $mode == emit ]] && action=(-emit-module -emit-module-path $OUT/$m.swiftmodule)
  local files=($(find $ROOT/$dir -name '*.swift' | sort))
  [[ -n ${6:-} ]] && files=(${files:#*/$6})
  if xcrun swiftc $action -module-name $m -parse-as-library $common $extra $files 2>$OUT/$m.err; then
    echo "ok   $m"
  else
    echo "FAIL $m"
    grep -E "error|warning" $OUT/$m.err | grep -v '^ *|' | sed "s#$ROOT/##" | head -8
    fail=1
  fi
}

run emit Core non Packages/Core/Sources/Core
run emit CoreTestSupport non Packages/Core/Sources/CoreTestSupport
run emit DesignSystem main Packages/DesignSystem/Sources/DesignSystem bundle
for m in PDFEngine DocumentStore OCR Scanning Search Intelligence Telemetry RemoteConfig Commerce; do
  run emit $m non Packages/$m/Sources/$m
done
run emit CommerceTestSupport non Packages/Commerce/Sources/CommerceTestSupport
run emit PDFEngineTestSupport non Packages/PDFEngine/Sources/PDFEngineTestSupport
run emit IntelligenceEvaluation non Packages/Intelligence/Sources/IntelligenceEvaluation
for f in Onboarding Library Reader Assistant Scan Settings Paywall; do
  run emit ${f}Feature main Packages/Features/$f/Sources/${f}Feature bundle
done
run check DesignSystemTests main Packages/DesignSystem/Tests
for m in Core PDFEngine DocumentStore OCR Scanning Search Intelligence Telemetry RemoteConfig Commerce; do
  run check ${m}Tests non Packages/$m/Tests
done
for f in Onboarding Library Reader Assistant Scan Settings Paywall; do
  run check ${f}FeatureTests main Packages/Features/$f/Tests
done
run emit PDFAlgoPro main App/PDFAlgoPro
# The app's tests link the test-only SnapshotTesting package (ADR-0018). Its module is built from the
# checkout that `xcodebuild -resolvePackageDependencies` made; without one, the snapshot tests are left out.
snap=${SNAPSHOT_TESTING_SOURCES:-$(ls -d $HOME/Library/Developer/Xcode/DerivedData/PDFAlgoPro-*/SourcePackages/checkouts/swift-snapshot-testing/Sources/SnapshotTesting 2>/dev/null | head -1)}
if [[ -n $snap && -d $snap ]] && xcrun swiftc -emit-module -emit-module-path $OUT/SnapshotTesting.swiftmodule \
  -module-name SnapshotTesting -parse-as-library -sdk $SDK -target arm64-apple-ios26.0-simulator -swift-version 5 \
  -F $PLAT/Developer/Library/Frameworks -I $PLAT/Developer/usr/lib $(find $snap -name '*.swift' | sort) 2>$OUT/snap.err; then
  run check PDFAlgoProTests main App/Tests
else
  echo "skip SnapshotTests.swift (resolve packages, or set SNAPSHOT_TESTING_SOURCES, to check it)"
  run check PDFAlgoProTests main App/Tests "" SnapshotTests.swift
fi
run check PDFAlgoProUITests non App/UITests
exit $fail
