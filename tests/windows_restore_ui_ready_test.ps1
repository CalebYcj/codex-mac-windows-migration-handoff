param()

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$RepoRestoreScript = Join-Path $RepoRoot "codex-rehome\scripts\restore_codex_to_windows.ps1"
$RepoVerifyScript = Join-Path $RepoRoot "codex-rehome\scripts\verify_windows_codex_restore.ps1"

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) {
        throw $Message
    }
}

function Write-Utf8NoBomLf {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][string]$Text
    )
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    $encoding = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($Path, ($Text -replace "`r`n", "`n"), $encoding)
}

$Python = (Get-Command python -ErrorAction SilentlyContinue)
if (-not $Python) {
    $Python = Get-Command py -ErrorAction SilentlyContinue
}
Assert-True ($null -ne $Python) "Python is required for this test."

$Tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("codex-rehome-win-test-" + [Guid]::NewGuid().ToString("N"))
$Package = Join-Path $Tmp "package"
$TargetHome = Join-Path $Tmp "target-home"
$TargetAppData = Join-Path $Tmp "target-appdata"
$TargetLocalAppData = Join-Path $Tmp "target-localappdata"
$ProjectsDir = Join-Path $TargetHome "Documents\Codex-Restored-Projects"

try {
    New-Item -ItemType Directory -Force -Path `
        (Join-Path $Package "home\.codex\sessions"), `
        (Join-Path $Package "metadata"), `
        (Join-Path $Package "projects\visual"), `
        (Join-Path $TargetHome ".codex"), `
        $TargetAppData, `
        $TargetLocalAppData | Out-Null

    $RestoreScript = Join-Path $Package "Restore-Codex-To-Windows.ps1"
    $VerifyScript = Join-Path $Package "Verify-Codex-Windows-Restore.ps1"
    Copy-Item -LiteralPath $RepoRestoreScript -Destination $RestoreScript -Force
    Copy-Item -LiteralPath $RepoVerifyScript -Destination $VerifyScript -Force

    $SourceProject = "C:\Users\OldUser\Documents\visual"
    $ThreadId = "11111111-2222-3333-4444-555555555555"
    $SessionPath = Join-Path $Package "home\.codex\sessions\$ThreadId.jsonl"
    $SessionText = @"
{"type":"session_meta","payload":{"id":"$ThreadId","thread_name":"Visual restored","cwd":"$SourceProject"}}
{"type":"event","payload":{"message":{"role":"user","content":"open $SourceProject"}}}
"@
    Write-Utf8NoBomLf -Path $SessionPath -Text $SessionText
    Write-Utf8NoBomLf -Path (Join-Path $Package "home\.codex\session_index.jsonl") -Text "{""id"":""$ThreadId"",""thread_name"":""Visual restored"",""updated_at"":""2026-06-18T10:00:00Z""}`n"
    Write-Utf8NoBomLf -Path (Join-Path $Package "projects\visual\README.md") -Text "visual project`n"

    $PathMap = @{
        schema = 3
        source_os = "Windows"
        target_os = "Windows"
        projects = @(@{
            source_path = $SourceProject
            source_path_variants = @($SourceProject, ($SourceProject -replace "\\", "/"))
            package_project_name = "visual"
            package_project_path = "projects/visual"
        })
    } | ConvertTo-Json -Depth 8
    Write-Utf8NoBomLf -Path (Join-Path $Package "metadata\path_map.json") -Text ($PathMap + "`n")

    $Selected = @{
        schema = 3
        selected_chats = @(@{
            id = $ThreadId
            source_path = $SessionPath
            package_path = "selected_chats/$ThreadId.jsonl"
        })
    } | ConvertTo-Json -Depth 8
    Write-Utf8NoBomLf -Path (Join-Path $Package "metadata\selected_chats.json") -Text ($Selected + "`n")

    $ThreadExport = @{
        schema = 3
        source_os = "Windows"
        selected_thread_ids = @($ThreadId)
        threads = @(@{
            id = $ThreadId
            cwd = $SourceProject
            rollout_path = (Join-Path $SourceProject ".codex\sessions\$ThreadId.jsonl")
            title = "Visual restored"
            updated_at = "2026-06-18T10:00:00Z"
            archived = 0
            has_user_event = 1
            preview = "visual"
        })
    } | ConvertTo-Json -Depth 8
    Write-Utf8NoBomLf -Path (Join-Path $Package "metadata\thread_index_export.json") -Text ($ThreadExport + "`n")

    $Registry = @{
        schema = 3
        source_os = "Windows"
        project_registry = @{
            "electron-saved-workspace-roots" = @($SourceProject)
            "project-order" = @($SourceProject)
            "active-workspace-roots" = @($SourceProject)
            "thread-workspace-root-hints" = @{ $ThreadId = $SourceProject }
            "heartbeat-thread-permissions-by-id" = @{}
        }
    } | ConvertTo-Json -Depth 8
    Write-Utf8NoBomLf -Path (Join-Path $Package "metadata\project_ui_registry_export.json") -Text ($Registry + "`n")

    $StateDb = Join-Path $TargetHome ".codex\state_5.sqlite"
    $PyCode = @"
import sqlite3, sys
db = sys.argv[1]
con = sqlite3.connect(db)
con.execute('create table threads (id text primary key, cwd text, rollout_path text, title text, updated_at text, archived integer, has_user_event integer, preview text)')
con.commit()
con.close()
"@
    $PyFile = Join-Path $Tmp "create_state.py"
    Write-Utf8NoBomLf -Path $PyFile -Text $PyCode
    & $Python.Source $PyFile $StateDb
    Assert-True ($LASTEXITCODE -eq 0) "Failed to create test sqlite database."

    $oldUserProfile = $env:USERPROFILE
    $oldAppData = $env:APPDATA
    $oldLocalAppData = $env:LOCALAPPDATA
    $oldSkipAppRegistration = $env:CODEX_REHOME_SKIP_APP_REGISTRATION
    $oldSkipRunningCheck = $env:CODEX_REHOME_SKIP_RUNNING_CHECK

    $env:USERPROFILE = $TargetHome
    $env:APPDATA = $TargetAppData
    $env:LOCALAPPDATA = $TargetLocalAppData
    $env:CODEX_REHOME_SKIP_APP_REGISTRATION = "1"
    $env:CODEX_REHOME_SKIP_RUNNING_CHECK = "1"

    Push-Location $Package
    try {
        & $RestoreScript -RestoreProjects -ProjectsDir $ProjectsDir
        Assert-True ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) "Restore script failed."

        $ProjectReadme = Join-Path $ProjectsDir "visual\README.md"
        Assert-True (Test-Path -LiteralPath $ProjectReadme -PathType Leaf) "Project folder was not restored."

        $Report = Join-Path $TargetHome ".codex\codex-rehome-ui-ready-import-report.json"
        Assert-True (Test-Path -LiteralPath $Report -PathType Leaf) "UI-ready import report was not written."

        $RegistrationReport = Join-Path $TargetHome ".codex\codex-rehome-project-registration-report.json"
        Assert-True (Test-Path -LiteralPath $RegistrationReport -PathType Leaf) "Project registration report was not written."

        $RestoredSession = Get-Content -LiteralPath (Join-Path $TargetHome ".codex\sessions\$ThreadId.jsonl") -Raw
        Assert-True (-not $RestoredSession.Contains($SourceProject)) "Old Windows source path remained in restored session JSONL."
        Assert-True ($RestoredSession.Contains($ProjectsDir)) "Restored session JSONL does not contain target project path."

        $CheckPy = @"
import json, sqlite3, sys
db, thread_id = sys.argv[1], sys.argv[2]
con = sqlite3.connect(db)
row = con.execute('select cwd, rollout_path from threads where id=?', (thread_id,)).fetchone()
if not row:
    raise SystemExit('thread row missing')
print(json.dumps({'cwd': row[0], 'rollout_path': row[1]}))
"@
        $CheckPyFile = Join-Path $Tmp "check_state.py"
        Write-Utf8NoBomLf -Path $CheckPyFile -Text $CheckPy
        $ThreadRowJson = & $Python.Source $CheckPyFile $StateDb $ThreadId
        Assert-True ($LASTEXITCODE -eq 0) "Failed to inspect test sqlite database."
        $ThreadRow = $ThreadRowJson | ConvertFrom-Json
        Assert-True ([string]$ThreadRow.cwd -eq (Join-Path $ProjectsDir "visual")) "Thread cwd was not path-mapped into restored project dir."
        Assert-True (Test-Path -LiteralPath ([string]$ThreadRow.rollout_path) -PathType Leaf) "Thread rollout_path does not point to an existing session file."

        $Verify = & $VerifyScript -PackageRoot $Package -ProjectsDir $ProjectsDir -Json | ConvertFrom-Json
        Assert-True ($Verify.counts.selected_chats_in_state_threads -eq 1) "Verifier did not report selected chat in state threads."
        Assert-True ($Verify.ui_readiness.state_threads_ready -eq $true) "Verifier did not report state thread readiness."
        Assert-True ($Verify.ui_readiness.project_path_mapping_ready -eq $true) "Verifier did not report project path mapping readiness."
    } finally {
        Pop-Location
        $env:USERPROFILE = $oldUserProfile
        $env:APPDATA = $oldAppData
        $env:LOCALAPPDATA = $oldLocalAppData
        $env:CODEX_REHOME_SKIP_APP_REGISTRATION = $oldSkipAppRegistration
        $env:CODEX_REHOME_SKIP_RUNNING_CHECK = $oldSkipRunningCheck
    }

    Write-Host "windows_restore_ui_ready_test passed"
} finally {
    Remove-Item -LiteralPath $Tmp -Recurse -Force -ErrorAction SilentlyContinue
}
