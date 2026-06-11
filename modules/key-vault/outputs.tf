output "key_vault_id" {
  value       = azurerm_key_vault.main.id
  description = "Resource ID of the Key Vault. Pass to secret, key, and role-assignment resources in the calling module."
}

output "key_vault_uri" {
  value       = azurerm_key_vault.main.vault_uri
  description = "URI of the Key Vault (e.g., https://kv-myapp.vault.azure.net/). Use in application configuration to reference the vault endpoint."
}
