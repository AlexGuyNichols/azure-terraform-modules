# examples/container-app/secure/main.tf
# Full composition — THE showcase: system-assigned identity -> caller-side role assignment
# -> container app secret block reading the vault.
# Demonstrates the dependency pattern the module's principal_id output exists for.

provider "azurerm" {
  features {}
}

module "key_vault" {
  source = "../../../modules/key-vault"

  name                = "kv-ca-example"
  location            = "uksouth"
  resource_group_name = "rg-example"
}

# The principal_id reference below makes Terraform create the container app FIRST
# (the identity must exist before it can be granted anything) — this is the implicit
# ordering via the dependency graph. No explicit ordering attribute is needed or allowed
# here: adding one on the module call would create a dependency CYCLE (every resource
# inside the module would depend on the role assignment, which in turn depends on the
# module output) and terraform validate rejects the cycle with an error.
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
}

# BOOTSTRAP CAVEAT (Azure RBAC eventual consistency):
# Terraform orders app -> role assignment automatically via the principal_id reference.
# Because Azure resolves Key Vault secret references at app creation time and RBAC
# propagation is eventually consistent (can take up to ~10 minutes), the FIRST apply
# of a fresh composition may fail with 403 on the secret.
#
# Options to work around this on first deploy:
#   (a) Re-apply after the role assignment has propagated — Terraform is idempotent.
#   (b) Bootstrap with key_vault_secrets = {} on the first apply, then add the secrets
#       in a second apply once the role assignment is confirmed active.
#
# Never add ignore_changes on key_vault_secrets or secret_environment_variables to
# paper over this (MOD-08) — that would prevent Terraform from ever updating secrets.
module "container_app" {
  source = "../../../modules/container-app"

  name                         = "ca-example-secure"
  resource_group_name          = "rg-example"
  container_app_environment_id = var.container_app_environment_id
  image                        = "mcr.microsoft.com/k8se/quickstart:latest"

  # URI built from the module output — versionless reference, no literal vault URL (D-02)
  key_vault_secrets = {
    "db-password" = "${module.key_vault.key_vault_uri}secrets/db-password"
  }

  # Generic name — app-specific naming is the caller's concern (D-03)
  secret_environment_variables = {
    DB_PASSWORD = "db-password"
  }

  environment_variables = {
    APP_LOG_LEVEL = "info"
  }

  # Explicit opt-IN to external exposure — the module default renders no ingress at all (D-07)
  # HTTPS enforced: allow_insecure_connections = false
  ingress = {
    target_port                = 8080
    external_enabled           = true
    transport                  = "auto"
    allow_insecure_connections = false
  }

  # Identity-based ACR pull — replace server with your registry (D-08)
  # Remove this block when pulling public images (this example uses MCR, no registry auth needed)
  registries = [
    {
      server   = "acrexample.azurecr.io"
      identity = "System"
    }
  ]

  tags = {
    environment = "example"
    managed_by  = "terraform"
  }
}

output "container_app_principal_id" {
  value       = module.container_app.principal_id
  description = "Principal ID of the container app's system-assigned managed identity. Available for further caller-side grants."
}

output "container_app_id" {
  value       = module.container_app.container_app_id
  description = "Resource ID of the provisioned container app."
}
