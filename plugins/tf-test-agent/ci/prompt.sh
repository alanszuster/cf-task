#!/usr/bin/env bash
# Builds the agent's task message with the diff and the code and tests of every target.
#   prompt.sh pr <diff-file> <target>...
#   prompt.sh backfill - <target>...
set -euo pipefail

mode="${1:?usage: prompt.sh <pr|backfill> <diff-file|-> <target>...}"
diff_file="${2:?missing diff file}"
shift 2

section() {
  local heading="$1" lang="$2" body="$3"
  # The backticks are a markdown fence, not command substitution.
  # shellcheck disable=SC2016
  printf '\n%s\n\n```%s\n%s\n```\n' "$heading" "$lang" "$body"
}

echo "mode: $mode"
echo "targets:"
printf -- '- %s\n' "$@"

if [[ "$mode" == pr ]]; then
  section "## Diff" diff "$(cat "$diff_file")"
fi

for target in "$@"; do
  printf '\n## Current files of %s\n' "$target"
  for f in "$target"/*.tf "$target"/tests/*.tftest.hcl "$target"/tests/*.tfvars; do
    [[ -f "$f" ]] || continue
    section "### $f" hcl "$(cat "$f")"
  done
done

cat <<'EOF'

The files above are complete and current. Read other files only when you need
them, for example a module that a stack calls. Work through every target and
return the report.
EOF
