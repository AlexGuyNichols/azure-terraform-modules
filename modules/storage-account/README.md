# storage-account

Hardened, remote-state-grade Azure Storage Account module with secure defaults.

## Design Notes

This module is fresh-authored (not extracted from an existing deployment), built specifically
to host Terraform remote state and general-purpose blob workloads. It applies the following
hardening decisions:

- **HTTPS-only, TLS 1.2, no anonymous blob access** — `https_traffic_only_enabled = true`,
  `min_tls_version = "TLS1_2"`, and `allow_nested_items_to_be_public = false` are all
  hardcoded in the resource block (not variables). These three settings form the module's
  non-negotiable security floor; callers cannot weaken them.
- **Blob versioning on by default** — `blob_versioning_enabled` defaults to `true`, with blob
  delete retention defaulting to 7 days and container delete retention defaulting to 7 days.
  Both retention periods are bounded by validation to the range 1–365. This gives remote-state
  consumers point-in-time recovery for accidental overwrites or deletions out of the box.
- **Containers always private** — `container_access_type` is hardcoded to `"private"` on every
  container created by this module. The `containers` input only names the containers; callers
  cannot configure anonymous read access through this module.
- **DELIBERATE DIVERGENCE from key-vault** — `public_network_access_enabled` defaults to `true`
  here, the **opposite** of key-vault's default-deny posture. This is intentional, not an
  oversight. A remote-state account must be reachable by CI runners and developer workstations
  at `terraform plan` and `terraform apply` time; locking the account down by default would
  break the primary use case. Network-level isolation is the caller's choice via the optional
  `network_rules` object (when supplied, `default_action` defaults to `"Deny"`). The D-05 trio
  above (HTTPS/TLS/no-anonymous-blob) provides the hardened floor regardless of firewall posture.
- **LRS by default** — cost-aware default suitable for remote state in a single region. Callers
  opt up to ZRS, GRS, GZRS, or their read-access variants via the validated `account_replication_type`
  enum.
- **Shared access keys enabled by default** — the `azurerm` backend's access-key authentication
  path requires `shared_access_key_enabled = true`. The module exposes `primary_access_key` as a
  sensitive output for this use case. Set `shared_access_key_enabled = false` when using `azuread`
  backend auth to enforce Entra ID-only access.

## Usage

```hcl
module "storage_account" {
  source = "git::https://github.com/AlexGuyNichols/azure-terraform-modules//modules/storage-account?ref=v0.1.0"

  name                = "stmyappprodstate"
  location            = "uksouth"
  resource_group_name = "rg-myapp-prod"
}
```

Only `name`, `location`, and `resource_group_name` are required. All security defaults are
inherited automatically.

The typical remote-state consumption story pairs this module with an `azurerm` backend block:

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "rg-myapp-prod"
    storage_account_name = "stmyappprodstate"
    container_name       = "tfstate"
    key                  = "prod.terraform.tfstate"
  }
}
```

For the optional surface (network_rules with firewall rules, explicit containers, extended
retention periods, ZRS replication, and tags) see
[examples/storage-account/basic](../../examples/storage-account/basic) and
[examples/storage-account/secure](../../examples/storage-account/secure).

## Provider Version Note

The declared constraint is `>= 4.9, < 5.0`. The `storage_account_id` argument on
`azurerm_storage_container` — the 4.x replacement for the deprecated `storage_account_name`
argument — is available from azurerm v4.9. Declaring the true floor turns a plan-time
unknown-attribute error into a clear init-time version-resolution error for consumers running
an older provider. In practice the current stable release is well above this floor (v4.76+),
so this constraint is never a practical limitation.

## Data Protection Note

Blob versioning combined with delete retention protects against the two most common remote-state
accidents: accidental overwrite of the state blob (versioning retains the previous version
indefinitely) and accidental deletion (soft-delete keeps the blob recoverable for the retention
window). The defaults (7-day retention) are a safe baseline; production state stores may want
to extend both `blob_delete_retention_days` and `container_delete_retention_days` to 30 or
more days for a wider recovery window.

## Access Key Note

`primary_access_key` is output with `sensitive = true`. Even with `sensitive = true`, the key
value lands in the consumer's Terraform state file — treat the state file as a secret. Where
the workflow allows, prefer `azuread` backend auth (`use_azuread_auth = true` in the backend
block) and set `shared_access_key_enabled = false` to enforce Entra ID-only access and prevent
Shared Key authentication entirely.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.9, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.9, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_storage_account.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Data replication strategy for the storage account. Defaults to LRS (cost-aware, single-region) suitable for remote state. Callers can opt up to GRS, RAGRS, ZRS, GZRS, or RAGZRS for higher durability or regional redundancy. | `string` | `"LRS"` | no |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | Performance tier for the storage account. 'Standard' covers all common workloads including remote state; 'Premium' provides low-latency SSD storage for high-transaction scenarios. | `string` | `"Standard"` | no |
| <a name="input_blob_delete_retention_days"></a> [blob\_delete\_retention\_days](#input\_blob\_delete\_retention\_days) | Number of days to retain deleted blobs before permanent removal. Range 1-365; defaults to 7 days as a safe baseline for remote-state recovery. | `number` | `7` | no |
| <a name="input_blob_versioning_enabled"></a> [blob\_versioning\_enabled](#input\_blob\_versioning\_enabled) | Enable blob versioning to retain previous versions of blobs on overwrite or delete. Defaults to true (SEC-02 — versioning provides point-in-time recovery for remote state and prevents data loss on accidental overwrites). | `bool` | `true` | no |
| <a name="input_container_delete_retention_days"></a> [container\_delete\_retention\_days](#input\_container\_delete\_retention\_days) | Number of days to retain deleted containers before permanent removal. Range 1-365; defaults to 7 days as a safe baseline for remote-state recovery. | `number` | `7` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | Set of container names to create under the storage account. Each container is created with container\_access\_type hardcoded to 'private' (D-03 — no anonymous blob access). Intended for the remote-state tfstate container use case. | `set(string)` | `[]` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the storage account will be deployed. | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Name of the storage account. Must be globally unique within Azure; lowercase alphanumeric, 3-24 characters. | `string` | n/a | yes |
| <a name="input_network_rules"></a> [network\_rules](#input\_network\_rules) | Network rules configuration. When null (default) no network\_rules block is rendered; the account's public\_network\_access\_enabled setting governs reachability. When supplied, default\_action defaults to 'Deny' (deny-by-default firewall); bypass must contain only valid elements (AzureServices, Logging, Metrics, None); ip\_rules and virtual\_network\_subnet\_ids allow specific sources. | <pre>object({<br/>    default_action             = optional(string, "Deny")<br/>    bypass                     = optional(set(string), ["AzureServices"])<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Allow public internet access to the storage account. Defaults to true — DELIBERATE divergence from key-vault's default-deny posture: remote-state accounts must be reachable by CI runners and developer workstations. See the README for the reasoning. Callers with private network access can set this to false and configure network\_rules. | `bool` | `true` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group in which to deploy the storage account. | `string` | n/a | yes |
| <a name="input_shared_access_key_enabled"></a> [shared\_access\_key\_enabled](#input\_shared\_access\_key\_enabled) | Allow Shared Key authorisation for the storage account. Defaults to true because the remote-state consumption path authenticates with the access key (primary\_access\_key output). Set to false when using azuread backend auth to enforce Entra ID-only access; the primary\_access\_key output will still be present in state but will not function for auth. | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to apply to all resources managed by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_primary_access_key"></a> [primary\_access\_key](#output\_primary\_access\_key) | Primary access key for the storage account. This is a full-control credential that lands in Terraform state; treat as a secret. Use azuread backend auth and set shared\_access\_key\_enabled = false where possible. |
| <a name="output_primary_blob_endpoint"></a> [primary\_blob\_endpoint](#output\_primary\_blob\_endpoint) | Primary blob service endpoint URL. Use as the endpoint in backend configuration or when constructing blob URIs in application config. |
| <a name="output_storage_account_id"></a> [storage\_account\_id](#output\_storage\_account\_id) | Resource ID of the storage account. Pass to role-assignment, private-endpoint, and diagnostic resources in the calling module. |
| <a name="output_storage_account_name"></a> [storage\_account\_name](#output\_storage\_account\_name) | Name of the storage account. Use in backend blocks and data source references that require the account name rather than the resource ID. |
<!-- END_TF_DOCS -->
