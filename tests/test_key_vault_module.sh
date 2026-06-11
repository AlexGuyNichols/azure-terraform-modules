#!/usr/bin/env bash
# Static security gate for modules/key-vault.
# Mirrors test_sanitise.sh style: set -euo pipefail, PASS/FAIL helpers, exit-code discipline.
# RED: exits non-zero when modules/key-vault/ is absent.
# GREEN: exits 0 when the module satisfies all assertions below.
#
# NON-NEGOTIABLE: this file must never contain a literal UUID-shaped string
# or real private name. Runtime synthesis is used where needed.
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
MODULE_DIR="$REPO_ROOT/modules/key-vault"

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Resolve checkov binary
# resolve_checkov: prints the path to a working checkov; exits 1 if not found.
# ---------------------------------------------------------------------------
resolve_checkov() {
  if command -v checkov > /dev/null 2>&1; then
    echo "checkov"
    return 0
  fi
  local venv_checkov="$HOME/.venv-checkov/Scripts/checkov"
  if [[ -x "$venv_checkov" ]]; then
    echo "$venv_checkov"
    return 0
  fi
  echo "ERROR: checkov not found. Install with: python -m pip install checkov" >&2
  return 1
}

# ---------------------------------------------------------------------------
# Assertion 1: Required module files exist
# ---------------------------------------------------------------------------
MISSING_FILE=""
for f in versions.tf variables.tf outputs.tf main.tf; do
  if [[ ! -f "$MODULE_DIR/$f" ]]; then
    MISSING_FILE="modules/key-vault/$f"
    break
  fi
done

if [[ -n "$MISSING_FILE" ]]; then
  fail "Assertion 1: required file missing — $MISSING_FILE (modules/key-vault does not exist or is incomplete)"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi
pass "Assertion 1: all four module files exist (versions.tf, variables.tf, outputs.tf, main.tf)"

# ---------------------------------------------------------------------------
# Assertion 2: versions.tf carries library-standard constraints (MOD-04)
# ---------------------------------------------------------------------------
if grep -qE 'required_version\s*=\s*">= 1\.5"' "$MODULE_DIR/versions.tf" \
   && grep -qE '">= 4\.0, < 5\.0"' "$MODULE_DIR/versions.tf"; then
  pass "Assertion 2: versions.tf has required_version >= 1.5 and azurerm >= 4.0, < 5.0 (MOD-04)"
else
  fail "Assertion 2: versions.tf missing library-standard constraints (MOD-04)"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Effective-line checks on main.tf (comment-stripped)
# Strip comment lines before asserting to avoid matching commented-out code.
# ---------------------------------------------------------------------------
EFFECTIVE_MAIN="$(grep -vE '^\s*#' "$MODULE_DIR/main.tf")"

# 3a: rbac_authorization_enabled = true (D-12 — hardcoded)
if echo "$EFFECTIVE_MAIN" | grep -qE 'rbac_authorization_enabled\s*=\s*true'; then
  pass "Assertion 3a: rbac_authorization_enabled = true present in main.tf (D-12)"
else
  fail "Assertion 3a: rbac_authorization_enabled = true missing from main.tf (D-12)"
fi

# 3b: network_acls block physically present (CKV_AZURE_109)
if echo "$EFFECTIVE_MAIN" | grep -qE 'network_acls\s*\{'; then
  pass "Assertion 3b: network_acls block present in main.tf (CKV_AZURE_109)"
else
  fail "Assertion 3b: network_acls block missing from main.tf (CKV_AZURE_109)"
fi

# 3c: purge_protection_enabled wired to variable
if echo "$EFFECTIVE_MAIN" | grep -qE 'purge_protection_enabled\s*=\s*var\.purge_protection_enabled'; then
  pass "Assertion 3c: purge_protection_enabled = var.purge_protection_enabled in main.tf"
else
  fail "Assertion 3c: purge_protection_enabled not wired to variable in main.tf"
fi

# 3d: data "azurerm_client_config" "current" data source present (D-04)
if echo "$EFFECTIVE_MAIN" | grep -qE 'data\s+"azurerm_client_config"\s+"current"'; then
  pass "Assertion 3d: data.azurerm_client_config.current data source present (D-04)"
else
  fail "Assertion 3d: data.azurerm_client_config.current data source missing (D-04)"
fi

# 3e: role assignment scoped to vault (D-01)
if echo "$EFFECTIVE_MAIN" | grep -qE 'scope\s*=\s*azurerm_key_vault\.main\.id'; then
  pass "Assertion 3e: azurerm_role_assignment.main scoped to azurerm_key_vault.main.id (D-01)"
else
  fail "Assertion 3e: role assignment scope missing or not set to azurerm_key_vault.main.id (D-01)"
fi

# 3f: tenant_id from data source (D-04 — no tenant UUID ever in HCL)
if echo "$EFFECTIVE_MAIN" | grep -qE 'tenant_id\s*=\s*data\.azurerm_client_config\.current\.tenant_id'; then
  pass "Assertion 3f: tenant_id = data.azurerm_client_config.current.tenant_id (D-04)"
else
  fail "Assertion 3f: tenant_id not sourced from data.azurerm_client_config.current (D-04)"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Secure default comment count (SEC-04)
# Note: this gate intentionally counts comment lines (not stripped).
# ---------------------------------------------------------------------------
SECURE_DEFAULT_COUNT="$(grep -c '# Secure default:' "$MODULE_DIR/main.tf" || true)"
if [[ "$SECURE_DEFAULT_COUNT" -ge 4 ]]; then
  pass "Assertion 4: >= 4 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
else
  fail "Assertion 4: fewer than 4 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Zero-match gates on comment-stripped content of all *.tf files
# These must be absent from effective (non-comment) lines only.
# ---------------------------------------------------------------------------
ALL_EFFECTIVE="$(cat \
  "$MODULE_DIR/versions.tf" \
  "$MODULE_DIR/variables.tf" \
  "$MODULE_DIR/outputs.tf" \
  "$MODULE_DIR/main.tf" \
  | grep -vE '^\s*#')"

# 5a: No provider block (MOD-08)
PROVIDER_COUNT="$(echo "$ALL_EFFECTIVE" | grep -cE '^\s*provider\s+"' || true)"
if [[ "$PROVIDER_COUNT" -eq 0 ]]; then
  pass "Assertion 5a: no provider block in module files (MOD-08)"
else
  fail "Assertion 5a: provider block found in module files (MOD-08, count=$PROVIDER_COUNT)"
fi

# 5b: No ignore_changes (MOD-08)
IGNORE_COUNT="$(echo "$ALL_EFFECTIVE" | grep -cE 'ignore_changes' || true)"
if [[ "$IGNORE_COUNT" -eq 0 ]]; then
  pass "Assertion 5b: no ignore_changes in module files (MOD-08)"
else
  fail "Assertion 5b: ignore_changes found in module files (MOD-08, count=$IGNORE_COUNT)"
fi

# 5c: No azurerm_key_vault_secret resource (vault-only, D-05/D-06)
SECRET_COUNT="$(echo "$ALL_EFFECTIVE" | grep -cE 'azurerm_key_vault_secret' || true)"
if [[ "$SECRET_COUNT" -eq 0 ]]; then
  pass "Assertion 5c: no azurerm_key_vault_secret in module files (vault-only, D-05)"
else
  fail "Assertion 5c: azurerm_key_vault_secret found in module files (vault-only D-05, count=$SECRET_COUNT)"
fi

# 5d: No tenant_id variable (D-04 — tenant from data source, not variable)
TENANT_VAR_COUNT="$(echo "$ALL_EFFECTIVE" | grep -cE 'variable\s+"tenant_id"' || true)"
if [[ "$TENANT_VAR_COUNT" -eq 0 ]]; then
  pass "Assertion 5d: no variable \"tenant_id\" in module files (D-04)"
else
  fail "Assertion 5d: variable \"tenant_id\" found in module files (D-04, count=$TENANT_VAR_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 6: Zero checkov:skip annotations in raw content (SEC-05)
# Scan raw files (not stripped) — skip annotations ARE comments and must be absent.
# ---------------------------------------------------------------------------
SKIP_COUNT="$(grep -rl 'checkov:skip' "$MODULE_DIR"/ 2>/dev/null | wc -l | tr -d ' \t')"
if [[ "$SKIP_COUNT" -eq 0 ]]; then
  pass "Assertion 6: zero checkov:skip annotations in modules/key-vault/ (SEC-05)"
else
  fail "Assertion 6: checkov:skip annotations found in modules/key-vault/ (SEC-05, files_with_skips=$SKIP_COUNT)"
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
# Assertion 9: Validation block count (MOD-07)
# Require >= 4: sku_name enum, retention range, network_acls bypass enum,
# network_acls default_action enum.
# ---------------------------------------------------------------------------
VALIDATION_COUNT="$(grep -c 'validation {' "$MODULE_DIR/variables.tf" || true)"
if [[ "$VALIDATION_COUNT" -ge 4 ]]; then
  pass "Assertion 9: >= 4 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
else
  fail "Assertion 9: fewer than 4 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 10: Required outputs exist
# ---------------------------------------------------------------------------
if grep -q 'output "key_vault_id"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "key_vault_uri"' "$MODULE_DIR/outputs.tf"; then
  pass "Assertion 10: outputs key_vault_id and key_vault_uri both present (contract outputs)"
else
  fail "Assertion 10: one or both required outputs missing from outputs.tf (key_vault_id, key_vault_uri)"
fi

# ---------------------------------------------------------------------------
# Assertion 11: checkov passes CKV_AZURE_42, CKV_AZURE_109, CKV_AZURE_110, CKV_AZURE_189
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
  pass "Assertion 11a: checkov passes all checks on modules/key-vault (SEC-01)"
else
  fail "Assertion 11a: checkov found failures in modules/key-vault (SEC-01)"
  echo "  checkov output:"
  echo "$CHECKOV_FULL_OUT" | head -40 | sed 's/^/    /'
fi

set +e
CHECKOV_SPECIFIC_OUT="$("$CHECKOV_BIN" -d "$MODULE_DIR" --framework terraform --compact --quiet --check CKV_AZURE_42,CKV_AZURE_109,CKV_AZURE_110,CKV_AZURE_189 2>&1)"
CHECKOV_SPECIFIC_EXIT=$?
set -e

if [[ "$CHECKOV_SPECIFIC_EXIT" -eq 0 ]]; then
  pass "Assertion 11b: checkov CKV_AZURE_42, CKV_AZURE_109, CKV_AZURE_110, CKV_AZURE_189 all pass (SEC-01)"
else
  fail "Assertion 11b: one or more of CKV_AZURE_42/CKV_AZURE_109/CKV_AZURE_110/CKV_AZURE_189 failed"
  echo "  checkov output:"
  echo "$CHECKOV_SPECIFIC_OUT" | head -40 | sed 's/^/    /'
fi

# ---------------------------------------------------------------------------
# Assertion 12: terraform fmt clean (works on Windows; validate does NOT)
# ---------------------------------------------------------------------------
set +e
FMT_OUT="$(terraform fmt -check -recursive "$MODULE_DIR" 2>&1)"
FMT_EXIT=$?
set -e

if [[ "$FMT_EXIT" -eq 0 ]]; then
  pass "Assertion 12: terraform fmt -check -recursive modules/key-vault exits 0"
else
  fail "Assertion 12: terraform fmt check failed — run 'terraform fmt -recursive modules/key-vault'"
  echo "  Unformatted files:"
  echo "$FMT_OUT" | sed 's/^/    /'
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
