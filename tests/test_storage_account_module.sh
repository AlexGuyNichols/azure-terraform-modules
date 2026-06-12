#!/usr/bin/env bash
# Static security gate for modules/storage-account.
# Mirrors test_key_vault_module.sh style: set -euo pipefail, PASS/FAIL helpers,
# resolve_checkov, WR-01 grouped-fallback counting, early-exit on missing files.
# RED:   exits non-zero when modules/storage-account/ is absent.
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
MODULE_DIR="$REPO_ROOT/modules/storage-account"

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
    MISSING_FILE="modules/storage-account/$f"
    break
  fi
done

if [[ -n "$MISSING_FILE" ]]; then
  fail "Assertion 1: required file missing — $MISSING_FILE (modules/storage-account does not exist or is incomplete)"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
fi
pass "Assertion 1: all four module files exist (versions.tf, variables.tf, outputs.tf, main.tf)"

# ---------------------------------------------------------------------------
# Assertion 2: versions.tf carries library-standard constraints (MOD-04/D-12)
# Floor is >= 4.9 — best-evidence: storage_account_id on azurerm_storage_container
# (the 4.x attribute replacing deprecated storage_account_name) is documented as
# available from v4.9. Honest floor is init-time resolution error vs plan-time unknown.
# ---------------------------------------------------------------------------
if grep -qE 'required_version\s*=\s*">= 1\.5"' "$MODULE_DIR/versions.tf" \
   && grep -qE '">= 4\.9, < 5\.0"' "$MODULE_DIR/versions.tf"; then
  pass "Assertion 2: versions.tf has required_version >= 1.5 and azurerm >= 4.9, < 5.0 (MOD-04/D-12)"
else
  fail "Assertion 2: versions.tf missing library-standard constraints (MOD-04/D-12)"
fi

# ---------------------------------------------------------------------------
# Assertion 3: Effective-line checks on main.tf (comment-stripped)
# Strip comment lines before asserting to avoid matching commented-out code.
# ---------------------------------------------------------------------------
EFFECTIVE_MAIN="$(grep -vE '^\s*#' "$MODULE_DIR/main.tf")"

# 3a: https_traffic_only_enabled = true (D-05 — plaintext HTTP rejected at platform edge)
if echo "$EFFECTIVE_MAIN" | grep -qE 'https_traffic_only_enabled\s*=\s*true'; then
  pass "Assertion 3a: https_traffic_only_enabled = true present in main.tf (D-05)"
else
  fail "Assertion 3a: https_traffic_only_enabled = true missing from main.tf (D-05)"
fi

# 3b: min_tls_version = "TLS1_2" (D-05)
if echo "$EFFECTIVE_MAIN" | grep -qE 'min_tls_version\s*=\s*"TLS1_2"'; then
  pass "Assertion 3b: min_tls_version = \"TLS1_2\" present in main.tf (D-05)"
else
  fail "Assertion 3b: min_tls_version = \"TLS1_2\" missing from main.tf (D-05)"
fi

# 3c: allow_nested_items_to_be_public = false (D-05 — anonymous blob access off)
if echo "$EFFECTIVE_MAIN" | grep -qE 'allow_nested_items_to_be_public\s*=\s*false'; then
  pass "Assertion 3c: allow_nested_items_to_be_public = false present in main.tf (D-05)"
else
  fail "Assertion 3c: allow_nested_items_to_be_public = false missing from main.tf (D-05)"
fi

# 3d: versioning_enabled wired to variable (D-06)
if echo "$EFFECTIVE_MAIN" | grep -qE 'versioning_enabled\s*=\s*var\.blob_versioning_enabled'; then
  pass "Assertion 3d: versioning_enabled = var.blob_versioning_enabled present in main.tf (D-06)"
else
  fail "Assertion 3d: versioning_enabled = var.blob_versioning_enabled missing from main.tf (D-06)"
fi

# 3e: delete_retention_policy block present (D-08)
if echo "$EFFECTIVE_MAIN" | grep -qE 'delete_retention_policy\s*\{'; then
  pass "Assertion 3e: delete_retention_policy block present in main.tf (D-08)"
else
  fail "Assertion 3e: delete_retention_policy block missing from main.tf (D-08)"
fi

# 3f: container_delete_retention_policy block present (D-08)
if echo "$EFFECTIVE_MAIN" | grep -qE 'container_delete_retention_policy\s*\{'; then
  pass "Assertion 3f: container_delete_retention_policy block present in main.tf (D-08)"
else
  fail "Assertion 3f: container_delete_retention_policy block missing from main.tf (D-08)"
fi

# 3g: public_network_access_enabled wired to variable (D-07)
if echo "$EFFECTIVE_MAIN" | grep -qE 'public_network_access_enabled\s*=\s*var\.public_network_access_enabled'; then
  pass "Assertion 3g: public_network_access_enabled = var.public_network_access_enabled in main.tf (D-07)"
else
  fail "Assertion 3g: public_network_access_enabled not wired to variable in main.tf (D-07)"
fi

# 3h: dynamic network_rules block present (D-07 — block renders only when caller supplies it)
if echo "$EFFECTIVE_MAIN" | grep -qE 'dynamic\s+"network_rules"'; then
  pass "Assertion 3h: dynamic \"network_rules\" block present in main.tf (D-07)"
else
  fail "Assertion 3h: dynamic \"network_rules\" block missing from main.tf (D-07)"
fi

# 3i: container_access_type hardcoded to private (D-03)
if echo "$EFFECTIVE_MAIN" | grep -qE 'container_access_type\s*=\s*"private"'; then
  pass "Assertion 3i: container_access_type = \"private\" hardcoded in main.tf (D-03)"
else
  fail "Assertion 3i: container_access_type = \"private\" missing from main.tf (D-03)"
fi

# 3j: storage_account_id used for container wiring (4.x path — NOT deprecated storage_account_name)
if echo "$EFFECTIVE_MAIN" | grep -qE 'storage_account_id\s*=\s*azurerm_storage_account\.main\.id'; then
  pass "Assertion 3j: storage_account_id = azurerm_storage_account.main.id in container resource (4.x path)"
else
  fail "Assertion 3j: storage_account_id = azurerm_storage_account.main.id missing from main.tf (4.x path)"
fi

# ---------------------------------------------------------------------------
# Assertion 4: Secure default comment count (SEC-04)
# This gate intentionally counts comment lines (not stripped).
# Gate requires >= 5 (D-05 trio + versioning + container access).
# ---------------------------------------------------------------------------
SECURE_DEFAULT_COUNT="$(grep -c '# Secure default:' "$MODULE_DIR/main.tf" || true)"
if [[ "$SECURE_DEFAULT_COUNT" -ge 5 ]]; then
  pass "Assertion 4: >= 5 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
else
  fail "Assertion 4: fewer than 5 '# Secure default:' comments in main.tf (SEC-04, count=$SECURE_DEFAULT_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 5: Zero-match gates on comment-stripped content of all *.tf files
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

# 5b: No ignore_changes (MOD-08)
IGNORE_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'ignore_changes' || true; })"
if [[ "$IGNORE_COUNT" -eq 0 ]]; then
  pass "Assertion 5b: no ignore_changes in module files (MOD-08)"
else
  fail "Assertion 5b: ignore_changes found in module files (MOD-08, count=$IGNORE_COUNT)"
fi

# 5c: No deprecated enable_https_traffic_only (D-12 honest naming — 4.x renamed to https_traffic_only_enabled)
DEPRECATED_HTTPS_COUNT="$({ echo "$ALL_EFFECTIVE" | grep -cE 'enable_https_traffic_only' || true; })"
if [[ "$DEPRECATED_HTTPS_COUNT" -eq 0 ]]; then
  pass "Assertion 5c: deprecated enable_https_traffic_only absent from effective lines (D-12)"
else
  fail "Assertion 5c: deprecated enable_https_traffic_only found in effective lines (D-12, count=$DEPRECATED_HTTPS_COUNT)"
fi

# 5d: No deprecated storage_account_name container argument (scoped to main.tf only —
# outputs.tf legitimately has output "storage_account_name")
EFFECTIVE_MAIN_ONLY="$(grep -vE '^\s*#' "$MODULE_DIR/main.tf")"
DEPRECATED_SA_NAME_COUNT="$({ echo "$EFFECTIVE_MAIN_ONLY" | grep -cE 'storage_account_name\s*=' || true; })"
if [[ "$DEPRECATED_SA_NAME_COUNT" -eq 0 ]]; then
  pass "Assertion 5d: deprecated storage_account_name = absent from main.tf effective lines (4.x path)"
else
  fail "Assertion 5d: deprecated storage_account_name = found in main.tf effective lines (count=$DEPRECATED_SA_NAME_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 6: Zero checkov:skip annotations in raw content (SEC-05/D-09)
# Scan raw files — skip annotations ARE comments and must be absent.
# WR-01: group the grep with || true so wc -l gets the count not raw paths.
# ---------------------------------------------------------------------------
SKIP_COUNT="$({ grep -rl 'checkov:skip' "$MODULE_DIR"/ 2>/dev/null || true; } | wc -l | tr -d ' \t')"
if [[ "$SKIP_COUNT" -eq 0 ]]; then
  pass "Assertion 6: zero checkov:skip annotations in modules/storage-account/ (SEC-05/D-09)"
else
  fail "Assertion 6: checkov:skip annotations found in modules/storage-account/ (SEC-05/D-09, files=$SKIP_COUNT)"
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
# Require >= 6 validations: name regex, account_tier enum, replication enum,
# two retention ranges 1-365, network_rules null-safe ternary validations.
# Require >= 9 nullable=false: every defaulted variable except network_rules.
# ---------------------------------------------------------------------------
VALIDATION_COUNT="$(grep -c 'validation {' "$MODULE_DIR/variables.tf" || true)"
if [[ "$VALIDATION_COUNT" -ge 6 ]]; then
  pass "Assertion 9a: >= 6 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
else
  fail "Assertion 9a: fewer than 6 validation blocks in variables.tf (MOD-07, count=$VALIDATION_COUNT)"
fi

NULLABLE_COUNT="$(grep -cE '^\s*nullable\s*=\s*false' "$MODULE_DIR/variables.tf" || true)"
if [[ "$NULLABLE_COUNT" -ge 9 ]]; then
  pass "Assertion 9b: >= 9 nullable = false lines in variables.tf (WR-02, count=$NULLABLE_COUNT)"
else
  fail "Assertion 9b: fewer than 9 nullable = false lines in variables.tf (WR-02, count=$NULLABLE_COUNT)"
fi

# ---------------------------------------------------------------------------
# Assertion 10: Required outputs exist and primary_access_key is sensitive (D-04/SEC-02)
# ---------------------------------------------------------------------------
if grep -q 'output "storage_account_id"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "storage_account_name"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "primary_blob_endpoint"' "$MODULE_DIR/outputs.tf" \
   && grep -q 'output "primary_access_key"' "$MODULE_DIR/outputs.tf"; then
  pass "Assertion 10a: all four contract outputs present in outputs.tf (D-04)"
else
  fail "Assertion 10a: one or more contract outputs missing from outputs.tf (D-04)"
fi

SENSITIVE_COUNT="$({ grep -A5 'output "primary_access_key"' "$MODULE_DIR/outputs.tf" | grep -cE 'sensitive\s*=\s*true' || true; })"
if [[ "$SENSITIVE_COUNT" -ge 1 ]]; then
  pass "Assertion 10b: primary_access_key output is marked sensitive = true (SEC-02/D-04)"
else
  fail "Assertion 10b: primary_access_key output missing sensitive = true (SEC-02/D-04)"
fi

# ---------------------------------------------------------------------------
# Assertion 11: checkov live run (D-09/SEC-02)
# 11a: Full scan with justified command-level skips exits 0.
# 11b: Must-pass trio CKV_AZURE_3/44/190 exits 0 — these IDs must NEVER be skipped.
# ---------------------------------------------------------------------------
CHECKOV_BIN="$(resolve_checkov)" || {
  fail "Assertion 11: checkov not found — install with: python -m pip install checkov"
  echo ""
  echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
  exit 1
}

# Justified skip list (D-09) — one-line rationale per ID:
# CKV_AZURE_35:   public_network_access_enabled defaults true — deliberate divergence per D-07
#                 (remote-state accounts must be reachable by CI/dev machines; README documents)
# CKV_AZURE_59:   same D-07 rationale — default-reachable storage, firewall is caller's choice
# CKV_AZURE_206:  LRS is the cost-aware default per D-02; callers opt up via validated enum
# CKV2_AZURE_1:   CMK (customer-managed key) is caller-side composition, not module responsibility
# CKV2_AZURE_33:  private endpoint is caller-side infrastructure (mirrors key-vault CKV2_AZURE_32)
# CKV2_AZURE_40:  shared-key auth is the remote-state consumption path; variable lets callers disable
# CKV2_AZURE_41:  SAS expiration policy — module issues no SAS tokens
# CKV2_AZURE_21:  blob logging — diagnostic settings are caller-side monitoring composition
# CKV_AZURE_33:   queue logging — module manages blob workloads only; drop if check does not fire
# CKV_AZURE_36:   trusted Microsoft services bypass — only meaningful when a network_rules block
#                 is rendered; when network_rules = null (no block) the check fires spuriously;
#                 when the caller supplies network_rules, bypass defaults to AzureServices
SKIP_LIST="CKV_AZURE_35,CKV_AZURE_59,CKV_AZURE_206,CKV2_AZURE_1,CKV2_AZURE_33,CKV2_AZURE_40,CKV2_AZURE_41,CKV2_AZURE_21,CKV_AZURE_33,CKV_AZURE_36"

set +e
CHECKOV_FULL_OUT="$("$CHECKOV_BIN" -d "$MODULE_DIR" --framework terraform --compact --quiet --skip-check "$SKIP_LIST" 2>&1)"
CHECKOV_FULL_EXIT=$?
set -e

if [[ "$CHECKOV_FULL_EXIT" -eq 0 ]]; then
  pass "Assertion 11a: checkov passes all checks on modules/storage-account with justified skips (D-09)"
else
  fail "Assertion 11a: checkov found failures in modules/storage-account"
  echo "  checkov output:"
  echo "$CHECKOV_FULL_OUT" | head -40 | sed 's/^/    /'
fi

# Must-pass trio — CKV_AZURE_3, CKV_AZURE_44, CKV_AZURE_190 NEVER skipped (SEC-02)
set +e
CHECKOV_SPECIFIC_OUT="$("$CHECKOV_BIN" -d "$MODULE_DIR" --framework terraform --compact --quiet --check CKV_AZURE_3,CKV_AZURE_44,CKV_AZURE_190 2>&1)"
CHECKOV_SPECIFIC_EXIT=$?
set -e

if [[ "$CHECKOV_SPECIFIC_EXIT" -eq 0 ]]; then
  pass "Assertion 11b: checkov CKV_AZURE_3, CKV_AZURE_44, CKV_AZURE_190 all pass natively (SEC-02 must-pass trio)"
else
  fail "Assertion 11b: one or more of CKV_AZURE_3/CKV_AZURE_44/CKV_AZURE_190 failed — fix main.tf, never skip"
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
  pass "Assertion 12: terraform fmt -check -recursive modules/storage-account exits 0"
else
  fail "Assertion 12: terraform fmt check failed — run 'terraform fmt -recursive modules/storage-account'"
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
