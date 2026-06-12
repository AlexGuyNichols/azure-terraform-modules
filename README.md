# azure-terraform-modules

> Reusable, production-style **Azure Terraform modules** with secure defaults and CI validation
> (`fmt` · `validate` · `tflint` · `checkov`). Built to be composed — these modules are being
> adopted as the infrastructure layer of the **fitness-leaderboard-platform** case study
> (private during build-out).

[![CI](https://github.com/AlexGuyNichols/azure-terraform-modules/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AlexGuyNichols/azure-terraform-modules/actions/workflows/ci.yml)

## Why

Real infrastructure is built from reusable modules with secure defaults — not one throwaway
`main.tf`. The modules bake in hardening appropriate to each resource — HTTPS-only and TLS
minimums for storage, RBAC-only and network-deny for Key Vault, managed identity for Container
Apps — and each ships with an example you can `plan` immediately.

## Modules

| Module | Provisions | Secure defaults |
|--------|-----------|-----------------|
| [`key-vault`](modules/key-vault/README.md) | Key Vault + scoped role assignments | RBAC-only authorisation, purge protection, 90-day soft-delete retention, public network access denied |
| [`storage-account`](modules/storage-account/README.md) | Remote-state-grade storage account + always-private containers | HTTPS-only, TLS 1.2 minimum, no public blob access, blob versioning + delete retention |
| [`container-app`](modules/container-app/README.md) | Container App in a caller-owned environment | System-assigned identity (hardcoded), no ingress by default, Key Vault-backed secrets only, scale-to-zero |

## Usage

```hcl
module "key_vault" {
  source = "git::https://github.com/AlexGuyNichols/azure-terraform-modules//modules/key-vault?ref=v0.1.0"

  name                = "kv-myapp-prod"
  location            = "uksouth"
  resource_group_name = "rg-myapp-prod"
}
```

Only `name`, `location`, and `resource_group_name` are required; all security defaults are
inherited automatically. The other two modules follow the same
`git::…//modules/<name>?ref=v0.1.0` pattern — see
[`storage-account`](modules/storage-account/README.md) and
[`container-app`](modules/container-app/README.md) for their required inputs.

## Design Decisions

### Secure by default

Hardening is hardcoded or defaulted on — not left to the caller to configure. Every hardened
argument carries a `# Secure default:` comment in the source so the intent is visible during
code review. Per-module bash gate scripts in `tests/` assert the posture mechanically in CI,
so a future change that weakens a default fails CI immediately and cannot pass unnoticed.

One documented exception: `storage-account` defaults `public_network_access_enabled = true` so
remote-state backends stay reachable from CI runners and developer machines; firewall posture
is the caller's choice via the optional `network_rules` input — see the
[module README](modules/storage-account/README.md) for the rationale and how to lock it down.

### Justified skips only

Zero inline `#checkov:skip` annotations exist in any `.tf` file in this repository. The CI
workflow's `skip_check` list carries a written per-ID justification comment for every entry —
skips are explicit, visible, and auditable. Must-pass checks (hardened arguments asserted by
the gate scripts) are never skipped.

### Honest provider floors

Each module declares the floor its code actually requires — not a round number, not the latest
release:

- `key-vault`: `>= 4.42, < 5.0` (the `rbac_authorization_enabled` attribute name used here was
  introduced in azurerm v4.42)
- `storage-account`: `>= 4.9, < 5.0` (the `storage_account_id` argument on
  `azurerm_storage_container` is available from azurerm v4.9)
- `container-app`: `>= 4.0, < 5.0` (no feature in this module forces a higher floor)

A consumer whose root constraints resolve azurerm below the declared floor gets a clear
init-time version-resolution error rather than a silent plan-time failure. See each module
README for the full rationale: [key-vault](modules/key-vault/README.md),
[storage-account](modules/storage-account/README.md),
[container-app](modules/container-app/README.md).

## Validation (CI)

The static pipeline runs on every push and pull request:

1. **Sanitise** — a private-pattern sweep gates all other jobs; nothing proceeds if a private
   identifier is found. The sweep self-test also runs on every CI invocation to prove the gate's
   own behaviour is correct.
2. **Module gates** — three per-module bash scripts in `tests/` assert every hardened argument
   and justified skip in isolation (22 assertions for key-vault, 29 for storage-account, 30 for
   container-app).
3. **Discover** — a dynamic matrix is built from every module directory and every example
   sub-directory (currently 9 directories), so new modules join CI with zero workflow edits.
4. **Validate matrix** — for each discovered directory: `terraform fmt -check`, `terraform init
   -backend=false`, `terraform validate`, `tflint` with the azurerm ruleset, and `checkov` with
   `soft_fail: false`. All GitHub Actions steps are SHA-pinned.

No `terraform plan` or `terraform apply` runs in CI — the pipeline is static-only and holds no
Azure credentials.

## Cost Posture

Any demo resources created while developing this library are torn down after use and are not
reflected in the repository. CI never provisions Azure resources — the pipeline is static-only
and holds no Azure credentials, so there is no ongoing cloud spend from CI runs. The
`container-app` module defaults to `min_replicas = 0` (scale-to-zero), so idle container apps
incur no compute cost.

## Status

v0.1.0 — three modules (`key-vault`, `storage-account`, `container-app`), each with basic and
secure examples, validated by the static CI pipeline. See [CHANGELOG.md](CHANGELOG.md).

## License

MIT — see [LICENSE](LICENSE).
