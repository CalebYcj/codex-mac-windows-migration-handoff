# Codex Mac Windows Migration Handoff

Codex Mac Windows Migration Handoff is an open-source Codex skill for moving OpenAI Codex Desktop from macOS to Windows. It helps package, transfer, restore, and verify Codex conversations, sessions, memories, skills, plugins, MCP/connectors, generated images, project folders, and path mappings.

Use this project when you need to migrate Codex Desktop from Mac to Windows, back up Codex conversations, restore Codex skills and plugins on Windows, or hand off a local AI agent workspace to another computer.

## Main Guides

- [How to migrate OpenAI Codex Desktop from Mac to Windows](migrate-codex-from-mac-to-windows.md)
- [How to back up Codex conversations and sessions](backup-codex-conversations-and-sessions.md)
- [How to restore Codex skills, plugins, and projects on Windows](restore-codex-skills-plugins-and-projects.md)
- [Troubleshooting Codex Mac-to-Windows migration](troubleshooting.md)

## What It Migrates

| Data type | Included in standard mode |
|---|---|
| Codex conversations and sessions | Yes |
| Archived sessions | Yes |
| Thread SQLite state | Yes |
| Memories and goals | Yes |
| Skills and plugin cache | Yes |
| Generated images | Yes |
| Project folders | Yes, when passed with `--project` |
| Browser cookies and login state | No |
| `.env`, API keys, private keys | No |

## Repository

GitHub: [CalebYcj/codex-mac-windows-migration-handoff](https://github.com/CalebYcj/codex-mac-windows-migration-handoff)

