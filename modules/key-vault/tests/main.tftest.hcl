mock_provider "azurerm" {}

variables {
  name                = "kv-tp-test"
  resource_group_name = "rg-test"
  location            = "westeurope"
  tenant_id           = "00000000-0000-0000-0000-000000000000"
  secret_readers = {
    adf = "11111111-1111-1111-1111-111111111111"
  }
}

run "vault_uses_rbac_and_purge_protection" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.rbac_authorization_enabled == true
    error_message = "The vault must use role-based access, not access policies."
  }

  assert {
    condition     = azurerm_key_vault.this.purge_protection_enabled == true
    error_message = "Purge protection must be on."
  }
}

run "creates_one_role_assignment_per_reader" {
  command = plan

  assert {
    condition     = length(azurerm_role_assignment.secret_reader) == 1
    error_message = "Expected one role assignment for each secret reader."
  }
}

run "denies_network_by_default_and_allows_only_listed_subnets" {
  command = plan

  variables {
    allowed_subnet_ids = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/virtualNetworks/vnet-test/subnets/apps"]
  }

  assert {
    condition     = azurerm_key_vault.this.network_acls[0].default_action == "Deny"
    error_message = "The vault firewall must deny traffic by default."
  }

  assert {
    condition     = tolist(azurerm_key_vault.this.network_acls[0].virtual_network_subnet_ids) == tolist(var.allowed_subnet_ids)
    error_message = "Only the subnets passed in allowed_subnet_ids may reach the vault."
  }
}

run "grants_secrets_user_role_to_each_reader_principal" {
  command = plan

  assert {
    condition     = azurerm_role_assignment.secret_reader["adf"].principal_id == var.secret_readers["adf"]
    error_message = "Each secret reader must be granted access as its own principal, keyed by its short name."
  }

  assert {
    condition     = data.azurerm_role_definition.secrets_user.name == "Key Vault Secrets User"
    error_message = "Readers must get the Secrets User role, not a broader one."
  }
}

run "keeps_deleted_secrets_recoverable_for_30_days" {
  command = plan

  assert {
    condition     = azurerm_key_vault.this.soft_delete_retention_days == 30
    error_message = "Soft delete retention must be 30 days, the recovery window the platform relies on."
  }
}
