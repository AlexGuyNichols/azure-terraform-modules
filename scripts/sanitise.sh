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
# WR-02: tracked files are scanned from their INDEX (staged) content via
#       `git show :<path>` — that snapshot is what a commit would actually
#       record, so a secret that is staged and then removed from the working
#       copy (without re-staging) is still caught. Untracked files have no
#       index entry and are scanned from the working tree.
# ---------------------------------------------------------------------------
# WR-03: NUL-delimited listing (-z). With git's default core.quotepath=true a
# newline-delimited listing C-quotes non-ASCII paths (with literal quote
# characters); the existence check then fails and the file silently drops out
# of scan scope. -z always emits the raw path.
TRACKED_FILES=()
while IFS= read -r -d '' f; do
  TRACKED_FILES+=("$f")
done < <(git ls-files -z --cached)

UNTRACKED_FILES=()
while IFS= read -r -d '' f; do
  UNTRACKED_FILES+=("$f")
done < <(git ls-files -z --others --exclude-standard)

FOUND=0

# scan_pattern <label> <index> <pattern>
# Scans every in-scope file for <pattern>, emitting one leak-safe HIT line
# per match (D-07: path + line number + pattern index — never the matched
# text or the pattern itself). FOUND is incremented in the parent shell via
# process substitution, never a pipe subshell.
# D-08: grep -i everywhere — matching is case-insensitive.
# Cut field 1 (line number) directly from grep -inE output; do NOT add a
# second grep pipe to re-number — that corrupts the reported line number.
# WR-01: `--` ends option parsing so a pattern starting with '-' is treated
# as a pattern, never consumed as a grep option.
# WR-03: git-show/grep stderr is NOT suppressed — a failing read surfaces on
# stderr instead of silently scanning as clean, and an unreadable untracked
# file fails the gate outright. (grep's exit-1-on-no-match is normal and
# prints nothing; the `|| true` tail only guards the cut pipeline's status.)
scan_pattern() {
  local label="$1" idx="$2" pattern="$3" file lineno
  # Tracked: scan index content (WR-02). Deliberately NO working-tree
  # existence check — a file deleted from the working copy but still staged
  # is exactly the content that must be scanned.
  for file in "${TRACKED_FILES[@]}"; do
    while IFS= read -r lineno; do
      echo "HIT: $file:$lineno ($label pattern #$idx)"
      FOUND=$((FOUND + 1))
    done < <(git show ":$file" | grep -inE -- "$pattern" | cut -d: -f1 || true)
  done
  # Untracked, not-ignored: no index entry — scan the working tree.
  for file in "${UNTRACKED_FILES[@]}"; do
    [[ -f "$file" ]] || continue  # vanished since listing — nothing to commit
    if [[ ! -r "$file" ]]; then
      # WR-03: fail closed — an unreadable file must not pass as clean.
      echo "ERROR: cannot read $file — failing closed." >&2
      exit 1
    fi
    while IFS= read -r lineno; do
      echo "HIT: $file:$lineno ($label pattern #$idx)"
      FOUND=$((FOUND + 1))
    done < <(grep -inE -- "$pattern" "$file" | cut -d: -f1 || true)
  done
}

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
  scan_pattern "generic" "$PATTERN_INDEX" "$pattern"
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
  scan_pattern "private" "$PATTERN_INDEX" "$pattern"
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
