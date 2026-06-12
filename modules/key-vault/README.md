# key-vault

Hardened, RBAC-only Azure Key Vault module with secure defaults.

## Design Notes

This module is extracted and generalised from a real Azure deployment that used access policies
and purge protection disabled. The conversion applies the following hardening decisions:

- **RBAC-only authorisation** — `rbac_authorization_enabled` is hardcoded `true` in the resource
  block (not a variable). Microsoft deprecated access policies in favour of RBAC; mixing both in a
  library module creates audit risk. The `enable_rbac_authorization` attribute (used in provider
  versions prior to v4.42) is a renamed alias — the current name is used throughout.
- **Purge protection on by default** — the source deployment had purge protection disabled for
  ease of teardown during development. This module defaults to `true` (safe for production). Set
  `purge_protection_enabled = false` BEFORE first deployment for non-prod vaults that need clean
  teardown; once a vault is deployed with purge protection enabled, the setting cannot be reversed.
- **Retention 90 days** — the source used 7. This module defaults to 90 (the Azure maximum and
  safest choice). Callers can reduce this to the Azure minimum of 7 for short-lived environments.
- **Public network access denied by default** — all traffic must flow via a private endpoint or
  approved network rules. Set `public_network_access_enabled = true` and configure
  `network_acls.ip_rules` to allow specific CIDR ranges (see examples/key-vault/secure).
- **Vault-only scope** — callers create `azurerm_key_vault_secret` resources directly against the
  `key_vault_id` output. Bundling secret creation inside the module would entangle credentials
  with infrastructure provisioning and complicate `ignore_changes` lifecycle management.

## Usage

```hcl
module "key_vault" {
  source = "git::https://github.com/AlexGuyNichols/azure-terraform-modules//modules/key-vault?ref=v0.1.0"

  name                = "kv-myapp-prod"
  location            = "uksouth"
  resource_group_name = "rg-myapp-prod"
}
```

Only `name`, `location`, and `resource_group_name` are required. All security defaults are
inherited automatically. For the optional surface (network_acls with ip_rules, variable-driven
role_assignments, explicit retention, and tags) see
[examples/key-vault/basic](../../examples/key-vault/basic) and
[examples/key-vault/secure](../../examples/key-vault/secure).

## Provider Version Note

The declared constraint is `>= 4.42, < 5.0`. The `rbac_authorization_enabled` attribute was
introduced in azurerm v4.42 (provider issue #31406), so the declared floor matches the real
requirement — consumers whose root constraints resolve azurerm to v4.0–v4.41 get a clear
version-resolution error at `terraform init` instead of an unknown-attribute error at plan
time. In practice the current stable release is v4.76+, so this floor is never a practical
constraint.

## Purge Protection Warning

Once purge protection is enabled on a deployed vault, it **cannot be disabled**. This is an
Azure platform constraint — the API returns a 400 error for any attempt to flip
`purge_protection_enabled` from `true` to `false` on an existing vault.

If you need clean teardown in a non-production environment, set
`purge_protection_enabled = false` **before** the first `terraform apply`. Changing this after
first deployment requires deleting and recreating the vault.

## RBAC Propagation Note

If you are creating `azurerm_key_vault_secret` resources in the same Terraform configuration as
`role_assignments` input entries, add a `depends_on` from the secret resource to the key vault
module (or split secret creation into a separate apply). Azure RBAC is eventually consistent —
propagation can take up to approximately 30 seconds, and a secret-creation call that runs before
the role assignment is fully propagated will receive a 403 Forbidden error even though the
assignment technically exists.

```hcl
resource "azurerm_key_vault_secret" "app_db_password" {
  name         = "app-db-password"
  value        = var.db_password
  key_vault_id = module.key_vault.key_vault_id

  depends_on = [module.key_vault]
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.42, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.42, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_key_vault.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_role_assignment.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the Key Vault will be deployed. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the Key Vault. Must be globally unique within Azure. | `string` | n/a | yes |
| <a name="input_network_acls"></a> [network\_acls](#input\_network\_acls) | Network access control list configuration. bypass controls which Azure services can bypass the firewall; default is 'AzureServices'. default\_action is hardcoded to 'Deny' in the resource; validation rejects any other value. Populate ip\_rules or virtual\_network\_subnet\_ids to allow specific sources (requires public\_network\_access\_enabled = true). | <pre>object({<br/>    bypass                     = optional(string, "AzureServices")<br/>    default_action             = optional(string, "Deny")<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Allow public internet access to the Key Vault. Defaults to false; all traffic must flow via private endpoint or approved network rules. Set to true and configure network\_acls.ip\_rules to allow specific CIDRs. | `bool` | `false` | no |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Enable purge protection to prevent permanent deletion of the vault and its objects. WARNING: once enabled on a deployed vault, this cannot be disabled. Set to false in non-prod environments that require clean teardown. | `bool` | `true` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group in which to deploy the Key Vault. | `string` | n/a | yes |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | Map of RBAC role assignments scoped to this Key Vault. Key is an arbitrary label; value is the role name and principal ID. Common roles: 'Key Vault Secrets User' (read), 'Key Vault Secrets Officer' (read/write), 'Key Vault Administrator' (full control). | <pre>map(object({<br/>    role_definition_name = string<br/>    principal_id         = string<br/>  }))</pre> | `{}` | no |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | SKU tier for the Key Vault. 'standard' uses software-protected keys; 'premium' adds HSM-backed keys. | `string` | `"standard"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Number of days that deleted Key Vault objects are retained and recoverable. Azure enforces a range of 7 to 90. | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to apply to all resources managed by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | Resource ID of the Key Vault. Pass to secret, key, and role-assignment resources in the calling module. |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | URI of the Key Vault (e.g., https://kv-myapp.vault.azure.net/). Use in application configuration to reference the vault endpoint. |
<!-- END_TF_DOCS -->
