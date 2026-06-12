# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-06-12

### Added

- `key-vault` module — hardened, RBAC-only Azure Key Vault with purge protection on by default,
  90-day soft-delete retention, and public network access denied by default; scoped role
  assignments via a `role_assignments` map input
- `storage-account` module — remote-state-grade Azure Storage Account with HTTPS-only, TLS 1.2
  minimum, no public blob access, blob versioning, and always-private containers hardcoded
- `container-app` module — hardened Container App in a caller-owned environment with
  system-assigned identity hardcoded on, no ingress by default, Key Vault-backed secrets only
  (via managed identity), and scale-to-zero defaults
- Basic and secure examples for each module (`examples/key-vault/basic`,
  `examples/key-vault/secure`, `examples/storage-account/basic`,
  `examples/storage-account/secure`, `examples/container-app/basic`,
  `examples/container-app/secure`)
- Sanitisation sweep (`scripts/sanitise.sh`) with pre-commit hook and CI `Sanitise` job that
  gates all other jobs — protects the public repo from private-identifier leaks on every commit
  and push
- Static CI pipeline (`fmt -check`, `terraform init -backend=false`, `terraform validate`,
  `tflint` with the azurerm ruleset, `checkov` with `soft_fail: false`) across a dynamically
  discovered 9-directory matrix; all GitHub Actions steps SHA-pinned
- Three per-module bash gate scripts in `tests/` (`test_key_vault_module.sh`,
  `test_storage_account_module.sh`, `test_container_app_module.sh`) that assert every hardened
  argument and justified checkov skip in CI

[Unreleased]: https://github.com/AlexGuyNichols/azure-terraform-modules/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/AlexGuyNichols/azure-terraform-modules/releases/tag/v0.1.0
