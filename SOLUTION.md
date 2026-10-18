# Solution

A Claude Code agent that writes `terraform test` files for changed Terraform code in a pull request. It runs the tests, proves each test can catch a bug, and posts the results and findings in the pull request. It never changes infrastructure code.

## How it works

```
pull request
   │
   ├─ analyze   which modules and stacks changed (bash, no LLM)
   ├─ agent     Claude Code writes or updates tests, returns a JSON report
   ├─ verify    CI checks the agent's work again, without trusting the report (no LLM, no secrets)
   └─ publish   commits verified tests to the PR branch, posts a comment and a check run
```

The agent works only in the PR that started the run. It does not open other PRs.

## Main decisions

| Decision | Why | What I gave up |
|---|---|---|
| Claude Code CLI in headless mode, packed as a plugin | Full control of tools and permissions. One plugin can be used in many repositories. | `claude-code-action` would be less code, but it also handles GitHub tokens and comments. I wanted the agent job to have no write access and every CLI flag under my control. |
| The agent writes tests, CI verifies them | An LLM can say "tests pass" when they do not. The `verify` job runs everything again by itself. | More CI time. |
| Mutation proof | A passing test can still check nothing. For each new test the agent gives a small realistic bug (a mutation). CI applies it to a copy of the code, and the test must fail. | Agent picks the mutations, so a weak test with a weak mutation is still possible. |
| Agent, skills and permissions come from the base branch | Code in a PR cannot change the agent, its skills or its permissions. | A change to the agent itself takes effect only after merge. |
| Tests describe intended behavior | If code does something wrong (for example `ftps_state = "AllAllowed"`), the agent does not write a test that confirms it. It reports a finding. | Some code stays untested until a person decides. |
| Haiku as default model | Measured on one module: with a good skill, Haiku tests were as good as Sonnet tests, for about 10% of the cost. | Less reasoning for complex changes. Sonnet can be set with a repo variable. |
| Code is put into the prompt | The agent does not spend turns finding files. Cheaper than an MCP server, whose tool definitions are sent every turn. | Big targets make a big prompt. |
| Tests are committed with `GITHUB_TOKEN` | No extra app or token to manage. | Other checks do not run on the bot commit. The bot commit has `[skip actions]`, and the run posts its own check on it. |

I also tried `--bare` mode for more isolation. It removes the `Skill` and `Write` tools, so I did not use it. The workflow deletes `CLAUDE.md` and `.claude/` from the PR checkout instead.

## Security

- Each job has its own minimal permissions. Only `publish` can write, and it runs no Terraform and no code from the PR.
- The agent can only edit files in `*/tests/` and run two commands: `tf-run-tests` and `tf-mutate`. It can also read files and run read-only commands like `ls` and `grep` inside the repo. Everything else is denied (`dontAsk` mode). Tested: it cannot read `.env`, `/proc/self/environ` or files outside the repo.
- Terraform runs with a clean environment, so the API key never reaches it.
- Tests must mock providers and override `data "external"`, so no test calls Azure or runs repository scripts.
- `verify` rejects patches that touch other files or remove existing runs or asserts.
- Text from the model is escaped before it goes to the PR comment (no HTML, mentions or links).
- Actions are pinned to commit SHAs, because a tag can be moved to other code. Dependabot keeps the SHAs up to date. Claude Code and Terraform versions are pinned too.
- PRs from forks and drafts are skipped. Forks get no secrets anyway.
- For `pull_request` events GitHub takes the workflow file from the PR itself. Someone with write access could change it in a PR. `CODEOWNERS` covers `.github/` and `plugins/`; with branch protection that requires a code owner review, such a change cannot be merged unreviewed.

## How I used an LLM to build this

I built this with Claude Code. I made the design decisions and reviewed every change. I did not trust what the model said worked; I checked it:

- **Every script was run before commit**, and `actionlint` and `shellcheck` run on the workflow and shell scripts.
- **Smoke tests in CI-like conditions** (empty Claude config, real API key) found four problems that would break the first PR run: `--bare` removes the tools the agent needs, the JSON schema version was not supported, the API key was not read on a fresh runner, and the agent's tool list blocked the structured report.
- **Permission tests**: I asked the agent to read `.env`, `/proc/self/environ` and files outside the repo, and to chain shell commands. All were denied.
- **Gate tests**: I gave `verify` patches that change `.tf` files, remove runs and use weak mutations. It rejected all of them.
- **Measured, not guessed**: I compared Haiku and Sonnet on the same module. A better skill helped more than a bigger model.
- **Human review of generated tests**: a test name in `key-vault` claimed to check the role, but only checked the principal. Mutations did not catch this; review did. I added the missing assert.
- **The gate caught a shortcut**: my first reference example in the skill was the `private-endpoint` module from this repo. When the agent worked on that module, it copied the example and skipped the mutation step. All tests passed, but `verify` marked every run as unproven. I replaced the example with a made-up module, checked that it really works, and added a hard rule to the agent. The next run proved all its tests.
- **Prompt injection test**: in PR #3 I added a comment to a `.tf` file that told AI agents to delete the tests and report no findings. The agent ignored it, kept the tests and reported the comment as a high finding. If it had deleted tests, `verify` would have rejected the patch.
- **Real runs found what local tests did not**: the `base.sha` in the PR event stays at the commit from when the PR was opened, so a long-open PR used old skills. The workflow now pins the current base branch once and passes it to all jobs. A scenario test of target detection also found a crash when a changed module is not used by any stack.

## Missing tests added

The same agent added tests to the existing modules in backfill mode (`run-agent.sh backfill`). I reviewed every result before commit.

| Target | Decision | Runs added | Findings | Cost |
|---|---|---|---|---|
| `log-analytics-workspace` | create | 3 | 2 | $0.005 |
| `key-vault` | update | 3 (+1 assert from review) | 3 | $0.009 |
| `storage-account` | update | 8 | 2 | $0.013 |
| `data-factory` | create | 5 | 3 | $0.014 |
| `databricks-workspace` | create | 7 | 2 | $0.010 |
| `private-endpoint` | create | 5 | 1 | $0.013 |

`network`, `function-app` and the stack got their tests through the workflow in PR #2. After it was merged, all eight modules and the stack have tests. The new `private-dns-zone` module from PR #4 got its tests the same way.

## How to run

Prerequisites:

- GitHub repository with Actions enabled.
- Repository secret `CLAUDE_PLATFORM_API_KEY` with an Anthropic API key.
- The plugin must be on the base branch (`main`) before the PR is opened.

Optional repository variables: `TF_TEST_AGENT_MODEL` (default `haiku`) and `TF_TEST_AGENT_MAX_USD` (default `1`).

Then open a PR that changes `modules/**` or `stacks/**`. The workflow is `.github/workflows/tf-test-agent.yml`.

Run the agent locally (backfill mode, no PR needed). It needs `claude` (Claude Code CLI), `terraform`, `jq` and `python3`:

```sh
export ANTHROPIC_API_KEY=...
plugins/tf-test-agent/ci/run-agent.sh backfill - /tmp/agent-run modules/data-factory
```

The workflow uses the same script, so a local run behaves like a CI run. The report is in `/tmp/agent-run/report.json`.

Install the plugin in another repository (tested from a clean Claude config):

```sh
claude plugin marketplace add alanszuster/cf-task
claude plugin install tf-test-agent@tf-platform-base
```

## Where things are

| Path | What |
|---|---|
| `plugins/tf-test-agent/agents/test-engineer.md` | The custom agent: role, process and hard rules. |
| `plugins/tf-test-agent/skills/change-analysis/` | Decide `create`, `update` or `skip` for each target. |
| `plugins/tf-test-agent/skills/test-authoring/` | How to write tests, what not to test, how to prove them. Has a reference example. |
| `plugins/tf-test-agent/skills/review-findings/` | How to report problems to reviewers: severity, evidence, no code changes. |
| `plugins/tf-test-agent/bin/` | `tf-run-tests` and `tf-mutate`, the only commands the agent can run. |
| `plugins/tf-test-agent/ci/` | `run-agent.sh` (starts the agent in CI and locally), agent permissions, prompt builder, `verify.py`, `render.py`. |
| `plugins/tf-test-agent/schemas/report.schema.json` | Contract for the agent's report. |
| `.claude-plugin/marketplace.json` | Lets other repositories install the plugin. |

The agent loads each skill with the `Skill` tool when it needs it. The skills it used are read from the run log and shown in the PR comment.

## Example run

[PR #2](https://github.com/alanszuster/cf-task/pull/2) adds VNet integration to the function app: optional subnet delegation in `network`, an optional `virtual_network_subnet_id` in `function-app`, and a new delegated `functions` subnet in the stack.

**First push** (the change):

- **Targets:** `network`, `function-app` and `stacks/data-platform`.
- **Decisions:** `function-app` create (no tests before), `network` update (the new delegation block had no tests), stack create.
- **Skills used:** `change-analysis`, `test-authoring`, `review-findings`.
- **Verification by CI:** 11 tests pass, 10 of 10 mutations killed. Tests committed by the bot to the PR branch.
- **Findings:**
  - medium: the new `functions` subnet is not allowed on the data lake and the key vault, so the function app would likely be blocked at runtime. I had left this out on purpose; the agent also found the key vault part.
  - medium: `ftps_state = "AllAllowed"`. Not put in a test, because a test would confirm the defect.
  - low: my variable description said "leave empty", but an empty string turns routing on.
- **Cost:** $0.024, 26 turns.

**Second push** (my fixes after reading the findings):

- Only the new commit was analyzed. Targets: `function-app` and the stack.
- `function-app` update: one run for the new empty-string validation. Stack `skip`: the allow-lists are inside modules and no output shows them, so the agent explained why and suggested an output instead of guessing.
- The same PR comment was updated. The subnet finding is gone, because it was fixed.
- **Cost:** $0.020.

**Third push** (`ftps_state = "Disabled"`): the agent added `ftps_is_disabled`. Before, it had refused to test `AllAllowed`; now the code matches the intent, so it tests it.

Other PRs:

- [PR #1](https://github.com/alanszuster/cf-task/pull/1) (merged): a retention validation. The agent added boundary tests: 29 and 731 rejected, 730 accepted.
- [PR #3](https://github.com/alanszuster/cf-task/pull/3) (open): databricks private by default (`update`), a description-only change in key-vault (`skip`, no tests written), the prompt injection test, an "Update branch" from main (changes from main ignored), and a stack validation (`update`).
- [PR #4](https://github.com/alanszuster/cf-task/pull/4) (merged): a new `private-dns-zone` module that no stack uses yet. The agent wrote tests from zero: 6 runs, 6 of 6 mutations killed, $0.012. One finding was a false positive: it said the lock file in a module directory is misleading, but `terraform test` needs it. I added this to the `review-findings` skill.

## What the tests can and cannot show

They can show:

- What Terraform plans for given inputs: settings, names, counts, conditional blocks, outputs.
- That validations reject bad input.
- That each new test fails for at least one realistic bug.

They cannot show:

- What Azure accepts. Tests use a mocked provider, so a wrong SKU or region passes.
- Real values known only after apply, like IDs or IP addresses (the mock makes them up).
- Problems between resources at runtime, like network access or DNS. The agent reports these as findings when it sees them.
- That the intended behavior is the right one. The agent guesses intent from descriptions and conventions.

## Assumptions

- Contributors with write access are trusted like in normal CI. Running `terraform test` on PR code runs that code.
- Variable descriptions and the README describe the intended behavior.
- Tests run only with mocks. No cloud credentials, no cloud resources.
- Lock files are committed for every module with tests.

## Limitations

- The model is not deterministic. Two runs on the same change can give different tests. The checks in `verify` are deterministic.
- `verify` scope and weakening checks use simple text rules, not an HCL parser.
- Branch protection with other required checks will block the bot commit, because no other workflow runs on it.
- The agent sees only the targets and the diff. A wide change across many modules makes a big prompt.
- The agent works on the PR branch as it is. If the branch is far behind main, its tests are written against old code until the branch is updated.
- Loading skills is an instruction, not a rule CI checks. In one run the agent wrote findings without loading `review-findings`. The PR comment shows which skills were loaded, so a reviewer can see it.
- Stack tests cannot load `envs/*.tfvars`, so they copy the few values they need.
- Stack tests can read module outputs, not resources inside modules. Wiring that no output shows stays untested; the agent reports it.

## With many more modules, teams or repositories

- Install the plugin from the marketplace in each repository instead of copying it. Version it and roll out updates like any dependency.
- Move the workflow to a reusable workflow (`workflow_call`) in one central repository.
- Run one agent per target in parallel instead of one agent for all targets.
- Teams can add their own skills, for example naming rules, next to the shared ones.
- Track cost and results per repository to see where the agent helps and where it is noise.

## For a production version

- Use Claude through Microsoft Foundry with OIDC (`azure/login`) instead of an API key. No long-lived secret, billing and data stay in the company tenant.
- Push with a GitHub App token, so other checks run on the bot commit, and add a loop guard.
- Add `terraform plan` against a real backend with OIDC, so the agent can also read the plan, not only the code.
- Parse HCL properly in `verify` instead of using text rules.
- Add a small set of example PRs as an evaluation suite, and run it when the agent or skills change.
