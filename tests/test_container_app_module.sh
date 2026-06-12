#!/usr/bin/env bash
# Static security gate for modules/container-app.
# Mirrors test_storage_account_module.sh style: set -euo pipefail, PASS/FAIL helpers,
# resolve_checkov dual venv probe, WR-01 grouped-fallback counting, early-exit on
# missing files, assertion 13 normalised ci.yml comparison with tr -d '\r'.
# RED:   exits non-zero when modules/container-app/ is absent.
# GREEN: exits 0 when the module satisfies all assertions below.
#
# NON-NEGOTIABLE: this file must never contain a literal UUID-shaped string
# or real private name.
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
MODULE_DIR="$REPO_ROOT/modules/container-app"

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Resolve checkov binary.
# Probes PATH, Windows venv (Scripts/), and Linux venv (bin/) — IN-03 fix.
# resolve_checkov: prints the path to a working checkov; exits 1 if not found.
# ---------------------------------------------------------------------------
resolve_checkov() {
  if command -v checkov > /dev/null 2>&1; then
    echo "checkov"
    return 0
  fi
  local venv_scripts="$HOME/.venv-checkov/Scripts/checkov"
  if [[ -x "$venv_scripts" ]]; then
    echo "$venv_scripts"
    return 0
  fi
  local venv_bin="$HOME/.venv-checkov/bin/checkov"
  if [[ -x "$venv_bin" ]]; then
    echo "$venv_bin"
    return 0
  fi
  echo "ERROR: checkov not found. Install with: python -m pip install checkov" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Assertion 1: Required module files exist
# Fail fast naming the first missing file (RED path when module not yet authored).
# ---------------------------------------------------------------------------
MISSING_FILE=""
for f in versions.tf variables.tf outputs.tf main.tf; do
  if [[ ! -f "$MODULE_DIR/$f" ]]; then
    MISSING_FILE="modules/container-app/$f"
    break
  fi
done

if [[ -n "$MISSING_FILE" ]]; then
  fail "Assertion 1: required file missing — $MISSING_FILE (modules/container-app does not exist or is incomplete)"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi
pass "Assertion 1: all four module files exist (versions.tf, variables.tf, outputs.tf, main.tf)"

# ---------------------------------------------------------------------------
# Assertion 2: versions.tf carries library-standard constraints (MOD-04/D-12)
# Floor is >= 4.0 — research confirmed NO attribute or fix-release forces a floor
# above 4.0; key_vault_secret_id + identity = "System" on the secret block are
# available throughout 4.x (confirmed in provider source, main branch). Bug #31376/
# PR #32292 (env/secret ordering) is unmerged — the merged-env-map workaround is
# used instead of raising the floor.
# ---------------------------------------------------------------------------
if grep -qE 'required_version\s*=\s*">= 1\.5"' "$MODULE_DIR/versions.tf" \
   && grep -qE '">= 4\.0, < 5\.0"' "$MODULE_DIR/versions.tf"; then
  pass "Assertion 2: versions.tf has required_version >= 1.5 and azurerm >= 4.0, < 5.0 (MOD-04/D-12)"
else
  fail "Assertion 2: versions.tf missing library-standard constraints (MOD-04/D-12)"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Effective-line assertions on main.tf (comment-stripped)
# Strip comment lines before asserting to avoid matching commented-out code.
# ---------------------------------------------------------------------------
EFFECTIVE_MAIN="$(grep -vE '^\s*#' "$MODULE_DIR/main.tf")"

# 3a: identity block present (system-assigned identity block)
if echo "$EFFECTIVE_MAIN" | grep -qE 'identity\s*\{'; then
  pass "Assertion 3a: identity block present in main.tf (D-05)"
else
  fail "Assertion 3a: identity block missing from main.tf (D-05)"
fi

# 3b: type = "SystemAssigned" — hardcoded system-assigned identity (D-05/SEC-03)
if echo "$EFFECTIVE_MAIN" | grep -qE 'type\s*=\s*"SystemAssigned"'; then
  pass "Assertion 3b: type = \"SystemAssigned\" hardcoded in main.tf (D-05/SEC-03)"
else
  fail "Assertion 3b: type = \"SystemAssigned\" missing from main.tf (D-05/SEC-03)"
fi

# 3c: revision_mode wired to variable (D-01)
if echo "$EFFECTIVE_MAIN" | grep -qE 'revision_mode\s*=\s*var\.revision_mode'; then
  pass "Assertion 3c: revision_mode = var.revision_mode present in main.tf (D-01)"
else
  fail "Assertion 3c: revision_mode = var.revision_mode missing from main.tf (D-01)"
fi

# 3d: dynamic "secret" block present (D-02 — Key Vault-backed secrets)
if echo "$EFFECTIVE_MAIN" | grep -qE 'dynamic\s+"secret"'; then
  pass "Assertion 3d: dynamic \"secret\" block present in main.tf (D-02)"
else
  fail "Assertion 3d: dynamic \"secret\" block missing from main.tf (D-02)"
fi

# 3e: key_vault_secret_id wired to secret.value (D-02 — 4.x attribute name, NOT the
# deprecated v3 key_vault_id; confirmed in provider source main branch)
if echo "$EFFECTIVE_MAIN" | grep -qE 'key_vault_secret_id\s*=\s*secret\.value'; then
  pass "Assertion 3e: key_vault_secret_id = secret.value present in main.tf (D-02/4.x)"
else
  fail "Assertion 3e: key_vault_secret_id = secret.value missing from main.tf (D-02/4.x)"
fi

# 3f: identity = "System" on secret block (D-02 — EXACT string; "System" is the secret-block
# selector value; "SystemAssigned" is the DIFFERENT top-level identity block type value;
# provider validates against StringInSlice([]string{"System"}, false))
if echo "$EFFECTIVE_MAIN" | grep -qE 'identity\s*=\s*"System"'; then
  pass "Assertion 3f: identity = \"System\" (secret-block selector) present in main.tf (D-02)"
else
  fail "Assertion 3f: identity = \"System\" (secret-block selector) missing from main.tf (D-02)"
fi

# 3g: dynamic "ingress" block present (D-07 — null default = no ingress rendered)
if echo "$EFFECTIVE_MAIN" | grep -qE 'dynamic\s+"ingress"'; then
  pass "Assertion 3g: dynamic \"ingress\" block present in main.tf (D-07)"
else
  fail "Assertion 3g: dynamic \"ingress\" block missing from main.tf (D-07)"
fi

# 3h: dynamic "registry" block present (D-08 — identity-based ACR pull)
if echo "$EFFECTIVE_MAIN" | grep -qE 'dynamic\s+"registry"'; then
  pass "Assertion 3h: dynamic \"registry\" block present in main.tf (D-08)"
else
  fail "Assertion 3h: dynamic \"registry\" block missing from main.tf (D-08)"
fi

# 3i: image wired to variable (SEC-03 — the required workload input)
if echo "$EFFECTIVE_MAIN" | grep -qE 'image\s*=\s*var\.image'; then
  pass "Assertion 3i: image = var.image present in main.tf (SEC-03)"
else
  fail "Assertion 3i: image = var.image missing from main.tf (SEC-03)"
fi

# 3j: exactly ONE merged dynamic "env" block — workaround for azurerm bug #29743/#31376
# (env ordering perpetual plan noise); PR #32292 is open and blocked as of 2026-06-12,
# not yet merged into any released 4.x version. Plain and secret-backed env vars are
# merged into a single map so one dynamic block renders the COMBINED set in lexicographic
# key order, matching Azure's alphabetical read-back of the whole env list. Two separate
# dynamic env blocks would concatenate in source order and break global ordering whenever
# a secret-backed name sorts before a plain name.
ENV_BLOCK_COUNT="$({ echo "$EFFECTIVE_MAIN" | grep -cE 'dynamic\s+"env"' || true; })"
ENV_MERGE_COUNT="$({ echo "$EFFECTIVE_MAIN" | grep -cE 'merged_environment_variables\s*=\s*merge\(' || true; })"
if [[ "$ENV_BLOCK_COUNT" -eq 1 && "$ENV_MERGE_COUNT" -ge 1 ]]; then
  pass "Assertion 3j: single merged dynamic \"env\" block via merge() in main.tf (#31376 global ordering workaround, env_blocks=$ENV_BLOCK_COUNT)"
else
  fail "Assertion 3j: expected exactly 1 dynamic \"env\" block fed by merged_environment_variables = merge() in main.tf (#31376 global ordering workaround, env_blocks=$ENV_BLOCK_COUNT, merge_count=$ENV_MERGE_COUNT)"
fi

# 3k: precondition blocks >= 2 (cpu/memory pairing + replica ordering live in lifecycle
# preconditions because cross-variable validation inside validation{} blocks requires
# Terraform >= 1.9, which is above the >= 1.5 library floor; precondition works from 1.2)
PRECONDITION_COUNT="$({ echo "$EFFECTIVE_MAIN" | grep -cE 'precondition\s*\{' || true; })"
if [[ "$PRECONDITION_COUNT" -ge 2 ]]; then
  pass "Assertion 3k: >= 2 precondition blocks in main.tf (cpu/memory pairing + replica ordering, count=$PRECONDITION_COUNT)"
else
  fail "Assertion 3k: fewer than 2 precondition blocks in main.tf (expected cpu/memory + replica ordering, count=$PRECONDITION_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Secure default comment count (SEC-04)
# This gate intentionally counts comment lines (not stripped).
# Gate requires >= 3: identity block, ingress-absent-by-default posture,
# secret-block managed-identity access.
# ---------------------------------------------------------------------------
SECURE_DEFAULT_COUNT="$(grep -c '# Secure default:' "$MODULE_DIR/main.tf" || true)"
if [[ "$SECURE_DEFAULT_COUNT" -ge 3 ]]; then
  pass "Assertion 4: >= 3 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
else
  fail "Assertion 4: fewer than 3 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Zero-match gates on comment-stripped content of all *.tf files
# (D-09/SC3 — the mechanical "no business logic survived" proof)
# These patterns must be absent from effective (non-comment) lines only.
# ---------------------------------------------------------------------------
ALL_EFFECTIVE="$(cat \
  "$MODULE_DIR/versions.tf" \
  "$MODULE_DIR/variables.tf" \
  "$MODULE_DIR/outputs.tf" \
  "$MODULE_DIR/main.tf" \
  | grep -vE '^\s*#')"

# 5a: No provider block (MOD-08)
PROVIDER_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE '^\s*provider\s+"' || true; })"
if [[ "$PROVIDER_COUNT" -eq 0 ]]; then
  pass "Assertion 5a: no provider block in module files (MOD-08)"
else
  fail "Assertion 5a: provider block found in module files (MOD-08, count=$PROVIDER_COUNT)"
fi

# 5b: No ignore_changes (MOD-08 — the source deployment's image-mutation lifecycle must
# not survive generalisation)
IGNORE_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'ignore_changes' || true; })"
if [[ "$IGNORE_COUNT" -eq 0 ]]; then
  pass "Assertion 5b: no ignore_changes in module files (MOD-08)"
else
  fail "Assertion 5b: ignore_changes found in module files (MOD-08, count=$IGNORE_COUNT)"
fi

# 5c: No ASPNETCORE_ env var names (SC3 — .NET-specific business logic must not survive)
ASPNETCORE_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'ASPNETCORE_' || true; })"
if [[ "$ASPNETCORE_COUNT" -eq 0 ]]; then
  pass "Assertion 5c: ASPNETCORE_ absent from effective lines (SC3)"
else
  fail "Assertion 5c: ASPNETCORE_ found in effective lines (SC3, count=$ASPNETCORE_COUNT)"
fi

# 5d: No DOTNET_ env var names (SC3 — .NET-specific business logic must not survive)
DOTNET_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'DOTNET_' || true; })"
if [[ "$DOTNET_COUNT" -eq 0 ]]; then
  pass "Assertion 5d: DOTNET_ absent from effective lines (SC3)"
else
  fail "Assertion 5d: DOTNET_ found in effective lines (SC3, count=$DOTNET_COUNT)"
fi

# 5e: No azurerm_role_assignment resource (D-06 — role assignments are caller-side composition
# enabled by the principal_id output; no CI/CD role assignments inside the module)
ROLE_ASSIGN_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'azurerm_role_assignment' || true; })"
if [[ "$ROLE_ASSIGN_COUNT" -eq 0 ]]; then
  pass "Assertion 5e: azurerm_role_assignment absent from effective lines (D-06)"
else
  fail "Assertion 5e: azurerm_role_assignment found in effective lines (D-06, count=$ROLE_ASSIGN_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 6: Zero checkov:skip annotations in raw content (SEC-05/D-09)
# Scan raw files — skip annotations ARE comments and must be absent.
# WR-01: group the grep with || true so wc -l gets the count not raw paths.
# ---------------------------------------------------------------------------
SKIP_COUNT="$({ grep -rl 'checkov:skip' "$MODULE_DIR"/ 2>/dev/null || true; } | wc -l | tr -d ' \t')"
if [[ "$SKIP_COUNT" -eq 0 ]]; then
  pass "Assertion 6: zero checkov:skip annotations in modules/container-app/ (SEC-05/D-09)"
else
  fail "Assertion 6: checkov:skip annotations found in modules/container-app/ (SEC-05/D-09, files=$SKIP_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 7: Description parity (MOD-05)
# Every variable and output must have a description line.
# ---------------------------------------------------------------------------
VAR_DECL_COUNT="$(grep -c '^variable "' "$MODULE_DIR/variables.tf" || true)"
VAR_DESC_COUNT="$(grep -cE '^\s*description\s*=' "$MODULE_DIR/variables.tf" || true)"
if [[ "$VAR_DECL_COUNT" -gt 0 && "$VAR_DECL_COUNT" -eq "$VAR_DESC_COUNT" ]]; then
  pass "Assertion 7a: variable/description count parity in variables.tf (MOD-05, count=$VAR_DECL_COUNT)"
else
  fail "Assertion 7a: variable/description mismatch in variables.tf (MOD-05, vars=$VAR_DECL_COUNT, descs=$VAR_DESC_COUNT)"
fi

OUT_DECL_COUNT="$(grep -c '^output "' "$MODULE_DIR/outputs.tf" || true)"
OUT_DESC_COUNT="$(grep -cE '^\s*description\s*=' "$MODULE_DIR/outputs.tf" || true)"
if [[ "$OUT_DECL_COUNT" -gt 0 && "$OUT_DECL_COUNT" -eq "$OUT_DESC_COUNT" ]]; then
  pass "Assertion 7b: output/description count parity in outputs.tf (MOD-05, count=$OUT_DECL_COUNT)"
else
  fail "Assertion 7b: output/description mismatch in outputs.tf (MOD-05, outputs=$OUT_DECL_COUNT, descs=$OUT_DESC_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 8: tags variable present (MOD-06)
# ---------------------------------------------------------------------------
if grep -q 'variable "tags"' "$MODULE_DIR/variables.tf" \
   && grep -q 'map(string)' "$MODULE_DIR/variables.tf"; then
  pass "Assertion 8: variable \"tags\" of type map(string) present in variables.tf (MOD-06)"
else
  fail "Assertion 8: variable \"tags\" or map(string) type missing from variables.tf (MOD-06)"
fi

# ---------------------------------------------------------------------------
# Assertion 9: Validation block count and nullable=false count (MOD-07/WR-02)
# Require >= 7 validations: name regex, revision_mode enum, cpu enum, memory enum,
# min_replicas range, max_replicas range, ingress null-safe transport, ingress
# null-safe target_port.
# Require >= 10 nullable=false: every defaulted variable except ingress (the
# documented null sentinel for "no ingress block rendered").
# ---------------------------------------------------------------------------
VALIDATION_COUNT="$(grep -c 'validation {' "$MODULE_DIR/variables.tf" || true)"
if [[ "$VALIDATION_COUNT" -ge 7 ]]; then
  pass "Assertion 9a: >= 7 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
else
  fail "Assertion 9a: fewer than 7 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
fi

NULLABLE_COUNT="$(grep -cE '^\s*nullable\s*=\s*false' "$MODULE_DIR/variables.tf" || true)"
if [[ "$NULLABLE_COUNT" -ge 10 ]]; then
  pass "Assertion 9b: >= 10 nullable = false lines in variables.tf (WR-02, count=$NULLABLE_COUNT)"
else
  fail "Assertion 9b: fewer than 10 nullable = false lines in variables.tf (WR-02, count=$NULLABLE_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 10: Required outputs exist and principal_id is wired to identity (D-04/SEC-03)
# ---------------------------------------------------------------------------
if grep -q 'output "container_app_id"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "container_app_name"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "principal_id"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "latest_revision_fqdn"' "$MODULE_DIR/outputs.tf"; then
  pass "Assertion 10a: all four contract outputs present in outputs.tf (D-04)"
else
  fail "Assertion 10a: one or more contract outputs missing from outputs.tf (D-04)"
fi

# 10b: principal_id is wired to the identity block (SEC-03 — the composition contract
# that enables caller-side role assignments without hardcoding a credential)
PRINCIPAL_ID_COUNT="$({ grep -cE 'identity\[0\]\.principal_id' "$MODULE_DIR/outputs.tf" || true; })"
if [[ "$PRINCIPAL_ID_COUNT" -ge 1 ]]; then
  pass "Assertion 10b: principal_id wired to identity[0].principal_id in outputs.tf (SEC-03)"
else
  fail "Assertion 10b: principal_id not wired to identity[0].principal_id in outputs.tf (SEC-03)"
fi

# ---------------------------------------------------------------------------
# Assertion 11: checkov live run (D-09/SEC-03)
# checkov 3.3.1 has ZERO checks targeting azurerm_container_app — the only
# container-resource checks target azurerm_container_registry and
# azurerm_container_group (a different, legacy resource). This was empirically
# verified against the installed checkov 3.3.1 package. Consequently:
# - The SKIP_LIST is EMPTY (no checks exist to skip)
# - No must-pass trio assertion is possible (no native checks exist to count)
# - The gate runs the full scan to fail loudly if a future checkov version
#   introduces azurerm_container_app checks that the module violates
# Do NOT add a Passed-checks-count assertion for this module.
# ---------------------------------------------------------------------------
CHECKOV_BIN="$(resolve_checkov)" || {
  fail "Assertion 11: checkov not found — install with: python -m pip install checkov"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
}

set +e
CHECKOV_FULL_OUT="$("$CHECKOV_BIN" -d "$MODULE_DIR" --framework terraform --compact --quiet 2>&1)"
CHECKOV_FULL_EXIT=$?
set -e

if [[ "$CHECKOV_FULL_EXIT" -eq 0 ]]; then
  pass "Assertion 11: checkov exits 0 on modules/container-app with empty skip list (no azurerm_container_app checks in 3.3.1 — zero native checks exist to fire)"
else
  fail "Assertion 11: checkov found failures in modules/container-app (unexpected — verify checkov version; 3.3.1 has zero azurerm_container_app checks)"
  echo "  checkov output:"
  echo "$CHECKOV_FULL_OUT" | head -40 | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Assertion 12: terraform fmt clean (works on Windows; validate does NOT)
# ---------------------------------------------------------------------------
set +e
FMT_OUT="$(terraform fmt -check -recursive "$MODULE_DIR" 2>&1)"
FMT_EXIT=$?
set -e

if [[ "$FMT_EXIT" -eq 0 ]]; then
  pass "Assertion 12: terraform fmt -check -recursive modules/container-app exits 0"
else
  fail "Assertion 12: terraform fmt check failed — run 'terraform fmt -recursive modules/container-app'"
  echo "  Unformatted files:"
  echo "$FMT_OUT" | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Assertion 13: ci.yml skip_check mirrors the current expected set (WR-03/CR-01)
# Container-app contributes ZERO skip IDs (no azurerm_container_app checks exist
# in checkov 3.3.1 — empirically verified). The expected set is EXACTLY:
# CKV2_AZURE_32 (key-vault) + the 10 storage-account IDs = 11 IDs total.
# This assertion is intentionally identical to the storage gate's expectation —
# it duplicates the check so drift fails BOTH gates loudly, and any future skip_check
# addition must be justified in a gate script before CI will accept it.
# Comparison is order/whitespace-normalised (IDs split one per line, sorted);
# tr -d '\r' guards against CRLF checkouts.
# ---------------------------------------------------------------------------
STORAGE_SKIP_LIST="CKV_AZURE_35,CKV_AZURE_59,CKV_AZURE_206,CKV2_AZURE_1,CKV2_AZURE_33,CKV2_AZURE_40,CKV2_AZURE_41,CKV2_AZURE_21,CKV_AZURE_33,CKV_AZURE_36"

CI_SKIPS_RAW="$({ grep -E '^[[:space:]]*skip_check:' "$REPO_ROOT/.github/workflows/ci.yml" || true; } | tr -d '\r' | sed -E 's/^[[:space:]]*skip_check:[[:space:]]*//')"
CI_SKIPS_NORM="$(echo "$CI_SKIPS_RAW" | tr ',' '\n' | sed -E 's/[[:space:]]+//g' | { grep -v '^$' || true; } | sort)"
GATE_SKIPS_NORM="$(echo "CKV2_AZURE_32,$STORAGE_SKIP_LIST" | tr ',' '\n' | sed -E 's/[[:space:]]+//g' | { grep -v '^$' || true; } | sort)"

if [[ -n "$CI_SKIPS_NORM" && "$CI_SKIPS_NORM" == "$GATE_SKIPS_NORM" ]]; then
  pass "Assertion 13: ci.yml skip_check matches expected 11-ID set (key-vault + storage; container-app adds zero IDs) (WR-03/CR-01)"
else
  fail "Assertion 13: ci.yml skip_check has drifted from expected 11-ID set (WR-03/CR-01)"
  echo "  ci.yml skip_check: ${CI_SKIPS_RAW:-<no skip_check line found>}"
  echo "  gate expectation:  CKV2_AZURE_32,$STORAGE_SKIP_LIST"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [[ "$FAIL_COUNT" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
