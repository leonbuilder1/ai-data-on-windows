# AI Data on Windows

将 Windows 上 AI 编程工具的大体积用户数据、缓存和后续下载放到指定的数据盘，同时保留原有逻辑路径，以减少对登录状态、会话、插件、设置和启动入口的影响。

适用对象：Codex、Claude Code、Cursor。项目以 Windows PowerShell 7 为运行环境，所有脚本默认只审计；只有加上 `-Execute` 才会改动电脑。

> 本项目不上传、打印或提交认证令牌、会话内容、设置、项目文件或迁移报告。不要把 `D:\AIData`、迁移回执或应用目录提交到 Git。

## 目标与边界

默认数据根是 `D:\AIData`，可改为任何健康的 NTFS 数据盘路径。项目采用：

```text
逻辑兼容路径（通常在 C） ── NTFS Junction ──> 数据盘真实目录
工具程序/Windows 管理元数据                       └─ 保留在系统原位置
```

因此，已有快捷方式、协议处理、CLI 和工具更新继续看见原逻辑路径，但实际用户数据写入数据盘。它不是“把整个 Windows 应用文件夹硬搬走”的工具。

项目明确不自动处理：

- Microsoft Store / MSIX / AppX 包的 `WindowsApps`、`WpSystem`、`Local\Packages`；这些必须通过 Windows 或厂商支持的安装/移动方式处理。
- Claude Desktop 的程序包和系统服务。可以保留程序主体在系统盘；本项目自动管理的是 **Claude Code** 的配置与临时文件。
- 非当前用户拥有的系统日志、系统更新缓存或未知第三方扩展目录。

这样能避免手动移动系统托管目录导致升级、修复、服务或权限损坏。

## 支持矩阵

| 工具配置文件名 | 迁移内容 | 后续写入位置 | 保持兼容的方法 |
| --- | --- | --- | --- |
| `Codex` | `CODEX_HOME` / 传统 `.codex` 状态 | `Data\Codex\Home`、`Tools\Codex\Bin` | 原目录 Junction + 用户环境变量 |
| `ClaudeCode` | Claude Code 配置、会话、插件与临时文件 | `Data\ClaudeCode\Config`、`Temp\ClaudeCode` | 原 `.claude` Junction + 官方环境变量 |
| `Cursor` | `.cursor` 与 Roaming profile | `Data\Cursor\Home`、`Data\Cursor\Roaming` | 两个原目录 Junction |

Codex 的 `CODEX_HOME` 可覆盖状态根目录；`CODEX_SQLITE_HOME` 可覆盖 SQLite 状态；`CODEX_INSTALL_DIR` 控制 Windows 独立安装器将可见 `codex` 命令安装到哪里。官方文档也说明独立包缓存仍在 `CODEX_HOME` 下。详见 [Codex 环境变量](https://learn.chatgpt.com/docs/config-file/environment-variables)。

Claude Code 的 `CLAUDE_CONFIG_DIR` 覆盖默认配置目录，包含设置、会话历史、插件及 Windows 凭据；`CLAUDE_CODE_TMPDIR` 覆盖内部临时目录。详见 [Claude Code 环境变量](https://code.claude.com/docs/en/env-vars)。

## 使用前条件

1. 使用 PowerShell 7，并先关闭目标工具、该工具的终端以及扩展宿主进程。
2. 数据盘必须是健康的 NTFS 卷，并有足够空间容纳源数据与迁移期间的副本。
3. 先在系统备份、磁盘快照或组织认可的备份体系中保留可恢复点。脚本只保留 C 盘 `pre-ai-data-*` 回退目录，直到验收后才允许清理。
4. 一次只迁移一个工具配置文件；每次切换后重新打开该工具并完成验收。

## 快速开始

以下命令以 `D:\AIData` 为例。先把仓库下载到任意非应用数据目录，再在新 PowerShell 7 窗口中运行。

### 1. 初始化数据根

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Initialize-AIDataRoot.ps1 -DataRoot D:\AIData
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Initialize-AIDataRoot.ps1 -DataRoot D:\AIData -Execute
```

第一条只展示计划，第二条只创建数据根目录结构，尚不移动任何工具数据。

### 2. 先审计一个工具

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-AIDataProfileMove.ps1 -Tool Codex -DataRoot D:\AIData
```

确认来源和目标无误、目标工具完全关闭后，再执行：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-AIDataProfileMove.ps1 -Tool Codex -DataRoot D:\AIData -Execute
```

输出会给出一份 `move-receipt.json`。保留它；回退和最终清理都要使用它。

### 3. 自动路径验证与人工验收

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-AIDataProfile.ps1 -Tool Codex -DataRoot D:\AIData -ReceiptPath D:\AIData\Reports\<tool-and-time>\move-receipt.json
```

然后新开一个终端/桌面应用，人工确认：

- 登录状态、设置、插件/Skills/MCP 配置正常；
- 能看到一个既有会话或项目；
- 能新建一次最小会话或项目并确认新写入出现在数据盘；
- 工具更新后再重复以上检查一次。

对 Claude Code 和 Cursor 分别将 `-Tool` 替换为 `ClaudeCode` 或 `Cursor`。Cursor 必须关闭所有窗口、Agent 和扩展宿主进程。

### 4. 回退或最终释放 C 盘空间

验收不通过时，关闭工具后使用回执回退。回退只恢复原 C 路径和用户环境变量，不删除数据盘副本：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Restore-AIDataProfileMove.ps1 -ReceiptPath D:\AIData\Reports\<tool-and-time>\move-receipt.json -Execute
```

连续使用一段时间、并确认应用升级后仍正常，才删除 C 盘回退目录：

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Complete-AIDataProfileMove.ps1 -ReceiptPath D:\AIData\Reports\<tool-and-time>\move-receipt.json
pwsh -NoProfile -ExecutionPolicy Bypass -File .\scripts\Complete-AIDataProfileMove.ps1 -ReceiptPath D:\AIData\Reports\<tool-and-time>\move-receipt.json -Execute
```

第一条仅审计；第二条永久删除 **回执中精确记录的** `pre-ai-data-*` 目录。它拒绝递归跟随目录联接。

## 更新与新增依赖仍写入数据盘

- **Codex**：用户环境变量将状态、SQLite 与未来独立安装器的可见命令位置定向到数据根；独立包缓存仍随 `CODEX_HOME` 进入数据盘。
- **Claude Code**：配置、会话、插件、Windows 凭据和内部临时文件使用官方变量进入数据盘。新终端或重启 Claude Code 后生效。
- **Cursor**：更新仍由 Cursor 自己管理；其 profile 路径通过 Junction 指向数据盘，因此新扩展、聊天/状态数据及缓存不产生第二份 C 盘 profile。
- **Claude Desktop**：请保留 Windows/厂商托管程序主体在系统盘。使用应用支持的移动或安装方式管理包，而不要手工移动 `WindowsApps` 或 `WpSystem`。本项目不承诺消除这类系统管理元数据。

## 安全设计

- 只接受三个固定工具配置文件；不接受任意源/目标目录。
- 切换前复制，再以文件数、目录数和字节数验证；**不计算文件哈希**。
- 源目录或其子目录存在重解析点时停止，避免跟随未知链接。
- 先同父目录改名保留 C 盘回退副本，再建立 NTFS Junction。
- 所有可破坏操作均要求 `-Execute`；最终删除还要求一份有效迁移回执。
- 回退不删除数据盘 live 副本。

更多边界和故障处理请看 [安全模型](docs/SAFETY_MODEL.md) 与 [工具说明](docs/SUPPORTED_TOOLS.md)。

## 让 Codex、Claude Code 或 Cursor 协助执行

把本仓库打开给任一工具后，让它先阅读 [AGENTS.md](AGENTS.md)，再执行相应的“审计模式”命令。Agent 不应自行加 `-Execute`；必须由电脑所有者确认来源、目标、停机窗口和验收结果后才可切换。

## 贡献与发布

- 请勿提交迁移回执、日志、数据根、用户名、绝对用户目录、会话、令牌或应用配置。
- 新增工具时，优先使用厂商公开的环境变量；只有没有官方重定向方式时，才设计可回退的 Junction 方案。
- 先增加审计、回退和验收，再允许 `-Execute`。

详见 [贡献说明](docs/CONTRIBUTING.md)。本项目采用 [MIT License](LICENSE)。
