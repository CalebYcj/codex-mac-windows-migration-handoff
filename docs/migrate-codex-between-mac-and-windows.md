# How to Migrate OpenAI Codex Desktop Between Mac and Windows

This guide explains how to use `codex-rehome` when the source and target computers may be Mac or Windows.

The basic flow is always the same:

1. Close Codex on the source computer.
2. Package Codex data on the source computer.
3. Transfer the generated zip privately.
4. Install and open Codex once on the target computer.
5. Close Codex on the target computer.
6. Restore with the target OS script.
7. Verify the restore.
8. Confirm project folders are visible from their new target paths.

## Choose Your Direction

| Direction | Package on source | Restore on target | Verify on target |
|---|---|---|---|
| Mac to Windows | `create_mac_codex_migration_package.sh` | `Restore-Codex-To-Windows.ps1` | `Verify-Codex-Windows-Restore.ps1` |
| Windows to Mac | `create_windows_codex_migration_package.ps1` | `Restore-Codex-To-Mac.sh` | `Verify-Codex-Mac-Restore.sh` |
| Windows to Windows | `create_windows_codex_migration_package.ps1` | `Restore-Codex-To-Windows.ps1` | `Verify-Codex-Windows-Restore.ps1` |
| Mac to Mac | `create_mac_codex_migration_package.sh` | `Restore-Codex-To-Mac.sh` | `Verify-Codex-Mac-Restore.sh` |

## Package On Mac

Run from Terminal:

```bash
cd /path/to/codex-rehome
bash scripts/create_mac_codex_migration_package.sh \
  --mode standard \
  --project "$HOME/Documents/New project"
```

The generated package is written to the Mac Desktop by default.

For an acceptance package that highlights specific conversations, pass selected session JSONL files:

```bash
bash scripts/create_mac_codex_migration_package.sh \
  --mode standard \
  --project "$HOME/Documents/New project" \
  --selected-chat "$HOME/.codex/sessions/2026/06/18/rollout-example.jsonl"
```

## Package On Windows

Run from PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\codex-rehome\scripts\create_windows_codex_migration_package.ps1 `
  -Mode standard `
  -Project "$env:USERPROFILE\Documents\New project"
```

The generated package is written to the Windows Desktop by default.

For an acceptance package that highlights specific conversations, pass selected session JSONL files:

```powershell
.\codex-rehome\scripts\create_windows_codex_migration_package.ps1 `
  -Mode standard `
  -Project "$env:USERPROFILE\Documents\New project" `
  -SelectedChat "$env:USERPROFILE\.codex\sessions\2026\06\18\rollout-example.jsonl"
```

## Restore To Windows

Unzip the package, open PowerShell inside the extracted folder, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Restore-Codex-To-Windows.ps1 -RestoreProjects
.\Verify-Codex-Windows-Restore.ps1 -Json
```

By default, `-RestoreProjects` copies package projects into `%USERPROFILE%\Documents\Codex-Restored-Projects`. Use `-ProjectsDir <dir>` if you want a different project destination.

## Restore To Mac

Unzip the package, open Terminal inside the extracted folder, then run:

```bash
bash ./Restore-Codex-To-Mac.sh --restore-projects
bash ./Verify-Codex-Mac-Restore.sh --json
```

By default, `--restore-projects` copies package projects into `~/Documents/Codex-Restored-Projects`. Use `--projects-dir <dir>` if you want a different project destination.

## What Gets Moved

Standard mode is designed for normal migration. It includes Codex conversations, sessions, archived sessions, memories, goals, user skills, plugin cache and manifests, generated images, selected app state, path mapping, and project folders passed with `--project` or `-Project`.

It excludes browser cookies, Login Data, Local Storage, `.env` files, API keys, private keys, sockets, `.git`, `node_modules`, virtual environments, and runtime-only files by default.

## Project Folders Matter

Codex history and project files are separate. If the old conversations mention a local project, include that project folder with `--project` on Mac or `-Project` on Windows.

Do not bulk rewrite old JSONL session files by hand. Keep the history intact, let the target restore script apply schema v3 path mappings for selected restored conversations, and use Codex Desktop's own project-open path to register the restored workspace.

Mac and Windows packages include schema v3 metadata for path mapping, selected chats, thread rows, and project UI registry hints. Windows-generated packages are Mac-friendly: zip entries use forward slashes, `SHA256SUMS.txt` uses LF with no BOM, and both `MANIFEST.txt` and `MANIFEST.json` include source OS, schema version, mode, counts, and exclusion strategy.

If `selected_chats/` is present, the Mac and Windows verifiers report the selected chat count and whether those chats also appear in restored `.codex/sessions`, `session_index.jsonl`, and `state_*.sqlite.threads`.

## Login State

Expect to log in again on the target computer. Cross-machine login state is fragile and often tied to OS keychains, browser stores, or encrypted app storage. The default migration modes intentionally avoid copying those files.

## Supported Directions

All four directions are supported by the neutral package layout and target-specific restore scripts:

- Mac to Windows
- Windows to Mac
- Windows to Windows
- Mac to Mac

For details, see [Feature status](validation-status.md). For any migration, run the target verifier and check that sessions, skills, plugins, generated images, and project folders are visible before deleting anything from the source computer.
