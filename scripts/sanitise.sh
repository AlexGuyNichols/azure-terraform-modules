#!/usr/bin/env bash
# Sanitisation sweep — scans tracked and stageable files for private identifiers.
#
# Exit codes:
#   0  — clean tree; no hits found
#   1  — one or more hits found, or the private pattern source is unusable
#
# Output contract (D-07):
#   On hit:  stdout  "HIT: <path>:<line> (generic pattern #N)"
#                 or "HIT: <path>:<line> (private pattern #N)"
#            stderr  "FAIL: sanitisation sweep found <N> hit(s). ..."
#   On pass: stdout  "OK: sanitisation sweep passed (0 hits)."
#
# Decisions implemented: D-01 D-02 D-03 D-04 D-05 D-06 D-07 D-08
set -euo pipefail

# ---------------------------------------------------------------------------
# D-06: Resolve repo root once; single code path, no env-var branch.
#       Works whether called from a hook, a subdirectory, or CI.
# ---------------------------------------------------------------------------
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

PATTERNS_FILE="scripts/.private-patterns"

# ---------------------------------------------------------------------------
# D-02: Hard-fail on missing pattern file.
# ---------------------------------------------------------------------------
if [[ ! -f "$PATTERNS_FILE" ]]; then
  echo "ERROR: $PATTERNS_FILE not found. Create it locally or ensure CI wrote the secret." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# D-02 (strengthened): Hard-fail when the pattern file has zero effective lines.
# An empty CI secret must not silently weaken the gate.
# ---------------------------------------------------------------------------
EFFECTIVE_LINES=$(grep -cv -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$PATTERNS_FILE" || true)
if [[ "$EFFECTIVE_LINES" -eq 0 ]]; then
  echo "ERROR: $PATTERNS_FILE contains no effective patterns (only comments/blank lines). The gate cannot run." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# D-04: Scan scope — tracked + stageable files.
#       Catches untracked-but-not-ignored files before they can be committed.
# ---------------------------------------------------------------------------
FILES=$(git ls-files --cached --others --exclude-standard)

FOUND=0

# ---------------------------------------------------------------------------
# D-03: Generic built-in patterns — UUID shape.
#       These live IN the public script; private names live in PATTERNS_FILE.
#       D-08: grep -i makes matching case-insensitive (catches uppercase UUIDs).
# ---------------------------------------------------------------------------
GENERIC_PATTERNS=(
  '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
)

PATTERN_INDEX=0
for pattern in "${GENERIC_PATTERNS[@]}"; do
  PATTERN_INDEX=$((PATTERN_INDEX + 1))
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    # D-08: -i for case-insensitive; -n for line numbers; -E for extended regex.
    # Cut field 1 (line number) directly from grep -inE output; do NOT add a
    # second grep pipe to re-number — that corrupts the reported line number.
    # Guard grep's exit-1-on-no-match under set -e with || true.
    while IFS= read -r lineno; do
      # D-07: Output path + line + pattern index; never the matched text.
      echo "HIT: $file:$lineno (generic pattern #$PATTERN_INDEX)"
      FOUND=$((FOUND + 1))
    done < <(grep -inE "$pattern" "$file" 2>/dev/null | cut -d: -f1 || true)
  done <<< "$FILES"
done

# ---------------------------------------------------------------------------
# Private patterns from the gitignored pattern file (D-01, D-06).
# ---------------------------------------------------------------------------
PATTERN_INDEX=0
# CR-03: `|| [[ -n "$pattern" ]]` keeps the final line when the file lacks a
# trailing newline — read returns non-zero there but still fills $pattern, so
# without the guard the last (or only) pattern would be silently dropped.
while IFS= read -r pattern || [[ -n "$pattern" ]]; do
  # CR-04: strip one trailing CR so a CRLF-encoded pattern file (the default
  # for many Windows editors) still matches — "pattern\r" never appears
  # mid-line in LF files, which would silently disable the private sweep.
  pattern="${pattern%$'\r'}"
  # Skip blank lines and comments.
  [[ -z "$pattern" || "$pattern" == \#* ]] && continue
  PATTERN_INDEX=$((PATTERN_INDEX + 1))
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    # D-08: Case-insensitive matching for all private patterns.
    # D-07: Never print the matched text or the pattern string.
    while IFS= read -r lineno; do
      echo "HIT: $file:$lineno (private pattern #$PATTERN_INDEX)"
      FOUND=$((FOUND + 1))
    done < <(grep -inE "$pattern" "$file" 2>/dev/null | cut -d: -f1 || true)
  done <<< "$FILES"
done < "$PATTERNS_FILE"

# ---------------------------------------------------------------------------
# Final verdict.
# ---------------------------------------------------------------------------
if [[ "$FOUND" -gt 0 ]]; then
  echo "FAIL: sanitisation sweep found $FOUND hit(s). Review and remove private identifiers." >&2
  exit 1
fi

echo "OK: sanitisation sweep passed (0 hits)."
exit 0
