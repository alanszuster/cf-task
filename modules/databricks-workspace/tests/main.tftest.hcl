mock_provider "azurerm" {}

run "workspace_has_no_public_ip" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.custom_parameters[0].no_public_ip == true
    error_message = "The workspace must use no public IPs on its cluster nodes (secure cluster connectivity)."
  }
}

run "managed_resource_group_follows_naming" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.managed_resource_group_name == "${var.resource_group_name}-${var.name}-managed"
    error_message = "The managed resource group must be named <resource group>-<workspace name>-managed so it is unique per workspace."
  }
}

run "public_access_follows_input" {
  command = plan

  variables {
    public_network_access_enabled = false
  }

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "public_network_access_enabled must follow the input; the stack relies on it to disable public access per environment."
  }
}

run "public_access_is_off_by_default" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.public_network_access_enabled == false
    error_message = "Public network access must be off when the caller does not set it; the default is the secure baseline."
  }
}

run "default_sku_is_premium" {
  command = plan

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "premium"
    error_message = "The default SKU must be premium; the stack does not set sku and relies on it."
  }
}

run "rejects_unsupported_sku" {
  command = plan

  variables {
    sku = "basic"
  }

  expect_failures = [
    var.sku,
  ]
}

run "accepts_standard_sku" {
  command = plan

  variables {
    sku = "standard"
  }

  assert {
    condition     = azurerm_databricks_workspace.this.sku == "standard"
    error_message = "The standard SKU must be accepted and passed through unchanged."
  }
}

run "outputs_expose_workspace_attributes" {
  command = apply

  assert {
    condition     = output.id == azurerm_databricks_workspace.this.id
    error_message = "The id output must expose the workspace id."
  }

  assert {
    condition     = output.workspace_url == azurerm_databricks_workspace.this.workspace_url
    error_message = "The workspace_url output must expose the workspace URL, not another attribute."
  }
}
