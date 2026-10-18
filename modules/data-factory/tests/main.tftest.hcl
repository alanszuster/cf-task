mock_provider "azurerm" {
  mock_resource "azurerm_data_factory" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.DataFactory/factories/adf-tp-test"
    }
  }
}

run "public_access_can_be_disabled" {
  command = plan

  variables {
    public_network_enabled = false
  }

  assert {
    condition     = azurerm_data_factory.this.public_network_enabled == false
    error_message = "The factory must not be reachable from the public internet when var.public_network_enabled is false."
  }
}

run "uses_a_system_assigned_identity" {
  command = plan

  assert {
    condition     = azurerm_data_factory.this.identity[0].type == "SystemAssigned"
    error_message = "The factory must use a system-assigned managed identity; the stack grants secret access to its principal."
  }
}

run "links_each_lake_with_managed_identity" {
  command = plan

  variables {
    linked_storage_accounts = {
      raw     = "https://strawtest001.dfs.core.windows.net/"
      curated = "https://stcuratedtest001.dfs.core.windows.net/"
    }
  }

  assert {
    condition     = length(azurerm_data_factory_linked_service_data_lake_storage_gen2.this) == 2
    error_message = "Exactly one linked service must be created per entry in var.linked_storage_accounts."
  }

  assert {
    condition     = azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].name == "ls-raw" && azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].url == var.linked_storage_accounts["raw"]
    error_message = "The linked service for a lake must be named ls-<key> and point at that lake's DFS endpoint."
  }

  assert {
    condition     = azurerm_data_factory_linked_service_data_lake_storage_gen2.this["raw"].use_managed_identity == true && azurerm_data_factory_linked_service_data_lake_storage_gen2.this["curated"].use_managed_identity == true
    error_message = "Linked lakes must authenticate with the factory's managed identity, not an account key."
  }
}

run "diagnostics_capture_pipeline_and_activity_runs" {
  command = plan

  assert {
    condition     = azurerm_monitor_diagnostic_setting.this.name == "diag-adf-tp-test"
    error_message = "The diagnostic setting must be named diag-<factory name>."
  }

  assert {
    condition     = length(azurerm_monitor_diagnostic_setting.this.enabled_log) == 2
    error_message = "Exactly two log categories must be enabled: PipelineRuns and ActivityRuns."
  }

  assert {
    condition     = contains([for log in azurerm_monitor_diagnostic_setting.this.enabled_log : log.category], "PipelineRuns") && contains([for log in azurerm_monitor_diagnostic_setting.this.enabled_log : log.category], "ActivityRuns")
    error_message = "Diagnostics must send PipelineRuns and ActivityRuns; these are the logs used to troubleshoot pipeline failures."
  }
}

run "outputs_expose_the_factory_identity" {
  command = apply

  assert {
    condition     = output.principal_id == azurerm_data_factory.this.identity[0].principal_id
    error_message = "Output principal_id must be the factory's managed identity object ID, which the stack grants secret access to."
  }
}
