# Workaround for azurerm issue #29743/#31376 (env block ordering perpetual diffs).
# PR #32292 is open but not yet merged as of 2026-06-12. Plain and secret-backed env
# vars are merged into ONE map so a single dynamic env block renders the COMBINED set
# in lexicographic key order (Terraform map iteration), matching Azure's alphabetical
# read-back of the whole env list. Two separate dynamic blocks would concatenate in
# source order — plain entries then secret entries — which is only globally
# alphabetical by luck. Key collisions between the two maps would be silently won by
# the secret map under merge(); a lifecycle precondition rejects them at plan time.
locals {
  merged_environment_variables = merge(
    { for k, v in var.environment_variables : k => { value = v, secret_name = null } },
    { for k, v in var.secret_environment_variables : k => { value = null, secret_name = v } }
  )
}

resource "azurerm_container_app" "main" {
  name                         = var.name
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  revision_mode                = var.revision_mode

  # Secure default: system-assigned managed identity is hardcoded on — enables
  # credential-less Key Vault secret access and ACR image pull; not configurable,
  # like RBAC-only in the key-vault module. principal_id is exported so callers
  # can wire least-privilege role assignments without receiving any credential.
  identity {
    type = "SystemAssigned"
  }

  # Workaround for azurerm issue #29743/#31376 (secret block ordering sensitivity).
  # PR #32292 is open but not yet merged as of 2026-06-12. Map iteration is
  # lexicographic in Terraform, which matches Azure's alphabetical read-back order.
  dynamic "secret" {
    for_each = var.key_vault_secrets
    content {
      name = secret.key
      # Secure default: Key Vault access via the app's managed identity — no stored
      # credentials; identity = "System" selects the resource's system-assigned
      # managed identity (distinct from the top-level identity block's "SystemAssigned").
      identity            = "System"
      key_vault_secret_id = secret.value
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = var.name
      image  = var.image
      cpu    = var.cpu
      memory = var.memory

      # Workaround for azurerm issue #29743/#31376 (env block ordering perpetual diffs).
      # PR #32292 is open but not yet merged as of 2026-06-12. One merged map (see
      # locals) means one dynamic block whose lexicographic map iteration yields a
      # single globally alphabetical env list across BOTH plain and secret-backed
      # entries — matching Azure's read-back order and suppressing perpetual plan diffs.
      dynamic "env" {
        for_each = local.merged_environment_variables
        content {
          name        = env.key
          value       = env.value.value
          secret_name = env.value.secret_name
        }
      }
    }
  }

  # Secure default: ingress is null by default — no ingress block rendered means the app
  # has no inbound network exposure. Callers opt in explicitly by supplying the ingress
  # object; allow_insecure_connections and external_enabled both default to false for a
  # hardened posture when ingress IS configured.
  dynamic "ingress" {
    for_each = var.ingress == null ? [] : [var.ingress]
    content {
      target_port                = ingress.value.target_port
      external_enabled           = ingress.value.external_enabled
      transport                  = ingress.value.transport
      allow_insecure_connections = ingress.value.allow_insecure_connections

      traffic_weight {
        latest_revision = true
        percentage      = 100
      }
    }
  }

  dynamic "registry" {
    for_each = var.registries
    content {
      server   = registry.value.server
      identity = registry.value.identity
    }
  }

  tags = var.tags

  lifecycle {
    precondition {
      # Cross-variable cpu/memory pairing for the Consumption plan (capped at 2.0/4.0Gi).
      # This is a lifecycle precondition rather than a variable validation block because
      # cross-variable references in validation{} require Terraform >= 1.9, which is above
      # the >= 1.5 library floor. precondition{} works from Terraform 1.2.
      # GOTCHA: tostring(1.0) renders "1" and tostring(2.0) renders "2" in Terraform —
      # whole-number lookup keys must be written WITHOUT a decimal point to match.
      # Valid pairs: 0.25/0.5Gi, 0.5/1.0Gi, 0.75/1.5Gi, 1/2.0Gi,
      #              1.25/2.5Gi, 1.5/3.0Gi, 1.75/3.5Gi, 2/4.0Gi
      condition = lookup(
        {
          "0.25" = "0.5Gi"
          "0.5"  = "1.0Gi"
          "0.75" = "1.5Gi"
          "1"    = "2.0Gi"
          "1.25" = "2.5Gi"
          "1.5"  = "3.0Gi"
          "1.75" = "3.5Gi"
          "2"    = "4.0Gi"
        },
        tostring(var.cpu),
        ""
      ) == var.memory
      error_message = "cpu and memory must form a valid Consumption-plan pair. Valid pairs: 0.25/0.5Gi, 0.5/1.0Gi, 0.75/1.5Gi, 1/2.0Gi, 1.25/2.5Gi, 1.5/3.0Gi, 1.75/3.5Gi, 2/4.0Gi."
    }

    precondition {
      condition     = var.max_replicas >= var.min_replicas
      error_message = "max_replicas must be >= min_replicas."
    }

    precondition {
      condition     = alltrue([for s in values(var.secret_environment_variables) : contains(keys(var.key_vault_secrets), s)])
      error_message = "Every value in secret_environment_variables must match a key in key_vault_secrets. Check that each secret-backed env var references a declared secret name."
    }

    precondition {
      # Both maps merge into one env list (see locals); merge() would silently let the
      # secret-backed entry win on a key collision, so reject duplicates at plan time.
      condition     = length(setintersection(keys(var.environment_variables), keys(var.secret_environment_variables))) == 0
      error_message = "environment_variables and secret_environment_variables must not declare the same env var name — each env var must be either plain or secret-backed, not both."
    }
  }
}
