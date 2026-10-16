---
name: change-analysis
description: Decide whether a Terraform change needs new or updated tests. Use before writing tests for a pull request or a module.
---

# Terraform change analysis

The goal is one decision per target, `create`, `update` or `skip`, with a reason a reviewer can check.

## Classify each change

| Change | Behavior change? |
|---|---|
| Resource, data source or module block added, removed or changed | yes |
| Argument value, `for_each`, `count`, `dynamic`, conditional expression | yes |
| Variable type, default or `validation` | yes |
| Output added, removed or changed value | yes |
| `locals` used by any of the above | yes |
| Provider or Terraform version constraint | yes, tests must still pass |
| Script or file read by the code (`data "external"`, `file()`, `templatefile()`) | yes, and a security-relevant one |
| Environment variable files (`envs/*.tfvars`) | yes for the stack |
| Formatting, comments, descriptions only | no |

## Decide

- `create`: the target has no tests and has behavior worth testing.
- `update`: the target has tests, and the change adds or alters behavior that they do not cover. Name the behavior.
- `skip`: no behavior change, or the existing tests already cover it. Name the `run` block that covers it.

A change in a module can break the stack that uses it. Find the callers with `Grep` for `source = "../../modules/<name>"` and check how they pass inputs. If the stack is a target too, decide for it separately.

## What to read

- The diff, then the full files around it. A diff alone hides the defaults and validations a test depends on.
- The module's `variables.tf` descriptions and the repository `README.md` conventions. They describe the intended behavior; the code shows the current behavior. Differences are findings.
- The existing tests of the target, so you extend them instead of duplicating them.
