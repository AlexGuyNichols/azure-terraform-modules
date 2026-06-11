# examples/key-vault/secure/main.tf
# Full production surface — demonstrates all module inputs with hardened ACL.
# Reference for consumers who need ip_rules, role_assignments, and explicit retention.

provider "azurerm" {
  features {}
}

module "key_vault" {
  source = "../../../modules/key-vault"

  name                = "kv-example-secure"
  location            = "uksouth"
  resource_group_name = "rg-example"

  sku_name                   = "standard"
  soft_delete_retention_days = 90
  purge_protection_enabled   = true

  # enabled here to demonstrate ip_rules usage; the module hardcodes default_action = Deny
  public_network_access_enabled = true

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"] # RFC 5737 documentation range; replace in real use
  }

  role_assignments = {
    api_reader = {
      role_definition_name = "Key Vault Secrets User"
      principal_id         = var.api_principal_id
    }
  }

  tags = {
    environment = "example"
    managed_by  = "terraform"
  }
}

output "key_vault_id" {
  value       = module.key_vault.key_vault_id
  description = "Resource ID of the provisioned Key Vault."
}
