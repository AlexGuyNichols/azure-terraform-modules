# examples/storage-account/secure/main.tf
# Full production surface — hardened remote-state reference: firewalled,
# zone-redundant, versioned, with a tfstate container.
# Reference for consumers who need network_rules, explicit retention,
# and container creation in one place.

provider "azurerm" {
  features {}
}

module "storage_account" {
  source = "../../../modules/storage-account"

  name                = "stexamplesecure"
  location            = "uksouth"
  resource_group_name = "rg-example"

  account_tier             = "Standard"
  account_replication_type = "ZRS" # zone-redundant — production-grade durability for state

  blob_versioning_enabled         = true
  blob_delete_retention_days      = 30
  container_delete_retention_days = 30

  # Reachable for CI/dev machines per the module's deliberate default — D-07;
  # traffic is firewalled by network_rules below.
  public_network_access_enabled = true

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
    ip_rules       = ["203.0.113.0/24"] # RFC 5737 documentation range; replace in real use
  }

  containers = ["tfstate"] # remote-state container — access is always private, hardcoded in the module

  tags = {
    environment = "example"
    managed_by  = "terraform"
  }
}

output "storage_account_id" {
  value       = module.storage_account.storage_account_id
  description = "Resource ID of the provisioned storage account."
}
