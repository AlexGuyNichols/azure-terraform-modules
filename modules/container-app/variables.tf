variable "name" {
  type        = string
  description = "Name of the container app. Must be 2-32 characters: lowercase letters, numbers, and hyphens (no consecutive hyphens); must start with a letter and end with a letter or number."
  validation {
    # RE2 (Terraform's regex engine) has no lookahead, so the no-consecutive-hyphens
    # rule is expressed structurally: alphanumeric runs separated by single hyphens.
    # Length bounds are checked separately because the group structure cannot carry
    # a {0,30} quantifier across runs.
    condition     = can(regex("^[a-z][a-z0-9]*(-[a-z0-9]+)*$", var.name)) && length(var.name) >= 2 && length(var.name) <= 32
    error_message = "name must be 2-32 characters: lowercase letters, numbers, and hyphens (no consecutive hyphens); must start with a letter and end with a letter or number (Azure container app naming rule)."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the resource group in which the container app will be deployed."
}

variable "container_app_environment_id" {
  type        = string
  description = "Resource ID of the Container Apps Environment. The environment is caller-owned shared infrastructure; the module does not provision it (composability over convenience)."
}

variable "image" {
  type        = string
  description = "Container image to deploy, including tag (e.g. 'mcr.microsoft.com/k8se/quickstart:latest'). Required — the module enforces a consumer-specified workload image rather than a default (SEC-03)."
}

variable "revision_mode" {
  type        = string
  description = "Revision mode for the container app. 'Single' (default) keeps one active revision. 'Multiple' keeps prior revisions available, but this module always routes 100% of traffic to the latest revision — traffic splitting across revisions is managed outside this module."
  default     = "Single"
  nullable    = false
  validation {
    condition     = contains(["Single", "Multiple"], var.revision_mode)
    error_message = "revision_mode must be one of: Single, Multiple."
  }
}

# The cpu/memory PAIRING is enforced by a lifecycle precondition in main.tf because
# cross-variable validation inside validation{} blocks requires Terraform >= 1.9, which
# is above the >= 1.5 library floor. precondition{} works from Terraform 1.2.
variable "cpu" {
  type        = number
  description = "vCPU allocation for the container. Valid Consumption-plan values: 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2. Must pair with memory (see pairing rule enforced by lifecycle precondition in main.tf). Defaults to 0.25 (cost-aware minimum)."
  default     = 0.25
  nullable    = false
  validation {
    condition     = contains([0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2], var.cpu)
    error_message = "cpu must be one of: 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2 (Consumption-plan vCPU steps)."
  }
}

variable "memory" {
  type        = string
  description = "Memory allocation for the container. Valid Consumption-plan values: 0.5Gi, 1.0Gi, 1.5Gi, 2.0Gi, 2.5Gi, 3.0Gi, 3.5Gi, 4.0Gi. Must pair with cpu (see pairing rule enforced by lifecycle precondition in main.tf). Defaults to 0.5Gi (cost-aware minimum)."
  default     = "0.5Gi"
  nullable    = false
  validation {
    condition     = contains(["0.5Gi", "1.0Gi", "1.5Gi", "2.0Gi", "2.5Gi", "3.0Gi", "3.5Gi", "4.0Gi"], var.memory)
    error_message = "memory must be one of: 0.5Gi, 1.0Gi, 1.5Gi, 2.0Gi, 2.5Gi, 3.0Gi, 3.5Gi, 4.0Gi (Consumption-plan memory steps)."
  }
}

variable "min_replicas" {
  type        = number
  description = "Minimum number of container app replicas. Defaults to 0 (scale-to-zero when idle, cost-aware). Valid range: 0-300."
  default     = 0
  nullable    = false
  validation {
    condition     = var.min_replicas >= 0 && var.min_replicas <= 300
    error_message = "min_replicas must be between 0 and 300."
  }
}

variable "max_replicas" {
  type        = number
  description = "Maximum number of container app replicas. Defaults to 1 (cost-aware; prevents unexpected scale-out). Valid range: 1-300. Must be >= min_replicas (enforced by lifecycle precondition in main.tf)."
  default     = 1
  nullable    = false
  validation {
    condition     = var.max_replicas >= 1 && var.max_replicas <= 300
    error_message = "max_replicas must be between 1 and 300."
  }
}

variable "environment_variables" {
  type        = map(string)
  description = "Plain environment variables for the container: map of name to literal value. Generic map — naming conventions for application-specific env vars are the caller's concern. For secret-backed env vars, use secret_environment_variables instead; the same name must not appear in both maps (enforced by lifecycle precondition in main.tf)."
  default     = {}
  nullable    = false
}

variable "secret_environment_variables" {
  type        = map(string)
  description = "Secret-backed environment variables: map of env var name to secret name. Each value must match a key in key_vault_secrets — the secret name references an in-scope secret block (enforced by lifecycle precondition in main.tf). The same env var name must not also appear in environment_variables (enforced by lifecycle precondition in main.tf). The actual secret value is resolved at runtime by the container app runtime via managed identity."
  default     = {}
  nullable    = false
}

variable "key_vault_secrets" {
  type        = map(string)
  description = "Key Vault-backed secrets: map of app-visible secret name to Key Vault secret URI (versionless or versioned). Each secret is accessed using the app's system-assigned managed identity. The caller must grant that identity the 'Key Vault Secrets User' role assignment on the vault. No plaintext-value secret variable exists in this module — credentials never appear in caller config or Terraform state."
  default     = {}
  nullable    = false
}

# ingress defaults to null by design (D-07): when null no ingress block is rendered,
# meaning the app has no inbound network exposure. This is the secure default posture.
# nullable is intentionally omitted (null is the legitimate sentinel for "no ingress block").
variable "ingress" {
  type = object({
    target_port                = number
    external_enabled           = optional(bool, false)
    transport                  = optional(string, "auto")
    allow_insecure_connections = optional(bool, false)
  })
  description = "Ingress configuration. When null (default) no ingress block is rendered and the app has no inbound network exposure. When supplied, external_enabled defaults to false (internal-only), transport defaults to 'auto', and allow_insecure_connections defaults to false (HTTPS-only)."
  default     = null
  validation {
    condition     = var.ingress == null ? true : contains(["auto", "http", "http2", "tcp"], var.ingress.transport)
    error_message = "ingress.transport must be one of: auto, http, http2, tcp."
  }
  validation {
    condition     = var.ingress == null ? true : (var.ingress.target_port >= 1 && var.ingress.target_port <= 65535)
    error_message = "ingress.target_port must be between 1 and 65535."
  }
}

variable "registries" {
  type = list(object({
    server   = string
    identity = optional(string, "System")
  }))
  description = "Container registry configurations for image pull. Each entry specifies a registry server; identity defaults to 'System' for credential-less pull using the app's system-assigned managed identity (no stored credentials needed)."
  default     = []
  nullable    = false
}

variable "tags" {
  type        = map(string)
  description = "Map of tags to apply to all resources managed by this module."
  default     = {}
  nullable    = false
}
