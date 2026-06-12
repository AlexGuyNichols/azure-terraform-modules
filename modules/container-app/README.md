# container-app

Hardened Azure Container App module with system-assigned identity and credential-less Key Vault secret access.

## Design Notes

This module is extracted and generalised from a real Azure deployment, with all application-specific
logic removed. It applies the following hardening decisions:

- **System-assigned identity hardcoded on** — `identity { type = "SystemAssigned" }` is hardcoded
  in the resource block (not a variable). The module's identity is non-negotiable, like RBAC-only
  in the key-vault module. The `principal_id` output is exported so callers can wire least-privilege
  role assignments without receiving any credential (D-05).
- **No ingress by default** — `ingress = null` is the default, which renders no ingress block at
  all. The app has zero inbound network exposure until the caller explicitly opts in by supplying
  the `ingress` object. Even when ingress is configured, `allow_insecure_connections` defaults to
  `false` (HTTPS-only) (D-07).
- **No business logic** — there are no image-mutation lifecycle rules, no application-specific
  environment variable names, and no source-deployment remnants. Environment variables pass through
  generic maps and image deployments are the caller's pipeline concern (D-03/D-09).
- **Key Vault-backed secrets only** — there is deliberately no plaintext secret input. Secrets are
  Key Vault secret URIs resolved at runtime by the container app runtime via the system-assigned
  managed identity. Credentials never appear in caller config or Terraform state (D-02).
- **Cost-aware scale defaults** — `min_replicas = 0` (scale-to-zero when idle), `max_replicas = 1`
  (prevents unexpected scale-out), and the smallest Consumption-plan pair (0.25 vCPU / 0.5Gi
  memory) are the defaults. Callers opt up explicitly (D-04).
- **Caller-owned environment** — the module accepts `container_app_environment_id` as an input.
  Container Apps Environments are shared infrastructure that often host multiple apps; the module
  does not provision one (D-01).

## Usage

```hcl
module "container_app" {
  source = "git::https://github.com/AlexGuyNichols/azure-terraform-modules//modules/container-app?ref=v0.1.0"

  name                         = "ca-myapp-prod"
  resource_group_name          = "rg-myapp-prod"
  container_app_environment_id = azurerm_container_app_environment.main.id
  image                        = "myregistry.azurecr.io/myapp:1.0.0"
}
```

Only `name`, `resource_group_name`, `container_app_environment_id`, and `image` are required. All
security defaults are inherited automatically.

For the optional surface (ingress, Key Vault secret access, registry authentication, scale
settings, and tags) see
[examples/container-app/basic](../../examples/container-app/basic) and
[examples/container-app/secure](../../examples/container-app/secure).

## Provider Version Note

The declared constraint is `>= 4.0, < 5.0`. No feature in this module forces a higher floor —
`key_vault_secret_id` with `identity = "System"` on the secret block is available throughout the
4.x line (confirmed in provider source).

**Known open bug — azurerm #29743/#31376 (ordering sensitivity):** The azurerm provider has a
confirmed bug where env and secret blocks read back from the Azure API in alphabetical order,
which conflicts with any non-alphabetical declaration order and causes perpetual plan diffs. Fix
PR #32292 is open but **not yet merged in any released version** as of the time of writing. This
module mitigates the bug by merging plain and secret-backed env vars into a single map rendered
by one dynamic `env` block: Terraform iterates maps in lexicographic key order, so the combined
env list is globally alphabetical — matching Azure's read-back order across both kinds of entry
(two separate blocks would concatenate in source order and reorder on refresh whenever a
secret-backed name sorts before a plain one). When the fix ships, the workaround is harmless and
can remain; there is no fix-version floor to raise (D-12).

## Key Vault Composition

Granting a container app access to Key Vault secrets requires three resources in the right
order. This is the trickiest part of the module's consumption story — understanding the ordering
avoids both a broken deployment and a dependency cycle Terraform will reject.

**Why the module takes no vault input (D-06):** The container app's system-assigned managed
identity does not exist until the app resource is created. A role assignment granting that
identity vault access cannot be created before the identity exists. This is why the role
assignment must live in the caller's configuration and why the module exports `principal_id`
rather than accepting a vault reference.

**The correct wiring pattern:**

```hcl
# 1. The container app — creates the system-assigned identity
module "container_app" {
  source = "git::https://github.com/AlexGuyNichols/azure-terraform-modules//modules/container-app?ref=v0.1.0"

  name                         = "ca-myapp-prod"
  resource_group_name          = "rg-myapp-prod"
  container_app_environment_id = var.container_app_environment_id
  image                        = "myregistry.azurecr.io/myapp:1.0.0"

  key_vault_secrets = {
    "app-secret" = "${module.key_vault.key_vault_uri}secrets/my-secret"
  }
}

# 2. The role assignment — grants the identity read access to the vault
resource "azurerm_role_assignment" "kv_secrets_user" {
  scope                = module.key_vault.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = module.container_app.principal_id
}
```

The `principal_id` output reference tells Terraform to create the container app first, then the
role assignment. This is the complete and correct implicit ordering — no `depends_on` is needed
or wanted.

**Do NOT add `depends_on` to the module call.** Adding `depends_on = [azurerm_role_assignment.kv_secrets_user]`
on the `module "container_app"` block creates a dependency cycle: every resource inside the
module would depend on the role assignment, which itself depends on `module.container_app.principal_id`.
Terraform will reject this with a cycle error at plan time.

**First-apply bootstrap requirement:** Azure validates `key_vault_secret_id` URIs at app create
time, and the dependency ordering above means the app is created BEFORE the role assignment (the
identity must exist first). On a fresh composition, an app created with secret references
therefore fails with a 403 on the secret — the identity has no vault grant yet, the apply halts
at the app resource, and the role assignment is never created. Re-applying hits the same failure
indefinitely; worse, the failed ARM create can leave an orphaned container app in Azure that is
not in Terraform state, requiring manual deletion or import before any retry.

The working first-deploy path is a two-apply bootstrap:

1. First apply with `key_vault_secrets = {}` and `secret_environment_variables = {}` (the
   precondition requires every secret-backed env var to reference a declared secret). This
   creates the app, its identity, and then the role assignment.
2. Second apply with the real secret references. This succeeds once the role assignment has
   propagated — RBAC is eventually consistent, typically under 30 seconds but occasionally a few
   minutes; if the second apply hits a transient 403, re-apply after a short wait.

Never paper over this with `lifecycle` hacks or artificial delays — the two-apply bootstrap is
the honest Azure-native solution.

The working reference implementation is
[examples/container-app/secure](../../examples/container-app/secure), which demonstrates the
full identity → role assignment → secret access composition with no `depends_on`.

## Scale and Cost Note

The Consumption-plan cpu/memory pairing is enforced as a plan-time precondition. Eight valid
pairs are accepted (the Consumption-plan cap is 2.0 vCPU / 4.0Gi memory):

| vCPU | Memory |
|------|--------|
| 0.25 | 0.5Gi  |
| 0.5  | 1.0Gi  |
| 0.75 | 1.5Gi  |
| 1.0  | 2.0Gi  |
| 1.25 | 2.5Gi  |
| 1.5  | 3.0Gi  |
| 1.75 | 3.5Gi  |
| 2.0  | 4.0Gi  |

Callers on dedicated workload profiles who need larger sizes should supply the cpu/memory pair
appropriate for their profile — the validation rejects only values outside the Consumption
enumeration and may need adjustment for dedicated-profile environments.

The scale-to-zero default (`min_replicas = 0`) means the app incurs no compute cost while idle.
The `max_replicas = 1` default caps scale-out to prevent cost surprises during load spikes —
callers with variable traffic should raise this explicitly.

Cross-variable pairing rules (valid cpu/memory pair, `max_replicas >= min_replicas`, and
secret-reference integrity) are all enforced as `lifecycle` preconditions at plan time.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_azurerm"></a> [azurerm](#requirement\_azurerm) | >= 4.0, < 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | >= 4.0, < 5.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_app.main](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_app) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_container_app_environment_id"></a> [container\_app\_environment\_id](#input\_container\_app\_environment\_id) | Resource ID of the Container Apps Environment. The environment is caller-owned shared infrastructure; the module does not provision it (composability over convenience). | `string` | n/a | yes |
| <a name="input_cpu"></a> [cpu](#input\_cpu) | vCPU allocation for the container. Valid Consumption-plan values: 0.25, 0.5, 0.75, 1, 1.25, 1.5, 1.75, 2. Must pair with memory (see pairing rule enforced by lifecycle precondition in main.tf). Defaults to 0.25 (cost-aware minimum). | `number` | `0.25` | no |
| <a name="input_environment_variables"></a> [environment\_variables](#input\_environment\_variables) | Plain environment variables for the container: map of name to literal value. Generic map — naming conventions for application-specific env vars are the caller's concern. For secret-backed env vars, use secret\_environment\_variables instead; the same name must not appear in both maps (enforced by lifecycle precondition in main.tf). | `map(string)` | `{}` | no |
| <a name="input_image"></a> [image](#input\_image) | Container image to deploy, including tag (e.g. 'mcr.microsoft.com/k8se/quickstart:latest'). Required — the module enforces a consumer-specified workload image rather than a default (SEC-03). | `string` | n/a | yes |
| <a name="input_ingress"></a> [ingress](#input\_ingress) | Ingress configuration. When null (default) no ingress block is rendered and the app has no inbound network exposure. When supplied, external\_enabled defaults to false (internal-only), transport defaults to 'auto', and allow\_insecure\_connections defaults to false (HTTPS-only). | <pre>object({<br/>    target_port                = number<br/>    external_enabled           = optional(bool, false)<br/>    transport                  = optional(string, "auto")<br/>    allow_insecure_connections = optional(bool, false)<br/>  })</pre> | `null` | no |
| <a name="input_key_vault_secrets"></a> [key\_vault\_secrets](#input\_key\_vault\_secrets) | Key Vault-backed secrets: map of app-visible secret name to Key Vault secret URI (versionless or versioned). Each secret is accessed using the app's system-assigned managed identity. The caller must grant that identity the 'Key Vault Secrets User' role assignment on the vault. No plaintext-value secret variable exists in this module — credentials never appear in caller config or Terraform state. | `map(string)` | `{}` | no |
| <a name="input_max_replicas"></a> [max\_replicas](#input\_max\_replicas) | Maximum number of container app replicas. Defaults to 1 (cost-aware; prevents unexpected scale-out). Valid range: 1-300. Must be >= min\_replicas (enforced by lifecycle precondition in main.tf). | `number` | `1` | no |
| <a name="input_memory"></a> [memory](#input\_memory) | Memory allocation for the container. Valid Consumption-plan values: 0.5Gi, 1.0Gi, 1.5Gi, 2.0Gi, 2.5Gi, 3.0Gi, 3.5Gi, 4.0Gi. Must pair with cpu (see pairing rule enforced by lifecycle precondition in main.tf). Defaults to 0.5Gi (cost-aware minimum). | `string` | `"0.5Gi"` | no |
| <a name="input_min_replicas"></a> [min\_replicas](#input\_min\_replicas) | Minimum number of container app replicas. Defaults to 0 (scale-to-zero when idle, cost-aware). Valid range: 0-300. | `number` | `0` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the container app. Must be 2-32 characters: lowercase letters, numbers, and hyphens (no consecutive hyphens); must start with a letter and end with a letter or number. | `string` | n/a | yes |
| <a name="input_registries"></a> [registries](#input\_registries) | Container registry configurations for image pull. Each entry specifies a registry server; identity defaults to 'System' for credential-less pull using the app's system-assigned managed identity (no stored credentials needed). | <pre>list(object({<br/>    server   = string<br/>    identity = optional(string, "System")<br/>  }))</pre> | `[]` | no |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group in which the container app will be deployed. | `string` | n/a | yes |
| <a name="input_revision_mode"></a> [revision\_mode](#input\_revision\_mode) | Revision mode for the container app. 'Single' (default) keeps one active revision. 'Multiple' keeps prior revisions available, but this module always routes 100% of traffic to the latest revision — traffic splitting across revisions is managed outside this module. | `string` | `"Single"` | no |
| <a name="input_secret_environment_variables"></a> [secret\_environment\_variables](#input\_secret\_environment\_variables) | Secret-backed environment variables: map of env var name to secret name. Each value must match a key in key\_vault\_secrets — the secret name references an in-scope secret block (enforced by lifecycle precondition in main.tf). The same env var name must not also appear in environment\_variables (enforced by lifecycle precondition in main.tf). The actual secret value is resolved at runtime by the container app runtime via managed identity. | `map(string)` | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Map of tags to apply to all resources managed by this module. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_app_id"></a> [container\_app\_id](#output\_container\_app\_id) | Resource ID of the container app. |
| <a name="output_container_app_name"></a> [container\_app\_name](#output\_container\_app\_name) | Name of the container app. |
| <a name="output_latest_revision_fqdn"></a> [latest\_revision\_fqdn](#output\_latest\_revision\_fqdn) | Fully qualified domain name of the latest active revision. Only populated when ingress is configured; empty string when ingress is null. |
| <a name="output_principal_id"></a> [principal\_id](#output\_principal\_id) | Principal ID of the system-assigned managed identity. Use this in caller-side role assignments to grant the app access to Azure resources (e.g. 'Key Vault Secrets User' for vault secret access). |
<!-- END_TF_DOCS -->
