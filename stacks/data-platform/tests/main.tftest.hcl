mock_provider "azurerm" {}

mock_provider "external" {}

override_data {
  target = module.function_app.data.external.build_info
  values = {
    result = {
      revision = "test"
    }
  }
}

run "resource_group_follows_the_naming_convention" {
  command = plan

  assert {
    condition     = output.resource_group_name == "rg-tp-dev"
    error_message = "The resource group must be named rg-<prefix>, where the prefix is tp-<environment>."
  }
}

run "rejects_an_unknown_environment" {
  command = plan

  variables {
    environment = "staging"
  }

  expect_failures = [var.environment]
}

run "every_endpoint_subresource_has_a_private_dns_zone" {
  command = plan

  assert {
    condition     = sort(keys(module.private_dns.zone_ids)) == tolist(["privatelink.blob.core.windows.net", "privatelink.dfs.core.windows.net", "privatelink.vaultcore.azure.net"])
    error_message = "Private DNS must hold one privatelink zone for each endpoint sub-resource: blob, dfs and vault. Without them, endpoint names do not resolve to private IPs."
  }
}

run "every_lake_gets_blob_and_dfs_endpoints" {
  command = plan

  assert {
    condition     = length(module.lake_endpoint) == 2 * length(var.data_lakes) && alltrue([for key in keys(var.data_lakes) : contains(keys(module.lake_endpoint), "${key}-blob") && contains(keys(module.lake_endpoint), "${key}-dfs")])
    error_message = "Every data lake must get a private endpoint for both its blob and its dfs sub-resource."
  }
}
