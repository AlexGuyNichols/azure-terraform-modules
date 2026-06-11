variable "name" {
  type        = string
  description = "Name of the Key Vault. Must be globally unique within Azure."
}

variable "location" {
  type        = string
  description = "Azure region where the Key Vault will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which to deploy the Key Vault."
}

variable "sku_name" {
  type        = string
  description = "SKU tier for the Key Vault. 'standard' uses software-protected keys; 'premium' adds HSM-backed keys."
  default     = "standard"
  validation {
    condition     = contains(["standard", "premium"], var.sku_name)
    error_message = "sku_name must be 'standard' or 'premium'."
  }
}

variable "soft_delete_retention_days" {
  type        = number
  description = "Number of days that deleted Key Vault objects are retained and recoverable. Azure enforces a range of 7 to 90."
  default     = 90
  validation {
    condition     = var.soft_delete_retention_days >= 7 && var.soft_delete_retention_days <= 90
    error_message = "soft_delete_retention_days must be between 7 and 90 (Azure platform limit)."
  }
}

variable "purge_protection_enabled" {
  type        = bool
  description = "Enable purge protection to prevent permanent deletion of the vault and its objects. WARNING: once enabled on a deployed vault, this cannot be disabled. Set to false in non-prod environments that require clean teardown."
  default     = true
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Allow public internet access to the Key Vault. Defaults to false; all traffic must flow via private endpoint or approved network rules. Set to true and configure network_acls.ip_rules to allow specific CIDRs."
  default     = false
}

variable "network_acls" {
  type = object({
    bypass                     = optional(string, "AzureServices")
    default_action             = optional(string, "Deny")
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  description = "Network access control list configuration. bypass controls which Azure services can bypass the firewall; default is 'AzureServices'. default_action is accepted for type compatibility but the module hardcodes 'Deny' in the resource. Populate ip_rules or virtual_network_subnet_ids to allow specific sources (requires public_network_access_enabled = true)."
  default     = {}
  validation {
    condition     = contains(["AzureServices", "None"], var.network_acls.bypass)
    error_message = "network_acls.bypass must be 'AzureServices' (allow trusted Azure services) or 'None' (block everything)."
  }
  validation {
    condition     = contains(["Allow", "Deny"], var.network_acls.default_action)
    error_message = "network_acls.default_action must be 'Allow' or 'Deny'."
  }
}

variable "role_assignments" {
  type = map(object({
    role_definition_name = string
    principal_id         = string
  }))
  description = "Map of RBAC role assignments scoped to this Key Vault. Key is an arbitrary label; value is the role name and principal ID. Common roles: 'Key Vault Secrets User' (read), 'Key Vault Secrets Officer' (read/write), 'Key Vault Administrator' (full control)."
  default     = {}
}

variable "tags" {
  type        = map(string)
  description = "Map of tags to apply to all resources managed by this module."
  default     = {}
}
