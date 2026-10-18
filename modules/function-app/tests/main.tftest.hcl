mock_provider "azurerm" {}

mock_provider "external" {}

override_data {
  target = data.external.build_info
  values = {
    result = {
      revision = "test"
    }
  }
}

run "is_https_only_with_tls_12_and_managed_identity" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.https_only == true
    error_message = "The function app must only accept HTTPS."
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].minimum_tls_version == "1.2"
    error_message = "The function app must require TLS 1.2 or later."
  }

  assert {
    condition     = azurerm_linux_function_app.this.storage_uses_managed_identity == true
    error_message = "The runtime storage must be accessed with the managed identity, not an access key."
  }

  assert {
    condition     = azurerm_linux_function_app.this.identity[0].type == "SystemAssigned"
    error_message = "The function app must use a system-assigned managed identity."
  }
}

run "runtime_storage_role_is_scoped_to_the_storage_account" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.runtime_storage.role_definition_name == "Storage Blob Data Owner"
    error_message = "The runtime identity must hold Storage Blob Data Owner on the storage account."
  }

  assert {
    condition     = azurerm_role_assignment.runtime_storage.scope == var.storage_account_id
    error_message = "The role assignment must be scoped to the storage account given as input."
  }
}

run "private_when_public_access_is_disabled" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_linux_function_app.this.public_network_access_enabled == false
    error_message = "Public network access must be disabled when the input says so."
  }
}

run "vnet_integration_routes_all_traffic_when_a_subnet_is_given" {
  command = plan

  variables {
    virtual_network_subnet_id = "/subscriptions/00000000-0000-0000-0000-000000000001/resourceGroups/rg-tp-test/providers/Microsoft.Network/virtualNetworks/vnet-tp-test/subnets/snet-functions"
  }

  assert {
    condition     = azurerm_linux_function_app.this.virtual_network_subnet_id == var.virtual_network_subnet_id
    error_message = "The function app must be integrated with the subnet given as input."
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].vnet_route_all_enabled == true
    error_message = "All outbound traffic must route through the VNet when integration is enabled."
  }
}

run "no_vnet_integration_without_a_subnet" {
  command = plan

  assert {
    condition     = azurerm_linux_function_app.this.virtual_network_subnet_id == null
    error_message = "Without a subnet input the function app must not be integrated with a VNet."
  }

  assert {
    condition     = azurerm_linux_function_app.this.site_config[0].vnet_route_all_enabled == false
    error_message = "VNet routing must stay disabled when there is no subnet."
  }
}

run "rejects_an_empty_string_subnet_instead_of_null" {
  command = plan

  variables {
    virtual_network_subnet_id = ""
  }

  expect_failures = [var.virtual_network_subnet_id]
}
