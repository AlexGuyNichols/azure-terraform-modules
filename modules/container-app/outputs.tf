output "container_app_id" {
  description = "Resource ID of the container app."
  value       = azurerm_container_app.main.id
}

output "container_app_name" {
  description = "Name of the container app."
  value       = azurerm_container_app.main.name
}

output "principal_id" {
  description = "Principal ID of the system-assigned managed identity. Use this in caller-side role assignments to grant the app access to Azure resources (e.g. 'Key Vault Secrets User' for vault secret access)."
  value       = azurerm_container_app.main.identity[0].principal_id
}

output "latest_revision_fqdn" {
  description = "Fully qualified domain name of the latest active revision. Only populated when ingress is configured; empty string when ingress is null."
  value       = azurerm_container_app.main.latest_revision_fqdn
}
