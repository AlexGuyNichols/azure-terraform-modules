output "storage_account_id" {
  value       = azurerm_storage_account.main.id
  description = "Resource ID of the storage account. Pass to role-assignment, private-endpoint, and diagnostic resources in the calling module."
}

output "storage_account_name" {
  value       = azurerm_storage_account.main.name
  description = "Name of the storage account. Use in backend blocks and data source references that require the account name rather than the resource ID."
}

output "primary_blob_endpoint" {
  value       = azurerm_storage_account.main.primary_blob_endpoint
  description = "Primary blob service endpoint URL. Use as the endpoint in backend configuration or when constructing blob URIs in application config."
}

output "primary_access_key" {
  value       = azurerm_storage_account.main.primary_access_key
  sensitive   = true
  description = "Primary access key for the storage account. This is a full-control credential that lands in Terraform state; treat as a secret. Use azuread backend auth and set shared_access_key_enabled = false where possible."
}
