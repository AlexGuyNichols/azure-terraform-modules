terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # WR-04: floor is 4.9, not 4.0 — storage_account_id on azurerm_storage_container
      # (the 4.x argument replacing deprecated storage_account_name) is available from v4.9.
      # Declaring the true floor turns a plan-time unknown-attribute error into a clear
      # init-time version-resolution error when a consumer runs an older provider.
      # Best-evidence: attribute documented in azurerm v4.x release notes; CI validates
      # against ~> 4.76 in examples which confirms attribute existence at current stable.
      version = ">= 4.9, < 5.0"
    }
  }
}
