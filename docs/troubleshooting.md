# Troubleshooting Codex Mac-to-Windows Migration

This page lists common issues when migrating OpenAI Codex Desktop from Mac to Windows.

## Socket Or IPC File Copy Failure

Some live Codex or Git cache folders can contain socket or IPC files. The Mac package script excludes `*.ipc`, `*.sock`, runtime folders, and process manager state by default.

## `vendor_imports` Or Git Object Permission Denied

Some cached Git objects under runtime or vendor import folders may be unreadable. Standard mode excludes `vendor_imports`, `.git`, `node_modules`, `.venv`, `venv`, and `__pycache__`.

## Package Is Too Large

Codex session history can be large. If the package is too large, inspect:

- `~/.codex/sessions`
- generated images
- project `outputs` and `artifacts`
- selected project folders passed with `--project`

Avoid including `node_modules`, virtual environments, and Git object stores.

## Windows Codex Requires Login Again

This is expected. Standard and full modes do not migrate browser login state, cookies, auth tokens, or private keys.

## Old Conversations Reference Mac Paths

Old threads may contain paths like `/Users/<name>/Documents/...`. On Windows, restore or move the project folder, then reopen it from Codex. Avoid direct JSONL path rewrites unless you have a verified backup and a parser-safe migration tool.

## Chrome Plugin Or Native Host Is Disconnected

Codex Chrome integration may need Windows-side setup. Reinstall or repair the Chrome plugin from Codex on Windows and confirm the Codex Chrome extension is installed and enabled in the same Chrome profile.

