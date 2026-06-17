# Validation Status

This page records what has actually been tested for `codex-mac-windows-migration-handoff`.

## Current Matrix

| Direction | Status | Evidence |
|---|---|---|
| Mac to Windows | Real-world migration succeeded | Original project path: a separate Mac was migrated to the current Windows Codex machine. |
| Windows to Windows | Isolated simulation passed | A fake Windows source profile and fake Windows target profile were created on one Windows machine. Packaging, restore, verifier counts, plugin cache, and default exclusions passed. |
| Mac to Mac | Isolated simulation passed on Intel Mac | Tested on an Intel Mac, `x86_64`, macOS 12.7.6 build 21H1320. Packaging, restore to fake HOME, verifier counts, plugin cache, and default exclusions passed. |
| Windows to Mac | Layout validated, not end-to-end with a Windows-origin zip | Windows and Mac packages use the same neutral layout consumed by `Restore-Codex-To-Mac.sh`; a real Windows-origin zip still needs to be restored on Mac for full end-to-end validation. |

## Windows to Windows Simulation

The Windows simulation used isolated environment variables rather than real user data:

- fake `%USERPROFILE%`
- fake `%APPDATA%`
- fake `%LOCALAPPDATA%`
- fake source `.codex`
- fake target profile

The restored verifier counts were:

| Count | Result |
|---|---:|
| sessions | 1 |
| archived_sessions | 1 |
| skills | 1 |
| plugin_manifests | 1 |
| generated_images | 1 |
| sqlite_files | 3 |

Default exclusions were checked for:

- `auth.json`
- `.env` and `.env.*`
- private key names
- cookies and login databases
- `.git`
- `node_modules`
- virtualenv directories
- socket, IPC, and singleton runtime files

## Intel Mac to Mac Simulation

The Mac simulation was run on:

```text
Mac architecture: x86_64 Intel Mac
macOS version: macOS 12.7.6, build 21H1320
Codex app path: /Applications/Codex.app/Contents/Resources/codex
Node: not found
Python: /usr/bin/python3
```

Bash syntax passed for all four Mac scripts:

- `create_mac_codex_migration_package.sh`
- `restore_codex_to_mac.sh`
- `verify_mac_codex_restore.sh`
- `collect_mac_codex_inventory.sh`

Inventory found:

| Path | Status |
|---|---:|
| `.codex` | found, 228.19 MB |
| `~/Library/Application Support/Codex` | found, 116.19 MB |
| `~/Library/Application Support/com.openai.codex` | found, 0.34 MB |

Real Mac packaging produced:

```text
/Users/ling/Desktop/Codex-Migration-Mac-Source-20260617-180412.zip
unzipped dir: /Users/ling/Desktop/Codex-Migration-Mac-Source-20260617-180412
zip size: 59 MB
unzipped staging size: 129 MB
zip entry count: 1092
```

An isolated Mac package was also produced:

```text
/tmp/codex-mac-migration-sim.vFYE5I/out/Codex-Migration-Mac-Source-20260617-180529.zip
```

The isolated restore verifier counts were:

| Count | Result |
|---|---:|
| sessions | 1 |
| archived_sessions | 1 |
| skills | 1 |
| plugin_manifests | 1 |
| generated_images | 1 |
| sqlite_files | 3 |

## Known Caveats

- Mac packaging can emit a harmless locale warning when `C.UTF-8` is not supported on older macOS versions.
- Restore scripts prompt if any Codex process is running, even during fake-HOME simulations.
- Project folders are included under `projects/`, but restore scripts do not automatically move them into the target home directory. Move or reopen them manually on the target computer.
- Intel vs Apple Silicon should not affect core migration logic because architecture-specific dependency folders and binary-heavy runtime paths are excluded by default.
