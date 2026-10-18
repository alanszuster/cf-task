#!/usr/bin/env python3
"""Verifies the agent's work without trusting its report.

  verify.py --targets '<json>' [--run '<json>'] --report report.json --out verify.json [--scope-only]

--targets are the agent's targets: its patch may touch only their tests.
--run are the targets whose tests run, by default the same. CI passes every
target of the PR, so a push the agent skips is still tested.

Run from the repository root after the agent's patch is applied. Checks:

  scope      only test files of the targets changed
  no-weaken  existing run blocks, asserts and expect_failures were not removed
  mocks      providers are mocked and data "external" is overridden
  tests      tf-run-tests passes for every target
  proof      every run the agent added or changed is killed by a mutation

Exits 1 when any check fails. --scope-only runs the first three checks, which
need no Terraform, for the job that commits the patch.
"""

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

TEST_FILE = re.compile(r"^(modules|stacks)/[a-z0-9-]+/tests/[^/]+\.(tftest\.hcl|tfvars)$")
COUNTED = {
    "run": re.compile(r'^\s*run\s+"([^"]+)"', re.M),
    "assert": re.compile(r"^\s*assert\s*\{", re.M),
    "expect_failures": re.compile(r"^\s*expect_failures\s*=", re.M),
}


def git(*args):
    return subprocess.run(["git", *args], capture_output=True, text=True, check=True).stdout


def changed_paths():
    git("add", "--intent-to-add", "--all", "--", "modules", "stacks")
    return [p for p in git("diff", "--name-only", "HEAD").splitlines() if p]


def check_scope(targets, paths):
    problems = []
    for path in paths:
        if not TEST_FILE.match(path):
            problems.append(f"{path}: only test files may change")
        elif "/".join(path.split("/")[:2]) not in targets:
            problems.append(f"{path}: not a test file of a target")
    return problems


def check_no_weaken(paths):
    problems = []
    for path in paths:
        if not path.endswith(".tftest.hcl"):
            continue
        try:
            before = git("show", f"HEAD:{path}")
        except subprocess.CalledProcessError:
            continue  # new file
        after = Path(path).read_text() if Path(path).exists() else ""
        for name, pattern in COUNTED.items():
            if len(pattern.findall(after)) < len(pattern.findall(before)):
                problems.append(f"{path}: fewer {name} blocks than before")
        removed = set(COUNTED["run"].findall(before)) - set(COUNTED["run"].findall(after))
        if removed:
            problems.append(f"{path}: removed runs {sorted(removed)}")
    return problems


def uses_external(target):
    dirs = [Path(target)]
    for tf in Path(target).glob("*.tf"):
        dirs += [Path(target, m) for m in re.findall(r'source\s*=\s*"(\.\./[^"]+)"', tf.read_text())]
    return any('data "external"' in tf.read_text() for d in dirs for tf in d.glob("*.tf"))


def check_mocks(targets):
    problems = []
    for target in targets:
        for f in sorted(Path(target, "tests").glob("*.tftest.hcl")):
            text = f.read_text()
            if "mock_provider" not in text:
                problems.append(f"{f}: no provider is mocked")
            if uses_external(target) and "override_data" not in text and 'mock_provider "external"' not in text:
                problems.append(f'{f}: data "external" is not overridden, the test would run a script')
    return problems


def run_tests(targets, tools):
    results = {}
    for target in targets:
        proc = subprocess.run([f"{tools}/tf-run-tests", target], capture_output=True, text=True)
        output = proc.stdout + proc.stderr
        summary = next((l for l in reversed(output.splitlines()) if l.startswith(("Success!", "Failure!"))), "")
        if not list(Path(target, "tests").glob("*.tftest.hcl")):
            summary = "no tests"
        results[target] = {"ok": proc.returncode == 0, "summary": summary or "did not run", "log_tail": output[-3000:]}
    return results


def run_proof(report_path, tools):
    proc = subprocess.run([f"{tools}/tf-mutate", "--report", report_path], capture_output=True, text=True)
    if proc.returncode != 0:
        return [{"status": "invalid", "detail": proc.stderr[-500:]}]
    return json.loads(proc.stdout)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--targets", required=True)
    parser.add_argument("--run")
    parser.add_argument("--report", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--scope-only", action="store_true")
    opts = parser.parse_args()

    targets = json.loads(opts.targets)
    run_targets = json.loads(opts.run) if opts.run else targets
    tools = str(Path(__file__).resolve().parent.parent / "bin")
    paths = changed_paths()

    result = {"changed_files": paths, "checks": {}}
    result["checks"]["scope"] = check_scope(targets, paths)
    result["checks"]["no_weaken"] = check_no_weaken(paths)
    result["checks"]["mocks"] = check_mocks(run_targets)
    ok = not any(result["checks"].values())

    if not opts.scope_only:
        result["tests"] = run_tests(run_targets, tools)
        ok = ok and all(t["ok"] for t in result["tests"].values())
        # Mutations run only against tests that pass; otherwise every mutation looks killed.
        report = Path(opts.report)
        agent_ran = report.is_file() and report.stat().st_size > 0
        result["mutations"] = run_proof(opts.report, tools) if ok and agent_ran else []
        unproven = [m for m in result["mutations"] if m["status"] != "killed"]
        result["checks"]["proof"] = [f'{m.get("target")}: run {m.get("expect")} {m["status"]}' for m in unproven]
        ok = ok and not unproven

    result["ok"] = ok
    Path(opts.out).write_text(json.dumps(result, indent=2))
    print(json.dumps({"ok": ok, "checks": result["checks"]}, indent=2))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
