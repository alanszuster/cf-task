#!/usr/bin/env bash
# Runs the agent from the repository root. Used by the workflow and locally.
#   run-agent.sh <pr|backfill> <diff-file|-> <out-dir> <target>...
# Writes prompt.txt, transcript.jsonl and report.json to <out-dir>.
set -euo pipefail

plugin="$(cd "$(dirname "$0")/.." && pwd)"
mode="${1:?usage: run-agent.sh <pr|backfill> <diff-file|-> <out-dir> <target>...}"
diff_file="${2:?missing diff file}"
out="${3:?missing output directory}"
shift 3
: "${ANTHROPIC_API_KEY:?ANTHROPIC_API_KEY is not set}"

mkdir -p "$out"
"$plugin/ci/prompt.sh" "$mode" "$diff_file" "$@" > "$out/prompt.txt"

# An empty config directory: no personal settings, plugins or permissions, same as on a CI runner.
CLAUDE_CONFIG_DIR="$(mktemp -d)"
export CLAUDE_CONFIG_DIR
trap 'rm -rf "$CLAUDE_CONFIG_DIR"' EXIT

status=0
claude -p "$(cat "$out/prompt.txt")" \
  --plugin-dir "$plugin" \
  --agent tf-test-agent:test-engineer \
  --settings "$plugin/ci/claude-settings.json" \
  --setting-sources user \
  --model "${TF_TEST_AGENT_MODEL:-haiku}" \
  --max-turns $((10 + 12 * $#)) \
  --max-budget-usd "${TF_TEST_AGENT_MAX_USD:-1}" \
  --json-schema "$(cat "$plugin/schemas/report.schema.json")" \
  --output-format stream-json --verbose \
  > "$out/transcript.jsonl" || status=$?

jq -c 'select(.type == "result") | .structured_output // empty' "$out/transcript.jsonl" > "$out/report.json"
jq -r 'select(.type == "result") | "result: \(.subtype), turns: \(.num_turns), cost: $\(.total_cost_usd)"' "$out/transcript.jsonl"
exit "$status"
