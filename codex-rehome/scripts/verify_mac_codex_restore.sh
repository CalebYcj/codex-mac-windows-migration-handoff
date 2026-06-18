#!/usr/bin/env bash
set -euo pipefail

PACKAGE_ROOT=""
JSON="false"
PROJECTS_DIR="$HOME/Documents/Codex-Restored-Projects"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --package-root)
      PACKAGE_ROOT="$2"
      shift 2
      ;;
    --projects-dir)
      PROJECTS_DIR="$2"
      shift 2
      ;;
    --json)
      JSON="true"
      shift
      ;;
    -h|--help)
      echo "Usage: verify_mac_codex_restore.sh [--package-root DIR] [--projects-dir DIR] [--json]"
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$PACKAGE_ROOT" ]]; then
  PACKAGE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ "$(basename "$PACKAGE_ROOT")" == "scripts" ]]; then
    PACKAGE_ROOT="$(cd "$PACKAGE_ROOT/.." && pwd)"
  fi
fi

CODEX_HOME="$HOME/.codex"
APP_SUPPORT="$HOME/Library/Application Support/Codex"
MAC_USER="${USER:-$(id -un 2>/dev/null || echo unknown)}"

count_files() {
  local path="$1"
  local name="${2:-*}"
  [[ -d "$path" ]] || { echo 0; return; }
  find "$path" -name "$name" -type f 2>/dev/null | wc -l | tr -d ' '
}

count_dirs() {
  local path="$1"
  local name="${2:-*}"
  [[ -d "$path" ]] || { echo 0; return; }
  find "$path" -name "$name" -type d 2>/dev/null | wc -l | tr -d ' '
}

size_mb() {
  local path="$1"
  [[ -e "$path" ]] || { echo "null"; return; }
  du -sk "$path" 2>/dev/null | awk '{printf "%.2f", $1 / 1024}'
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

json_string_array_from_lines() {
  local first="true"
  printf '['
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ "$first" == "true" ]]; then
      first="false"
    else
      printf ','
    fi
    printf '"%s"' "$(json_escape "$line")"
  done
  printf ']'
}

checksum_status() {
  if [[ ! -f "$PACKAGE_ROOT/SHA256SUMS.txt" ]]; then
    echo "missing"
    return
  fi
  if command -v shasum >/dev/null 2>&1; then
    if (cd "$PACKAGE_ROOT" && shasum -a 256 -c SHA256SUMS.txt >/dev/null 2>&1); then
      echo "ok"
    else
      echo "failed"
    fi
  elif command -v sha256sum >/dev/null 2>&1; then
    if (cd "$PACKAGE_ROOT" && sha256sum -c SHA256SUMS.txt >/dev/null 2>&1); then
      echo "ok"
    else
      echo "failed"
    fi
  else
    echo "unavailable"
  fi
}

forbidden_count_in_root() {
  local root="$1"
  [[ -d "$root" ]] || { echo 0; return; }
  find "$root" \( \
    -name 'auth.json' -o \
    -name '.env' -o -name '.env.*' -o \
    -name '*.pem' -o -name '*.key' -o \
    -name 'id_rsa' -o -name 'id_dsa' -o -name 'id_ecdsa' -o -name 'id_ed25519' -o \
    -name 'Cookies' -o -name 'Cookies-journal' -o \
    -name 'Login Data' -o -name 'Login Data-journal' -o \
    -name 'Login Data For Account' -o -name 'Login Data For Account-journal' -o \
    -name 'Local Storage' -o -name 'Session Storage' -o \
    -name '.git' -o -name 'node_modules' -o -name '.venv' -o -name 'venv' -o \
    -name 'SingletonLock' -o -name 'SingletonCookie' -o -name 'SingletonSocket' -o \
    -name '*.sock' -o -name '*.ipc' \
  \) 2>/dev/null | wc -l | tr -d ' '
}

selected_chats_count() {
  count_files "$PACKAGE_ROOT/selected_chats" "*.jsonl"
}

selected_chats_in_sessions_count() {
  local selected="$PACKAGE_ROOT/selected_chats"
  [[ -d "$selected" && -d "$CODEX_HOME/sessions" ]] || { echo 0; return; }
  local found=0
  local chat base
  shopt -s nullglob
  for chat in "$selected"/*.jsonl; do
    base="$(basename "$chat")"
    if find "$CODEX_HOME/sessions" -type f -name "$base" 2>/dev/null | grep -q .; then
      found=$((found + 1))
      continue
    fi
    local first_id
    first_id="$(grep -m 1 -o '"id":"[^"]*"' "$chat" 2>/dev/null | head -n 1 | cut -d '"' -f 4 || true)"
    if [[ -n "$first_id" ]] && find "$CODEX_HOME/sessions" -type f -name "*$first_id*.jsonl" 2>/dev/null | grep -q .; then
      found=$((found + 1))
    fi
  done
  shopt -u nullglob
  echo "$found"
}

project_paths_lines() {
  [[ -d "$PROJECTS_DIR" ]] || return
  find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort
}

restored_project_count() {
  [[ -d "$PROJECTS_DIR" ]] || { echo 0; return; }
  find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' '
}

CHECKSUM_STATUS="$(checksum_status)"
SESSIONS="$(count_files "$CODEX_HOME/sessions" "*.jsonl")"
ARCHIVED_SESSIONS="$(count_files "$CODEX_HOME/archived_sessions" "*.jsonl")"
SKILLS="$(count_files "$CODEX_HOME/skills" "SKILL.md")"
PLUGIN_MANIFESTS="$(count_files "$CODEX_HOME/plugins/cache" "plugin.json")"
GENERATED_IMAGES="$(count_files "$CODEX_HOME/generated_images" "*")"
SQLITE_FILES="$(count_files "$CODEX_HOME" "*.sqlite")"
RESTORED_PROJECT_COUNT="$(restored_project_count)"
SELECTED_CHATS="$(selected_chats_count)"
SELECTED_CHATS_IN_SESSIONS="$(selected_chats_in_sessions_count)"
FORBIDDEN_CODEX="$(forbidden_count_in_root "$CODEX_HOME")"
FORBIDDEN_PROJECTS="$(forbidden_count_in_root "$PROJECTS_DIR")"
FORBIDDEN_TOTAL="$((FORBIDDEN_CODEX + FORBIDDEN_PROJECTS))"

if [[ "$JSON" == "true" ]]; then
  PROJECT_PATHS_JSON="$(project_paths_lines | json_string_array_from_lines)"
  cat <<EOF
{
  "generated_at": "$(date +%Y-%m-%dT%H:%M:%S)",
  "package_root": "$(json_escape "$PACKAGE_ROOT")",
  "mac_user": "$(json_escape "$MAC_USER")",
  "checksum": {
    "sha256sums_txt": "$(json_escape "$CHECKSUM_STATUS")"
  },
  "paths": {
    "codex_home": {"path": "$(json_escape "$CODEX_HOME")", "exists": $(test -e "$CODEX_HOME" && echo true || echo false), "size_mb": $(size_mb "$CODEX_HOME")},
    "app_support_codex": {"path": "$(json_escape "$APP_SUPPORT")", "exists": $(test -e "$APP_SUPPORT" && echo true || echo false), "size_mb": $(size_mb "$APP_SUPPORT")},
    "projects_dir": {"path": "$(json_escape "$PROJECTS_DIR")", "exists": $(test -e "$PROJECTS_DIR" && echo true || echo false)}
  },
  "counts": {
    "sessions": $SESSIONS,
    "archived_sessions": $ARCHIVED_SESSIONS,
    "skills": $SKILLS,
    "plugin_manifests": $PLUGIN_MANIFESTS,
    "generated_images": $GENERATED_IMAGES,
    "sqlite_files": $SQLITE_FILES,
    "restored_project_count": $RESTORED_PROJECT_COUNT,
    "selected_chats": $SELECTED_CHATS,
    "selected_chats_in_restored_sessions": $SELECTED_CHATS_IN_SESSIONS
  },
  "restored_project_paths": $PROJECT_PATHS_JSON,
  "forbidden_files": {
    "codex_home": $FORBIDDEN_CODEX,
    "projects": $FORBIDDEN_PROJECTS,
    "total": $FORBIDDEN_TOTAL
  }
}
EOF
  exit 0
fi

echo "Codex Mac restore verification"
echo "Generated: $(date +%Y-%m-%dT%H:%M:%S)"
echo "Package root: $PACKAGE_ROOT"
echo "Checksum: $CHECKSUM_STATUS"
echo
for path in \
  "$CODEX_HOME" \
  "$APP_SUPPORT" \
  "$HOME/Library/Application Support/com.openai.codex" \
  "$HOME/Library/Application Support/OpenAI/Codex" \
  "$HOME/Library/Caches/Codex" \
  "$PROJECTS_DIR"; do
  if [[ -e "$path" ]]; then
    echo "  [found]   $path ($(size_mb "$path") MB)"
  else
    echo "  [missing] $path"
  fi
done
echo
echo "Counts:"
echo "  sessions: $SESSIONS"
echo "  archived_sessions: $ARCHIVED_SESSIONS"
echo "  skills: $SKILLS"
echo "  plugin_manifests: $PLUGIN_MANIFESTS"
echo "  generated_images: $GENERATED_IMAGES"
echo "  sqlite_files: $SQLITE_FILES"
echo "  restored_project_count: $RESTORED_PROJECT_COUNT"
echo "  selected_chats: $SELECTED_CHATS"
echo "  selected_chats_in_restored_sessions: $SELECTED_CHATS_IN_SESSIONS"
echo "  forbidden_files_total: $FORBIDDEN_TOTAL"
echo
echo "Restored project paths:"
project_paths_lines | sed 's/^/  /' || true
echo
echo "Next checks:"
echo "  1. Open Codex and confirm old threads are visible."
echo "  2. Reopen migrated project folders from their Mac paths."
echo "  3. Reconnect GitHub, Gmail, Chrome, Feishu, or other services if prompted."
