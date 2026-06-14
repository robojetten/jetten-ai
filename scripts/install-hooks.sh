#!/bin/bash
# install-hooks.sh — wire the preflight check into the local pre-commit hook.
# Idempotent; safe to re-run.

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
hook_path="$repo_root/.git/hooks/pre-commit"

if [ ! -d "$repo_root/.git" ]; then
  echo "Not a git repo: $repo_root" >&2
  exit 1
fi

cat > "$hook_path" <<'HOOK'
#!/bin/bash
# Auto-installed by scripts/install-hooks.sh.  Edit there, not here.
exec "$(git rev-parse --show-toplevel)/scripts/preflight.sh"
HOOK

chmod +x "$hook_path"
echo "Installed pre-commit hook at $hook_path"
