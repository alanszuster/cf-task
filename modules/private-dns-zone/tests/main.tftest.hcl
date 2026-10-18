mock_provider "azurerm" {}

run "creates_one_zone_and_one_link_per_name" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone.this) == length(toset(var.zone_names))
    error_message = "Expected exactly one private DNS zone for each distinct zone name."
  }

  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == length(azurerm_private_dns_zone.this)
    error_message = "Every zone must have exactly one virtual network link."
  }

  assert {
    condition     = azurerm_private_dns_zone.this["privatelink.blob.core.windows.net"].resource_group_name == var.resource_group_name
    error_message = "Zones must be created in the resource group passed in resource_group_name."
  }
}

run "links_each_zone_to_the_network_without_auto_registration" {
  command = plan

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.this["privatelink.blob.core.windows.net"].virtual_network_id == var.virtual_network_id
    error_message = "Each link must attach its zone to the virtual network passed in virtual_network_id."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.this["privatelink.blob.core.windows.net"].registration_enabled == false
    error_message = "Auto-registration must stay off on privatelink zones; VM records must not be written into them."
  }

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.this["privatelink.blob.core.windows.net"].private_dns_zone_name == "privatelink.blob.core.windows.net"
    error_message = "Each link must point at the zone with the same name, not at another zone."
  }
}

run "link_name_replaces_dots_with_dashes" {
  command = plan

  assert {
    condition     = azurerm_private_dns_zone_virtual_network_link.this["privatelink.vaultcore.azure.net"].name == "link-privatelink-vaultcore-azure-net"
    error_message = "Link names must follow link-<zone name with dots replaced by dashes> so they stay unique per zone."
  }
}

run "empty_zone_list_creates_nothing" {
  command = plan

  variables {
    zone_names = []
  }

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 0 && length(azurerm_private_dns_zone_virtual_network_link.this) == 0
    error_message = "An empty zone_names list must create no zones and no links."
  }
}

run "zone_names_must_be_privatelink_zones" {
  command = plan

  variables {
    zone_names = ["privatelink.blob.core.windows.net", "blob.core.windows.net"]
  }

  expect_failures = [var.zone_names]
}

run "output_zone_ids_maps_each_name_to_its_zone_id" {
  command = apply

  assert {
    condition     = output.zone_ids["privatelink.blob.core.windows.net"] == azurerm_private_dns_zone.this["privatelink.blob.core.windows.net"].id
    error_message = "zone_ids must map each zone name to the ID of the zone with that name."
  }

  assert {
    condition     = length(output.zone_ids) == length(toset(var.zone_names))
    error_message = "zone_ids must contain one entry per zone."
  }
}
