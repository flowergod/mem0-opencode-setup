# mem0-opencode-setup

[English](README.md) | **简体中文**

一条命令，在 [opencode](https://opencode.ai) 里装好一套**跨设备的持久记忆系统**，由 [Mem0](https://mem0.ai) 驱动。

它安装三样东西，并固定在同一个记忆空间（`user_id = "opencode"`），使每台机器共享同一份记忆、行为完全一致：

- **MCP server** —— 给 agent 用的 mem0 工具
- **记忆协议**（`memory-protocol.md`）—— 让 agent 自动存 / 取
- **插件**（`mem0-memory.js`）—— 自动 recall（每次模型请求前）+ 防抖 save（会话空闲后）

安装前会**先检测并移除本机其它 mem0 集成**（opencode / Claude / Codex / Cursor / Windsurf / VS Code），所有改动都会先备份。

## 安装（Windows）

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

## 参数

| 参数 | 作用 |
| --- | --- |
| `-DryRun` | 只展示会删除/安装什么，不写入 |
| `-SkipCleanup` | 不去动其它配置 |
| `-SkillOnly` | 只安装 opencode 的 skill 文件 |
| `-ApiKey "m0-..."` | 同时把 `MEM0_API_KEY` 写入用户环境变量 |

## 它做了什么

1. **检测并移除其它 mem0 集成**（先备份）
2. 把 `memory-protocol.md` 和 `plugins/mem0-memory.js` 装进 `~/.config/opencode/`
3. 把 mem0 MCP server + instructions 合并进 `opencode.jsonc`
4. 写入 `MEM0_API_KEY`（可选）
5. 提示重启 opencode

装完请**完全重启 opencode**。

## 安装之后

安装器还会在 opencode 里放一个 **skill**（`mem0-opencode-setup`）。重启 opencode 后，可以用自然语言唤起它，例如：
"用 mem0-opencode-setup 同步/重装这台机器的记忆体系"。

## 装好的行为

- **recall** —— 每个 session 一次，在**模型调用之前**注入 system prompt
- **save** —— 会话空闲 5 分钟后防抖写入（或攒满 10 条消息提前写）
- 可调参数在 `files/mem0-memory.js` 顶部：`SAVE_DEBOUNCE_MS`、`MAX_PENDING`、`MIN_SCORE`、`MAX_MEMORIES`

## 回滚

所有改动都在 `~/.config/opencode/mem0-setup-backup/<时间戳>/`。从那里恢复即可；
或手动删除 `memory-protocol.md`、`mem0-memory.js` 插件，以及 `opencode.jsonc` 里的 `mem0` 条目。

## 说明

- 仅 Windows（PowerShell 5.1+）。
- `user_id` 在协议和插件里都**刻意写死**为 `"opencode"`。若确需更换，两处都要改。
