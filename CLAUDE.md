<!-- GSD:project-start source:PROJECT.md -->
## Project

**azure-terraform-modules**

A small public library of reusable, production-style Azure Terraform modules with automated CI validation. The modules are extracted and sanitised from the real (private) fitness-leaderboard Azure deployment, then generalised — and are consumed by the public flagship platform repo via versioned git sources, so both repos are genuinely real and visibly linked.

**Core Value:** The modules are genuinely reusable and secure by default — a consumer can drop one into their config, get a clean plan, and inherit hardened settings without reading the source.

### Constraints

- **Security**: Public repo — no secrets, no real Azure identifiers, sanitise everything copied from the private deployment
- **Budget**: Cost-aware — any demo resources are torn down; noted in the README; CI never provisions Azure resources
- **Tech stack**: Terraform + azurerm provider + GitHub Actions — matches the real deployment and flagship consumer
- **Timeline**: ~1–2 evenings of effort — scope is 3 modules, not a sprawling module registry
- **Dependencies**: Flagship repo consumption drives interface design — module inputs/outputs must serve a real consumer, not hypothetical flexibility
<!-- GSD:project-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Recommended Stack
### Core Technologies
| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| Terraform CLI | `~> 1.5` (min), `1.15.5` current stable | IaC engine; fmt + validate commands | 1.15.x is the current stable line; `~> 1.5` in `required_version` gives consumers flexibility while excluding pre-1.x behaviour changes. Do NOT pin to `>= 1.0` — too loose for modules; do NOT pin to an exact patch version — breaks consumer CI on upgrade. |
| azurerm provider | `>= 4.0, < 5.0` | All Azure resource management | 4.x dropped legacy AAD resources in favour of AzureAD provider split; v4.76.0 is current. Modules should declare a wide range constraint (`>= 4.0`) so consumers can upgrade provider independently. Root module (examples/) can tighten this further. |
| tflint | `0.63.1` | Terraform-aware linting (invalid resource types, deprecated attrs, unused vars) | Goes deeper than `terraform validate`; catches azurerm-specific errors (invalid SKUs, retired VM sizes) that validate misses. v0.63.0 added Terraform 1.15 support. |
| tflint-ruleset-azurerm | `0.32.0` | 200+ Azure-specific lint rules | Official ruleset from terraform-linters org; catches azurerm resource-level issues (deprecated resources, invalid arguments). Pairs with tflint core. |
| checkov | `3.2.526` (latest) via action | Security policy scanning (CIS, NIST) | Replaces tfsec (deprecated) and terrascan (archived Nov 2025). 1000+ built-in Azure policies. Inline `#checkov:skip=CKV_AZURE_XXX:reason` for justified suppressions on intentional secure-but-flagged patterns. |
| terraform-docs | `0.24.0` | Generate `README.md` inputs/outputs tables | De-facto standard; reads variables.tf + outputs.tf and renders markdown tables. Run locally; commit output. CI validates it is not stale (optional). |
### GitHub Actions
| Action | Version | Purpose | Notes |
|--------|---------|---------|-------|
| `hashicorp/setup-terraform` | `v4.0.1` (`v4`) | Install pinned Terraform CLI in CI | Use `terraform_version: "1.15.5"` to pin; omitting defaults to latest which is non-deterministic. |
| `terraform-linters/setup-tflint` | `v6.2.2` (`v6`) | Install tflint in CI | Set `tflint_version: "v0.63.1"` explicitly. Supports caching. |
| `bridgecrewio/checkov-action` | `v12.1347.0` (`v12`) | Run checkov scan | Use `directory: .`, `framework: terraform`, and `soft_fail: false` to fail the build on findings. |
| `terraform-docs/gh-actions` | `v1.4.1` (`v1`) | (Optional) Auto-commit docs to PR | Worth adding once modules stabilise; not needed for MVP CI. |
### Supporting / Local Dev Tools
| Tool | Purpose | When to Use |
|------|---------|-------------|
| `antonbabenko/pre-commit-terraform` | Local pre-commit hooks running fmt, validate, tflint, checkov before every commit | Optional but strongly recommended for solo dev; mirrors CI checks locally to catch issues before push. Not required in CI (CI runs tools directly). |
| `.tflint.hcl` config file | Declare plugin + ruleset versions for reproducible tflint runs | Required in repo root; tflint reads it for plugin resolution. |
| `.terraform.lock.hcl` | Provider version lock file | Commit to repo so `terraform init` is reproducible; CI must run `terraform init` before validate/tflint. |
## Installation
# Terraform — install via tfenv (cross-platform version manager) or direct binary
# https://github.com/tfutils/tfenv
# tflint
# macOS
# Linux / CI
# terraform-docs
# macOS
# Linux / CI — or use the gh-actions action
# checkov — Python-based, install via pip
# Or use the bridgecrewio/checkov-action in CI (preferred; avoids Python env management)
# pre-commit (optional local dev)
## Alternatives Considered
| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| checkov | tfsec | tfsec is deprecated; Aqua merged all checks into Trivy; no new Azure checks being added |
| checkov | trivy (`trivy config`) | Trivy is a valid choice (inherits all tfsec checks). Checkov preferred here because it has broader Azure policy coverage (CIS Azure Foundations) and native Terraform support without requiring Docker. Either works. |
| checkov | terrascan | Archived by Tenable November 2025; read-only; do not use |
| tflint + ruleset | terraform validate only | `validate` only checks syntax/schema; tflint catches semantic errors (invalid SKUs, deprecated attributes) that validate misses |
| `hashicorp/setup-terraform` v4 | Direct `apt install terraform` in CI | Action handles version pinning, PATH, and wrapper; cleaner and version-portable |
| terraform-docs | Manual README maintenance | terraform-docs output is always in sync with variables.tf; manual docs drift |
## What NOT to Use
| Avoid | Why | Use Instead |
|-------|-----|-------------|
| tfsec | Deprecated; Aqua Security redirected all development to Trivy; no new checks after the merge | checkov or `trivy config` |
| terrascan | Archived by Tenable November 2025; read-only repository | checkov |
| bridgecrew-action (the OLD action) | Replaced by `checkov-action` v12 | `bridgecrewio/checkov-action@v12` |
| `azurerm ~> 3.x` constraint | v3 is the previous major; v4 dropped legacy AAD resources and changed authentication defaults; modules written against v3 need migration | `azurerm >= 4.0, < 5.0` |
| Terraform Registry publishing | Requires repo-per-module layout; git-source consumption is sufficient and already chosen | Semver git tags + `git::https://...//modules/<name>?ref=vX.Y.Z` |
| terratest | Integration testing framework requiring real Azure creds; this repo is static-only CI | None needed; fmt + validate + tflint + checkov covers static quality gate without credentials |
| `terraform plan`/`apply` in CI | Public repo; Azure credentials cannot safely live in CI secrets without careful scope management | Validate locally; CI is static-only by design |
## Version Compatibility
| Component | Compatible With | Notes |
|-----------|-----------------|-------|
| tflint `0.63.x` | Terraform `>= 1.0` (badge verified); `1.15.x` explicitly tested in v0.63.0 release | Must run `terraform init` before tflint so it can read the provider schema |
| tflint-ruleset-azurerm `0.32.0` | tflint `>= 0.46` | Plugin downloaded by tflint at init via `.tflint.hcl`; no manual install needed |
| checkov `3.x` | Terraform `>= 0.12`; azurerm `4.x` resources fully supported | Checkov reads HCL directly; no `terraform init` required |
| terraform-docs `0.24.0` | Terraform `>= 0.12` | Run after modules are written; re-run when variables.tf / outputs.tf change |
| azurerm `4.x` | Terraform `>= 1.3` (required for `optional()` in object types) | The 4.0 upgrade guide explicitly requires Terraform 1.3+; set `required_version = ">= 1.5"` to stay safe |
## Key Configuration Files
### `.tflint.hcl` (repo root)
### `versions.tf` (per module — e.g., `modules/key-vault/versions.tf`)
### GitHub Actions workflow skeleton (`.github/workflows/ci.yml`)
## Stack Patterns by Variant
- Include a `versions.tf` with tighter provider constraint (`~> 4.76`) and a `providers.tf` with `features {}` block
- Run the same CI matrix over `modules/<name>/examples/` directories
- Do NOT run `terraform plan` in CI (no Azure creds)
- Use `backend "local" {}` explicitly so CI `terraform init -backend=false` works without a real backend config
- Use inline suppression: `#checkov:skip=CKV_AZURE_XXX:Intentional — purge protection is configurable via variable`
- Document the reason; don't suppress blindly
## Sources
- [hashicorp/terraform-provider-azurerm releases](https://github.com/hashicorp/terraform-provider-azurerm/releases) — v4.76.0 confirmed latest stable (2026-06-04). HIGH confidence.
- [hashicorp/terraform releases](https://github.com/hashicorp/terraform/releases) — v1.15.5 confirmed latest stable. HIGH confidence.
- [terraform-linters/tflint releases](https://github.com/terraform-linters/tflint/releases) — v0.63.1 confirmed latest stable (2026-06-03). HIGH confidence.
- [terraform-linters/tflint-ruleset-azurerm releases](https://github.com/terraform-linters/tflint-ruleset-azurerm/releases) — v0.32.0 confirmed latest stable (2025-04-25). HIGH confidence.
- [terraform-docs/terraform-docs releases](https://github.com/terraform-docs/terraform-docs/releases) — v0.24.0 confirmed latest stable (2026-05-10). HIGH confidence.
- [hashicorp/setup-terraform releases](https://github.com/hashicorp/setup-terraform/releases) — v4.0.1 confirmed latest stable. HIGH confidence.
- [terraform-linters/setup-tflint releases](https://github.com/terraform-linters/setup-tflint/releases) — v6.2.2 confirmed latest stable (2025-03-14). HIGH confidence.
- [bridgecrewio/checkov-action releases](https://github.com/bridgecrewio/checkov-action/releases) — v12.1347.0 confirmed latest stable. HIGH confidence.
- [aquasecurity/tfsec](https://github.com/aquasecurity/tfsec) — tfsec deprecated; merged into Trivy. HIGH confidence.
- [env0 blog: Checkov vs Trivy in 2026](https://www.env0.com/blog/best-iac-scan-tool-comparing-checkov-vs-tfsec-vs-terrascan) — terrascan archived Nov 2025 confirmed. MEDIUM confidence (secondary source, consistent with GitHub repo status).
- [HashiCorp: Standard Module Structure](https://developer.hashicorp.com/terraform/language/modules/develop/structure) — Official module file layout. HIGH confidence.
- [antonbabenko/pre-commit-terraform](https://github.com/antonbabenko/pre-commit-terraform) — terraform_tfsec deprecated in favour of terraform_trivy in hooks. MEDIUM confidence.
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
