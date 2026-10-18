#!/usr/bin/env python3
"""Builds the pull request comment and the check run from the agent's report
and the independent verification.

  render.py --targets '<json>' --report report.json --verify verify.json
            --transcript transcript.jsonl --comment comment.md --check check.json
            [--commit SHA] [--run-url URL]

All text written by the model is escaped: no HTML, no mentions, no links that
render. The structure of the comment is fixed here, not by the model.
"""

import argparse
import json
import os
import re
from pathlib import Path

LEVEL = {"high": "failure", "medium": "warning", "low": "notice", "info": "notice"}
ICON = {"high": "🔴", "medium": "🟠", "low": "🟡", "info": "🔵"}


def text(value):
    value = str(value).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    value = re.sub(r"@(?=\w)", "@\u200b", value)            # no mentions
    value = re.sub(r"\]\(", "]\u200b(", value)              # no markdown links
    value = value.replace("|", "\\|").replace("\n", " ")
    return value


def code(value):
    return "~~~\n" + str(value).replace("~~~", "~ ~ ~") + "\n~~~"


def load(path, default):
    try:
        return json.loads(Path(path).read_text())
    except (OSError, json.JSONDecodeError):
        return default


def transcript_stats(path):
    skills, tools, result = [], {}, {}
    try:
        lines = Path(path).read_text().splitlines()
    except OSError:
        lines = []
    for line in lines:
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        if event.get("type") == "assistant":
            for block in event.get("message", {}).get("content", []):
                if block.get("type") == "tool_use":
                    tools[block["name"]] = tools.get(block["name"], 0) + 1
                    if block["name"] == "Skill":
                        skills.append(block.get("input", {}).get("skill", "?"))
        elif event.get("type") == "result":
            result = event
    return skills, tools, result


def main():
    p = argparse.ArgumentParser()
    for name in ("targets", "report", "verify", "transcript", "comment", "check"):
        p.add_argument(f"--{name}", required=True)
    p.add_argument("--pr-targets", help="every target of the PR; their tests ran (default: --targets)")
    p.add_argument("--commit", default="")
    p.add_argument("--run-url", default="")
    o = p.parse_args()

    agent_targets = json.loads(o.targets)
    targets = json.loads(o.pr_targets) if o.pr_targets else agent_targets
    report = load(o.report, {})
    verify = load(o.verify, {})
    skills, tools, result = transcript_stats(o.transcript)
    findings = report.get("findings", [])
    verified = False

    # The comment is always updated, so it never shows results of code that is gone.
    if not targets:
        verified = True
        headline = "✅ This PR changes no modules or stacks."
    elif agent_targets and not report:
        headline = "❌ The agent did not return a valid report. Nothing was committed."
    elif not verify.get("ok", False):
        headline = "❌ Verification failed. Nothing was committed."
    else:
        verified = True
        if o.commit:
            headline = f"✅ Tests verified and committed in {o.commit[:7]}."
        elif not agent_targets:
            headline = "✅ No new changes in this push need the agent. All tests of this PR pass."
        else:
            headline = "✅ Verified. No test changes were needed."

    lines = ["## 🧪 Terraform test agent", "", headline, ""]

    tests = verify.get("tests", {})
    mutations = verify.get("mutations", [])
    if targets:
        lines += ["| Target | Decision | Tests (re-run by CI) | Mutation proof |", "|---|---|---|---|"]
    by_target = {t.get("path"): t for t in report.get("targets", [])}
    for target in targets:
        t = by_target.get(target, {})
        if t:
            decision = f'**{t["decision"]}**: {text(t["reason"])}'
        else:
            decision = "not reported" if target in agent_targets else "no new changes in this push"
        test = tests.get(target)
        if not test:
            test_cell = "not run"
        elif test["summary"] == "no tests":
            test_cell = "⚪ no tests"
        else:
            test_cell = ("✅ " if test["ok"] else "❌ ") + text(test["summary"])
        mine = [m for m in mutations if m.get("target") == target]
        killed = sum(m["status"] == "killed" for m in mine)
        proof = f"{killed}/{len(mine)} killed" if mine else "–"
        lines.append(f"| `{target}` | {decision} | {test_cell} | {proof} |")
    lines.append("")

    failed = {k: v for k, v in verify.get("checks", {}).items() if v}
    failing_tests = {t: r for t, r in tests.items() if not r["ok"]}
    if failed or failing_tests:
        lines += ["### Verification problems", ""]
        for check, problems in failed.items():
            lines += [f"- **{check}**: {text(p)}" for p in problems]
        lines += [f"- **tests**: `{t}` fails: {text(r['summary'])}" for t, r in failing_tests.items()]
        lines.append("")
        for target, test in failing_tests.items():
            lines += [f"<details><summary>Test output for <code>{target}</code></summary>", "", code(test["log_tail"]), "", "</details>", ""]

    runs = [(t["path"], r) for t in report.get("targets", []) for r in t.get("runs", [])]
    if runs:
        lines += ["<details><summary>What the new and changed runs prove</summary>", "",
                  "| Target | Run | Proves | Mutation |", "|---|---|---|---|"]
        for target, run in runs:
            status = [m["status"] for m in mutations if m.get("target") == target and m.get("expect") == run["name"]]
            lines.append(f'| `{target}` | `{text(run["name"])}` | {text(run["proves"])} | {", ".join(status) or "–"} |')
        lines += ["", "</details>", ""]

    if findings:
        lines += [f"### Findings for reviewers ({len(findings)})", "",
                  "The agent does not change infrastructure code. These are for you to decide.", ""]
        order = ["high", "medium", "low", "info"]
        for f in sorted(findings, key=lambda f: order.index(f["severity"])):
            where = f'`{text(f["file"])}:{f["line"]}`' + ("" if f["in_diff"] else " (existing code)")
            lines += [f'<details><summary>{ICON[f["severity"]]} <b>{f["severity"]}</b>: {text(f["title"])}</summary>', "",
                      f"{where}", "", code(f["evidence"]), "", f'**Why it matters:** {text(f["why"])}', "",
                      f'**Suggestion:** {text(f["recommendation"])}', "", "</details>", ""]

    limits = [n for t in report.get("targets", []) for n in t.get("not_covered", [])]
    if limits:
        lines += ["<details><summary>What these tests cannot show</summary>", ""]
        lines += [f"- {text(n)}" for n in limits]
        lines += ["", "</details>", ""]

    footer = [f"skills: {', '.join(sorted(set(skills))) or 'none'}",
              f"tool calls: {sum(tools.values())}"]
    if result:
        footer.append(f'turns: {result.get("num_turns", "?")}')
        if result.get("total_cost_usd") is not None:
            footer.append(f'cost: ${result["total_cost_usd"]:.3f}')
    if o.run_url:
        footer.append(f"[run]({o.run_url})")
    lines += ["<sub>" + " · ".join(footer) + "</sub>"]

    Path(o.comment).write_text("\n".join(lines) + "\n")

    annotations = []
    for f in findings:
        if Path(f["file"]).is_file():
            annotations.append({"path": f["file"], "start_line": f["line"], "end_line": f["line"],
                                "annotation_level": LEVEL[f["severity"]],
                                "title": f'{f["severity"]}: {f["title"]}'[:255],
                                "message": f'{f["why"]}\n\nSuggestion: {f["recommendation"]}'[:64000]})
    check = {
        "conclusion": "success" if verified else "failure",
        "output": {"title": headline.replace("**", "")[:255],
                   "summary": f"{len(findings)} finding(s) for reviewers. Details in the pull request comment."},
        "annotations": annotations[:50],
    }
    Path(o.check).write_text(json.dumps(check, indent=2))

    # json.dumps escapes newlines, so model text cannot inject extra outputs.
    if os.environ.get("GITHUB_OUTPUT"):
        with open(os.environ["GITHUB_OUTPUT"], "a") as out:
            out.writelines(f"{k}={v if isinstance(v, str) else json.dumps(v)}\n" for k, v in check.items())


if __name__ == "__main__":
    main()
