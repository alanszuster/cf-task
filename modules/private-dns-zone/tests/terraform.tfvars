zone_names = [
  "privatelink.blob.core.windows.net",
  "privatelink.vaultcore.azure.net",
]
resource_group_name = "rg-test-dns"
virtual_network_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-test-network/providers/Microsoft.Network/virtualNetworks/vnet-test"
tags = {
  environment = "test"
}
