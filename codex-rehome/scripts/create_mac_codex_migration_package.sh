#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$HOME/Desktop"
PROJECTS=()
SELECTED_CHATS=()
MODE="standard"
ALLOW_SECRETS="false"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --project)
      PROJECTS+=("$2")
      shift 2
      ;;
    --selected-chat)
      SELECTED_CHATS+=("$2")
      shift 2
      ;;
    --i-understand-secrets)
      ALLOW_SECRETS="true"
      shift
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  create_mac_codex_migration_package.sh [options]

Options:
  --mode standard|full|full-with-secrets
      standard: Codex core data, skills, plugins, generated images, and selected app data.
      full:     standard plus logs/caches/environment inventory, still excluding secrets.
      full-with-secrets:
                includes sensitive auth/token/env/login-state files. Requires
                --i-understand-secrets.

  --out DIR
      Output directory. Defaults to ~/Desktop.

  --project PATH
      Include a project folder. May be repeated.

  --selected-chat PATH
      Include a specific session JSONL file for UI-readiness audit. May be repeated.

  --i-understand-secrets
      Required with --mode full-with-secrets.
EOF
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

case "$MODE" in
  standard|full|full-with-secrets) ;;
  *)
    echo "Invalid --mode: $MODE" >&2
    exit 1
    ;;
esac

if [[ "$MODE" == "full-with-secrets" && "$ALLOW_SECRETS" != "true" ]]; then
  echo "Refusing full-with-secrets without --i-understand-secrets." >&2
  echo "This mode may package auth tokens, .env files, browser login state, and private keys." >&2
  exit 1
fi

STAMP="$(date +%Y%m%d-%H%M%S)"
STAGE="$OUT_DIR/Codex-Migration-Mac-Source-$STAMP"
ZIP_PATH="$OUT_DIR/Codex-Migration-Mac-Source-$STAMP.zip"
EXCLUDE_FILE="$STAGE/docs/rsync-excludes.txt"
SENSITIVE_REPORT="$STAGE/docs/SENSITIVE-FILES.txt"
ENV_REPORT="$STAGE/docs/ENV-INVENTORY.txt"
METADATA="$STAGE/metadata"

mkdir -p "$STAGE/home" \
  "$STAGE/appdata_roaming/OpenAI" \
  "$STAGE/appdata_local" \
  "$STAGE/mac_only/Library/Preferences" \
  "$STAGE/projects" \
  "$STAGE/selected_chats" \
  "$METADATA" \
  "$STAGE/docs"

cat > "$EXCLUDE_FILE" <<'EOF'
.DS_Store
.tmp/
tmp/
process_manager/
vendor_imports/
.git/
node_modules/
.venv/
venv/
__pycache__/
*.ipc
*.sock
SingletonLock
SingletonCookie
SingletonSocket
RunningChromeVersion
EOF

if [[ "$MODE" != "full-with-secrets" ]]; then
  cat >> "$EXCLUDE_FILE" <<'EOF'
auth.json
Cookies
Cookies-journal
Login Data
Login Data For Account
Login Data-journal
Login Data For Account-journal
Local Storage/
Session Storage/
Network/Cookies
.env
.env.*
id_rsa
id_dsa
id_ecdsa
id_ed25519
*.pem
*.key
EOF
fi

if [[ "$MODE" == "standard" ]]; then
  cat >> "$EXCLUDE_FILE" <<'EOF'
logs_*.sqlite
logs_*.sqlite*
logs/
Library/Logs/
Cache/
Caches/
GPUCache/
Code Cache/
Service Worker/CacheStorage/
EOF
fi

copy_dir() {
  local src="$1"
  local dst="$2"
  if [[ -d "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    if command -v rsync >/dev/null 2>&1; then
      rsync -aE --delete --exclude-from="$EXCLUDE_FILE" "$src/" "$dst/"
    elif command -v ditto >/dev/null 2>&1; then
      echo "Warning: rsync not found; falling back to ditto without exclude support for $src" >&2
      ditto "$src" "$dst"
    else
      echo "Neither rsync nor ditto is available." >&2
      exit 1
    fi
  fi
}

copy_file() {
  local src="$1"
  local dst="$2"
  if [[ -f "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    cp -p "$src" "$dst"
  fi
}

find_python3() {
  if command -v python3 >/dev/null 2>&1; then
    command -v python3
    return 0
  fi
  if command -v python >/dev/null 2>&1; then
    command -v python
    return 0
  fi
  return 1
}

if command -v sqlite3 >/dev/null 2>&1; then
  for db in "$HOME/.codex"/*.sqlite; do
    [[ -f "$db" ]] && sqlite3 "$db" 'PRAGMA wal_checkpoint(PASSIVE);' >/dev/null 2>&1 || true
  done
fi

copy_dir "$HOME/.codex" "$STAGE/home/.codex"
copy_dir "$HOME/Library/Application Support/Codex" "$STAGE/appdata_roaming/Codex"
copy_dir "$HOME/Library/Application Support/com.openai.codex" "$STAGE/appdata_roaming/com.openai.codex"
copy_dir "$HOME/Library/Application Support/OpenAI/Codex" "$STAGE/appdata_roaming/OpenAI/Codex"

if [[ "$MODE" != "standard" ]]; then
  copy_dir "$HOME/Library/Caches/Codex" "$STAGE/appdata_local/Codex"
  copy_dir "$HOME/Library/Caches/com.openai.codex" "$STAGE/appdata_local/com.openai.codex"
  copy_dir "$HOME/Library/Caches/com.openai.sky.CUAService" "$STAGE/appdata_local/com.openai.sky.CUAService"
  copy_dir "$HOME/Library/Caches/com.openai.sky.CUAService.cli" "$STAGE/appdata_local/com.openai.sky.CUAService.cli"
  copy_dir "$HOME/Library/Logs/com.openai.codex" "$STAGE/mac_only/Library/Logs/com.openai.codex"
fi

copy_file "$HOME/Library/Preferences/com.openai.codex.plist" "$STAGE/mac_only/Library/Preferences/com.openai.codex.plist"
copy_file "$HOME/Library/Preferences/com.openai.sky.CUAService.plist" "$STAGE/mac_only/Library/Preferences/com.openai.sky.CUAService.plist"
copy_file "$HOME/Library/Preferences/com.openai.sky.CUAService.cli.plist" "$STAGE/mac_only/Library/Preferences/com.openai.sky.CUAService.cli.plist"

rm -f "$STAGE/appdata_roaming/Codex/SingletonLock" \
  "$STAGE/appdata_roaming/Codex/SingletonCookie" \
  "$STAGE/appdata_roaming/Codex/SingletonSocket" \
  "$STAGE/appdata_roaming/Codex/RunningChromeVersion"

for project in "${PROJECTS[@]}"; do
  if [[ -d "$project" ]]; then
    base="$(basename "$project")"
    copy_dir "$project" "$STAGE/projects/$base"
  else
    echo "Missing project: $project" >&2
  fi
done

for chat in "${SELECTED_CHATS[@]}"; do
  if [[ -f "$chat" ]]; then
    cp -p "$chat" "$STAGE/selected_chats/$(basename "$chat")"
  else
    echo "Missing selected chat: $chat" >&2
  fi
done

export_ui_ready_metadata() {
  local request_path="$METADATA/export_request.json"
  local py
  if ! py="$(find_python3)"; then
    echo "Warning: Python with sqlite3 was not found. UI-ready metadata export skipped." >&2
    return
  fi

  "$py" - "$request_path" "$STAMP" "$HOME" "$STAGE" "$METADATA" "$HOME/.codex" "$HOME/.codex/.codex-global-state.json" "${PROJECTS[@]}" -- "${SELECTED_CHATS[@]}" <<'PY'
import json
import sys
from pathlib import Path

request_path = Path(sys.argv[1])
stamp = sys.argv[2]
source_home = sys.argv[3]
stage = sys.argv[4]
metadata_dir = sys.argv[5]
source_codex_home = Path(sys.argv[6])
global_state = sys.argv[7]
args = sys.argv[8:]
split = args.index("--") if "--" in args else len(args)
projects = args[:split]
selected_chats = args[split + 1:] if split < len(args) else []
state_files = [str(p) for p in sorted(source_codex_home.glob("state_*.sqlite"), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)]
payload = {
    "created_at": stamp,
    "source_os": "Mac",
    "source_home": source_home,
    "source_codex_home": str(source_codex_home),
    "stage": stage,
    "metadata_dir": metadata_dir,
    "projects": projects,
    "selected_chats": selected_chats,
    "state_files": state_files,
    "global_state": global_state,
}
request_path.parent.mkdir(parents=True, exist_ok=True)
request_path.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY

  "$py" - "$request_path" <<'PY'
import json
import re
import sqlite3
import sys
from pathlib import Path, PurePosixPath

request_path = Path(sys.argv[1])
req = json.loads(request_path.read_text(encoding="utf-8"))
metadata_dir = Path(req["metadata_dir"])
metadata_dir.mkdir(parents=True, exist_ok=True)
source_codex_home = Path(req.get("source_codex_home") or "")

def posix_norm(path):
    if not path:
        return ""
    s = str(path).replace("\\", "/")
    try:
        s = str(Path(s).expanduser().resolve(strict=False))
    except Exception:
        pass
    return s.rstrip("/")

def variants(path):
    vals = []
    if not path:
        return vals
    s = str(path)
    vals.append(s)
    vals.append(s.replace("\\", "/"))
    try:
        vals.append(str(Path(s).expanduser().resolve(strict=False)))
    except Exception:
        pass
    if s.startswith("/private/tmp/"):
        vals.append(s.replace("/private/tmp/", "/tmp/", 1))
    if s.startswith("/tmp/"):
        vals.append(s.replace("/tmp/", "/private/tmp/", 1))
    return list(dict.fromkeys(v for v in vals if v))

def selected_id(path):
    sid = ""
    try:
        with open(path, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                try:
                    row = json.loads(line)
                except Exception:
                    continue
                payload = row.get("payload") if isinstance(row.get("payload"), dict) else {}
                if row.get("type") == "session_meta" or payload.get("type") == "session_meta":
                    sid = str(payload.get("id") or row.get("id") or sid)
                    if sid:
                        return sid
                if not sid:
                    sid = str(row.get("id") or payload.get("id") or "")
    except Exception:
        pass
    if sid:
        return sid
    match = re.search(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", Path(path).stem, re.I)
    return match.group(0) if match else Path(path).stem

project_entries = []
project_roots = set()
for project in req.get("projects") or []:
    if not project:
        continue
    source_path = str(Path(project).expanduser())
    name = Path(source_path).name
    entry = {
        "source_path": source_path,
        "source_path_normalized": posix_norm(source_path),
        "source_path_variants": variants(source_path),
        "package_project_name": name,
        "package_project_path": f"projects/{name}",
        "target_mac_default_path": f"~/Documents/Codex-Restored-Projects/{name}",
        "target_windows_default_path": f"%USERPROFILE%\\Documents\\Codex-Restored-Projects\\{name}",
    }
    project_entries.append(entry)
    project_roots.add(posix_norm(source_path))

selected_ids = []
selected_chat_files = []
for chat in req.get("selected_chats") or []:
    if not chat:
        continue
    sid = selected_id(chat)
    selected_ids.append(sid)
    selected_chat_files.append({"id": sid, "source_path": chat, "package_path": f"selected_chats/{Path(chat).name}"})

def path_matches_project(path):
    n = posix_norm(path)
    if not n:
        return False
    return any(n == root or n.startswith(root + "/") for root in project_roots)

thread_rows = []
seen = set()
state_files = [p for p in req.get("state_files") or [] if p and Path(p).exists()]
for state_file in state_files:
    try:
        con = sqlite3.connect(f"file:{Path(state_file).as_posix()}?mode=ro", uri=True)
        con.row_factory = sqlite3.Row
        cols = [r[1] for r in con.execute("pragma table_info(threads)").fetchall()]
        if not cols:
            con.close()
            continue
        order_col = "updated_at_ms" if "updated_at_ms" in cols else "updated_at" if "updated_at" in cols else cols[0]
        rows = con.execute(f"select * from threads order by {order_col} desc").fetchall()
    except Exception:
        continue
    for row in rows:
        d = {k: row[k] for k in row.keys()}
        tid = str(d.get("id") or "")
        if not tid or tid in seen:
            continue
        include = tid in selected_ids or path_matches_project(d.get("cwd"))
        if not include and not selected_ids and not project_roots and len(thread_rows) < 50:
            include = True
        if not include:
            continue
        rollout_path = d.get("rollout_path") or ""
        rel = ""
        try:
            rp = Path(str(rollout_path))
            rel_to_codex = rp.relative_to(source_codex_home)
            rel = "home/.codex/" + rel_to_codex.as_posix()
        except Exception:
            rel = ""
        d["source_state_file"] = str(state_file)
        d["relative_package_session_path"] = rel
        thread_rows.append(d)
        seen.add(tid)
    try:
        con.close()
    except Exception:
        pass

for row in thread_rows:
    cwd = row.get("cwd") or ""
    if not cwd:
        continue
    cwd_name = PurePosixPath(str(cwd).replace("\\", "/")).name
    for entry in project_entries:
        if entry.get("package_project_name") == cwd_name:
            existing = set(entry.get("source_path_variants") or [])
            for value in variants(cwd):
                if value and value not in existing:
                    entry.setdefault("source_path_variants", []).append(value)
                    existing.add(value)
            entry.setdefault("additional_source_paths", [])
            if cwd not in entry["additional_source_paths"]:
                entry["additional_source_paths"].append(cwd)
            project_roots.add(posix_norm(cwd))

thread_ids = {str(r.get("id")) for r in thread_rows if r.get("id")}
global_state_path = Path(req.get("global_state") or "")
registry = {
    "electron-saved-workspace-roots": [],
    "project-order": [],
    "active-workspace-roots": [],
    "projectless-thread-ids": [],
    "thread-workspace-root-hints": {},
    "thread-projectless-output-directories": {},
    "heartbeat-thread-permissions-by-id": {},
}
if global_state_path.exists():
    try:
        gs = json.loads(global_state_path.read_text(encoding="utf-8", errors="ignore"))
        for key in ["electron-saved-workspace-roots", "project-order", "active-workspace-roots"]:
            registry[key] = [p for p in gs.get(key, []) if path_matches_project(p) or posix_norm(p) in project_roots]
        registry["projectless-thread-ids"] = [tid for tid in gs.get("projectless-thread-ids", []) if tid in thread_ids]
        hints = gs.get("thread-workspace-root-hints", {})
        registry["thread-workspace-root-hints"] = {tid: path for tid, path in hints.items() if tid in thread_ids or path_matches_project(path)}
        outputs = gs.get("thread-projectless-output-directories", {})
        registry["thread-projectless-output-directories"] = {tid: path for tid, path in outputs.items() if tid in thread_ids or path_matches_project(path)}
        perms = (gs.get("electron-persisted-atom-state", {}) or {}).get("heartbeat-thread-permissions-by-id", {})
        registry["heartbeat-thread-permissions-by-id"] = {tid: perms[tid] for tid in thread_ids if tid in perms}
    except Exception:
        pass

(metadata_dir / "path_map.json").write_text(json.dumps({
    "schema": 3,
    "source_os": "Mac",
    "target_os": "Any",
    "projects": project_entries,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

(metadata_dir / "selected_chats.json").write_text(json.dumps({
    "schema": 3,
    "selected_chats": selected_chat_files,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

(metadata_dir / "thread_index_export.json").write_text(json.dumps({
    "schema": 3,
    "source_os": "Mac",
    "source_state_files": state_files,
    "selected_thread_ids": selected_ids,
    "threads": thread_rows,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

(metadata_dir / "project_ui_registry_export.json").write_text(json.dumps({
    "schema": 3,
    "source_os": "Mac",
    "source_global_state": str(global_state_path) if global_state_path else "",
    "project_registry": registry,
}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
PY
}

export_ui_ready_metadata

{
  echo "Sensitive files report"
  echo "Generated: $STAMP"
  echo "Mode: $MODE"
  echo
  echo "The following paths exist or matched common sensitive patterns on the source Mac."
  echo "Contents are intentionally not printed."
  echo
  for path in \
    "$HOME/.codex/auth.json" \
    "$HOME/Library/Application Support/Codex/Cookies" \
    "$HOME/Library/Application Support/Codex/Default/Login Data" \
    "$HOME/Library/Application Support/Codex/Local Storage" \
    "$HOME/Library/Application Support/Codex/Session Storage"; do
    [[ -e "$path" ]] && echo "$path"
  done
  for project in "${PROJECTS[@]}"; do
    [[ -d "$project" ]] && find "$project" -name ".env" -o -name ".env.*" -o -name "*.pem" -o -name "*.key" 2>/dev/null | sed 's#^#project: #'
  done
  if [[ -d "$HOME/.ssh" ]]; then
    find "$HOME/.ssh" -maxdepth 1 -type f 2>/dev/null | sed 's#^#ssh: #'
  fi
} > "$SENSITIVE_REPORT"

if [[ "$MODE" != "standard" ]]; then
  {
    echo "Environment inventory"
    echo "Generated: $STAMP"
    echo
    echo "[system]"
    sw_vers 2>/dev/null || true
    uname -a 2>/dev/null || true
    echo
    echo "[tools]"
    for cmd in codex git node npm pnpm yarn python3 pip3 uv cargo rustc go brew; do
      if command -v "$cmd" >/dev/null 2>&1; then
        printf "%s: " "$cmd"
        "$cmd" --version 2>/dev/null | head -n 1 || command -v "$cmd"
      fi
    done
    echo
    echo "[git]"
    git config --global --list 2>/dev/null | sed -E 's#(token|password|secret|key)=.*#\1=<redacted>#I' || true
    echo
    echo "[shell]"
    echo "SHELL=${SHELL:-}"
    echo "PATH=$PATH" | sed -E 's#(token|password|secret|key)=[^:; ]+#\1=<redacted>#Ig'
  } > "$ENV_REPORT"
fi

cat > "$STAGE/README-Restore.txt" <<'EOF'
Codex migration package
=======================

This package uses a neutral layout so it can be restored to either Windows or Mac.

Before restoring on any target:
1. Install Codex on the target computer.
2. Open it once on the target computer, then close all Codex windows.
3. Unzip this package.

Windows restore:
1. Open PowerShell in the unzipped folder.
2. Run:
   Set-ExecutionPolicy -Scope Process Bypass
   .\Restore-Codex-To-Windows.ps1 -RestoreProjects
3. Verify:
   .\Verify-Codex-Windows-Restore.ps1 -Json

Mac restore:
1. Open Terminal in the unzipped folder.
2. Run:
   bash Restore-Codex-To-Mac.sh --restore-projects
3. Verify:
   bash Verify-Codex-Mac-Restore.sh --json

Manual mapping:
home\.codex -> C:\Users\<you>\.codex
appdata_roaming\Codex -> C:\Users\<you>\AppData\Roaming\Codex
appdata_roaming\com.openai.codex -> C:\Users\<you>\AppData\Roaming\com.openai.codex
appdata_roaming\OpenAI\Codex -> C:\Users\<you>\AppData\Roaming\OpenAI\Codex

home/.codex -> ~/.codex
appdata_roaming/Codex -> ~/Library/Application Support/Codex
appdata_roaming/com.openai.codex -> ~/Library/Application Support/com.openai.codex
appdata_roaming/OpenAI/Codex -> ~/Library/Application Support/OpenAI/Codex

Project folders, if included, are under projects/. On Windows, Restore-Codex-To-Windows.ps1 -RestoreProjects copies them to %USERPROFILE%\Documents\Codex-Restored-Projects by default and attempts:

  codex app <restored-project-path>

On Mac, Restore-Codex-To-Mac.sh --restore-projects copies them to ~/Documents/Codex-Restored-Projects by default and invokes:

  /Applications/Codex.app/Contents/Resources/codex app <restored-project-path>

This official Codex Desktop entry point registers/opens restored projects in the app-visible project list. Hand-editing .codex-global-state.json alone is not enough, because a running Codex Desktop process can overwrite that file on quit. If Windows packaged-app permissions block the CLI call, reopen the restored folder from Codex Desktop and rerun the verifier.

If Codex asks you to log in again, log in normally.

Security note:
By default this package is expected to exclude browser login state, auth.json,
.env files, and private keys. If it was created with full-with-secrets, treat it
like a password vault and transfer it only through a private channel.
EOF

cp -p "$STAGE/README-Restore.txt" "$STAGE/README-Windows-Restore.txt"

if [[ -f "$SCRIPT_DIR/restore_codex_to_windows.ps1" ]]; then
  cp -p "$SCRIPT_DIR/restore_codex_to_windows.ps1" "$STAGE/Restore-Codex-To-Windows.ps1"
else
  echo "Missing restore_codex_to_windows.ps1" >&2
  exit 1
fi

if [[ -f "$SCRIPT_DIR/verify_windows_codex_restore.ps1" ]]; then
  cp -p "$SCRIPT_DIR/verify_windows_codex_restore.ps1" "$STAGE/Verify-Codex-Windows-Restore.ps1"
fi
if [[ -f "$SCRIPT_DIR/restore_codex_to_mac.sh" ]]; then
  cp -p "$SCRIPT_DIR/restore_codex_to_mac.sh" "$STAGE/Restore-Codex-To-Mac.sh"
fi
if [[ -f "$SCRIPT_DIR/verify_mac_codex_restore.sh" ]]; then
  cp -p "$SCRIPT_DIR/verify_mac_codex_restore.sh" "$STAGE/Verify-Codex-Mac-Restore.sh"
fi
if [[ -f "$SCRIPT_DIR/collect_mac_codex_inventory.sh" ]]; then
  cp -p "$SCRIPT_DIR/collect_mac_codex_inventory.sh" "$STAGE/Collect-Mac-Codex-Inventory.sh"
fi

{
  echo "created_at=$STAMP"
  echo "source_home=$HOME"
  echo "source_os=Mac"
  echo "package_schema_version=3"
  echo "mode=$MODE"
  echo "package=$ZIP_PATH"
  echo "projects=${PROJECTS[*]:-}"
  echo "selected_chats=${SELECTED_CHATS[*]:-}"
  echo
  echo "[source_paths]"
  for path in \
    "$HOME/.codex" \
    "$HOME/Library/Application Support/Codex" \
    "$HOME/Library/Application Support/com.openai.codex" \
    "$HOME/Library/Application Support/OpenAI/Codex" \
    "$HOME/Library/Caches/Codex" \
    "$HOME/Library/Logs/com.openai.codex"; do
    if [[ -e "$path" ]]; then
      printf "%s\t" "$path"
      du -sh "$path" 2>/dev/null | awk '{print $1}' || true
    fi
  done
  echo
  echo "[counts]"
  [[ -d "$HOME/.codex/sessions" ]] && echo "sessions=$(find "$HOME/.codex/sessions" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  [[ -d "$HOME/.codex/archived_sessions" ]] && echo "archived_sessions=$(find "$HOME/.codex/archived_sessions" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  [[ -d "$HOME/.codex/skills" ]] && echo "skills=$(find "$HOME/.codex/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')"
  [[ -d "$HOME/.codex/plugins/cache" ]] && echo "plugin_manifests=$(find "$HOME/.codex/plugins/cache" -name 'plugin.json' 2>/dev/null | wc -l | tr -d ' ')"
  [[ -d "$HOME/.codex/generated_images" ]] && echo "generated_images=$(find "$HOME/.codex/generated_images" -type f 2>/dev/null | wc -l | tr -d ' ')"
  echo "projects=$(find "$STAGE/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')"
  echo "selected_chats=$(find "$STAGE/selected_chats" -name '*.jsonl' 2>/dev/null | wc -l | tr -d ' ')"
  echo "thread_index_export=$(find "$METADATA" -name 'thread_index_export.json' 2>/dev/null | wc -l | tr -d ' ')"
  echo "path_map=$(find "$METADATA" -name 'path_map.json' 2>/dev/null | wc -l | tr -d ' ')"
  echo "project_ui_registry_export=$(find "$METADATA" -name 'project_ui_registry_export.json' 2>/dev/null | wc -l | tr -d ' ')"
  echo
  echo "[sizes]"
  du -sh "$STAGE"/* 2>/dev/null || true
} > "$STAGE/MANIFEST.txt"

count_matches() {
  local root="$1"
  shift
  if [[ -e "$root" ]]; then
    find "$root" "$@" 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

SESSIONS_COUNT="$(count_matches "$STAGE/home/.codex/sessions" -name '*.jsonl')"
ARCHIVED_SESSIONS_COUNT="$(count_matches "$STAGE/home/.codex/archived_sessions" -name '*.jsonl')"
SKILLS_COUNT="$(count_matches "$STAGE/home/.codex/skills" -name 'SKILL.md')"
PLUGIN_MANIFESTS_COUNT="$(count_matches "$STAGE/home/.codex/plugins/cache" -name 'plugin.json')"
GENERATED_IMAGES_COUNT="$(count_matches "$STAGE/home/.codex/generated_images" -type f)"
SQLITE_FILES_COUNT="$(count_matches "$STAGE/home/.codex" -name '*.sqlite')"
PROJECTS_COUNT="$(count_matches "$STAGE/projects" -mindepth 1 -maxdepth 1 -type d)"
SELECTED_CHATS_COUNT="$(count_matches "$STAGE/selected_chats" -name '*.jsonl')"
THREAD_INDEX_EXPORT_COUNT="$(count_matches "$METADATA" -name 'thread_index_export.json')"
PATH_MAP_COUNT="$(count_matches "$METADATA" -name 'path_map.json')"
PROJECT_UI_REGISTRY_EXPORT_COUNT="$(count_matches "$METADATA" -name 'project_ui_registry_export.json')"

cat > "$STAGE/MANIFEST.json" <<EOF
{
  "created_at": "$STAMP",
  "source_os": "Mac",
  "package_schema_version": 3,
  "source_home": "$HOME",
  "mode": "$MODE",
  "package": "$ZIP_PATH",
  "projects": "$(printf '%s ' "${PROJECTS[@]:-}" | sed 's/ *$//')",
  "selected_chats": "$(printf '%s ' "${SELECTED_CHATS[@]:-}" | sed 's/ *$//')",
  "counts": {
    "sessions": $SESSIONS_COUNT,
    "archived_sessions": $ARCHIVED_SESSIONS_COUNT,
    "skills": $SKILLS_COUNT,
    "plugin_manifests": $PLUGIN_MANIFESTS_COUNT,
    "generated_images": $GENERATED_IMAGES_COUNT,
    "sqlite_files": $SQLITE_FILES_COUNT,
    "projects": $PROJECTS_COUNT,
    "selected_chats": $SELECTED_CHATS_COUNT,
    "thread_index_export": $THREAD_INDEX_EXPORT_COUNT,
    "path_map": $PATH_MAP_COUNT,
    "project_ui_registry_export": $PROJECT_UI_REGISTRY_EXPORT_COUNT
  },
  "notes": [
    "Schema v3 metadata exports thread rows, path mapping, selected chats, and non-sensitive project UI registry hints for target restore.",
    "Use docs/SENSITIVE-FILES.txt to review suspected sensitive files without exposing values.",
    "Run the restore script for the target OS only after closing Codex on that target."
  ]
}
EOF

(cd "$STAGE" && find . -type f ! -name SHA256SUMS.txt -print0 | xargs -0 shasum -a 256 > SHA256SUMS.txt)
(cd "$OUT_DIR" && zip -qry "$(basename "$ZIP_PATH")" "$(basename "$STAGE")")

echo "Created: $ZIP_PATH"
du -sh "$ZIP_PATH" "$STAGE"
