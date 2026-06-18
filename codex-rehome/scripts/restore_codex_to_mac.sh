#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ "$(basename "$ROOT")" == "scripts" ]]; then
  ROOT="$(cd "$ROOT/.." && pwd)"
fi

RESTORE_PROJECTS="false"
PROJECTS_DIR="$HOME/Documents/Codex-Restored-Projects"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --restore-projects)
      RESTORE_PROJECTS="true"
      shift
      ;;
    --projects-dir)
      PROJECTS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage: Restore-Codex-To-Mac.sh [--restore-projects] [--projects-dir DIR]

Restores home/.codex into $HOME/.codex and optional project folders into
$HOME/Documents/Codex-Restored-Projects or a custom --projects-dir.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
MAC_USER="${USER:-$(id -un 2>/dev/null || echo unknown)}"

normalize_package_permissions() {
  local rel
  for rel in home projects appdata_roaming appdata_local mac_only; do
    if [[ -e "$ROOT/$rel" ]]; then
      chmod -R u+rwX "$ROOT/$rel" || {
        echo "Failed to normalize permissions for $ROOT/$rel" >&2
        exit 1
      }
    fi
  done
}

backup_if_exists() {
  local path="$1"
  if [[ -e "$path" ]]; then
    local backup="$path.backup-$STAMP"
    echo "Backing up existing data:"
    echo "  $path"
    echo "  -> $backup"
    mv "$path" "$backup"
  fi
}

restore_dir() {
  local src="$1"
  local dst="$2"
  if [[ ! -d "$src" ]]; then
    echo "Skipping missing source: $src"
    return
  fi
  if [[ ! -r "$src" || ! -x "$src" ]]; then
    echo "Source exists but is not readable/enterable: $src" >&2
    exit 1
  fi
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  if command -v rsync >/dev/null 2>&1; then
    rsync -aE "$src/" "$dst/"
  elif command -v ditto >/dev/null 2>&1; then
    ditto "$src" "$dst"
  else
    cp -Rp "$src" "$dst"
  fi
  echo "Restored: $dst"
}

restore_file() {
  local src="$1"
  local dst="$2"
  if [[ ! -f "$src" ]]; then
    return
  fi
  mkdir -p "$(dirname "$dst")"
  backup_if_exists "$dst"
  cp -p "$src" "$dst"
  echo "Restored: $dst"
}

restore_projects() {
  local src_root="$ROOT/projects"
  if [[ "$RESTORE_PROJECTS" != "true" ]]; then
    echo "Project restore not requested. Pass --restore-projects to copy projects/."
    return
  fi
  if [[ ! -d "$src_root" ]]; then
    echo "Project restore requested but package has no projects/ directory." >&2
    exit 1
  fi
  mkdir -p "$PROJECTS_DIR"
  local restored=0
  local project
  shopt -s nullglob
  for project in "$src_root"/*; do
    [[ -d "$project" ]] || continue
    restore_dir "$project" "$PROJECTS_DIR/$(basename "$project")"
    restored=$((restored + 1))
  done
  shopt -u nullglob
  if [[ "$restored" -eq 0 ]]; then
    echo "Project restore requested but projects/ contains no project folders." >&2
    exit 1
  fi
  echo "Restored project folders to: $PROJECTS_DIR"
}

normalize_package_permissions

if [[ ! -d "$ROOT/home/.codex" ]]; then
  echo "Required source missing: $ROOT/home/.codex" >&2
  exit 1
fi
if [[ ! -r "$ROOT/home/.codex" || ! -x "$ROOT/home/.codex" ]]; then
  echo "Required source is not readable/enterable: $ROOT/home/.codex" >&2
  exit 1
fi

if pgrep -if "Codex" >/dev/null 2>&1; then
  if [[ "$HOME" == /tmp/codex-* || "$HOME" == /private/tmp/codex-* ]]; then
    echo "Codex appears to be running, but HOME is a temporary isolated restore target; continuing."
  else
    echo "Codex appears to be running. Close Codex before continuing."
    read -r -p "Press Enter after Codex is closed"
  fi
fi

echo "Restoring Codex data to Mac user: $MAC_USER"

restore_dir "$ROOT/home/.codex" "$HOME/.codex"
restore_dir "$ROOT/appdata_roaming/Codex" "$HOME/Library/Application Support/Codex"
restore_dir "$ROOT/appdata_roaming/com.openai.codex" "$HOME/Library/Application Support/com.openai.codex"
restore_dir "$ROOT/appdata_roaming/OpenAI/Codex" "$HOME/Library/Application Support/OpenAI/Codex"
restore_dir "$ROOT/appdata_local/Codex" "$HOME/Library/Caches/Codex"
restore_dir "$ROOT/appdata_local/com.openai.codex" "$HOME/Library/Caches/com.openai.codex"
restore_dir "$ROOT/appdata_local/com.openai.sky.CUAService" "$HOME/Library/Caches/com.openai.sky.CUAService"
restore_dir "$ROOT/appdata_local/com.openai.sky.CUAService.cli" "$HOME/Library/Caches/com.openai.sky.CUAService.cli"

restore_file "$ROOT/mac_only/Library/Preferences/com.openai.codex.plist" "$HOME/Library/Preferences/com.openai.codex.plist"
restore_file "$ROOT/mac_only/Library/Preferences/com.openai.sky.CUAService.plist" "$HOME/Library/Preferences/com.openai.sky.CUAService.plist"
restore_file "$ROOT/mac_only/Library/Preferences/com.openai.sky.CUAService.cli.plist" "$HOME/Library/Preferences/com.openai.sky.CUAService.cli.plist"

restore_projects

rm -f "$HOME/Library/Application Support/Codex/SingletonLock" \
  "$HOME/Library/Application Support/Codex/SingletonCookie" \
  "$HOME/Library/Application Support/Codex/SingletonSocket"

echo "Done. Open Codex and log in again if prompted."
