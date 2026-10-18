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

run "rejects_public_access_outside_dev" {
  command = plan

  variables {
    environment           = "uat"
    public_access_enabled = true
  }

  expect_failures = [var.public_access_enabled]
}
