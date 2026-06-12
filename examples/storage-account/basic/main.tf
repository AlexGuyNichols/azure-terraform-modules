# examples/storage-account/basic/main.tf
# Minimal required inputs — all hardened defaults inherited.
# Proves: drop in the module with required inputs only and get a clean plan
# suitable for remote state; HTTPS-only, TLS 1.2, no public blob access,
# versioning and soft-delete enabled — all without any configuration.

provider "azurerm" {
  features {}
}

module "storage_account" {
  source = "../../../modules/storage-account"

  name                = "stexamplebasic"
  location            = "uksouth"
  resource_group_name = "rg-example"
}
