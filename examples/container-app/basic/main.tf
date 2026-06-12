# examples/container-app/basic/main.tf
# Minimal required inputs — all hardened defaults inherited: system-assigned identity on,
# no ingress rendered, scale-to-zero Consumption defaults.
# The log analytics workspace and container app environment are created inline ONLY so the
# example is self-contained for static validation; in production the environment is
# caller-owned shared infrastructure — pass its id in.

provider "azurerm" {
  features {}
}

resource "azurerm_log_analytics_workspace" "example" {
  name                = "law-ca-example-basic"
  location            = "uksouth"
  resource_group_name = "rg-example"
  sku                 = "PerGB2018"
  retention_in_days   = 30
}

resource "azurerm_container_app_environment" "example" {
  name                       = "cae-example-basic"
  location                   = "uksouth"
  resource_group_name        = "rg-example"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
}

module "container_app" {
  source = "../../../modules/container-app"

  name                         = "ca-example-basic"
  resource_group_name          = "rg-example"
  container_app_environment_id = azurerm_container_app_environment.example.id
  image                        = "mcr.microsoft.com/k8se/quickstart:latest"
}
