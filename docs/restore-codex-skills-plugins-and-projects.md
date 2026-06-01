# How to Restore Codex Skills, Plugins, and Projects on Windows

This guide explains how to restore Codex skills, plugin cache, generated images, and project folders on Windows after creating a Mac migration package.

## What The Restore Script Copies

The Windows restore script maps Mac-oriented package folders to Windows Codex locations:

| Package folder | Windows destination |
|---|---|
| `home/.codex` | `%USERPROFILE%\.codex` |
| `appdata_roaming/Codex` | `%APPDATA%\Codex` |
| `appdata_roaming/com.openai.codex` | `%APPDATA%\com.openai.codex` |
| `appdata_roaming/OpenAI/Codex` | `%APPDATA%\OpenAI\Codex` |

Project folders are included under `projects/` in the migration package. Move or copy them to the desired Windows project location, then reopen that folder from Codex.

## Restore Command

After unzipping the package and closing Codex:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Restore-Codex-To-Windows.ps1
```

Then verify:

```powershell
.\Verify-Codex-Windows-Restore.ps1
```

## Path Mapping Notes

Old conversations may reference Mac paths like:

```text
/Users/caleb/Documents/New project
```

On Windows, reopen the matching project folder, for example:

```text
C:\Users\<you>\Documents\New project
```

Do not bulk-edit JSONL session files in place. Prefer restoring files first, reopening the Windows project folder, and letting Codex rebuild or map workspace context safely.

