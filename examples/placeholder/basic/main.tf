# Placeholder example — deleted in Phase 2 when the key-vault module lands.
# Exercises CI matrix against a real module call.

module "placeholder" {
  source = "../../../modules/placeholder"

  location            = "uksouth"
  resource_group_name = "rg-placeholder"

  tags = {
    environment = "example"
    managed_by  = "terraform"
  }
}
