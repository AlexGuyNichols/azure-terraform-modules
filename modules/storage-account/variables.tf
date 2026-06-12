variable "name" {
  type        = string
  description = "Name of the storage account. Must be globally unique within Azure; lowercase alphanumeric, 3-24 characters."
  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.name))
    error_message = "name must be 3-24 lowercase alphanumeric characters (Azure storage account naming rule)."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the storage account will be deployed."
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which to deploy the storage account."
}

# Premium is deliberately excluded from the enum: the module does not set account_kind,
# so the azurerm default (StorageV2) applies — and Premium + StorageV2 creates a premium
# page-blob-only account. That account type cannot host block blobs (the module's stated
# remote-state mission stores tfstate as block blobs) and rejects blob versioning (module
# default blob_versioning_enabled = true) at apply time. There is no module configuration
# in which Premium works for the documented purpose; re-admit it only if account_kind is
# ever exposed as an input.
variable "account_tier" {
  type        = string
  description = "Performance tier for the storage account. Only 'Standard' is supported: the module's implicit account_kind (StorageV2) would make 'Premium' a page-blob-only account, which cannot host block blobs (remote state) and rejects blob versioning at apply time."
  default     = "Standard"
  nullable    = false
  validation {
    condition     = var.account_tier == "Standard"
    error_message = "Only 'Standard' is supported: the module's default account_kind (StorageV2) makes Premium a page-blob-only account, which cannot host block blobs (remote state) and rejects blob versioning."
  }
}

variable "account_replication_type" {
  type        = string
  description = "Data replication strategy for the storage account. Defaults to LRS (cost-aware, single-region) suitable for remote state. Callers can opt up to GRS, RAGRS, ZRS, GZRS, or RAGZRS for higher durability or regional redundancy."
  default     = "LRS"
  nullable    = false
  validation {
    condition     = contains(["LRS", "GRS", "RAGRS", "ZRS", "GZRS", "RAGZRS"], var.account_replication_type)
    error_message = "account_replication_type must be one of: LRS, GRS, RAGRS, ZRS, GZRS, RAGZRS."
  }
}

variable "shared_access_key_enabled" {
  type        = bool
  description = "Allow Shared Key authorisation for the storage account. Defaults to true because the remote-state consumption path authenticates with the access key (primary_access_key output). Set to false when using azuread backend auth to enforce Entra ID-only access; the primary_access_key output will still be present in state but will not function for auth."
  default     = true
  nullable    = false
}

variable "blob_versioning_enabled" {
  type        = bool
  description = "Enable blob versioning to retain previous versions of blobs on overwrite or delete. Defaults to true (SEC-02 — versioning provides point-in-time recovery for remote state and prevents data loss on accidental overwrites)."
  default     = true
  nullable    = false
}

variable "blob_delete_retention_days" {
  type        = number
  description = "Number of days to retain deleted blobs before permanent removal. Range 1-365; defaults to 7 days as a safe baseline for remote-state recovery."
  default     = 7
  nullable    = false
  validation {
    condition     = var.blob_delete_retention_days >= 1 && var.blob_delete_retention_days <= 365
    error_message = "blob_delete_retention_days must be between 1 and 365."
  }
}

variable "container_delete_retention_days" {
  type        = number
  description = "Number of days to retain deleted containers before permanent removal. Range 1-365; defaults to 7 days as a safe baseline for remote-state recovery."
  default     = 7
  nullable    = false
  validation {
    condition     = var.container_delete_retention_days >= 1 && var.container_delete_retention_days <= 365
    error_message = "container_delete_retention_days must be between 1 and 365."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  description = "Allow public internet access to the storage account. Defaults to true — DELIBERATE divergence from key-vault's default-deny posture: remote-state accounts must be reachable by CI runners and developer workstations. See the README for the reasoning. Callers with private network access can set this to false and configure network_rules."
  default     = true
  nullable    = false
}

# network_rules defaults to null by design (D-07): when null no network_rules block is rendered,
# giving drop-in callers an unrestricted firewall posture. Callers requiring network-level isolation
# supply the object; default_action defaults to "Deny" inside the object when the block is present.
# nullable is intentionally omitted (null is the legitimate sentinel for "no block").
variable "network_rules" {
  type = object({
    default_action             = optional(string, "Deny")
    bypass                     = optional(set(string), ["AzureServices"])
    ip_rules                   = optional(list(string), [])
    virtual_network_subnet_ids = optional(list(string), [])
  })
  description = "Network rules configuration. When null (default) no network_rules block is rendered; the account's public_network_access_enabled setting governs reachability. When supplied, default_action defaults to 'Deny' (deny-by-default firewall); bypass must contain only valid elements (AzureServices, Logging, Metrics, None); ip_rules and virtual_network_subnet_ids allow specific sources."
  default     = null
  validation {
    condition     = var.network_rules == null ? true : contains(["Allow", "Deny"], var.network_rules.default_action)
    error_message = "network_rules.default_action must be 'Allow' or 'Deny'."
  }
  validation {
    condition     = var.network_rules == null ? true : alltrue([for b in var.network_rules.bypass : contains(["AzureServices", "Logging", "Metrics", "None"], b)])
    error_message = "network_rules.bypass elements must be one of: AzureServices, Logging, Metrics, None."
  }
}

variable "containers" {
  type        = set(string)
  description = "Set of container names to create under the storage account. Each container is created with container_access_type hardcoded to 'private' (D-03 — no anonymous blob access). Intended for the remote-state tfstate container use case."
  default     = []
  nullable    = false
}

variable "tags" {
  type        = map(string)
  description = "Map of tags to apply to all resources managed by this module."
  default     = {}
  nullable    = false
}
