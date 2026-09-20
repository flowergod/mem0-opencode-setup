---
name: mem0-opencode-setup
description: Use when setting up, reinstalling, repairing, or syncing the mem0-based automatic memory system for opencode on a Windows machine. It FIRST detects and removes every other mem0 integration (including the OLD mem0 MCP server + custom-plugin setup), then vendors a Node-patched copy of @mem0/opencode-plugin and wires it into opencode.jsonc so memory records, recalls, and syncs across devices under user_id/app_id "opencode". Trigger on phrases like "配置 mem0 记忆", "安装 mem0", "新设备记忆体系", "重装 mem0", "mem0 setup", "reinstall memory", "统一记忆配置", "记忆迁移".
---

# mem0 + opencode 便携安装（v2 · vendored + patched 插件）

在一台新的（Windows）设备上，一次性装出与标准完全一致的 mem0 自动记忆体系。
**安装前先"对账"**：检测并清掉这台机器上所有旧的 / 别的 mem0 集成与逻辑，
保证所有设备落在同一个 `user_id = "opencode"`、`app_id = "opencode"` 空间，
同一套运作模式（自动 recall + 自动 save）。

## 为什么是"vendored + patched"（根因）

`@mem0/opencode-plugin@0.4.0` 发布的是 **Bun 构建产物**，其中唯一的 Bun 专有写法是：

```js
var __require = import.meta.require;   // dist/index.js 里的那一行
```

- opencode **CLI / web**（Bun 运行时）：这行有效，插件能加载。
- opencode **桌面 App**（Electron / **Node** 运行时）：`import.meta.require` 是 `undefined`，
  于是所有 `__require(...)` 抛 `__require is not a function`，整个插件（工具 / 技能 / hooks）
  静默加载失败（没有任何工具、没有 `/mem0-*` 命令）。

修法（一行）：把该行换成 Node 的 `createRequire(import.meta.url)`。
它在 **Node 和 Bun 下都有效**，所以可以无条件打补丁。
本 skill 直接 **vendor 一份打好补丁的插件**到 `~/.config/opencode/mem0-plugin/`，
并让 opencode 用**绝对路径**加载它（不再依赖 npm 包名）。

## 包内容

- `install.ps1` —— 安装脚本（幂等；支持 DryRun / Verify）
- `files/memory-protocol.md` —— 协议指令（教 agent 自动存取、静默保存）
- `files/patch-mem0-plugin.ps1` —— 给插件打 Node 兼容补丁（幂等）
- `files/opencode-mem0.snippet.jsonc` —— 手动合并用的配置片段
- `mem0-setup.ps1` —— 自包含一键脚本（把整个 skill 内嵌，用于全新机器）

## 执行流程（agent 照做）

1. **先跑 DryRun**，把要删除 / 修改的东西给用户看：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\install.ps1" -DryRun
   ```

2. 用户确认后正式执行（可顺带写入 API key）：

   ```powershell
   powershell -ExecutionPolicy Bypass -File "<本skill目录>\install.ps1" -ApiKey "m0-xxxxxxxx"
   ```

3. 脚本依次：
   - **Step 0 对账/清理**（核心，先做）
     - `0a` 扫描并清掉其它工具的 mem0 配置：`.claude.json`、`.claude\settings*.json`、
       `.cursor\mcp.json`、`.codeium\windsurf\mcp_config.json`、VS Code `settings.json`
     - `0b` 清掉 Codex 的 `.codex\config.toml` 里的 mem0 段
     - `0c` 删掉**旧方案**的自写插件 `~\.config\opencode\plugins\mem0-memory.js`（含 `.disabled`）
     - `0d` 清掉 opencode 插件/技能目录里其它 mem0 残留文件
     - `0e` 其它技能目录里 mem0 命名的文件**只提示不删**（避免误删）
     - `0f` 检查并纠正用户环境变量：`MEM0_USER_ID` / `MEM0_APP_ID` 必须是 `opencode`；`MEM0_API_KEY` 必须存在
     - 对 `opencode.jsonc` 会清掉旧的 `mcp.mem0` 区块与 npm 包名插件项
   - **Step 1** 安装 `memory-protocol.md`
   - **Step 2** vendor + 打补丁：优先 `npm pack @mem0/opencode-plugin@0.4.0`，
     失败则从 registry 直连下载 tgz，再失败则复用本机 `~/.cache/opencode` 缓存；
     解包 `dist/ opencode-skills/ package.json index.d.ts LICENSE README.md` 到
     `~/.config/opencode/mem0-plugin/`，然后打补丁并做 Node 导入自检
   - **Step 3** 合并 `opencode.jsonc`：`instructions += memory-protocol.md`，
     `plugin` 数组里去掉任何 mem0 项并**前置** `~/.config/opencode/mem0-plugin`
   - **Step 4 自检**：补丁标记、`opencode debug config` 是否解析到 `mem0-plugin` 与 `mem0-*` 命令
   - **Step 5** 提示重启

4. 提醒用户**完全重启 opencode**（插件只在进程启动时加载，没有热重载）。

## 其它参数

- `-SkipCleanup`：跳过 Step 0 的清理（不动别人的配置）
- `-SkipPlugin`：复用已有的 `mem0-plugin\`，不重新下载
- `-RefreshPlugin`：强制重新下载插件
- `-PluginVersion 0.4.0`：指定插件版本
- `-Verify`：只体检、不修改（检查补丁、Node 可导入性、环境变量、配置解析）

## 装完后的校验清单

1. `opencode debug config` 输出里应出现：
   - `plugin` 含 `file:///.../mem0-plugin`
   - 注册了 `mem0-remember / mem0-search / mem0-status / mem0-tour / mem0-scope / mem0-forget / mem0-context-loader`
2. 在 opencode 里跑 `/mem0-status` → 五项检查全过。
3. 让 agent「记住一件事」，再在新会话里问它 → 能回忆起来（历史记忆会自动注入）。
4. 打开 app.mem0.ai → Memories，确认 `user_id = opencode`、`app_id = opencode`。
   同一 API key + 同 scope = **跨设备共享**。

## 回滚

所有改动前都备份到 `~/.config/opencode/mem0-setup-backup/<时间戳>/`。
还原对应文件即可；也可手动删除：

- `~/.config/opencode/memory-protocol.md`
- `~/.config/opencode/mem0-plugin\`
- `opencode.jsonc` 里的 `instructions` 条目与 `plugin` 里的 mem0 路径

## 注意

- 只针对 Windows（PowerShell 5.1+）。macOS / Linux 需另写脚本。
- `user_id` / `app_id` 固定为 `"opencode"`；换 scope 要同时改协议与配置。
- 涉及删除，务必先给用户看 DryRun 结果再执行。
- 桌面 App 与 CLI 共用 `~/.config/opencode/`；两边都指向同一个打补丁的插件，所以都能加载。
