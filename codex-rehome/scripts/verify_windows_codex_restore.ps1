param(
    [string]$PackageRoot = "",
    [string]$ProjectsDir = (Join-Path $env:USERPROFILE "Documents\Codex-Restored-Projects"),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($PackageRoot)) {
    $PackageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ((Split-Path -Leaf $PackageRoot) -ieq "scripts") {
        $PackageRoot = Split-Path -Parent $PackageRoot
    }
}

function Count-Files {
    param(
        [string]$Path,
        [string]$Filter = "*"
    )

    if (-not (Test-Path -LiteralPath $Path)) { return 0 }
    return @(
        Get-ChildItem -LiteralPath $Path -Filter $Filter -Recurse -Force -File -ErrorAction SilentlyContinue
    ).Count
}

function Directory-SizeMb {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $sum = (Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    if ($null -eq $sum) { $sum = 0 }
    return [Math]::Round($sum / 1MB, 2)
}

function Path-Status {
    param([string]$Path)

    [PSCustomObject]@{
        path = $Path
        exists = Test-Path -LiteralPath $Path
        size_mb = Directory-SizeMb -Path $Path
    }
}

function Count-JsonlEntries {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return 0 }
    return @(Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction SilentlyContinue | Where-Object {
        -not [string]::IsNullOrWhiteSpace($_)
    }).Count
}

function Count-ImmediateDirectories {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return 0 }
    return @(Get-ChildItem -LiteralPath $Path -Directory -Force -ErrorAction SilentlyContinue).Count
}

function Get-PythonCommand {
    $python = Get-Command python -ErrorAction SilentlyContinue
    if ($python) { return [pscustomobject]@{ command = $python.Source; args = @() } }
    $py = Get-Command py -ErrorAction SilentlyContinue
    if ($py) { return [pscustomobject]@{ command = $py.Source; args = @("-3") } }
    return $null
}

function Get-UiReadyReport {
    $python = Get-PythonCommand
    if (-not $python) {
        return [ordered]@{
            selected_chats = 0
            selected_chats_in_restored_sessions = 0
            selected_chats_in_session_index = 0
            selected_chats_in_state_threads = 0
            selected_chats_with_existing_rollout_path = 0
            selected_chats_with_target_cwd = 0
            selected_chats_with_session_meta_target_cwd = 0
            selected_chats_without_source_path_in_jsonl = 0
            restored_projects_in_global_state = 0
        }
    }
    $pyCode = @'
import json
import re
import sqlite3
import sys
from pathlib import Path

package = Path(sys.argv[1])
codex_home = Path(sys.argv[2])
projects_dir = Path(sys.argv[3])
metadata = package / "metadata"

def read_json(path, default):
    try:
        if path.exists():
            return json.loads(path.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        pass
    return default

path_map = read_json(metadata / "path_map.json", {"projects": []})
thread_export = read_json(metadata / "thread_index_export.json", {"selected_thread_ids": [], "threads": []})
selected_meta = read_json(metadata / "selected_chats.json", {"selected_chats": []})

def target_for_project(entry):
    name = entry.get("package_project_name") or Path(str(entry.get("source_path", ""))).name
    return str(projects_dir / name)

target_projects = []
source_variants = []
for entry in path_map.get("projects", []) or []:
    target = target_for_project(entry)
    if target not in target_projects:
        target_projects.append(target)
    for value in entry.get("source_path_variants") or []:
        if value:
            source_variants.append(str(value))
            source_variants.append(str(value).replace("\\", "\\\\"))
    src = entry.get("source_path")
    if src:
        source_variants.append(str(src))
        source_variants.append(str(src).replace("\\", "\\\\"))
        source_variants.append(str(src).replace("\\", "/"))

def selected_id_from_file(path):
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            payload = row.get("payload") or {}
            if row.get("type") == "session_meta" or payload.get("type") == "session_meta":
                return str(payload.get("id") or row.get("id") or path.stem)
            if row.get("id"):
                return str(row.get("id"))
    except Exception:
        pass
    return path.stem

selected_ids = []
for item in selected_meta.get("selected_chats", []) or []:
    tid = item.get("id")
    if tid and str(tid) not in selected_ids:
        selected_ids.append(str(tid))
for tid in thread_export.get("selected_thread_ids", []) or []:
    if tid and str(tid) not in selected_ids:
        selected_ids.append(str(tid))
selected_dir = package / "selected_chats"
if selected_dir.exists():
    for path in selected_dir.glob("*.jsonl"):
        tid = selected_id_from_file(path)
        if tid and tid not in selected_ids:
            selected_ids.append(tid)

def find_session_file(tid):
    sessions = codex_home / "sessions"
    if not sessions.exists():
        return None
    matches = list(sessions.rglob(f"*{tid}*.jsonl"))
    if matches:
        return matches[0]
    direct = sessions / f"{tid}.jsonl"
    return direct if direct.exists() else None

def read_index_ids():
    ids = set()
    index = codex_home / "session_index.jsonl"
    if not index.exists():
        return ids
    for line in index.read_text(encoding="utf-8", errors="ignore").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except Exception:
            continue
        if row.get("id"):
            ids.add(str(row["id"]))
    return ids

def session_meta_cwd(path):
    if not path or not path.exists():
        return ""
    try:
        for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except Exception:
                continue
            payload = row.get("payload") or {}
            if row.get("type") == "session_meta" or payload.get("type") == "session_meta":
                return str(payload.get("cwd") or row.get("cwd") or "")
    except Exception:
        pass
    return ""

def newest_state_db():
    dbs = sorted(codex_home.glob("state_*.sqlite"), key=lambda p: p.stat().st_mtime if p.exists() else 0, reverse=True)
    return dbs[0] if dbs else None

index_ids = read_index_ids()
sessions_count = 0
index_count = 0
state_count = 0
rollout_count = 0
target_cwd_count = 0
meta_cwd_count = 0
no_source_count = 0
rows = {}
db = newest_state_db()
if db:
    try:
        con = sqlite3.connect(str(db))
        con.row_factory = sqlite3.Row
        for tid in selected_ids:
            try:
                row = con.execute("select * from threads where id=?", (tid,)).fetchone()
            except Exception:
                row = None
            if row:
                rows[tid] = dict(row)
        con.close()
    except Exception:
        rows = {}

for tid in selected_ids:
    session = find_session_file(tid)
    if session:
        sessions_count += 1
        text = session.read_text(encoding="utf-8", errors="ignore")
        if not any(old and old in text for old in source_variants):
            no_source_count += 1
        cwd = session_meta_cwd(session)
        if cwd and (not target_projects or cwd in target_projects):
            meta_cwd_count += 1
    if tid in index_ids:
        index_count += 1
    row = rows.get(tid)
    if row:
        state_count += 1
        rollout = str(row.get("rollout_path") or "")
        if rollout and Path(rollout).exists():
            rollout_count += 1
        cwd = str(row.get("cwd") or "")
        if cwd and (not target_projects or cwd in target_projects):
            target_cwd_count += 1

global_state = read_json(codex_home / ".codex-global-state.json", {})
global_count = 0
for target in target_projects:
    if target and all(target in (global_state.get(key) or []) for key in ["electron-saved-workspace-roots", "project-order", "active-workspace-roots"]):
        global_count += 1

print(json.dumps({
    "selected_chats": len(selected_ids),
    "selected_chats_in_restored_sessions": sessions_count,
    "selected_chats_in_session_index": index_count,
    "selected_chats_in_state_threads": state_count,
    "selected_chats_with_existing_rollout_path": rollout_count,
    "selected_chats_with_target_cwd": target_cwd_count,
    "selected_chats_with_session_meta_target_cwd": meta_cwd_count,
    "selected_chats_without_source_path_in_jsonl": no_source_count,
    "restored_projects_in_global_state": global_count,
}, ensure_ascii=False))
'@
    $tmpPy = Join-Path $env:TEMP ("codex-rehome-verify-ui-ready-" + [Guid]::NewGuid().ToString("N") + ".py")
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmpPy, $pyCode, $encoding)
    try {
        $raw = & $python.command @($python.args) $tmpPy $PackageRoot $CodexHome $ProjectsDir
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($raw)) {
            throw "ui readiness helper failed"
        }
        return ($raw | ConvertFrom-Json)
    } catch {
        return [ordered]@{
            selected_chats = 0
            selected_chats_in_restored_sessions = 0
            selected_chats_in_session_index = 0
            selected_chats_in_state_threads = 0
            selected_chats_with_existing_rollout_path = 0
            selected_chats_with_target_cwd = 0
            selected_chats_with_session_meta_target_cwd = 0
            selected_chats_without_source_path_in_jsonl = 0
            restored_projects_in_global_state = 0
        }
    } finally {
        Remove-Item -LiteralPath $tmpPy -Force -ErrorAction SilentlyContinue
    }
}

function Read-ProjectRegistrationReport {
    $path = Join-Path $CodexHome "codex-rehome-project-registration-report.json"
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return [ordered]@{ status = "missing"; count = 0; paths = @() }
    }
    try {
        $data = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
        return [ordered]@{
            status = [string]$data.status
            count = @($data.registered_project_paths).Count
            paths = @($data.registered_project_paths)
        }
    } catch {
        return [ordered]@{ status = "invalid"; count = 0; paths = @() }
    }
}

$CodexHome = Join-Path $env:USERPROFILE ".codex"
$RoamingCodex = Join-Path $env:APPDATA "Codex"
$RoamingComOpenAi = Join-Path $env:APPDATA "com.openai.codex"
$RoamingOpenAiCodex = Join-Path $env:APPDATA "OpenAI\Codex"
$Ui = Get-UiReadyReport
$Registration = Read-ProjectRegistrationReport
$SessionIndexEntries = Count-JsonlEntries -Path (Join-Path $CodexHome "session_index.jsonl")
$RestoredProjectCount = Count-ImmediateDirectories -Path $ProjectsDir
$SelectedChats = [int]$Ui.selected_chats
$SelectedInSessions = [int]$Ui.selected_chats_in_restored_sessions
$SelectedInIndex = [int]$Ui.selected_chats_in_session_index
$SelectedInState = [int]$Ui.selected_chats_in_state_threads
$SelectedWithRollout = [int]$Ui.selected_chats_with_existing_rollout_path
$SelectedWithTargetCwd = [int]$Ui.selected_chats_with_target_cwd
$SelectedWithMetaCwd = [int]$Ui.selected_chats_with_session_meta_target_cwd
$SelectedWithoutSourcePath = [int]$Ui.selected_chats_without_source_path_in_jsonl
$RestoredProjectsInGlobalState = [int]$Ui.restored_projects_in_global_state
$SelectedSessionsReady = ($SelectedChats -eq 0 -or $SelectedInSessions -eq $SelectedChats)
$SelectedIndexReady = ($SelectedChats -eq 0 -or $SelectedInIndex -eq $SelectedChats)
$StateThreadsReady = ($SelectedChats -eq 0 -or $SelectedInState -eq $SelectedChats)
$RolloutReady = ($SelectedChats -eq 0 -or $SelectedWithRollout -eq $SelectedChats)
$PathMappingReady = ($SelectedChats -eq 0 -or $SelectedWithTargetCwd -eq $SelectedChats)
$SessionJsonlPathReady = ($SelectedChats -eq 0 -or $SelectedWithMetaCwd -eq $SelectedChats)
$SourcePathRemovedReady = ($SelectedChats -eq 0 -or $SelectedWithoutSourcePath -eq $SelectedChats)
$GlobalProjectRegistryReady = ($RestoredProjectCount -eq 0 -or $RestoredProjectsInGlobalState -eq $RestoredProjectCount)
$AppProjectRegistrationReady = ($RestoredProjectCount -eq 0 -or (($Registration.status -eq "invoked" -or $Registration.status -eq "skipped") -and $Registration.count -ge $RestoredProjectCount))

$Report = [ordered]@{
    generated_at = (Get-Date).ToString("s")
    package_root = $PackageRoot
    windows_user = $env:USERNAME
    paths = @(
        Path-Status -Path $CodexHome
        Path-Status -Path $RoamingCodex
        Path-Status -Path $RoamingComOpenAi
        Path-Status -Path $RoamingOpenAiCodex
        Path-Status -Path (Join-Path $env:LOCALAPPDATA "Codex")
    )
    counts = [ordered]@{
        sessions = Count-Files -Path (Join-Path $CodexHome "sessions") -Filter "*.jsonl"
        archived_sessions = Count-Files -Path (Join-Path $CodexHome "archived_sessions") -Filter "*.jsonl"
        skills = Count-Files -Path (Join-Path $CodexHome "skills") -Filter "SKILL.md"
        plugin_manifests = Count-Files -Path (Join-Path $CodexHome "plugins\cache") -Filter "plugin.json"
        generated_images = Count-Files -Path (Join-Path $CodexHome "generated_images")
        sqlite_files = Count-Files -Path $CodexHome -Filter "*.sqlite"
        session_index_entries = $SessionIndexEntries
        restored_project_count = $RestoredProjectCount
        selected_chats = $SelectedChats
        selected_chats_in_restored_sessions = $SelectedInSessions
        selected_chats_in_session_index = $SelectedInIndex
        selected_chats_in_state_threads = $SelectedInState
        selected_chats_with_existing_rollout_path = $SelectedWithRollout
        selected_chats_with_target_cwd = $SelectedWithTargetCwd
        selected_chats_with_session_meta_target_cwd = $SelectedWithMetaCwd
        selected_chats_without_source_path_in_jsonl = $SelectedWithoutSourcePath
        restored_projects_in_global_state = $RestoredProjectsInGlobalState
    }
    ui_readiness = [ordered]@{
        selected_chats_in_sessions_ready = $SelectedSessionsReady
        selected_chats_in_session_index_ready = $SelectedIndexReady
        state_threads_ready = $StateThreadsReady
        rollout_paths_ready = $RolloutReady
        project_path_mapping_ready = $PathMappingReady
        session_jsonl_path_mapping_ready = $SessionJsonlPathReady
        source_path_removed_ready = $SourcePathRemovedReady
        global_project_registry_ready = $GlobalProjectRegistryReady
        app_project_registration_ready = $AppProjectRegistrationReady
    }
    project_ui_registration = $Registration
    restored_project_paths = @(
        if (Test-Path -LiteralPath $ProjectsDir -PathType Container) {
            Get-ChildItem -LiteralPath $ProjectsDir -Directory -Force -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
        }
    )
    important_files = @(
        Path-Status -Path (Join-Path $CodexHome "state_5.sqlite")
        Path-Status -Path (Join-Path $CodexHome "memories_1.sqlite")
        Path-Status -Path (Join-Path $CodexHome "goals_1.sqlite")
        Path-Status -Path (Join-Path $CodexHome "config.toml")
    )
    package_files = @(
        Path-Status -Path (Join-Path $PackageRoot "MANIFEST.txt")
        Path-Status -Path (Join-Path $PackageRoot "MANIFEST.json")
        Path-Status -Path (Join-Path $PackageRoot "SHA256SUMS.txt")
        Path-Status -Path (Join-Path $PackageRoot "docs\SENSITIVE-FILES.txt")
    )
    project_candidates = @(
        Get-ChildItem -LiteralPath (Join-Path $env:USERPROFILE "Documents") -Directory -ErrorAction SilentlyContinue |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $_.FullName ".git") -PathType Container) -or
                (Test-Path -LiteralPath (Join-Path $_.FullName ".agents") -PathType Container) -or
                (Test-Path -LiteralPath (Join-Path $_.FullName "outputs") -PathType Container) -or
                (Test-Path -LiteralPath (Join-Path $_.FullName "artifacts") -PathType Container)
            } |
            Select-Object -First 50 -ExpandProperty FullName
    )
}

if ($Json) {
    $Report | ConvertTo-Json -Depth 6
    exit 0
}

Write-Host "Codex Windows restore verification"
Write-Host "Generated: $($Report.generated_at)"
Write-Host "Package root: $PackageRoot"
Write-Host ""

Write-Host "Paths:"
foreach ($item in $Report.paths) {
    $status = if ($item.exists) { "found" } else { "missing" }
    $size = if ($null -eq $item.size_mb) { "" } else { " ($($item.size_mb) MB)" }
    Write-Host "  [$status] $($item.path)$size"
}

Write-Host ""
Write-Host "Counts:"
foreach ($key in $Report.counts.Keys) {
    Write-Host "  ${key}: $($Report.counts[$key])"
}

Write-Host ""
Write-Host "UI readiness:"
foreach ($key in $Report.ui_readiness.Keys) {
    Write-Host "  ${key}: $($Report.ui_readiness[$key])"
}
Write-Host "  app_registration_status: $($Report.project_ui_registration.status)"
Write-Host "  app_registration_count: $($Report.project_ui_registration.count)"

Write-Host ""
Write-Host "Important files:"
foreach ($item in $Report.important_files) {
    $status = if ($item.exists) { "found" } else { "missing" }
    Write-Host "  [$status] $($item.path)"
}

Write-Host ""
Write-Host "Package metadata:"
foreach ($item in $Report.package_files) {
    $status = if ($item.exists) { "found" } else { "missing" }
    Write-Host "  [$status] $($item.path)"
}

Write-Host ""
Write-Host "Project candidates:"
foreach ($path in $Report.project_candidates) {
    Write-Host "  $path"
}

Write-Host ""
Write-Host "Next checks:"
Write-Host "  1. Open Codex and confirm old threads are visible."
Write-Host "  2. If app_project_registration_ready is false, run: codex app <restored-project-path>, or reopen that project folder from Codex Desktop."
Write-Host "  3. Reconnect GitHub, Gmail, Chrome, Feishu, or other external services if prompted."
