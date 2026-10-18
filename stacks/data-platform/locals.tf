locals {
  prefix = "tp-${var.environment}"

  tags = {
    environment = var.environment
    product     = "data-platform"
    managed_by  = "terraform"
  }

  subnets = {
    apps = {
      address_prefixes  = [cidrsubnet(var.vnet_address_space[0], 8, 0)]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    endpoints = {
      address_prefixes = [cidrsubnet(var.vnet_address_space[0], 8, 1)]
    }
    functions = {
      address_prefixes  = [cidrsubnet(var.vnet_address_space[0], 8, 2)]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
      delegation = {
        name    = "functions"
        service = "Microsoft.Web/serverFarms"
        actions = ["Microsoft.Network/virtualNetworks/subnets/action"]
      }
    }
  }

  lake_endpoints = {
    for pair in flatten([
      for lake_key in keys(var.data_lakes) : [
        for sub in ["blob", "dfs"] : {
          key  = "${lake_key}-${sub}"
          lake = lake_key
          sub  = sub
        }
      ]
    ]) : pair.key => pair
  }
}
