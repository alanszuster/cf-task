mock_provider "azurerm" {}

run "connects_automatically_to_the_target_subresource" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].private_connection_resource_id == var.target_resource_id
    error_message = "The endpoint must connect to the resource it was given."
  }

  assert {
    condition     = tolist(azurerm_private_endpoint.this.private_service_connection[0].subresource_names) == tolist([var.subresource_name])
    error_message = "The endpoint must connect to the sub-resource it was given, for example blob or vault."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].is_manual_connection == false
    error_message = "The connection must be approved automatically; a manual connection leaves the endpoint pending until someone approves it."
  }
}

run "endpoint_names_follow_the_convention" {
  command = plan

  assert {
    condition     = azurerm_private_endpoint.this.name == "pe-${var.name}"
    error_message = "The endpoint name must be pe- followed by var.name."
  }

  assert {
    condition     = azurerm_private_endpoint.this.private_service_connection[0].name == "psc-${var.name}"
    error_message = "The service connection name must be psc- followed by var.name."
  }
}

run "no_dns_zone_group_without_a_zone" {
  command = plan

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 0
    error_message = "No DNS zone group may be created when var.private_dns_zone_id is null."
  }
}

run "dns_zone_group_links_the_given_zone" {
  command = plan

  variables {
    private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test/providers/Microsoft.Network/privateDnsZones/privatelink.blob.core.windows.net"
  }

  assert {
    condition     = length(azurerm_private_endpoint.this.private_dns_zone_group) == 1
    error_message = "Exactly one DNS zone group must be created when a private DNS zone is given."
  }

  assert {
    condition     = tolist(azurerm_private_endpoint.this.private_dns_zone_group[0].private_dns_zone_ids) == tolist([var.private_dns_zone_id])
    error_message = "The DNS zone group must link the endpoint to the zone it was given, so names resolve to the private address."
  }
}

run "outputs_expose_the_endpoint_id_and_its_address" {
  command = apply

  assert {
    condition     = output.id == azurerm_private_endpoint.this.id
    error_message = "Output id must be the ID of the private endpoint."
  }

  assert {
    condition     = output.private_ip_address == azurerm_private_endpoint.this.private_service_connection[0].private_ip_address
    error_message = "Output private_ip_address must be the endpoint's private address."
  }
}
