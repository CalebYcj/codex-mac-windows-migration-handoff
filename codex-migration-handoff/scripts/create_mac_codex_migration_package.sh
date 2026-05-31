#!/usr/bin/env bash
set -euo pipefail

OUT_DIR="$HOME/Desktop"
PROJECTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --project)
      PROJECTS+=("$2")
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [--out DIR] [--project /path/to/project]..."
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

STAMP="$(date +%Y%m%d-%H%M%S)"
STAGE="$OUT_DIR/Codex-Windows-Migration-$STAMP"
ZIP_PATH="$OUT_DIR/Codex-Windows-Migration-$STAMP.zip"

mkdir -p "$STAGE/home" \
  "$STAGE/appdata_roaming/OpenAI" \
  "$STAGE/appdata_local" \
  "$STAGE/mac_only/Library/Preferences" \
  "$STAGE/projects" \
  "$STAGE/docs"

copy_dir() {
  local src="$1"
  local dst="$2"
  if [[ -d "$src" ]]; then
    mkdir -p "$(dirname "$dst")"
    if command -v ditto >/dev/null 2>&1; then
      ditto "$src" "$dst"
    else
      rsync -aE "$src/" "$dst/"
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

if command -v sqlite3 >/dev/null 2>&1; then
  for db in "$HOME/.codex"/*.sqlite; do
    [[ -f "$db" ]] && sqlite3 "$db" 'PRAGMA wal_checkpoint(PASSIVE);' >/dev/null 2>&1 || true
  done
fi

copy_dir "$HOME/.codex" "$STAGE/home/.codex"
copy_dir "$HOME/Library/Application Support/Codex" "$STAGE/appdata_roaming/Codex"
copy_dir "$HOME/Library/Application Support/com.openai.codex" "$STAGE/appdata_roaming/com.openai.codex"
copy_dir "$HOME/Library/Application Support/OpenAI/Codex" "$STAGE/appdata_roaming/OpenAI/Codex"

copy_dir "$HOME/Library/Caches/Codex" "$STAGE/appdata_local/Codex"
copy_dir "$HOME/Library/Caches/com.openai.codex" "$STAGE/appdata_local/com.openai.codex"
copy_dir "$HOME/Library/Caches/com.openai.sky.CUAService" "$STAGE/appdata_local/com.openai.sky.CUAService"
copy_dir "$HOME/Library/Caches/com.openai.sky.CUAService.cli" "$STAGE/appdata_local/com.openai.sky.CUAService.cli"

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

cat > "$STAGE/README-Windows-Restore.txt" <<'EOF'
Codex Mac -> Windows migration package
======================================

Before restoring:
1. Install Codex on Windows.
2. Open it once, then close all Codex windows.
3. Unzip this package.

Recommended restore:
1. Open PowerShell in the unzipped folder.
2. Run:
   Set-ExecutionPolicy -Scope Process Bypass
   .\Restore-Codex-To-Windows.ps1

Manual mapping:
home\.codex -> C:\Users\<you>\.codex
appdata_roaming\Codex -> C:\Users\<you>\AppData\Roaming\Codex
appdata_roaming\com.openai.codex -> C:\Users\<you>\AppData\Roaming\com.openai.codex
appdata_roaming\OpenAI\Codex -> C:\Users\<you>\AppData\Roaming\OpenAI\Codex

Project folders, if included, are under projects\. Move them to your desired Windows project location and reopen the folder in Codex.

If Codex asks you to log in again, log in normally.
EOF

cat > "$STAGE/Restore-Codex-To-Windows.ps1" <<'EOF'
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"

function Backup-IfExists {
    param([string]$Path)
    if (Test-Path -LiteralPath $Path) {
        Move-Item -LiteralPath $Path -Destination "$Path.backup-$Stamp"
    }
}

function Restore-Directory {
    param([string]$Source, [string]$Destination)
    if (-not (Test-Path -LiteralPath $Source)) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Backup-IfExists -Path $Destination
    Copy-Item -LiteralPath $Source -Destination $Destination -Recurse -Force
    Write-Host "Restored: $Destination"
}

if (Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match "Codex" }) {
    Write-Host "Close Codex before continuing."
    Read-Host "Press Enter after Codex is closed"
}

Restore-Directory (Join-Path $Root "home\.codex") (Join-Path $env:USERPROFILE ".codex")
Restore-Directory (Join-Path $Root "appdata_roaming\Codex") (Join-Path $env:APPDATA "Codex")
Restore-Directory (Join-Path $Root "appdata_roaming\com.openai.codex") (Join-Path $env:APPDATA "com.openai.codex")
Restore-Directory (Join-Path $Root "appdata_roaming\OpenAI\Codex") (Join-Path $env:APPDATA "OpenAI\Codex")
Restore-Directory (Join-Path $Root "appdata_local\Codex") (Join-Path $env:LOCALAPPDATA "Codex")
Restore-Directory (Join-Path $Root "appdata_local\com.openai.codex") (Join-Path $env:LOCALAPPDATA "com.openai.codex")
Restore-Directory (Join-Path $Root "appdata_local\com.openai.sky.CUAService") (Join-Path $env:LOCALAPPDATA "com.openai.sky.CUAService")
Restore-Directory (Join-Path $Root "appdata_local\com.openai.sky.CUAService.cli") (Join-Path $env:LOCALAPPDATA "com.openai.sky.CUAService.cli")

foreach ($File in @(
    (Join-Path $env:APPDATA "Codex\SingletonLock"),
    (Join-Path $env:APPDATA "Codex\SingletonCookie"),
    (Join-Path $env:APPDATA "Codex\SingletonSocket")
)) {
    if (Test-Path -LiteralPath $File) { Remove-Item -LiteralPath $File -Force }
}

Write-Host "Done. Open Codex and log in again if prompted."
EOF

{
  echo "created_at=$STAMP"
  echo "source_home=$HOME"
  echo "package=$ZIP_PATH"
  echo "projects=${PROJECTS[*]:-}"
  echo
  echo "[sizes]"
  du -sh "$STAGE"/* 2>/dev/null || true
} > "$STAGE/MANIFEST.txt"

(cd "$STAGE" && find . -type f -print0 | xargs -0 shasum -a 256 > SHA256SUMS.txt)
(cd "$OUT_DIR" && zip -qry "$(basename "$ZIP_PATH")" "$(basename "$STAGE")")

echo "Created: $ZIP_PATH"
du -sh "$ZIP_PATH" "$STAGE"
