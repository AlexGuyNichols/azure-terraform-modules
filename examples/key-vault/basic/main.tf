# examples/key-vault/basic/main.tf
# Minimal required inputs — all hardened defaults inherited.
# Proves: drop in the module with required inputs only and get a clean plan.

provider "azurerm" {
  features {}
}

module "key_vault" {
  source = "../../../modules/key-vault"

  name                = "kv-example-basic"
  location            = "uksouth"
  resource_group_name = "rg-example"
}
