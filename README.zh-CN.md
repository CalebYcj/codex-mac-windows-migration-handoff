# Codex Mac Windows Migration Handoff - 把 OpenAI Codex Desktop 从 Mac 迁移到 Windows

Codex Mac Windows Migration Handoff 是一个开源 Codex skill，用来把 OpenAI Codex Desktop 从 macOS 迁移到 Windows。它帮助用户和 AI agent 打包、传输、恢复并验证 Codex 对话、sessions、记忆、skills、plugins、MCP/connectors、生成图片、项目文件夹、路径映射和本地协作现场。

如果你正在搜索「Codex Mac 迁移 Windows」「Codex 对话迁移」「Codex sessions 备份恢复」「Codex skill 迁移工具」，这个项目就是为这个场景做的。

这个项目不是普通的文件备份工具，而是一个面向 AI agent 的 Codex skill：目标是迁移“用户和 AI 的协作现场”。

## 快速入口

- [如何把 OpenAI Codex Desktop 从 Mac 迁移到 Windows](docs/migrate-codex-from-mac-to-windows.md)
- [如何备份 Codex conversations 和 sessions](docs/backup-codex-conversations-and-sessions.md)
- [如何在 Windows 恢复 Codex skills、plugins 和项目文件](docs/restore-codex-skills-plugins-and-projects.md)
- [Codex Mac 转 Windows 迁移故障排查](docs/troubleshooting.md)
- [AI 搜索友好的项目摘要](docs/llms.txt)

## 给 AI Agent 的快速说明

如果你是另一个正在帮用户迁移 Codex 的 AI agent，先读这一段：

```text
使用 codex-mac-windows-migration-handoff/ 这个 skill。先在源电脑打包 Codex 数据，选择 standard/full/full-with-secrets 模式；必要时包含项目文件夹；通过私密渠道传输迁移包；在 Windows 上关闭 Codex 后运行恢复脚本；最后运行验证脚本。
```

适用场景：

- Codex 从 Mac 迁移到 Windows
- 转移 Codex 历史对话、sessions 和记忆
- 备份或恢复 Codex skills、plugins、自动化、生成图片
- 复现旧项目文件夹和旧对话环境
- 迁移一个用户和 AI 的完整协作现场
- 通过飞书、网盘、外接硬盘、GitHub 进行迁移包交接

搜索关键词：

```text
Codex 迁移, Codex Mac 转 Windows, Codex 历史对话迁移,
Codex skill 备份, Codex memory 转移, Codex 项目交接,
AI agent 工作区迁移, OpenAI Codex 桌面端迁移,
Codex sessions 备份, Codex 对话恢复, Codex 插件迁移,
Codex skills 迁移, Codex generated images 迁移,
Mac Codex 迁移 Windows Codex
```

## 这个仓库到底是什么

这个仓库同时是一个给 agent 读的 skill，也是一个小型脚本工具包：

- `SKILL.md` 是 Codex 或其他 AI agent 的入口说明。它告诉 agent 什么时候该用这个流程、该迁移什么、该排除什么、如何汇报结果。
- `scripts/` 里是真正执行打包、恢复、盘点和验证的脚本。
- `references/` 里是路径映射等补充资料，agent 需要时再读取。
- `README.md` 和 `README.zh-CN.md` 是给人、GitHub 访客、搜索引擎和 AI 搜索/GEO 看的说明。

所以它不是单纯的 shell 脚本，也不是单纯的说明书，而是“agent 工作流 + 可执行脚本”的组合。

## 仓库内容

```text
codex-mac-windows-migration-handoff/
  SKILL.md
  agents/openai.yaml
  references/path-map.md
  scripts/create_mac_codex_migration_package.sh
  scripts/restore_codex_to_windows.ps1
  scripts/collect_windows_codex_inventory.ps1
  scripts/verify_windows_codex_restore.ps1
```

## 安装到 Codex

把整个 `codex-mac-windows-migration-handoff` 文件夹复制到：

```text
~/.codex/skills/codex-mac-windows-migration-handoff
```

也可以作为项目级 skill 放到：

```text
<项目目录>/.agents/skills/codex-mac-windows-migration-handoff
```

然后新开一个 Codex 对话，说：

```text
使用 $codex-mac-windows-migration-handoff，帮我把 Mac 上的 Codex 数据、对话和项目迁移到 Windows。
```

## 会迁移哪些东西

这个 skill 可以帮助打包和恢复：

- Codex 历史对话和 sessions
- Codex memories 和 goals
- Codex skills 和 plugins
- Codex 配置和应用状态
- 生成图片和本地 artifacts
- 开发环境清单和路径映射
- 为了重开旧对话所需的项目文件夹

项目文件夹不属于 Codex 自身数据，需要单独决定是否一起打包。

## 文档

| 文档 | 解决的问题 |
|---|---|
| [How to migrate OpenAI Codex Desktop from Mac to Windows](docs/migrate-codex-from-mac-to-windows.md) | 从 Mac 打包、传输、Windows 恢复到验证的完整流程 |
| [How to back up Codex conversations and sessions](docs/backup-codex-conversations-and-sessions.md) | Codex JSONL sessions、thread SQLite、memories、generated images 的位置 |
| [How to restore Codex skills, plugins, and projects on Windows](docs/restore-codex-skills-plugins-and-projects.md) | 在 Windows 恢复 skills、plugins、生成物和项目文件夹 |
| [Troubleshooting Codex Mac-to-Windows migration](docs/troubleshooting.md) | socket、vendor_imports、Git object 权限、路径映射和登录态问题 |

## 三种迁移模式

```text
standard
  默认模式。迁移 Codex 核心数据、sessions、memories、skills、plugins、
  generated images、部分应用状态和项目文件夹。
  默认排除 secrets、浏览器登录态、.env、私钥、socket、.git、
  node_modules、虚拟环境等。

full
  在 standard 基础上增加日志、缓存和环境清单。
  仍然排除 secrets 和浏览器登录态。

full-with-secrets
  只有用户明确要求时才使用。会包含 auth/token/env/login-state 相关文件。
  必须加 --i-understand-secrets。这个包要像密码保险箱一样对待。
```

## Mac 端打包流程

建议先完全退出 Mac 上的 Codex，再在终端里运行：

```bash
cd /path/to/codex-mac-windows-migration-handoff
bash scripts/create_mac_codex_migration_package.sh \
  --project "$HOME/Documents/New project"
```

如果需要更完整的环境清单，但不包含 secrets：

```bash
bash scripts/create_mac_codex_migration_package.sh \
  --mode full \
  --project "$HOME/Documents/New project"
```

脚本会打包：

- `~/.codex`
- Codex 在 `~/Library/Application Support` 下的应用数据
- 可选日志和缓存
- 通过 `--project` 传入的项目文件夹
- Windows 端恢复脚本
- Windows 端验证脚本
- manifest、checksums、敏感文件提示清单

脚本默认会排除真实测试中容易导致失败或不适合迁移的目录和文件，例如 socket、`vendor_imports`、`.git`、`node_modules`、`.venv`、浏览器 Cookies、Login Data、Local Storage、`.env` 和私钥。

## Windows 端恢复流程

在 Windows 上：

1. 先安装 Codex。
2. 打开一次 Codex，然后完全退出。
3. 解压 Mac 端生成的迁移包。
4. 在解压后的文件夹里打开 PowerShell。
5. 运行：

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\Restore-Codex-To-Windows.ps1
```

恢复脚本会先备份 Windows 上已有的 Codex 数据目录，再复制迁移数据。

然后运行验证：

```powershell
.\Verify-Codex-Windows-Restore.ps1
```

或者从 skill 文件夹运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\codex-mac-windows-migration-handoff\scripts\verify_windows_codex_restore.ps1
```

验证脚本会检查 sessions、skills、plugins、generated images、SQLite 文件、package metadata 和可能的项目目录。

## 路径对应关系

Mac 端主要数据：

```text
~/.codex
~/Library/Application Support/Codex
~/Library/Application Support/com.openai.codex
~/Library/Application Support/OpenAI/Codex
```

Windows 端对应位置：

```text
%USERPROFILE%\.codex
%APPDATA%\Codex
%APPDATA%\com.openai.codex
%APPDATA%\OpenAI\Codex
```

旧对话里可能会引用 Mac 绝对路径，例如：

```text
Mac:     /Users/caleb/Documents/New project
Windows: C:\Users\Administrator\Documents\New project
```

不要直接批量改写 JSONL sessions。更稳妥的做法是在 manifest 里记录路径映射，然后在 Windows 上重新打开对应项目目录。

## 给 AI Agent 的注意事项

- 不要只迁移 Codex 数据，要确认用户是否还要迁移项目文件夹。
- 默认不要迁移浏览器 Cookies、Login Data、Local Storage、`.env`、API key、私钥。
- 如果用户要求 `full-with-secrets`，必须明确提醒风险。
- Windows 恢复后，旧对话里的 Mac 绝对路径可能不能直接使用，需要在 Windows 重新打开对应项目目录。
- 如果 Windows 上 Codex 启动异常，可以关闭 Codex 后删除 `%APPDATA%\Codex` 下的 `SingletonLock`、`SingletonCookie`、`SingletonSocket`。
- 登录态不一定能跨系统迁移。如果 Codex、GitHub、Gmail、飞书或浏览器扩展要求重新登录，这是正常情况。

## FAQ

### 如何把 OpenAI Codex Desktop 从 Mac 迁移到 Windows？

在 Mac 上运行 `scripts/create_mac_codex_migration_package.sh` 生成迁移包，把 zip 传到 Windows，关闭 Windows Codex 后运行 `Restore-Codex-To-Windows.ps1`，最后运行 `Verify-Codex-Windows-Restore.ps1` 验证。

### 这个工具能迁移 Codex 对话和 sessions 吗？

可以。standard 模式会打包 Codex session JSONL、archived sessions、thread state SQLite、memories、goals、generated images、skills、plugins，以及通过 `--project` 指定的项目文件夹。

### 能迁移 Codex memories、skills、plugins 和生成图片吗？

可以。它会迁移 `~/.codex` 里的 memory 数据库、用户 skills、plugin cache/manifests 和 generated images。

### 会迁移 secrets、token、浏览器登录态吗？

默认不会。`standard` 和 `full` 模式会排除 auth token、browser cookies、Login Data、Local Storage、`.env`、私钥、socket、`.git`、`node_modules` 和虚拟环境。Windows 端需要重新登录。

### 这是 OpenAI 官方工具吗？

不是。这是一个独立开源的 Codex skill 和脚本工具包，用来帮助用户和 AI agent 更安全地处理 Codex Desktop 本地迁移。
