---
name: test-authoring
description: Write `terraform test` files that encode intended behavior, run them, and prove each run with a mutation. Use when creating or updating tests for a Terraform module or stack.
---

# Writing Terraform tests

## Layout

- Tests live in `<target>/tests/main.tftest.hcl`. Add another `*.tftest.hcl` file only for a separate concern, for example `validation.tftest.hcl`.
- Keep shared inputs in one place. For a target without tests, put them in `<target>/tests/terraform.tfvars`, which `terraform test` loads automatically. When an existing test file has a file-level `variables {}` block, keep using it. Put a `variables {}` block inside a `run` only for what that scenario changes.
- Assertions compare with `var.*` or with a value the convention defines, for example `"pe-${var.name}"`. Do not repeat input literals in assertions.

## Providers and side effects

- Mock every provider the target uses: `mock_provider "azurerm" {}`.
- A `data "external"` source runs a program during plan, even in a test. Always override it, so a test never executes repository scripts:

  ```hcl
  override_data {
    target = data.external.build_info            # module.function_app.data.external.build_info from a stack
    values = { result = { revision = "test" } }
  }
  ```

- Provisioners (`local-exec`, `remote-exec`) still run under `command = apply`. If the target has one, test with `command = plan` only and report it.

## plan or apply

Use `command = plan` by default. Use `command = apply` only to check outputs or values that are unknown until apply. The mock provider fills them with generated values.

## What to test, in this order

1. Intended security and safety properties: TLS, public access, network default actions, role names and scopes, purge protection, `https_only`.
2. Every `validation` block: one run with an invalid value and `expect_failures = [var.<name>]`, and the valid boundary when there is one.
3. Both branches of every condition: `dynamic` blocks, `count`/`for_each` with an empty collection, ternaries, `null` defaults.
4. Cardinality and keys of `for_each` resources.
5. Naming conventions from the README.
6. Outputs: wired to the right attribute.
7. For a stack: properties per environment (for example that prod disables public access) and wiring between modules (for example that each lake gets `blob` and `dfs` endpoints). A run cannot load `envs/*.tfvars`, so put the few values a run needs in its `variables` block and keep them aligned with the environment file.

## Intent, not the current state

Derive the intended behavior from variable descriptions, names, the README conventions and a secure baseline. When the code does something else, for example `ftps_state = "AllAllowed"`, do not write an assertion that confirms it. Leave it untested and report a finding. A test that confirms a defect makes the defect harder to fix.

## Expressions that trip

- Nested blocks are lists: `azurerm_private_endpoint.this.private_service_connection[0].name`.
- Compare lists with `tolist([...])`; for sets use `contains(...)` or `length(...)`.
- A block that a `dynamic` creates zero times has `length(...) == 0`.
- Values computed by the provider are unknown under `plan`; asserting on them fails with an "unknown value" error, not a real failure.

See [reference.md](reference.md) for a complete example.

## Run and prove

1. Run `tf-run-tests <target>`. It checks `terraform fmt` of the tests, validates and runs all tests of the target. On success it prints one summary line; on failure the full output.
2. For every run you added or changed, prove it with at least one mutation: a small, realistic wrong change to a `.tf` file that the run must catch. Check all of them in one call:

   ```sh
   tf-mutate --batch '[
     {"target": "modules/x", "file": "modules/x/main.tf", "find": "is_manual_connection           = false", "replace": "is_manual_connection           = true", "expect": "connects_to_the_target_automatically"}
   ]'
   ```

   `find` is the exact text of one line or part of it, including its spacing. The result is one line per mutation:

   - `killed`: the run catches the regression. Keep the mutation for the report.
   - `survived`: the run does not catch it. Strengthen the run or choose the regression the run is really about.
   - `invalid`: the text is not found exactly once, or the mutated code does not validate. A syntax error proves nothing; mutate a value, a condition or a reference.

   Good mutations: flip a boolean, change a name prefix, drop a `for_each` filter, make a condition always true, swap a reference for another variable. One mutation per run is enough when it hits the property the run is named after.
3. Report each run with its mutations. CI repeats the test run and every mutation, independently of you.
