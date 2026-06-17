# Codex Mac Windows Migration Handoff

Codex Mac Windows Migration Handoff is an open-source Codex skill for moving OpenAI Codex Desktop between macOS and Windows computers. It helps package, transfer, restore, and verify Codex conversations, sessions, memories, skills, plugins, MCP/connectors, generated images, project folders, and path mappings.

Use this project when you need to migrate Codex Desktop from Mac to Windows, Windows to Mac, Windows to Windows, or Mac to Mac; back up Codex conversations; restore Codex skills and plugins; or hand off a local AI agent workspace to another computer.

## Main Guides

- [How to migrate Codex between Mac and Windows](migrate-codex-between-mac-and-windows.md)
- [How to migrate OpenAI Codex Desktop from Mac to Windows](migrate-codex-from-mac-to-windows.md)
- [How to back up Codex conversations and sessions](backup-codex-conversations-and-sessions.md)
- [How to restore Codex skills, plugins, and projects](restore-codex-skills-plugins-and-projects.md)
- [Troubleshooting Codex migration](troubleshooting.md)

## Supported Directions

| Source | Target | Status |
|---|---|---|
| Mac | Windows | Primary tested path |
| Windows | Mac | Script-supported path; verify on target Mac |
| Windows | Windows | Script-supported path; verify on target Windows |
| Mac | Mac | Script-supported path; verify on target Mac |

## What It Migrates

| Data type | Included in standard mode |
|---|---|
| Codex conversations and sessions | Yes |
| Archived sessions | Yes |
| Thread SQLite state | Yes |
| Memories and goals | Yes |
| Skills and plugin cache | Yes |
| Generated images | Yes |
| Project folders | Yes, when passed with `--project` or `-Project` |
| Browser cookies and login state | No |
| `.env`, API keys, private keys | No |

## Repository

GitHub: [CalebYcj/codex-mac-windows-migration-handoff](https://github.com/CalebYcj/codex-mac-windows-migration-handoff)
