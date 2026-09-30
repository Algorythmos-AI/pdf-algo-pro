#!/bin/zsh
# Typecheck every Swift module, test target and the app for the iOS simulator, with warnings as
# errors, without building binaries: a fast pre-push check that needs a few megabytes of disk
# instead of a full DerivedData. CI still builds and runs everything (ci.yml, `ios` job).
#
#   scripts/dev/typecheck.sh
#
# Module order follows the dependency graph in docs/ios-architecture-review.md. Package resource
# bundles are replaced by a stub, and DEBUG is defined, as in a Debug build.
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
  -warnings-as-errors -D DEBUG -I $OUT -F $PLAT/Developer/Library/Frameworks -I $PLAT/Developer/usr/lib -enable-testing)
[[ -d $TOOLCHAIN/lib/swift/host/plugins/testing ]] && common+=(-plugin-path $TOOLCHAIN/lib/swift/host/plugins/testing)
fail=0

run() { # emit|check module isolation dir [bundle]
  local mode=$1 m=$2 iso=$3 dir=$4 extra=()
  [[ $iso == main ]] && extra+=(-default-isolation MainActor)
  [[ ${5:-} == bundle ]] && extra+=($BUNDLE)
  local action=(-typecheck)
  [[ $mode == emit ]] && action=(-emit-module -emit-module-path $OUT/$m.swiftmodule)
  if xcrun swiftc $action -module-name $m -parse-as-library $common $extra $(find $ROOT/$dir -name '*.swift' | sort) 2>$OUT/$m.err; then
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
for m in PDFEngine DocumentStore OCR Scanning Search Intelligence Telemetry; do
  run emit $m non Packages/$m/Sources/$m
done
run emit PDFEngineTestSupport non Packages/PDFEngine/Sources/PDFEngineTestSupport
for f in Onboarding Library Reader Assistant Scan Settings; do
  run emit ${f}Feature main Packages/Features/$f/Sources/${f}Feature bundle
done
run check DesignSystemTests main Packages/DesignSystem/Tests
for m in Core PDFEngine DocumentStore OCR Scanning Search Intelligence Telemetry; do
  run check ${m}Tests non Packages/$m/Tests
done
for f in Onboarding Library Reader Assistant Scan Settings; do
  run check ${f}FeatureTests main Packages/Features/$f/Tests
done
run emit PDFAlgoPro main App/PDFAlgoPro
run check PDFAlgoProTests main App/Tests
run check PDFAlgoProUITests non App/UITests
exit $fail
