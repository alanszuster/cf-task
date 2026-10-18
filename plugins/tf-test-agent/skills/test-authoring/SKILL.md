---
name: test-authoring
description: Write `terraform test` files that encode intended behavior, run them, and prove each run with a mutation. Use when creating or updating tests for a Terraform module or stack.
---

# Writing Terraform tests

## Layout

- Tests live in `<target>/tests/main.tftest.hcl`. Add another `*.tftest.hcl` file only for a separate concern, for example `validation.tftest.hcl`.
- Shared inputs go in `<target>/tests/terraform.tfvars`, which `terraform test` loads automatically. A new test file has no file-level `variables {}` block. Only when you update an existing file that already has one, keep it as it is. Put a `variables {}` block inside a `run` only for what that scenario changes.
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

## Testing a stack

- Assertions can read resources of the stack itself, outputs of the modules it calls (`module.network.subnet_ids["functions"]`) and module instances of a `for_each` (`length(module.lake_endpoint)`, `keys(module.lake_endpoint)`).
- They cannot read resources inside a module (`module.function_app.azurerm_linux_function_app.this`). When the wiring you need is not in any output, report it as a finding and suggest the output; do not skip what outputs already show.
- Use `command = plan`. Under `apply`, mocked IDs from one resource often fail validation in another.
- Override every `data "external"` of called modules with its full address, for example `module.function_app.data.external.build_info`.

## What not to test

- An input passed unchanged to an argument (`name = var.name`). Terraform does that; a test adds nothing. Test it only when the value is transformed, combined or follows a convention.
- A hardcoded value whose meaning you cannot state. Assert a literal only when you can say in `error_message` why it matters, for example a security setting or a cost tier the stack relies on.
- Defaults no caller relies on. Check how the stack calls the module first.

A small module may need only two or three runs. That is a good result, not a gap.

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

   A mutation must be a mistake a person could realistically make in a pull request: flip a security boolean, change a name prefix, drop a `for_each` filter, make a condition always true, lower a retention, point an output at the wrong attribute. Swapping an argument for an unrelated variable is not realistic and proves nothing about the run. One mutation per run is enough when it hits the property the run is named after.
3. Report each run with its mutations. CI repeats the test run and every mutation, independently of you.
