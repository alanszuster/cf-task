# Reference test

A module with a conditional block, an optional input and outputs. The test covers both branches of the condition, keeps inputs in `tests/terraform.tfvars` and checks outputs with `apply`.

`tests/terraform.tfvars`:

```hcl
name                = "tp-test-raw-blob"
resource_group_name = "rg-test"
location            = "westeurope"
subnet_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-endpoints"
target_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Storage/storageAccounts/sttptest001"
subresource_name    = "blob"
```

`tests/main.tftest.hcl`:

```hcl
mock_provider "azurerm" {}

run "connects_to_the_target_automatically" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == var.target_resource_id
    error_message = "The endpoint must connect to var.target_resource_id."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be approved automatically, not wait for manual approval."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when var.private_dns_zone_id is null."
  }
}

run "registers_in_the_given_dns_zone" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids == tolist([var.private_dns_zone_id])
    error_message = "The DNS zone group must use exactly var.private_dns_zone_id."
  }
}

run "exposes_the_endpoint_outputs" {
  command = apply

  assert {
    condition     = output.private_ip_address == azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
    error_message = "Output private_ip_address must come from the service connection."
  }
}
```

Mutations that prove these runs:

| Run | File change | Result |
|---|---|---|
| `connects_to_the_target_automatically` | `is_manual_connection = false` to `true` | killed |
| `no_dns_zone_group_without_a_zone` | `var.private_dns_zone_id == null ? [] : [var.private_dns_zone_id]` to `[var.private_dns_zone_id]` | killed |
| `registers_in_the_given_dns_zone` | `[private_dns_zone_group.value]` to `[]` | killed |

Validation runs look like this:

```hcl
run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}
```
