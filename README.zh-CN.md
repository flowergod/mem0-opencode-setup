# mem0-opencode-setup

[English](README.md) | **简体中文**

一条命令，在 [opencode](https://opencode.ai) 里装好一套**跨设备的持久记忆系统**，由 [Mem0](https://mem0.ai) 驱动。

v2 会内置一份**打好 Node 兼容补丁**的 `@mem0/opencode-plugin`，所以同一套配置在 opencode **桌面 App**（Electron / Node）和 **CLI / web**（Bun）里都能加载。所有内容固定在同一个记忆空间（`user_id = "opencode"`、`app_id = "opencode"`），每台机器共享同一份记忆、行为完全一致。

## 安装（Windows）

两种方式任选。

**A. 单文件** —— 下载 `mem0-setup.ps1`，然后：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File mem0-setup.ps1 -ApiKey "m0-xxxxxxxx"
```

**B. 一句话**（在线获取并运行，可传参）：

```powershell
powershell -NoProfile -Command "& ([scriptblock]::Create((irm https://raw.githubusercontent.com/flowergod/mem0-opencode-setup/main/mem0-setup.ps1))) -ApiKey 'm0-xxxxxxxx'"
```

不想带 key，就省略 `-ApiKey`，装完后自己跑 `setx MEM0_API_KEY "m0-..."`。

先预览、不写任何东西：加 `-DryRun`。

装完请**完全重启 opencode** —— 插件只在进程启动时加载，没有热重载。

## 参数

| 参数 | 作用 |
| --- | --- |
| `-DryRun` | 只展示会删除/安装什么，不写入 |
| `-SkipCleanup` | 不去动其它工具的配置 |
| `-SkipPlugin` | 复用已有的 `mem0-plugin\`，不重新下载 |
| `-RefreshPlugin` | 强制重新下载插件 |
| `-PluginVersion 0.4.0` | 指定插件版本 |
| `-Verify` | 只体检、不修改 |
| `-SkillOnly` | 只安装 opencode 的 skill 文件 |
| `-ApiKey "m0-..."` | 同时把 `MEM0_API_KEY` 写入用户环境变量 |

## 它做了什么

1. **先对账 / 清理**（核心，先做），所有改动先备份：
   - 其它工具：Claude、Codex、Cursor、Windsurf、VS Code
   - **旧方案**：`mcp.mem0` 区块、`@mem0/opencode-plugin` npm 包名项、自写插件 `plugins/mem0-memory.js`
   - 环境变量检查：`MEM0_USER_ID` / `MEM0_APP_ID` 必须是 `opencode`；`MEM0_API_KEY` 必须存在
2. 把**打好 Node 补丁**的 `@mem0/opencode-plugin` vendored 到 `~/.config/opencode/mem0-plugin/`。
3. 安装 `memory-protocol.md`。
4. 把 `instructions` 和插件的**绝对路径**合并进 `opencode.jsonc`。
5. 自检，并提示重启。

装完请**完全重启 opencode**。

## 为什么要打补丁

`@mem0/opencode-plugin@0.4.0` 发布的是 **Bun 构建产物**，其中唯一的 Bun 专有写法是：

```js
var __require = import.meta.require;   // dist/index.js
```

- opencode **CLI / web**（Bun 运行时）：没问题，插件能加载。
- opencode **桌面 App**（Electron / **Node** 运行时）：`import.meta.require` 是 `undefined`，所有 `__require(...)` 抛 `__require is not a function`，整个插件（工具 / 技能 / hooks）**静默加载失败**。

修法只有一行 —— 换成 Node 的 `createRequire(import.meta.url)`，它在 **Node 和 Bun 下都有效**。`files/patch-mem0-plugin.ps1` 会幂等地打上这个补丁，安装器则直接 vendor 一份打好补丁的插件，让 opencode 用绝对路径加载。

## 安装之后

安装器还会在 opencode 里放一个 **skill**（`mem0-opencode-setup`）。重启 opencode 后，可以用自然语言唤起它，例如："用 mem0-opencode-setup 同步/重装这台机器的记忆体系"。

## 重启后的校验清单

1. `opencode debug config` 输出里应出现 `mem0-plugin` 路径和 `/mem0-*` 命令。
2. 在 opencode 里跑 `/mem0-status` → 检查全过。
3. 让 agent「记住一件事」，再在新会话里问它 → 能回忆起来。
4. 打开 app.mem0.ai → Memories，确认 `user_id = opencode`、`app_id = opencode`。

同一 API key + 同 scope = **跨设备共享**。

## 装好的行为

- **recall** —— 每个 session 一次，在模型调用前注入首条用户消息
- **save** —— 用户消息实时入库；会话状态在压缩时入库；工具报错也会被捕获
- **工具** —— 10 个记忆工具（`add_memory`、`search_memories`、`get_memories`、`get_memory`、`update_memory`、`delete_memory`、`delete_all_memories`、`delete_entities`、`list_entities`、`get_event_status`）
- **命令** —— `/mem0-remember`、`/mem0-search`、`/mem0-status`、`/mem0-tour`、`/mem0-scope`、`/mem0-forget`、`/mem0-context-loader`

## 仓库结构

| 路径 | 作用 |
| --- | --- |
| `mem0-setup.ps1` | 自包含一键脚本：内嵌整个 skill，再调用安装器 |
| `install.ps1` | 安装脚本（幂等；支持 `-DryRun` / `-Verify`） |
| `SKILL.md` | opencode skill 定义（给 agent 的执行说明） |
| `files/memory-protocol.md` | 协议指令（教 agent 自动存取） |
| `files/patch-mem0-plugin.ps1` | Node 兼容补丁（幂等） |
| `files/opencode-mem0.snippet.jsonc` | 手动合并用的配置片段 |

## 回滚

所有改动前都备份到 `~/.config/opencode/mem0-setup-backup/<时间戳>/`。还原对应文件即可；也可手动删除 `memory-protocol.md`、`mem0-plugin\` 文件夹，以及 `opencode.jsonc` 里的 mem0 条目。

## 说明

- 仅 Windows（PowerShell 5.1+）。macOS / Linux 需另写脚本。
- 需要 Node（用于补丁自检），以及 `npm.cmd` 或首次安装时的联网能力（下载插件）。
- `user_id` 刻意写死为 `"opencode"`。若确需更换 scope，协议、配置、环境变量三处要一起改。
