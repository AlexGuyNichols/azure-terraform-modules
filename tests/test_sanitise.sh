#!/usr/bin/env bash
# Behavioral test harness for scripts/sanitise.sh
# Plain bash + git only — no test framework required (D-05, D-13 minimalism).
# Runs from any CWD on Git Bash (Windows) and Ubuntu (CI).
#
# NON-NEGOTIABLE (T-01-04): this file must never contain a literal UUID-shaped
# string or real private name. All such values are synthesised at runtime.
set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"
SWEEP="$REPO_ROOT/scripts/sanitise.sh"

# ---------------------------------------------------------------------------
# Result tracking
# ---------------------------------------------------------------------------
PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ---------------------------------------------------------------------------
# Fixture helpers
# ---------------------------------------------------------------------------

# Build a minimal fixture git repo in a temp dir.
# Usage: make_fixture_repo
# Sets global FIXTURE_DIR.
FIXTURE_DIR=""
make_fixture_repo() {
  FIXTURE_DIR="$(mktemp -d)"
  git -C "$FIXTURE_DIR" init -q
  # Fixture .gitignore that mirrors the real repo (pattern file must not be
  # in scope or it would self-match)
  echo "scripts/.private-patterns" > "$FIXTURE_DIR/.gitignore"
  git -C "$FIXTURE_DIR" add .gitignore
}

# Write a fixture private-patterns file into the fixture repo.
# Usage: make_pattern_file [pattern...]
# Creates scripts/.private-patterns with the given patterns (one per line).
make_pattern_file() {
  mkdir -p "$FIXTURE_DIR/scripts"
  {
    echo "# Fixture private patterns"
    for p in "$@"; do
      echo "$p"
    done
  } > "$FIXTURE_DIR/scripts/.private-patterns"
  # The pattern file is gitignored — do NOT git add it.
}

# Stage (git add) a file inside the fixture repo.
stage_file() {
  git -C "$FIXTURE_DIR" add "$1"
}

# Run the sweep inside the fixture dir.
# Captures stdout, stderr, exit code into globals.
SWEEP_STDOUT=""
SWEEP_STDERR=""
SWEEP_EXIT=0
run_sweep() {
  SWEEP_STDOUT=""
  SWEEP_STDERR=""
  SWEEP_EXIT=0
  set +e
  SWEEP_STDOUT=$(cd "$FIXTURE_DIR" && bash "$SWEEP" 2>/tmp/sweep_stderr_$$.txt)
  SWEEP_EXIT=$?
  SWEEP_STDERR=$(cat /tmp/sweep_stderr_$$.txt 2>/dev/null || true)
  rm -f /tmp/sweep_stderr_$$.txt
  set -e
}

# Clean up fixture after each test.
cleanup_fixture() {
  if [[ -n "${FIXTURE_DIR:-}" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
    FIXTURE_DIR=""
  fi
}

# Ensure cleanup on EXIT.
trap 'cleanup_fixture' EXIT

# ---------------------------------------------------------------------------
# Runtime UUID synthesis (T-01-04)
# The printf format strings below are NOT UUID-shaped themselves.
# Low hex: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
# High HEX: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
# ---------------------------------------------------------------------------
make_lower_uuid() {
  printf '%08x-%04x-%04x-%04x-%012x' \
    $((RANDOM * RANDOM % 0xffffffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM * RANDOM * RANDOM % 0xffffffffffff))
}

make_upper_uuid() {
  printf '%08X-%04X-%04X-%04X-%012X' \
    $((RANDOM * RANDOM % 0xffffffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM % 0xffff)) \
    $((RANDOM * RANDOM * RANDOM % 0xffffffffffff))
}

# ---------------------------------------------------------------------------
# Test 1: Missing pattern file → exit 1, stderr contains "not found"
# ---------------------------------------------------------------------------
make_fixture_repo
# Deliberately do NOT create scripts/.private-patterns
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDERR" | grep -qi "not found"; then
  pass "Test 1: missing pattern file → exit 1 + stderr 'not found'"
else
  fail "Test 1: missing pattern file → exit 1 + stderr 'not found' (exit=$SWEEP_EXIT stderr='$SWEEP_STDERR')"
fi

# ---------------------------------------------------------------------------
# Test 2: Pattern file with only comment/blank lines → exit 1
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file
# Pattern file has only the comment line (added by make_pattern_file with no args)
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]]; then
  pass "Test 2: zero-effective-line pattern file → exit 1"
else
  fail "Test 2: zero-effective-line pattern file → exit 1 (exit=$SWEEP_EXIT)"
fi

# ---------------------------------------------------------------------------
# Test 3: Clean fixture tree → exit 0, stdout contains OK line
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
# Stage a clean file (no private identifiers)
echo "resource: safe content only" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -eq 0 ]] && echo "$SWEEP_STDOUT" | grep -q "OK: sanitisation sweep passed (0 hits)."; then
  pass "Test 3: clean tree → exit 0 + OK message"
else
  fail "Test 3: clean tree → exit 0 + OK message (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 4: Staged file with runtime-synthesized lowercase UUID
#          → exit 1, stdout contains "(generic pattern #1)" and file path
#          → stdout does NOT contain the UUID string itself
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
LOWER_UUID="$(make_lower_uuid)"
echo "tenant = $LOWER_UUID" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] \
   && echo "$SWEEP_STDOUT" | grep -q "(generic pattern #1)" \
   && echo "$SWEEP_STDOUT" | grep -q "main.tf" \
   && ! echo "$SWEEP_STDOUT" | grep -qF "$LOWER_UUID"; then
  pass "Test 4: lowercase UUID hit → exit 1, HIT line present, UUID not echoed"
else
  fail "Test 4: lowercase UUID hit (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 5: Staged file with runtime-synthesized uppercase UUID → exit 1
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
UPPER_UUID="$(make_upper_uuid)"
echo "tenant = $UPPER_UUID" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(generic pattern #1)"; then
  pass "Test 5: uppercase UUID hit → exit 1 (case-insensitive matching)"
else
  fail "Test 5: uppercase UUID hit (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 6: Staged file containing dummy name zzprivateorgzz
#          → exit 1, stdout contains "(private pattern #1)"
#          → stdout does NOT contain "zzprivateorgzz"
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] \
   && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)" \
   && ! echo "$SWEEP_STDOUT" | grep -qi "zzprivateorgzz"; then
  pass "Test 6: private name hit → exit 1, HIT line present, name not echoed"
else
  fail "Test 6: private name hit (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 7: Staged file containing ZZPRIVATEORGZZ with lowercase pattern
#          → exit 1 (case-insensitive matching, D-08)
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
echo "org: ZZPRIVATEORGZZ" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)"; then
  pass "Test 7: uppercase variant of private name → exit 1 (D-08 case-insensitive)"
else
  fail "Test 7: uppercase variant of private name (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 8: UNTRACKED (never git-added), not-ignored file containing zzprivateorgzz
#          → exit 1 (D-04: git ls-files --others --exclude-standard catches it)
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
# Write the file but do NOT stage it
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/untracked.tf"
# Verify it is truly untracked (not ignored)
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]]; then
  pass "Test 8: untracked not-ignored file with private name → exit 1 (D-04)"
else
  fail "Test 8: untracked not-ignored file with private name (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 9: gitignored file containing zzprivateorgzz → exit 0 (out of scope)
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
# Add the file to .gitignore inside the fixture
echo "ignored-secret.tf" >> "$FIXTURE_DIR/.gitignore"
git -C "$FIXTURE_DIR" add .gitignore
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/ignored-secret.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -eq 0 ]]; then
  pass "Test 9: gitignored file with private name → exit 0 (out of scope by design)"
else
  fail "Test 9: gitignored file with private name (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 10: Hit planted on a known line number N → stdout contains ":N " for that file
#           (real line numbers reported, not grep sequence numbers)
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
# Plant the hit on line 3 exactly
printf 'line one\nline two\norg: zzprivateorgzz\nline four\n' > "$FIXTURE_DIR/numbered.tf"
stage_file "numbered.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "numbered.tf:3"; then
  pass "Test 10: hit on line 3 → stdout contains 'numbered.tf:3' (real line numbers)"
else
  fail "Test 10: real line number reported (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 11 (CR-03): Pattern file WITHOUT a trailing newline → the final (only)
#           pattern must still be swept. read returns non-zero on the last
#           line of such a file; the loop must not silently drop it.
# ---------------------------------------------------------------------------
make_fixture_repo
mkdir -p "$FIXTURE_DIR/scripts"
# printf with no trailing \n after the pattern — editors routinely save this.
printf '# Fixture private patterns\n%s' "zzprivateorgzz" > "$FIXTURE_DIR/scripts/.private-patterns"
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)"; then
  pass "Test 11: pattern file without trailing newline → last pattern still swept (CR-03)"
else
  fail "Test 11: pattern file without trailing newline (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 12 (CR-04): CRLF-encoded pattern file → patterns must still match.
#           Without CR stripping each pattern carries a trailing \r and
#           matches nothing, silently disabling the private sweep.
# ---------------------------------------------------------------------------
make_fixture_repo
mkdir -p "$FIXTURE_DIR/scripts"
printf '# Fixture private patterns\r\n%s\r\n' "zzprivateorgzz" > "$FIXTURE_DIR/scripts/.private-patterns"
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)"; then
  pass "Test 12: CRLF pattern file → pattern still matches (CR-04)"
else
  fail "Test 12: CRLF pattern file (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 13 (WR-01): Pattern beginning with '-' → treated as a pattern, not a
#           grep option. Without `--` grep consumes it as an option, the
#           real pattern silently matches nothing, and stdin fallback can
#           corrupt the outer file loop.
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "-corp"
echo "name = acme-corp" > "$FIXTURE_DIR/main.tf"
stage_file "main.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)"; then
  pass "Test 13: leading-dash pattern → still swept as a pattern (WR-01)"
else
  fail "Test 13: leading-dash pattern (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 14 (WR-02): Secret staged, then removed from the working copy WITHOUT
#           re-staging → the staged blob is what `git commit` would record,
#           so the sweep must scan index content and still catch it.
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
echo "org: zzprivateorgzz" > "$FIXTURE_DIR/staged.tf"
stage_file "staged.tf"
# Clean the working copy but leave the dirty blob in the index.
echo "org: cleaned" > "$FIXTURE_DIR/staged.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] \
   && echo "$SWEEP_STDOUT" | grep -q "staged.tf" \
   && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)" \
   && ! echo "$SWEEP_STDOUT" | grep -qi "zzprivateorgzz"; then
  pass "Test 14: staged secret with cleaned working copy → caught from index (WR-02)"
else
  fail "Test 14: staged secret with cleaned working copy (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
fi

# ---------------------------------------------------------------------------
# Test 15 (WR-03): Non-ASCII filename → must stay in scan scope. Under git's
#           default core.quotepath=true a newline-delimited listing C-quotes
#           the path and the file silently drops out of the sweep.
# ---------------------------------------------------------------------------
make_fixture_repo
make_pattern_file "zzprivateorgzz"
printf 'org: zzprivateorgzz\n' > "$FIXTURE_DIR/tëst.tf"
stage_file "tëst.tf"
run_sweep
cleanup_fixture

if [[ "$SWEEP_EXIT" -ne 0 ]] && echo "$SWEEP_STDOUT" | grep -q "(private pattern #1)"; then
  pass "Test 15: non-ASCII filename stays in scan scope (WR-03)"
else
  fail "Test 15: non-ASCII filename in scan scope (exit=$SWEEP_EXIT stdout='$SWEEP_STDOUT')"
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
