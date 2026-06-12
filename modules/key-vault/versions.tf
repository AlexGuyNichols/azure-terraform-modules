terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source = "hashicorp/azurerm"
      # WR-04: floor is 4.42, not 4.0 — rbac_authorization_enabled was introduced in
      # azurerm v4.42. Declaring the true floor turns a plan-time unknown-attribute
      # error into a clear init-time version-resolution error.
      version = ">= 4.42, < 5.0"
    }
  }
}
