# Troubleshooting Codex Migration

This page lists common issues when migrating OpenAI Codex Desktop between Mac and Windows computers.

## Socket Or IPC File Copy Failure

Some live Codex or Git cache folders can contain socket or IPC files. The package scripts exclude `*.ipc`, `*.sock`, runtime folders, and process manager state by default.

## `vendor_imports` Or Git Object Permission Denied

Some cached Git objects under runtime or vendor import folders may be unreadable. Standard mode excludes `vendor_imports`, `.git`, `node_modules`, `.venv`, `venv`, and `__pycache__`.

## Package Is Too Large

Codex session history can be large. If the package is too large, inspect:

- `~/.codex/sessions`
- generated images
- project `outputs` and `artifacts`
- selected project folders passed with `--project`

Avoid including `node_modules`, virtual environments, and Git object stores.

## Target Codex Requires Login Again

This is expected. Standard and full modes do not migrate browser login state, cookies, auth tokens, or private keys.

## Old Conversations Reference Source Computer Paths

Old threads may contain paths like `/Users/<name>/Documents/...` or `C:\Users\<name>\Documents\...`. On the target computer, restore or move the project folder, then reopen it from Codex. Avoid direct JSONL path rewrites unless you have a verified backup and a parser-safe migration tool.

## Chrome Plugin Or Native Host Is Disconnected

Codex Chrome integration may need target-side setup. Reinstall or repair the Chrome plugin from Codex on the target computer and confirm the Codex Chrome extension is installed and enabled in the same Chrome profile.

