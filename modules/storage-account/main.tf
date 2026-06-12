# lifecycle blocks cannot be variable-driven, so hardcoding prevent_destroy = true would
# permanently block `terraform destroy` for every consumer of this reusable module. Storage
# data is already guarded by versioning + delete retention defaults; consumers who want a
# state-level deletion guard add prevent_destroy in their own root config.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_account" "main" {
  name                     = var.name
  location                 = var.location
  resource_group_name      = var.resource_group_name
  account_tier             = var.account_tier
  account_replication_type = var.account_replication_type

  # Secure default: plaintext HTTP rejected at the platform edge; all traffic must use HTTPS.
  https_traffic_only_enabled = true

  # Secure default: TLS 1.0 and 1.1 are deprecated; enforce TLS 1.2 as the minimum.
  min_tls_version = "TLS1_2"

  # Secure default: anonymous blob access disabled regardless of individual container settings.
  # This prevents any container from being promoted to anonymous read access by the caller.
  allow_nested_items_to_be_public = false

  # Secure default: shared-key auth exposed as a posture knob (default true for access-key
  # remote-state auth); set false when using azuread backend auth to enforce Entra ID-only access.
  shared_access_key_enabled = var.shared_access_key_enabled

  # Deliberate divergence from key-vault default-deny: remote-state accounts must be
  # reachable by CI runners and developer workstations. README documents this choice.
  public_network_access_enabled = var.public_network_access_enabled

  blob_properties {
    # Secure default: blob versioning retains previous versions on overwrite or delete,
    # enabling point-in-time recovery for remote state (SEC-02/D-06).
    versioning_enabled = var.blob_versioning_enabled

    # Secure default: soft-delete retention for blobs prevents data loss on accidental
    # deletion; 7-day default balances recovery window with storage cost (D-08).
    delete_retention_policy {
      days = var.blob_delete_retention_days
    }

    # Secure default: soft-delete retention for containers prevents data loss on accidental
    # container deletion; 7-day default mirrors blob retention baseline (D-08).
    container_delete_retention_policy {
      days = var.container_delete_retention_days
    }
  }

  dynamic "network_rules" {
    for_each = var.network_rules == null ? [] : [var.network_rules]
    content {
      default_action             = network_rules.value.default_action
      bypass                     = network_rules.value.bypass
      ip_rules                   = network_rules.value.ip_rules
      virtual_network_subnet_ids = network_rules.value.virtual_network_subnet_ids
    }
  }

  tags = var.tags
}

# lifecycle blocks cannot be variable-driven, so hardcoding prevent_destroy = true would
# permanently block `terraform destroy` for every consumer of this reusable module. Container
# data is already guarded by blob versioning + delete retention defaults; consumers who want a
# state-level deletion guard add prevent_destroy in their own root config.
# tflint-ignore: azurerm_resources_missing_prevent_destroy
resource "azurerm_storage_container" "main" {
  for_each = var.containers

  name               = each.value
  storage_account_id = azurerm_storage_account.main.id

  # Secure default: container access hardcoded to private; no anonymous blob access
  # permitted regardless of caller configuration (D-03/SEC-02).
  container_access_type = "private"
}
