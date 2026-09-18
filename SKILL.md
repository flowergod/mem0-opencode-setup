---
name: mem0-opencode-setup
description: Use when setting up, reinstalling, repairing, or syncing the mem0-based automatic memory system for opencode on a Windows machine. Installs the mem0 MCP server, the memory protocol, and the auto recall/save plugin, and FIRST detects and removes any other mem0 integrations so every device shares one identical setup (user_id "opencode"). Trigger on phrases like "配置 mem0 记忆", "安装 mem0", "新设备记忆体系", "重装 mem0", "mem0 setup", "reinstall memory", "统一记忆配置".
---

# mem0 + opencode 便携安装

在一台新的（Windows）设备上，一次性装上与我们标准一致的 mem0 自动记忆体系，
并在安装前**先检测并移除该设备上其它 mem0 集成/配置**，保证所有设备落在同一个
`user_id = "opencode"` 空间、同一套运作模式。

## 包内容

- `install.ps1` —— 安装脚本（Windows PowerShell 5.1+）
- `files/memory-protocol.md` —— 协议指令（教 agent 自动存取）
- `files/mem0-memory.js` —— opencode 插件（自动 recall / save）
- `files/opencode-mem0.snippet.jsonc` —— 需要合并进 opencode 配置的片段（脚本会自动合并）

## 执行流程（agent 照做）

1. **先跑 DryRun 预览**，把要删除/修改的东西给用户看：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\install.ps1" -DryRun
   ```

2. 用户确认后，正式执行（可顺带写入 API key）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\install.ps1" -ApiKey "m0-xxxxxxxx"
   ```

   若用户不在这里给 key，也可之后自己跑 `setx MEM0_API_KEY "m0-..."`。

3. 脚本会依次：
   - **步骤 0**：扫描常见位置（opencode / claude / agents / codex / cursor / windsurf / vscode），
     检测一切提到 mem0 的配置与文件，**先备份再移除**（`-SkipCleanup` 可跳过）
   - **步骤 1**：安装 `memory-protocol.md` 与 `plugins/mem0-memory.js`
   - **步骤 2**：把 mem0 MCP + instructions 合并进 `~/.config/opencode/opencode.jsonc`
   - **步骤 3**：设置 `MEM0_API_KEY`
   - **步骤 4**：提示重启 opencode

4. 提醒用户**完全重启 opencode**。

## 规则 / 注意

- 所有改动都有备份，目录：`~/.config/opencode/mem0-setup-backup/<时间戳>/`。
- 本体系**固定** `user_id = "opencode"`；任何用别的 user_id 的集成都会被当作"分叉"清掉。
- **不要**删除本 skill 目录本身（脚本已把自身排除在扫描外）。
- 只针对 Windows。macOS / Linux 需另写脚本。
- 默认 `-DryRun` 只预览；确认后再正式执行。涉及删除，务必先给用户看 DryRun 结果。
