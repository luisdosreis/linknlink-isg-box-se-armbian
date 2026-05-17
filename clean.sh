#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  cat <<'EOF'
usage: ./clean.sh [--dry-run]

Remove generated local artifacts so the next build starts fresh.

Removes:
  .cache/
  output/
  build/
  .firmware-backups/
  *.img.dump/ directories inside this repo

Options:
  --dry-run       Show what would be removed
  --help, -h      Show this help

Notes:
  - This does not remove Docker images, Docker volumes, or apt caches outside
    this repo.
  - Armbian/Docker may create root-owned files in build/. If cleanup fails with
    permission errors, run: sudo ./clean.sh
EOF
}

dry_run=no

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --dry-run)
      dry_run=yes
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

paths=(
  "$REPO_DIR/.cache"
  "$REPO_DIR/output"
  "$REPO_DIR/build"
  "$REPO_DIR/.firmware-backups"
)

rm_args=(-rf)
if rm --help 2>/dev/null | grep -q -- '--one-file-system'; then
  rm_args+=(--one-file-system)
fi

safe_rm_rf() {
  local path mounts error_file
  path="$1"
  error_file="$2"

  mounts="$(findmnt -R -rn -o TARGET "$path" 2>/dev/null || true)"
  if [[ -n "$mounts" ]]; then
    echo "Refusing to remove mounted filesystem(s) under: $path" >&2
    echo "$mounts" >&2
    echo "Unmount those paths first, then rerun cleanup." >&2
    return 1
  fi

  rm "${rm_args[@]}" "$path" 2>"$error_file"
}

while IFS= read -r -d '' dump_dir; do
  paths+=("$dump_dir")
done < <(find "$REPO_DIR" -maxdepth 4 -type d -name '*.img.dump' -print0 2>/dev/null)

echo "Cleanup targets:"
for path in "${paths[@]}"; do
  if [[ -e "$path" ]]; then
    du -shx "$path" 2>/dev/null || true
    echo "  $path"
  else
    echo "  $path (not present)"
  fi
done

if [[ "$dry_run" == "yes" ]]; then
  echo "Dry run only; no files removed."
  exit 0
fi

for path in "${paths[@]}"; do
  [[ -e "$path" ]] || continue
  case "$path" in
    "$REPO_DIR"/.cache|"$REPO_DIR"/output|"$REPO_DIR"/build|"$REPO_DIR"/.firmware-backups|"$REPO_DIR"/*.img.dump|"$REPO_DIR"/*/*.img.dump|"$REPO_DIR"/*/*/*.img.dump|"$REPO_DIR"/*/*/*/*.img.dump)
      if ! safe_rm_rf "$path" "/tmp/linknlink-clean-errors.$$"; then
        echo "Failed to remove: $path" >&2
        echo "Some Armbian/Docker build files may be owned by root or another container user." >&2
        echo "Run with elevated privileges if you want to remove those files:" >&2
        echo "  sudo ./clean.sh" >&2
        if [[ -s /tmp/linknlink-clean-errors.$$ ]]; then
          echo "First cleanup error:" >&2
          sed -n '1p' /tmp/linknlink-clean-errors.$$ >&2
        fi
        rm -f /tmp/linknlink-clean-errors.$$
        exit 1
      fi
      rm -f /tmp/linknlink-clean-errors.$$
      ;;
    *)
      echo "Refusing to remove unexpected path: $path" >&2
      exit 1
      ;;
  esac
done

echo "Cleanup complete."
