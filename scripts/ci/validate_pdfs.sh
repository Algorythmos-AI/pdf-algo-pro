#!/usr/bin/env bash
# Checks every PDF in a folder with qpdf, independently of PDFKit (plan revision 3, §3 B2).
#
#   scripts/ci/validate_pdfs.sh <folder>
#
# A file with a `<name>.password` beside it is checked with that password. qpdf exits 0 when a file is
# clean, 3 when it only has warnings (reported, not failed) and 2 on errors. Exits 1 when any file has
# errors, or when the folder holds no PDF (the export did not run).
set -uo pipefail
folder=${1:?usage: validate_pdfs.sh <folder>}
shopt -s nullglob
files=("$folder"/*.pdf)
if [ ${#files[@]} -eq 0 ]; then
  echo "::error::No PDFs to check in $folder"
  exit 1
fi
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
    3) echo "::warning title=qpdf warnings::$name"; echo "$output" | tail -5 ;;
    *) echo "::error title=qpdf errors::$name (exit $status)"; echo "$output" | tail -20; failed=1 ;;
  esac
done
exit $failed
