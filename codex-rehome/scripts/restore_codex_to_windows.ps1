param(
    [switch]$ReplaceCodexHome,
    [switch]$ReplaceState,
    [switch]$RestoreProjects,
    [string]$ProjectsDir = (Join-Path $env:USERPROFILE "Documents\Codex-Restored-Projects")
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
if ((Split-Path -Leaf $Root) -ieq "scripts") {
    $Root = Split-Path -Parent $Root
}

$Stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$SourceCodexHome = Join-Path $Root "home\.codex"
$TargetCodexHome = Join-Path $env:USERPROFILE ".codex"
$PreserveFiles = @(
    "auth.json",
    "config.toml",
    "installation_id",
    "models_cache.json",
    "chrome-native-hosts-v2.json"
)

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][AllowEmptyCollection()][string[]]$Lines
    )
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, (($Lines -join "`n") + "`n"), $encoding)
}

function Backup-CopyIfExists {
    param([string]$Path)

    if (Test-Path -LiteralPath $Path) {
        $BackupPath = "$Path.backup-$Stamp"
        Write-Host "Backing up existing data copy:"
        Write-Host "  $Path"
        Write-Host "  -> $BackupPath"
        Copy-Item -LiteralPath $Path -Destination $BackupPath -Recurse -Force
    }
}

function Merge-Directory {
    param(
        [string]$Source,
        [string]$Destination
    )

    if (-not (Test-Path -LiteralPath $Source -PathType Container)) {
        return
    }

    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $Destination $_.Name) -Recurse -Force
    }
    Write-Host "Merged: $Destination"
}

function Copy-FilePreserve {
    param(
        [string]$Source,
        [string]$Destination
    )
    if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { return }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Destination -Force
}

function Find-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) {
        return [pscustomobject]@{ command = $python.Source; args = @() }
    }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) {
        return [pscustomobject]@{ command = $py.Source; args = @("-3") }
    }
    return $null
}

function Save-PreservedFiles {
    param([string]$KeepDir)
    New-Item -ItemType Directory -Force -Path $KeepDir | Out-Null
    foreach ($name in $PreserveFiles) {
        $src = Join-Path $TargetCodexHome $name
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-FilePreserve -Source $src -Destination (Join-Path $KeepDir $name)
        }
    }
}

function Restore-PreservedFiles {
    param([string]$KeepDir)
    foreach ($name in $PreserveFiles) {
        $src = Join-Path $KeepDir $name
        if (Test-Path -LiteralPath $src -PathType Leaf) {
            Copy-FilePreserve -Source $src -Destination (Join-Path $TargetCodexHome $name)
        }
    }
}

function Get-SessionEntryFromJsonl {
    param([string]$Path)

    $sessionId = ""
    $threadName = ""
    $updatedAt = ""
    $firstUser = ""

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }

    Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try { $row = $_ | ConvertFrom-Json -ErrorAction Stop } catch { return }
        $payload = $null
        if ($row.PSObject.Properties.Name -contains "payload") { $payload = $row.payload }

        if (($row.type -eq "session_meta") -or ($payload -and $payload.type -eq "session_meta")) {
            if ($payload -and $payload.id) { $script:sessionIdFromMeta = [string]$payload.id }
            if ($payload -and $payload.thread_name) { $script:threadNameFromMeta = [string]$payload.thread_name }
            elseif ($payload -and $payload.name) { $script:threadNameFromMeta = [string]$payload.name }
            elseif ($payload -and $payload.title) { $script:threadNameFromMeta = [string]$payload.title }
        }
        if (-not $script:sessionIdFromAny) {
            if ($row.id) { $script:sessionIdFromAny = [string]$row.id }
            elseif ($payload -and $payload.id) { $script:sessionIdFromAny = [string]$payload.id }
        }
        $ts = $null
        if ($row.timestamp) { $ts = $row.timestamp }
        elseif ($payload -and $payload.timestamp) { $ts = $payload.timestamp }
        elseif ($row.updated_at) { $ts = $row.updated_at }
        elseif ($payload -and $payload.updated_at) { $ts = $payload.updated_at }
        if ($ts) { $script:updatedAtFromRows = [string]$ts }

        if (-not $script:firstUserFromRows -and $payload -and $payload.message -and $payload.message.role -eq "user") {
            $content = $payload.message.content
            if ($content -is [string]) {
                $script:firstUserFromRows = ($content -replace "`r?`n", " ").Trim()
            }
        }
    }

    $sessionId = $script:sessionIdFromMeta
    if (-not $sessionId) { $sessionId = $script:sessionIdFromAny }
    if (-not $sessionId) { $sessionId = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $threadName = $script:threadNameFromMeta
    if (-not $threadName) { $threadName = $script:firstUserFromRows }
    if (-not $threadName) { $threadName = [System.IO.Path]::GetFileNameWithoutExtension($Path) }
    $updatedAt = $script:updatedAtFromRows

    Remove-Variable -Scope Script -Name sessionIdFromMeta,threadNameFromMeta,sessionIdFromAny,updatedAtFromRows,firstUserFromRows -ErrorAction SilentlyContinue

    return [ordered]@{
        id = $sessionId
        thread_name = $threadName
        updated_at = $updatedAt
    }
}

function Read-SessionIndexRows {
    param([string]$Path)
    $rows = @()
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $rows }
    Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue | ForEach-Object {
        if ([string]::IsNullOrWhiteSpace($_)) { return }
        try { $rows += ($_ | ConvertFrom-Json -ErrorAction Stop) } catch {}
    }
    return $rows
}

function Merge-SessionIndex {
    New-Item -ItemType Directory -Force -Path $TargetCodexHome | Out-Null
    $targetIndex = Join-Path $TargetCodexHome "session_index.jsonl"
    $packageIndex = Join-Path $SourceCodexHome "session_index.jsonl"
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = @{}

    foreach ($row in (Read-SessionIndexRows -Path $targetIndex)) {
        if ($row.id -and -not $seen.ContainsKey([string]$row.id)) {
            $rows.Add($row)
            $seen[[string]$row.id] = $true
        }
    }

    $sourceRows = @(Read-SessionIndexRows -Path $packageIndex)
    if ($sourceRows.Count -eq 0) {
        $sourceRows = @()
        foreach ($root in @((Join-Path $SourceCodexHome "sessions"), (Join-Path $Root "selected_chats"))) {
            if (Test-Path -LiteralPath $root -PathType Container) {
                Get-ChildItem -LiteralPath $root -Filter "*.jsonl" -Recurse -Force -File -ErrorAction SilentlyContinue | ForEach-Object {
                    $entry = Get-SessionEntryFromJsonl -Path $_.FullName
                    if ($entry) { $sourceRows += [pscustomobject]$entry }
                }
            }
        }
    }

    foreach ($row in $sourceRows) {
        if ($row.id -and -not $seen.ContainsKey([string]$row.id)) {
            $rows.Add([ordered]@{
                id = [string]$row.id
                thread_name = if ($row.thread_name) { [string]$row.thread_name } else { [string]$row.id }
                updated_at = if ($row.updated_at) { [string]$row.updated_at } else { "" }
            })
            $seen[[string]$row.id] = $true
        }
    }

    $lines = foreach ($row in $rows) { $row | ConvertTo-Json -Compress -Depth 5 }
    Write-Utf8NoBomLf -Path $targetIndex -Lines $lines
    Write-Host "Merged session_index.jsonl"
}

function Merge-StateFiles {
    foreach ($pattern in @("state_*.sqlite", "state_*.sqlite-*", "memories_*.sqlite", "memories_*.sqlite-*", "goals_*.sqlite", "goals_*.sqlite-*")) {
        Get-ChildItem -LiteralPath $SourceCodexHome -Filter $pattern -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $dst = Join-Path $TargetCodexHome $_.Name
            if ($ReplaceState -or -not (Test-Path -LiteralPath $dst)) {
                Copy-FilePreserve -Source $_.FullName -Destination $dst
                Write-Host "Restored state file: $dst"
            } else {
                Write-Host "Kept existing state file: $dst"
            }
        }
    }
}

function Replace-CodexHome {
    $keepDir = Join-Path $env:USERPROFILE ".codex.preserved-$Stamp"
    Save-PreservedFiles -KeepDir $keepDir
    if (Test-Path -LiteralPath $TargetCodexHome) {
        $backup = "$TargetCodexHome.backup-$Stamp"
        Write-Host "Replacing .codex after backup:"
        Write-Host "  $TargetCodexHome"
        Write-Host "  -> $backup"
        Move-Item -LiteralPath $TargetCodexHome -Destination $backup
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $TargetCodexHome) | Out-Null
    Copy-Item -LiteralPath $SourceCodexHome -Destination $TargetCodexHome -Recurse -Force
    Restore-PreservedFiles -KeepDir $keepDir
    Remove-Item -LiteralPath $keepDir -Recurse -Force -ErrorAction SilentlyContinue
}

function Merge-CodexHome {
    New-Item -ItemType Directory -Force -Path $TargetCodexHome | Out-Null
    Backup-CopyIfExists -Path $TargetCodexHome

    Merge-Directory -Source (Join-Path $SourceCodexHome "sessions") -Destination (Join-Path $TargetCodexHome "sessions")
    Merge-Directory -Source (Join-Path $SourceCodexHome "archived_sessions") -Destination (Join-Path $TargetCodexHome "archived_sessions")
    Merge-Directory -Source (Join-Path $SourceCodexHome "skills") -Destination (Join-Path $TargetCodexHome "skills")
    Merge-Directory -Source (Join-Path $SourceCodexHome "plugins\cache") -Destination (Join-Path $TargetCodexHome "plugins\cache")
    Merge-Directory -Source (Join-Path $SourceCodexHome "generated_images") -Destination (Join-Path $TargetCodexHome "generated_images")

    Merge-StateFiles
    Merge-SessionIndex

    foreach ($name in $PreserveFiles) {
        $dst = Join-Path $TargetCodexHome $name
        if (Test-Path -LiteralPath $dst -PathType Leaf) {
            Write-Host "Preserved target file: $dst"
        }
    }
}

function Restore-Projects {
    if (-not $RestoreProjects) {
        Write-Host "Project restore not requested. Pass -RestoreProjects to copy projects\."
        return
    }
    $sourceProjects = Join-Path $Root "projects"
    if (-not (Test-Path -LiteralPath $sourceProjects -PathType Container)) {
        Write-Host "No projects directory found in package: $sourceProjects"
        return
    }
    New-Item -ItemType Directory -Force -Path $ProjectsDir | Out-Null
    Get-ChildItem -LiteralPath $sourceProjects -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Merge-Directory -Source $_.FullName -Destination (Join-Path $ProjectsDir $_.Name)
    }
    Write-Host "Restored project folders to: $ProjectsDir"
}

function Import-UiReadyMetadata {
    $metadataDir = Join-Path $Root "metadata"
    if (-not (Test-Path -LiteralPath $metadataDir -PathType Container)) {
        Write-Host "No schema v3 metadata directory found; skipping UI-ready metadata import."
        return
    }
    $python = Find-PythonCommand
    if (-not $python) {
        Write-Warning "Python with sqlite3 was not found. UI-ready metadata import skipped."
        return
    }

    $pyCode = @'
import json
import shutil
import sqlite3
import sys
from pathlib import Path

root = Path(sys.argv[1])
codex_home = Path(sys.argv[2])
projects_dir = Path(sys.argv[3])
stamp = sys.argv[4]
metadata = root / "metadata"

def read_json(path, default):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        pass
    return default

path_map = read_json(metadata / "path_map.json", {"projects": []})
thread_export = read_json(metadata / "thread_index_export.json", {"threads": [], "selected_thread_ids": []})
registry_export = read_json(metadata / "project_ui_registry_export.json", {"project_registry": {}})

def target_for_project(entry):
    name = entry.get("package_project_name") or Path(str(entry.get("source_path", ""))).name
    return str(projects_dir / name)

path_pairs = []
target_projects = []
for entry in path_map.get("projects", []) or []:
    target = target_for_project(entry)
    if target not in target_projects:
        target_projects.append(target)
    for src in entry.get("source_path_variants") or []:
        if src:
            path_pairs.append((str(src), target))
    src = entry.get("source_path")
    if src:
        src = str(src)
        path_pairs.append((src, target))
        path_pairs.append((src.replace("\\", "/"), target.replace("\\", "/")))
        if not src.startswith("\\\\?\\"):
            path_pairs.append(("\\\\?\\" + src, target))

path_pairs = sorted(
    list(dict.fromkeys(path_pairs)),
    key=lambda item: len(item[0]) if item and item[0] else 0,
    reverse=True,
)

def map_path(value):
    if value is None:
        return value
    s = str(value)
    for old, new in path_pairs:
        if old:
            s = s.replace(old, new)
            s = s.replace(old.replace("\\", "\\\\"), new)
    return s

def map_json_text(text):
    result = text
    for old, new in path_pairs:
        if not old:
            continue
        result = result.replace(old.replace("\\", "\\\\"), new.replace("\\", "\\\\"))
        result = result.replace(old, new)
        result = result.replace(old.replace("\\", "/"), new.replace("\\", "/"))
    return result

def selected_or_exported_ids():
    ids = []
    for tid in thread_export.get("selected_thread_ids", []) or []:
        if tid and str(tid) not in ids:
            ids.append(str(tid))
    for row in thread_export.get("threads", []) or []:
        tid = row.get("id")
        if tid and str(tid) not in ids:
            ids.append(str(tid))
    return ids

def find_session_file(thread_id):
    sessions = codex_home / "sessions"
    if not sessions.exists():
        return None
    matches = list(sessions.rglob(f"*{thread_id}*.jsonl"))
    if matches:
        return matches[0]
    direct = sessions / f"{thread_id}.jsonl"
    return direct if direct.exists() else None

def rewrite_jsonl_paths():
    changed = 0
    for tid in selected_or_exported_ids():
        path = find_session_file(tid)
        if not path or not path.exists():
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        new_text = map_json_text(text)
        if new_text != text:
            backup = path.with_name(path.name + f".backup-pathmap-{stamp}")
            if not backup.exists():
                shutil.copy2(path, backup)
            with path.open("w", encoding="utf-8", newline="\n") as f:
                f.write(new_text)
            changed += 1
    return changed

def newest_state_db():
    dbs = sorted(codex_home.glob("state_*.sqlite"), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return dbs[0] if dbs else None

def merge_sqlite_threads():
    db = newest_state_db()
    rows = thread_export.get("threads", []) or []
    if not db or not rows:
        return 0
    backup = db.with_name(db.name + f".backup-thread-import-{stamp}")
    if not backup.exists():
        shutil.copy2(db, backup)
    con = sqlite3.connect(str(db))
    con.row_factory = sqlite3.Row
    cols = [r[1] for r in con.execute("pragma table_info(threads)").fetchall()]
    if not cols:
        con.close()
        return 0
    required_defaults = {
        "rollout_path": "",
        "created_at": 0,
        "updated_at": 0,
        "source": "vscode",
        "model_provider": "openai",
        "cwd": "",
        "title": "",
        "sandbox_policy": "{}",
        "approval_mode": "on-request",
        "tokens_used": 0,
        "has_user_event": 0,
        "archived": 0,
        "cli_version": "",
        "first_user_message": "",
        "memory_mode": "enabled",
        "preview": "",
    }
    imported = 0
    for row in rows:
        tid = row.get("id")
        if not tid:
            continue
        tid = str(tid)
        d = dict(row)
        cwd = map_path(d.get("cwd") or "")
        if cwd:
            d["cwd"] = cwd
        session_file = find_session_file(tid)
        if session_file:
            d["rollout_path"] = str(session_file)
        elif d.get("rollout_path"):
            d["rollout_path"] = map_path(d.get("rollout_path"))
        for key in ["sandbox_policy", "git_origin_url", "agent_path"]:
            if d.get(key):
                d[key] = map_path(d[key])
        existing = con.execute("select * from threads where id=?", (tid,)).fetchone()
        values = {}
        for col in cols:
            if col == "id":
                values[col] = tid
            elif col in d and d[col] is not None:
                values[col] = d[col]
            elif existing is not None:
                values[col] = existing[col]
            else:
                values[col] = required_defaults.get(col)
        if existing is None:
            insert_cols = [c for c in cols if values.get(c) is not None]
            placeholders = ",".join(["?"] * len(insert_cols))
            con.execute(
                f"insert into threads ({','.join(insert_cols)}) values ({placeholders})",
                [values[c] for c in insert_cols],
            )
        else:
            update_cols = [c for c in cols if c != "id" and values.get(c) is not None]
            if update_cols:
                con.execute(
                    f"update threads set {','.join([c + '=?' for c in update_cols])} where id=?",
                    [values[c] for c in update_cols] + [tid],
                )
        imported += 1
    con.commit()
    con.close()
    return imported

def merge_global_state():
    state_path = codex_home / ".codex-global-state.json"
    if state_path.exists():
        try:
            data = json.loads(state_path.read_text(encoding="utf-8", errors="ignore"))
        except Exception:
            data = {}
    else:
        data = {}
    backup = state_path.with_name(state_path.name + f".backup-ui-registry-{stamp}")
    if state_path.exists() and not backup.exists():
        shutil.copy2(state_path, backup)
    for key in ["electron-saved-workspace-roots", "project-order", "active-workspace-roots"]:
        arr = data.get(key)
        if not isinstance(arr, list):
            arr = []
        for target in target_projects:
            if target and target not in arr:
                arr.append(target)
        data[key] = arr
    hints = data.get("thread-workspace-root-hints")
    if not isinstance(hints, dict):
        hints = {}
    for row in thread_export.get("threads", []) or []:
        tid = row.get("id")
        cwd = map_path(row.get("cwd") or "")
        if tid and cwd:
            hints[str(tid)] = cwd
    exported_hints = (registry_export.get("project_registry", {}) or {}).get("thread-workspace-root-hints", {}) or {}
    for tid, path in exported_hints.items():
        hints[str(tid)] = map_path(path)
    data["thread-workspace-root-hints"] = hints
    projectless = data.get("projectless-thread-ids")
    if isinstance(projectless, list):
        ids = set(selected_or_exported_ids())
        data["projectless-thread-ids"] = [tid for tid in projectless if tid not in ids]
    atom = data.get("electron-persisted-atom-state")
    if not isinstance(atom, dict):
        atom = {}
    perms = atom.get("heartbeat-thread-permissions-by-id")
    if not isinstance(perms, dict):
        perms = {}
    exported_perms = (registry_export.get("project_registry", {}) or {}).get("heartbeat-thread-permissions-by-id", {}) or {}
    for tid, value in exported_perms.items():
        perms[str(tid)] = value
    atom["heartbeat-thread-permissions-by-id"] = perms
    data["electron-persisted-atom-state"] = atom
    state_path.parent.mkdir(parents=True, exist_ok=True)
    with state_path.open("w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    return len(target_projects)

rewritten = rewrite_jsonl_paths()
imported = merge_sqlite_threads()
registered = merge_global_state()
report = {
    "schema": 3,
    "session_jsonl_rewritten": rewritten,
    "sqlite_threads_imported": imported,
    "restored_projects_registered": registered,
    "restart_required": True,
}
with (codex_home / "codex-rehome-ui-ready-import-report.json").open("w", encoding="utf-8", newline="\n") as f:
    f.write(json.dumps(report, ensure_ascii=False, indent=2) + "\n")
print(json.dumps(report, ensure_ascii=False, separators=(",", ":")))
'@
    $tmpPy = Join-Path $env:TEMP "codex-rehome-import-ui-ready-$Stamp.py"
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpPy, $pyCode, $encoding)
    try {
        & $python.command @($python.args) $tmpPy $Root $TargetCodexHome $ProjectsDir $Stamp
        if ($LASTEXITCODE -ne 0) {
            throw "UI-ready metadata import failed."
        }
    } finally {
        Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue
    }
}

function Write-RegistrationReport {
    param(
        [string]$Status,
        [string]$Message,
        [string[]]$Paths = @()
    )
    New-Item -ItemType Directory -Force -Path $TargetCodexHome | Out-Null
    $report = [ordered]@{
        status = $Status
        message = $Message
        method = "codex app <project-path>"
        registered_project_paths = @($Paths)
    }
    $json = $report | ConvertTo-Json -Depth 5
    Write-Utf8NoBomLf -Path (Join-Path $TargetCodexHome "codex-rehome-project-registration-report.json") -Lines @($json)
}

function Register-RestoredProjectsWithCodexApp {
    if (-not $RestoreProjects) {
        return
    }
    if ($env:CODEX_REHOME_SKIP_APP_REGISTRATION -eq "1") {
        Write-Host "Skipping Codex Desktop project registration because CODEX_REHOME_SKIP_APP_REGISTRATION=1"
        Write-RegistrationReport -Status "skipped" -Message "CODEX_REHOME_SKIP_APP_REGISTRATION=1"
        return
    }
    if (-not (Test-Path -LiteralPath $ProjectsDir -PathType Container)) {
        Write-RegistrationReport -Status "none" -Message "No restored project directory was found."
        return
    }
    $cmd = $env:CODEX_REHOME_CODEX_APP_PATH
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        $found = Get-Command codex -ErrorAction SilentlyContinue
        if ($found) { $cmd = $found.Source }
    }
    if ([string]::IsNullOrWhiteSpace($cmd)) {
        Write-Host "Codex CLI not found; project files restored, but app-visible project registration was not invoked."
        Write-RegistrationReport -Status "missing_cli" -Message "codex command was not found."
        return
    }

    $registered = New-Object System.Collections.Generic.List[string]
    $failed = 0
    Get-ChildItem -LiteralPath $ProjectsDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        Write-Host "Registering restored project with Codex Desktop: $($_.FullName)"
        try {
            & $cmd app $_.FullName
            if ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) {
                $registered.Add($_.FullName)
            } else {
                $failed += 1
            }
        } catch {
            $failed += 1
            Write-Warning "Codex Desktop project registration failed for $($_.FullName): $($_.Exception.Message)"
        }
    }
    if ($registered.Count -gt 0 -and $failed -eq 0) {
        Write-RegistrationReport -Status "invoked" -Message "codex app registration invoked" -Paths $registered.ToArray()
    } elseif ($registered.Count -gt 0) {
        Write-RegistrationReport -Status "partial" -Message "some codex app registrations failed" -Paths $registered.ToArray()
    } else {
        Write-RegistrationReport -Status "failed" -Message "no restored project directories were registered"
    }
}

if (-not (Test-Path -LiteralPath $SourceCodexHome -PathType Container)) {
    throw "Required source missing: $SourceCodexHome"
}

if ($env:CODEX_REHOME_SKIP_RUNNING_CHECK -ne "1") {
    $RunningCodex = Get-Process -ErrorAction SilentlyContinue | Where-Object {
        $_.ProcessName -match "Codex"
    }

    if ($RunningCodex) {
        Write-Host "Codex appears to be running. Close Codex before continuing."
        Read-Host "Press Enter after Codex is closed"
    }
}

Write-Host "Restoring Codex data..."
Write-Host "Restore mode: $(if ($ReplaceCodexHome) { 'replace-codex-home' } else { 'merge' })"
Write-Host "User profile: $env:USERPROFILE"
Write-Host "Roaming AppData: $env:APPDATA"
Write-Host "Local AppData: $env:LOCALAPPDATA"

if ($ReplaceCodexHome) {
    Replace-CodexHome
} else {
    Merge-CodexHome
}

Restore-Projects
Import-UiReadyMetadata
Register-RestoredProjectsWithCodexApp

foreach ($pair in @(
    @((Join-Path $Root "appdata_roaming\Codex"), (Join-Path $env:APPDATA "Codex")),
    @((Join-Path $Root "appdata_roaming\com.openai.codex"), (Join-Path $env:APPDATA "com.openai.codex")),
    @((Join-Path $Root "appdata_roaming\OpenAI\Codex"), (Join-Path $env:APPDATA "OpenAI\Codex")),
    @((Join-Path $Root "appdata_local\Codex"), (Join-Path $env:LOCALAPPDATA "Codex")),
    @((Join-Path $Root "appdata_local\com.openai.codex"), (Join-Path $env:LOCALAPPDATA "com.openai.codex")),
    @((Join-Path $Root "appdata_local\com.openai.sky.CUAService"), (Join-Path $env:LOCALAPPDATA "com.openai.sky.CUAService")),
    @((Join-Path $Root "appdata_local\com.openai.sky.CUAService.cli"), (Join-Path $env:LOCALAPPDATA "com.openai.sky.CUAService.cli"))
)) {
    $src = $pair[0]
    $dst = $pair[1]
    if (Test-Path -LiteralPath $src -PathType Container) {
        Backup-CopyIfExists -Path $dst
        Merge-Directory -Source $src -Destination $dst
    } else {
        Write-Host "Skipping missing source: $src"
    }
}

foreach ($File in @(
    (Join-Path $env:APPDATA "Codex\SingletonLock"),
    (Join-Path $env:APPDATA "Codex\SingletonCookie"),
    (Join-Path $env:APPDATA "Codex\SingletonSocket")
)) {
    if (Test-Path -LiteralPath $File) {
        Remove-Item -LiteralPath $File -Force
    }
}

Write-Host "Done. Merge restore completed. If restored projects were present, Codex Desktop project registration was attempted with codex app <path>."
