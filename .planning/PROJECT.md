# azure-terraform-modules

## What This Is

A small public library of reusable, production-style Azure Terraform modules with automated CI validation. The modules are extracted and sanitised from the real (private) fitness-leaderboard Azure deployment, then generalised — and are consumed by the public flagship platform repo via versioned git sources, so both repos are genuinely real and visibly linked.

## Core Value

The modules are genuinely reusable and secure by default — a consumer can drop one into their config, get a clean plan, and inherit hardened settings without reading the source.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] `key-vault` module — extracted from the real deployment's `keyvault.tf`, generalised and sanitised
- [ ] `container-app` module — extracted from the real deployment's `container_apps.tf`, generalised and sanitised
- [ ] `storage-account` module — suitable for remote state hosting; written fresh, informed by the real deployment's shape
- [ ] Each module ships `main.tf` · `variables.tf` · `outputs.tf` · `versions.tf` · per-module `README.md` · working `examples/`
- [ ] Secure defaults baked in (HTTPS-only, TLS minimum version, no public blob access, RBAC/purge protection on Key Vault, system-assigned identity)
- [ ] CI workflow on GitHub Actions: `terraform fmt -check`, `terraform validate`, `tflint`, `checkov` — across modules and examples
- [ ] Root README documenting the modules, how to consume them via versioned git source, the CI setup, and design decisions
- [ ] Semver release tags (v0.1.0 …) so the flagship repo can pin `?ref=vX.Y.Z`

### Out of Scope

- Running `terraform plan`/`apply` in CI — public repo; avoiding Azure credentials in CI. "Examples plan cleanly" is verified locally.
- `app-service` module — the real deployment runs Container Apps; no real source to extract from.
- Terraform Registry publishing — git source consumption is sufficient for the flagship link; registry requires repo-per-module layout.
- Business logic or application code — this repo is infrastructure modules only.
- Importing the private repo's git history — repo is built fresh; files are copied out and sanitised.

## Context

- **Source of truth:** the private fitness-leaderboard deployment at `C:\Users\alex\Documents\FitnessLeaderBoard\infra\terraform\` (`keyvault.tf`, `container_apps.tf`, plus `main.tf`, `locals.tf`, `variables.tf` for context). It is read-only source material: copy out and sanitise, never modify it.
- **No dedicated storage-account config exists in the source** — remote state storage was likely bootstrapped outside Terraform. The `storage-account` module is therefore written fresh but shaped to host remote state (versioning, no public access).
- **Consumer:** the public flagship platform repo references these modules via `git::https://...//modules/<name>?ref=vX.Y.Z` — this repo must stay public and auth-free to consume.
- **Layout:** single repo, `modules/<name>/` subdirectories (monorepo with git-source submodule paths, not repo-per-module).
- Sanitisation follows the flagship PRD checklist: no secrets, no real subscription/tenant/client IDs, no globally-unique resource names.
- This project was chosen as "Option 2" on 2026-06-09: extract + sanitise real infra rather than invent from scratch, so the public repos demonstrably reflect a real deployment.

## Constraints

- **Security**: Public repo — no secrets, no real Azure identifiers, sanitise everything copied from the private deployment
- **Budget**: Cost-aware — any demo resources are torn down; noted in the README; CI never provisions Azure resources
- **Tech stack**: Terraform + azurerm provider + GitHub Actions — matches the real deployment and flagship consumer
- **Timeline**: ~1–2 evenings of effort — scope is 3 modules, not a sprawling module registry
- **Dependencies**: Flagship repo consumption drives interface design — module inputs/outputs must serve a real consumer, not hypothetical flexibility

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Extract + sanitise from real private deployment (Option 2) | Both public repos stay genuinely real and visibly linked, not toy examples | — Pending |
| Modules: key-vault, container-app, storage-account | key-vault and container-app have real source files to extract; storage-account supports remote state and rounds out the library | — Pending |
| Single repo with `modules/<name>/` layout | Git-source submodule paths keep one CI setup and one README; registry publishing (which needs repo-per-module) is out of scope | — Pending |
| Semver git tags for consumption | Standard module-library practice; flagship pins `?ref=vX.Y.Z` for reproducible builds | — Pending |
| CI is static-only (fmt, validate, tflint, checkov) | Public repo without Azure creds; static checks give strong validation with zero credential risk and zero cost | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd:complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-06-11 after initialization*
