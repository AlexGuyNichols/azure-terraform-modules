terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # azurerm_container_app: key_vault_secret_id + identity = "System" on the secret
      # block are available throughout 4.x (attribute confirmed in provider source, main
      # branch). Bug #29743/#31376 (env/secret ordering perpetual diffs) is tracked in PR
      # #32292 — not yet merged as of 2026-06-12. Floor stays at >= 4.0; no fix-version
      # floor needed. The module iterates one merged, lexicographically-ordered env map instead of waiting
      # for the fix to ship.
      version = ">= 4.0, < 5.0"
    }
  }
}
