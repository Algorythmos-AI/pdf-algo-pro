#!/bin/zsh
# Every check a Mac can run before a push, in the order CI runs them (ci.yml): format, design tokens,
# docs, invariants, script tests, workflow lint, a typecheck of every module for the iOS simulator
# with warnings as errors, and the tests of every package that also builds for macOS. The UI tests,
# the accessibility audits and the coverage gate need the iOS simulator and run in CI (`ios` job).
#
#   scripts/dev/preflight.sh           # everything
#   scripts/dev/preflight.sh --quick   # without the package tests
#
# Package builds go to a temporary folder, removed after each package, so little disk is needed.
set -u
ROOT=${0:A:h:h:h}
cd "$ROOT"
quick=0
[[ ${1:-} == --quick ]] && quick=1
failed=()

step() { # name command...
  local name=$1
  shift
  print -n "== $name ... "
  local log
  log=$(mktemp "${TMPDIR:-/tmp}/preflight.XXXXXX")
  if "$@" >"$log" 2>&1; then
    print ok
  else
    print FAILED
    tail -25 "$log"
    failed+=("$name")
  fi
  rm -f "$log"
}

step "format (swift format, strict)" xcrun swift-format lint --strict --recursive App Packages
step "design tokens" python3 scripts/design/generate_tokens.py --check
step "docs" python3 scripts/ci/check_docs.py
step "tester notes" python3 scripts/ci/check_tester_notes.py
step "invariants" python3 scripts/ci/invariants.py
if command -v uv >/dev/null; then
  step "script tests" uv run --quiet --no-project --with pytest==8.4.2 --with pyyaml==6.0.2 \
    python -m pytest -q -p no:cacheprovider scripts
  step "workflow lint (actionlint)" uvx --from actionlint-py actionlint
else
  print "== script tests and workflow lint: skipped (they need uv: https://docs.astral.sh/uv/)"
fi
step "typecheck for the iOS simulator (warnings as errors)" zsh scripts/dev/typecheck.sh

if (( ! quick )); then
  build=$(mktemp -d "${TMPDIR:-/tmp}/preflight-build.XXXXXX")
  trap 'rm -rf "$build"' EXIT
  for manifest in Packages/*/Package.swift Packages/Features/*/Package.swift; do
    grep -q '\.macOS(' "$manifest" || continue
    dir=${manifest:h}
    step "tests: ${dir:t} (macOS)" swift test --package-path "$dir" --scratch-path "$build/${dir:t}"
    rm -rf "$build/${dir:t}"
  done
fi

if (( ${#failed} )); then
  print "\n${#failed} check(s) failed: ${(j:, :)failed}"
  exit 1
fi
print "\nAll checks passed. The UI tests, accessibility audits and coverage gate run in CI (ios job)."
