data "azurerm_client_config" "current" {}

resource "azurerm_key_vault" "main" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = var.sku_name

  # Secure default: RBAC is the only supported authorization mode in this module.
  # Access policies are deprecated by Microsoft and create harder-to-audit permissions.
  rbac_authorization_enabled = true

  # Secure default: prevents accidental or malicious permanent deletion of vault objects.
  # Note: once enabled on a deployed vault, purge protection cannot be disabled.
  # Set purge_protection_enabled = false in non-prod environments that need clean teardown.
  purge_protection_enabled = var.purge_protection_enabled

  # Secure default: retains deleted vault objects for the full recovery window.
  soft_delete_retention_days = var.soft_delete_retention_days

  # Secure default: all public internet access blocked; access must flow via private
  # endpoint or approved network rules defined in network_acls.
  public_network_access_enabled = var.public_network_access_enabled

  # Secure default: deny-by-default firewall with AzureServices bypass.
  # Required for CKV_AZURE_109 regardless of public_network_access_enabled value.
  # default_action is hardened to "Deny"; callers control bypass, ip_rules, and
  # virtual_network_subnet_ids via var.network_acls.
  network_acls {
    bypass                     = var.network_acls.bypass
    default_action             = "Deny"
    ip_rules                   = var.network_acls.ip_rules
    virtual_network_subnet_ids = var.network_acls.virtual_network_subnet_ids
  }

  tags = var.tags
}

resource "azurerm_role_assignment" "main" {
  for_each = var.role_assignments

  scope                = azurerm_key_vault.main.id
  role_definition_name = each.value.role_definition_name
  principal_id         = each.value.principal_id
}
