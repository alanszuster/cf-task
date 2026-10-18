mock_provider "azurerm" {}

variables {
  name                = "sttptest001"
  resource_group_name = "rg-test"
  location            = "westeurope"
  containers          = ["raw", "curated"]
}

run "account_is_locked_down_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.min_tls_version == "TLS1_2"
    error_message = "The account must require TLS 1.2."
  }

  assert {
    condition     = azurerm_storage_account.this.allow_nested_items_to_be_public == false
    error_message = "Public blob access must be off."
  }

  assert {
    condition     = azurerm_storage_account_network_rules.this.default_action == "Deny"
    error_message = "Network access must be denied by default."
  }
}

run "creates_one_container_per_name" {
  command = plan

  assert {
    condition     = length(azurerm_storage_container.this) == 2
    error_message = "Expected one container for each name."
  }
}

run "rejects_invalid_name" {
  command = plan

  variables {
    name = "Invalid-Name"
  }

  expect_failures = [var.name]
}

run "enforces_https_and_disables_shared_keys" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.https_traffic_only_enabled == true
    error_message = "Plain HTTP must be refused: https_traffic_only_enabled must be true."
  }

  assert {
    condition     = azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Shared key access must be off so that Entra ID is the only way in."
  }
}

run "allows_only_the_listed_subnets" {
  command = plan

  variables {
    allowed_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/snet-apps"]
  }

  assert {
    condition     = length(azurerm_storage_account_network_rules.this.virtual_network_subnet_ids) == 1 && contains(azurerm_storage_account_network_rules.this.virtual_network_subnet_ids, var.allowed_subnet_ids[0])
    error_message = "The network rules must allow exactly the subnets in var.allowed_subnet_ids."
  }
}

run "enables_hierarchical_namespace_for_data_lakes" {
  command = plan

  variables {
    is_data_lake = true
  }

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == true
    error_message = "A data lake account must have the hierarchical namespace enabled."
  }
}

run "keeps_hierarchical_namespace_off_by_default" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.is_hns_enabled == false
    error_message = "Accounts that are not data lakes must not get the hierarchical namespace."
  }
}

run "containers_are_private" {
  command = plan

  assert {
    condition     = alltrue([for c in azurerm_storage_container.this : c.container_access_type == "private"])
    error_message = "Every container must be private; anonymous read access is not allowed."
  }
}

run "keeps_seven_days_of_blob_soft_delete" {
  command = plan

  assert {
    condition     = azurerm_storage_account.this.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Blob soft delete must keep deleted data for 7 days so that accidental deletes can be recovered."
  }
}

run "accepts_name_at_the_24_character_limit" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwx"
  }
}

run "rejects_name_longer_than_24_characters" {
  command = plan

  variables {
    name = "abcdefghijklmnopqrstuvwxy"
  }

  expect_failures = [var.name]
}
