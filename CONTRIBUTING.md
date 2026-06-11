# Contributing

## One-time local setup

After cloning, three setup steps are required before making commits. None of these are
committed — they configure your local environment only.

### 1. Create the private patterns file

The sanitisation sweep (`scripts/sanitise.sh`) reads a gitignored file at
`scripts/.private-patterns`. This file lists the private identifiers that must never
appear in the public repo — things like your organisation handle and project shortnames.

Create the file with one grep-E pattern per line. `#`-prefixed lines and blank lines are
ignored. Matching is case-insensitive, so a single short form covers all casings.

Example structure (replace with your own private values):

```
# Private identifier patterns — ONE per line, grep -E compatible
your-org-handle
yourprojectshortname
YourProjectLongName
```

The file is gitignored and must never be committed. If you add or change patterns,
re-run step 3 below to keep CI in sync.

### 2. Enable the tracked pre-commit hook

```bash
git config core.hooksPath hooks
```

This wires `hooks/pre-commit` (checked in to the repo) as your local hook. The hook
runs `scripts/sanitise.sh` before every commit, so private identifiers are caught
before they enter local history — well before a push can reach the public remote.

### 3. Upload the pattern file to GitHub Actions

```bash
gh secret set SANITISE_PATTERNS < scripts/.private-patterns
```

This stores the pattern content as a repository secret. The CI `sanitise` job writes it
to `scripts/.private-patterns` on the runner before invoking the sweep. Re-run this
command whenever the pattern file changes.

Verify the secret is registered:

```bash
gh secret list
```

---

## CI overview

Every push and pull request triggers `.github/workflows/ci.yml`. The job graph is gated:

```
sanitise → discover → validate (matrix)
```

**sanitise** — Writes the `SANITISE_PATTERNS` secret to the well-known gitignored path,
runs the sweep self-test (`tests/test_sanitise.sh`), then runs the sweep itself
(`scripts/sanitise.sh`). All downstream jobs are blocked until this passes. Fork pull
requests that lack secret access will fail here — this is the accepted behaviour for a
public repo.

**discover** — Finds all directories matching `modules/*/` and `examples/*/*/` and emits
a JSON matrix. New modules added in future phases join the CI matrix automatically with
no workflow changes required.

**validate (matrix)** — Runs once per discovered directory:

| Step | Requirement |
|------|-------------|
| `terraform fmt -check -recursive` | CI-01 |
| `terraform init -backend=false` + `terraform validate` | CI-02 |
| `tflint --init` + `tflint` (azurerm ruleset) | CI-03 |
| checkov (`soft_fail: false`) | CI-04 |

CI never runs `terraform plan` or `terraform apply` and never holds Azure credentials.
All validation is static — no Azure resources are created or billed.

All action `uses:` lines are pinned to full 40-character commit SHAs with a version
comment (CI-05). Dependabot raises weekly pull requests when pins need updating; those
PRs are validated by this same pipeline.

---

## Local validation

Run these commands locally before pushing to match what CI will check:

```bash
# Sanitisation sweep
bash scripts/sanitise.sh

# Sweep self-test (proves the gate's own behaviour)
bash tests/test_sanitise.sh

# Terraform format check (run from a module or example directory)
terraform fmt -check -recursive

# Terraform validate (no backend or Azure credentials needed)
terraform -chdir=modules/placeholder init -backend=false
terraform -chdir=modules/placeholder validate

terraform -chdir=examples/placeholder/basic init -backend=false
terraform -chdir=examples/placeholder/basic validate
```

tflint and checkov are most conveniently run via CI, but can also be run locally if the
tools are installed. See `CLAUDE.md` for pinned tool versions.
