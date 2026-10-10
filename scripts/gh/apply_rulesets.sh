#!/usr/bin/env bash
# Apply .github/rulesets/*.json to the repo via the GitHub API (idempotent). An existing ruleset with
# the same name is updated by MERGING the committed file into the live ruleset
# (scripts/gh/merge_ruleset.py): keys the file does not mention — ones GitHub added later, such as
# require_extra_approval_for_unattributed_changes — are kept, never reset to a weaker default.
# Requires `gh auth` with admin on the repo. Apply only after every required check has reported
# at least once on a pull request, so the check names exist (docs/github-governance.md).
#   REPO=Algorythmos-AI/pdf-algo-pro bash scripts/gh/apply_rulesets.sh            # apply
#   REPO=Algorythmos-AI/pdf-algo-pro bash scripts/gh/apply_rulesets.sh --dry-run  # show what would change
set -euo pipefail
DRY=""; [ "${1:-}" = "--dry-run" ] && DRY=1
REPO="${REPO:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
echo "Applying rulesets to $REPO${DRY:+ (dry run)}"
# A listing that fails stops the script here (set -e). Swallowed, it left nothing listed, every file
# looked new, and each ruleset would have been created a second time beside the live one of its name.
existing="$(gh api "repos/$REPO/rulesets" --jq '.[] | "\(.id) \(.name)"')"
for f in .github/rulesets/*.json; do
  name="$(python3 -c "import json,sys;print(json.load(open('$f'))['name'])")"
  id="$(echo "$existing" | awk -v n="$name" '$2==n{print $1}')"
  if [ -n "$id" ]; then
    gh api "repos/$REPO/rulesets/$id" > "$TMP/live.json"
    echo "  '$name' (id $id) from $f:"
    python3 "$HERE/merge_ruleset.py" "$TMP/live.json" "$f" --diff | sed 's/^/    /'
    if [ -z "$DRY" ]; then
      python3 "$HERE/merge_ruleset.py" "$TMP/live.json" "$f" > "$TMP/put.json"
      gh api -X PUT "repos/$REPO/rulesets/$id" --input "$TMP/put.json" >/dev/null
    fi
  else
    echo "  creating '$name' from $f"
    [ -z "$DRY" ] && gh api -X POST "repos/$REPO/rulesets" --input "$f" >/dev/null
  fi
done
echo "Done.${DRY:+ Nothing was changed.} Verify in GitHub → Settings → Rules → Rulesets."
