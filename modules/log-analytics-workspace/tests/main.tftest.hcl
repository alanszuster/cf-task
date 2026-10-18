mock_provider "azurerm" {}

# The stack does not pass retention_in_days, so the default is what production gets.
run "uses_pay_as_you_go_sku_and_30_day_retention_by_default" {
  command = plan

  assert {
    condition     = azurerm_log_analytics_workspace.this.sku == "PerGB2018"
    error_message = "The workspace must use the PerGB2018 pay-as-you-go SKU; other SKUs change billing and are not what the stack expects."
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 30
    error_message = "retention_in_days must default to 30 because the stack relies on the default."
  }
}

run "retention_in_days_is_passed_through" {
  command = plan

  variables {
    retention_in_days = 90
  }

  assert {
    condition     = azurerm_log_analytics_workspace.this.retention_in_days == 90
    error_message = "A retention_in_days input must reach the workspace unchanged."
  }
}

run "output_id_points_at_the_workspace" {
  command = apply

  assert {
    condition     = output.id == azurerm_log_analytics_workspace.this.id
    error_message = "The id output must be the workspace resource ID, not another attribute."
  }
}
