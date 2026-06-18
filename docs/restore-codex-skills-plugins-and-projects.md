# How to Restore Codex Skills, Plugins, and Projects

This guide explains how to restore Codex skills, plugin cache, generated images, and project folders after creating a migration package with `codex-rehome`.

For the full direction picker, see [How to migrate Codex between Mac and Windows](migrate-codex-between-mac-and-windows.md).

## What The Restore Scripts Copy

The generated package uses neutral folder names so the same package can be restored to Mac or Windows.

| Package folder | Windows destination | Mac destination |
|---|---|---|
| `home/.codex` | `%USERPROFILE%\.codex` | `~/.codex` |
| `appdata_roaming/Codex` | `%APPDATA%\Codex` | `~/Library/Application Support/Codex` |
| `appdata_roaming/com.openai.codex` | `%APPDATA%\com.openai.codex` | `~/Library/Application Support/com.openai.codex` |
| `appdata_roaming/OpenAI/Codex` | `%APPDATA%\OpenAI\Codex` | `~/Library/Application Support/OpenAI/Codex` |

Project folders are included under `projects/` in the migration package. On Mac, pass `--restore-projects` to copy them into `~/Documents/Codex-Restored-Projects` by default, or pass `--projects-dir <dir>` to choose another location. On Windows, pass `-RestoreProjects` to copy them into `%USERPROFILE%\Documents\Codex-Restored-Projects` by default, or pass `-ProjectsDir <dir>` to choose another location.

## Restore To Windows

After unzipping the package and closing Codex:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Restore-Codex-To-Windows.ps1 -RestoreProjects
.\Verify-Codex-Windows-Restore.ps1 -Json
```

## Restore To Mac

After unzipping the package and closing Codex:

```bash
bash ./Restore-Codex-To-Mac.sh --restore-projects
bash ./Verify-Codex-Mac-Restore.sh --json
```

For an isolated Mac test without touching the real profile:

```bash
TEST_HOME="$(mktemp -d /tmp/codex-win-to-mac.XXXXXX)"
HOME="$TEST_HOME" bash ./Restore-Codex-To-Mac.sh --restore-projects
HOME="$TEST_HOME" bash ./Verify-Codex-Mac-Restore.sh --json
```

## Path Mapping Notes

Old conversations may reference source-computer paths like:

```text
/Users/caleb/Documents/New project
C:\Users\Administrator\Documents\New project
```

On the target computer, restore the matching project folder from its new location and let the restore script consume schema v3 metadata when present. Windows and Mac target scripts now rewrite selected restored session metadata, merge selected thread rows into `state_*.sqlite`, update project registry hints, and attempt app-visible project registration through `codex app <restored-project-path>`. If the Windows packaged app blocks CLI execution, the verifier reports app registration as incomplete; manually reopen that restored project folder from Codex Desktop.
