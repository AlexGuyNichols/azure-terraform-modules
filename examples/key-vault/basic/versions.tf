terraform {
  required_version = ">= 1.5"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.76" # examples tighten; modules stay wide (>= 4.42, < 5.0)
    }
  }
}
