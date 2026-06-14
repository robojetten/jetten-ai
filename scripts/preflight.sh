#!/bin/bash
# preflight.sh — opsec / identity-leak gate for jetten.ai.
#
# Scans the working tree for anything that could link this pseudonymous site
# back to its real author, BEFORE it is committed or published. Runs as a
# pre-commit hook AND inside the GitHub Actions build. Exits non-zero on any hit.
#
# IMPORTANT: this script contains NO identifying strings. The forbidden-pattern
# list lives OUTSIDE the repo so it can never be published by the guard itself:
#   - locally : a gitignored file (default: .preflight-patterns.local)
#   - in CI   : the OPSEC_PATTERNS repo secret, passed in as an env var
#
# Checks:
#   1. Identity patterns (real name / aliases / personal account / known IPs)
#   2. Git author + committer identity (must be Robo Jetten)
#   3. Any e-mail address that is not an allow-listed Robo Jetten address
#   4. IPv4 addresses (a pasted server/home IP)
#   5. Image metadata: GPS, author/creator/owner, camera serial, C2PA/JUMBF, AI-tool tags
#   6. Secrets: private-key blocks, GitHub/AWS tokens

set -euo pipefail

cd "$(cd "$(dirname "$0")" && pwd)/.."

violations=0
fail() { echo "ERROR: $*" >&2; violations=$((violations + 1)); }

# Everything tracked + about-to-be-added (respecting .gitignore), minus build dirs.
# NOTE: preflight.sh is intentionally NOT excluded any more — it holds no names,
# so it must be scanned like everything else. That self-exclusion used to be the
# loophole that hid the leak.
EXCLUDE_PATHS=(
  ":(exclude).git"
  ":(exclude)public"
  ":(exclude)resources"
  ":(exclude).hugo_cache"
)
files_list=$(git ls-files --cached --others --exclude-standard -- "${EXCLUDE_PATHS[@]}" 2>/dev/null || true)

scan() { # scan "<regex>" — print matching "file:line:text", never abort on no-match
  [ -n "$files_list" ] || return 0
  echo "$files_list" | tr '\n' '\0' | xargs -0 grep -inIE "$1" 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# 1) Identity patterns — loaded from OUTSIDE the repo.
#    Priority: $OPSEC_PATTERNS env (newline-separated) -> local file.
# ---------------------------------------------------------------------------
PATTERNS_FILE="${OPSEC_PATTERNS_FILE:-.preflight-patterns.local}"
patterns=()
if [ -n "${OPSEC_PATTERNS:-}" ]; then
  while IFS= read -r line; do [ -n "$line" ] && patterns+=("$line"); done <<< "$OPSEC_PATTERNS"
  echo "  identity patterns: ${#patterns[@]} from \$OPSEC_PATTERNS" >&2
elif [ -f "$PATTERNS_FILE" ]; then
  while IFS= read -r line; do
    case "$line" in ''|\#*) continue ;; esac
    patterns+=("$line")
  done < "$PATTERNS_FILE"
  echo "  identity patterns: ${#patterns[@]} from $PATTERNS_FILE" >&2
fi

if [ ${#patterns[@]} -gt 0 ]; then
  pat=$(printf '%s|' "${patterns[@]}"); pat="(${pat%|})"
  hits=$(scan "$pat")
  [ -n "$hits" ] && { fail "identity-leak strings in file content:"; echo "$hits" >&2; }
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    echo "$f" | grep -iqE "$pat" && fail "identity-leak string in filename: $f"
  done <<< "$files_list"
elif [ -n "${OPSEC_PATTERNS_ALLOW_MISSING:-}" ]; then
  echo "::warning::OPSEC_PATTERNS not set; identity-name scan DELIBERATELY skipped via OPSEC_PATTERNS_ALLOW_MISSING. Name enforcement relies on the local pre-commit hook + the commit-identity check. All other opsec checks still enforced." >&2
else
  fail "no identity patterns available (fail-closed). Set \$OPSEC_PATTERNS (CI secret) to enable the name scan, or set \$OPSEC_PATTERNS_ALLOW_MISSING=1 to deliberately skip it; locally, create $PATTERNS_FILE (see RUNBOOK.md)."
fi

# ---------------------------------------------------------------------------
# 2) Identity that lands on commits — checked against the allow-list.
#    Local pre-commit hook: the new commit does not exist yet, so validate the
#    CONFIGURED identity it will inherit. In CI: validate the ACTUAL author and
#    committer of the deployed commit(s) — the caller must not be able to set
#    git config to a passing value and thereby neuter this check.
# ---------------------------------------------------------------------------
ALLOW_EMAIL='(@jetten\.ai|@proton\.me|@protonmail\.com|users\.noreply\.github\.com)$'
check_ident() { # role email name
  local role="$1" e="$2" n="$3"
  if [ -z "$e" ]; then fail "$role e-mail is unset"
  elif ! printf '%s' "$e" | grep -qE "$ALLOW_EMAIL"; then fail "$role e-mail '$e' is not a Robo Jetten address"; fi
  case "$n" in
    "Robo Jetten") : ;;
    "") fail "$role name is unset" ;;
    *)  echo "  WARN: $role name is '$n' (expected 'Robo Jetten')" >&2 ;;
  esac
}
if [ -n "${CI:-}" ]; then
  log_spec="-1"
  if [ -n "${PREFLIGHT_COMMIT_RANGE:-}" ] && git rev-parse "${PREFLIGHT_COMMIT_RANGE}" >/dev/null 2>&1; then
    log_spec="${PREFLIGHT_COMMIT_RANGE}"
  fi
  commits=$(git log $log_spec --format='%ae|%an|%ce|%cn' 2>/dev/null || true)
  while IFS='|' read -r ae an ce cn; do
    [ -z "${ae}${an}" ] && continue
    check_ident "commit author" "$ae" "$an"
    check_ident "commit committer" "$ce" "$cn"
  done <<EOF
$commits
EOF
else
  check_ident "configured git" "$(git config --get user.email || echo '')" "$(git config --get user.name || echo '')"
fi

# ---------------------------------------------------------------------------
# 3) Any e-mail address that is not an allow-listed Robo Jetten address.
# ---------------------------------------------------------------------------
EMAIL_RE='[[:alnum:]._%+-]+@[[:alnum:].-]+\.[[:alpha:]]{2,}'
EMAIL_ALLOW='(robo@jetten\.ai|@proton\.me|@protonmail\.com|noreply\.github\.com|git@github\.com)'
if [ -n "$files_list" ]; then
  bad_emails=$(echo "$files_list" | tr '\n' '\0' | xargs -0 grep -hoIE "$EMAIL_RE" 2>/dev/null \
                 | grep -ivE "$EMAIL_ALLOW" | sort -u || true)
  [ -n "$bad_emails" ] && { fail "non-allow-listed e-mail address(es) found:"; echo "$bad_emails" >&2; }
fi

# ---------------------------------------------------------------------------
# 4) IPv4 addresses (loopback / unspecified / broadcast are ignored).
# ---------------------------------------------------------------------------
IPV4_RE='\b([0-9]{1,3}\.){3}[0-9]{1,3}\b'
if [ -n "$files_list" ]; then
  bad_ips=$(echo "$files_list" | tr '\n' '\0' | xargs -0 grep -hoIE "$IPV4_RE" 2>/dev/null \
              | grep -vE '^(0\.0\.0\.0|127\.0\.0\.1|255\.255\.255\.255)$' | sort -u || true)
  [ -n "$bad_ips" ] && { fail "IPv4 address(es) found (a pasted server/home IP?):"; echo "$bad_ips" >&2; }
fi

# ---------------------------------------------------------------------------
# 5) Image metadata — GPS, author/creator/owner, serial, C2PA/JUMBF, AI tools.
# ---------------------------------------------------------------------------
if command -v exiftool >/dev/null 2>&1; then
  META_RE='(GPS|Geolocation|Location|City|Country|Province|State|\bArtist\b|Creator|By-?line|Owner|Copyright|SerialNumber|CameraModel|LensModel|JUMBF|c2pa|ChatGPT|GPT-4|DALL|Midjourney|Stable ?Diffusion)'
  imgs=$(git ls-files --cached --others --exclude-standard -- "*.png" "*.jpg" "*.jpeg" "*.webp" "*.tif" "*.tiff" 2>/dev/null || true)
  while IFS= read -r img; do
    [ -z "$img" ] && continue
    meta=$(exiftool -G -a -s "$img" 2>/dev/null | grep -iE "$META_RE" || true)
    [ -n "$meta" ] && { fail "identity-adjacent metadata in $img:"; echo "$meta" >&2; }
  done <<< "$imgs"
else
  echo "  WARN: exiftool not installed — image-metadata check skipped." >&2
fi

# ---------------------------------------------------------------------------
# 6) Secrets — high-signal credential formats.
# ---------------------------------------------------------------------------
SECRET_RE='(-----BEGIN ([A-Z ]+ )?PRIVATE KEY-----|gh[pousr]_[A-Za-z0-9]{36,}|AKIA[0-9A-Z]{16}|xox[baprs]-[0-9A-Za-z-]{10,})'
secret_hits=$(scan "$SECRET_RE")
[ -n "$secret_hits" ] && { fail "possible secret/credential found:"; echo "$secret_hits" >&2; }

# ---------------------------------------------------------------------------
if [ "$violations" -gt 0 ]; then
  echo "" >&2
  echo "Preflight FAILED with $violations violation(s). Fix and re-run." >&2
  exit 1
fi
echo "preflight: clean."
