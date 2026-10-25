#!/usr/bin/env bash
# Checks every PDF in a folder with qpdf, independently of PDFKit (plan revision 3, §3 B2).
#
#   scripts/ci/validate_pdfs.sh <folder> [allowed-warnings-file]
#
# A file with a `<name>.password` beside it is checked with that password. qpdf exits 0 when a file is
# clean, 3 when it only has warnings and 2 on errors. Errors fail; so do warnings, except those listed
# for that file in the allowed-warnings file (default: qpdf_allowed_warnings.txt beside this script;
# lines `<file name>|<text the warning contains>`, # for comments), which are reported as notices.
# Exits 1 when any file fails, or when the folder holds no PDF (the export did not run).
set -uo pipefail
folder=${1:?usage: validate_pdfs.sh <folder> [allowed-warnings-file]}
allowed_file=${2:-"$(dirname "$0")/qpdf_allowed_warnings.txt"}
shopt -s nullglob
files=("$folder"/*.pdf)
if [ ${#files[@]} -eq 0 ]; then
  echo "::error::No PDFs to check in $folder"
  exit 1
fi
# The warnings allowed for one file, as fixed strings, one per line.
allowed_for() {
  [ -f "$allowed_file" ] || return 0
  grep -v '^[[:space:]]*#' "$allowed_file" | awk -F'|' -v name="$1" '$1 == name { sub(/^[^|]*\|/, ""); print }'
}
failed=0
for file in "${files[@]}"; do
  args=(--check)
  password_file="${file%.pdf}.password"
  [ -f "$password_file" ] && args+=("--password=$(cat "$password_file")")
  output=$(qpdf "${args[@]}" "$file" 2>&1)
  status=$?
  name=$(basename "$file")
  case $status in
    0) echo "ok       $name" ;;
    3)
      warnings=$(printf '%s\n' "$output" | grep '^WARNING:' || true)
      patterns=$(allowed_for "$name")
      if [ -n "$patterns" ]; then
        unexpected=$(printf '%s\n' "$warnings" | grep -v -F -f <(printf '%s\n' "$patterns") || true)
      else
        unexpected=$warnings
      fi
      if [ -z "$warnings" ] || [ -n "$unexpected" ]; then
        echo "::error title=qpdf warnings::$name has warnings that are not allowed (qpdf_allowed_warnings.txt)"
        printf '%s\n' "${unexpected:-$output}" | tail -20
        failed=1
      else
        echo "::notice title=qpdf allowed warnings::$name ($(printf '%s\n' "$warnings" | wc -l | tr -d ' ') allowed, see qpdf_allowed_warnings.txt)"
        printf '%s\n' "$warnings" | tail -5
      fi
      ;;
    *) echo "::error title=qpdf errors::$name (exit $status)"; echo "$output" | tail -20; failed=1 ;;
  esac
done
exit $failed
