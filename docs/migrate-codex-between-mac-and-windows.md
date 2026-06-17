# How to Migrate OpenAI Codex Desktop Between Mac and Windows

This guide explains how to use `codex-mac-windows-migration-handoff` when the source and target computers may be Mac or Windows.

The basic flow is always the same:

1. Close Codex on the source computer.
2. Package Codex data on the source computer.
3. Transfer the generated zip privately.
4. Install and open Codex once on the target computer.
5. Close Codex on the target computer.
6. Restore with the target OS script.
7. Verify the restore.
8. Reopen project folders from their new target paths.

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
cd /path/to/codex-mac-windows-migration-handoff
bash scripts/create_mac_codex_migration_package.sh \
  --mode standard \
  --project "$HOME/Documents/New project"
```

The generated package is written to the Mac Desktop by default.

## Package On Windows

Run from PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\codex-mac-windows-migration-handoff\scripts\create_windows_codex_migration_package.ps1 `
  -Mode standard `
  -Project "$env:USERPROFILE\Documents\New project"
```

The generated package is written to the Windows Desktop by default.

## Restore To Windows

Unzip the package, open PowerShell inside the extracted folder, then run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Restore-Codex-To-Windows.ps1
.\Verify-Codex-Windows-Restore.ps1
```

## Restore To Mac

Unzip the package, open Terminal inside the extracted folder, then run:

```bash
bash ./Restore-Codex-To-Mac.sh
bash ./Verify-Codex-Mac-Restore.sh
```

## What Gets Moved

Standard mode is designed for normal migration. It includes Codex conversations, sessions, archived sessions, memories, goals, user skills, plugin cache and manifests, generated images, selected app state, path mapping, and project folders passed with `--project` or `-Project`.

It excludes browser cookies, Login Data, Local Storage, `.env` files, API keys, private keys, sockets, `.git`, `node_modules`, virtual environments, and runtime-only files by default.

## Project Folders Matter

Codex history and project files are separate. If the old conversations mention a local project, include that project folder with `--project` on Mac or `-Project` on Windows.

Do not bulk rewrite old JSONL session files just to change old absolute paths. Keep the history intact, record the mapping in the package manifest, and reopen the project folder from the new path on the target computer.

## Login State

Expect to log in again on the target computer. Cross-machine login state is fragile and often tied to OS keychains, browser stores, or encrypted app storage. The default migration modes intentionally avoid copying those files.

## Which Path Is Most Tested?

The original successful real-world path was Mac to Windows. Windows to Windows has passed an isolated fake-profile simulation on Windows. Mac to Mac has passed an isolated fake-HOME simulation on an Intel Mac running macOS 12.7.6.

Windows to Mac is layout-validated because Windows and Mac packages use the same neutral package layout, but it still needs a real Windows-origin zip restored on Mac for full end-to-end validation.

For details, see [Validation status](validation-status.md). For any new direction, run the target verifier and check that sessions, skills, plugins, generated images, and project folders are visible before deleting anything from the source computer.
