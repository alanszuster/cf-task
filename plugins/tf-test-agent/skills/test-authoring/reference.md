# Reference test

A made-up module, not one from this repository. It shows the patterns; write your own runs for the real target.

The module creates a container registry with an optional replica:

```hcl
resource "azurerm_container_registry" "this" {
  name                          = "acr${var.name}"
  resource_group_name           = var.resource_group_name
  location                      = var.location
  sku                           = "Premium"
  admin_enabled                 = false
  public_network_access_enabled = var.public_network_access_enabled

  dynamic "georeplications" {
    for_each = var.replica_location == null ? [] : [var.replica_location]

    content {
      location                = georeplications.value
      zone_redundancy_enabled = true
    }
  }
}

output "login_server" {
  value = azurerm_container_registry.this.login_server
}
```

`tests/terraform.tfvars`:

```hcl
name                = "test"
resource_group_name = "rg-test"
location            = "westeurope"
```

`tests/main.tftest.hcl`:

```hcl
mock_provider "azurerm" {}

run "no_admin_user_and_private_by_default" {
  command = plan

  assert {
    condition     = azurerm_container_registry.this.admin_enabled == false
    error_message = "The shared admin user must stay off; access goes through identities."
  }

  assert {
    condition     = azurerm_container_registry.this.public_network_access_enabled == false
    error_message = "The registry must not be reachable from the internet unless a caller asks for it."
  }
}

run "no_replica_without_a_location" {
  command = plan

  assert {
    condition     = length(azurerm_container_registry.this.georeplications) == 0
    error_message = "No replica may be created when var.replica_location is null."
  }
}

run "replica_is_zone_redundant" {
  command = plan

  variables {
    replica_location = "northeurope"
  }

  assert {
    condition     = azurerm_container_registry.this.georeplications[0].zone_redundancy_enabled == true
    error_message = "A replica exists for resilience, so it must be zone redundant."
  }
}

run "login_server_output_is_the_registry_address" {
  command = apply

  assert {
    condition     = output.login_server == azurerm_container_registry.this.login_server
    error_message = "Output login_server must be the registry's address."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}
```

Mutations that prove these runs, as `tf-mutate --batch` entries:

| Run | `find` | `replace` |
|---|---|---|
| `no_admin_user_and_private_by_default` | `admin_enabled                 = false` | `admin_enabled                 = true` |
| `no_replica_without_a_location` | `var.replica_location == null ? [] : [var.replica_location]` | `[coalesce(var.replica_location, "northeurope")]` |
| `replica_is_zone_redundant` | `zone_redundancy_enabled = true` | `zone_redundancy_enabled = false` |
| `login_server_output_is_the_registry_address` | `azurerm_container_registry.this.login_server` | `azurerm_container_registry.this.name` |

A mutation that breaks every run proves nothing about one run. `[var.replica_location]` with a null value fails all plans, so the expected run is not shown to catch anything. "Always create a replica" is the mistake this run is about.

Every run you add or change needs its own mutation in the report, proven with `tf-mutate`. A run without one is rejected by CI.
