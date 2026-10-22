# AgentSweep — AI Agent 工具专用清理器（PRD v0.1）

## 1. 问题

开发者普遍同时装着 3–8 个 AI Agent 工具（Claude Code、Codex、Cursor、Gemini/Antigravity、opencode、Kimi、Qwen、Kiro、Trae、Windsurf……）。
它们在 `~` 下持续写入会话记录、SQLite 数据库、日志、缓存、扩展包、npx/uv 依赖。实测一台日常开发机：**> 40 GB**。

通用清理工具（CleanMyMac、DaisyDisk）只能告诉你“这个文件夹很大”，不能回答：
- 这是哪个 Agent 的？是干什么用的？
- 删了会怎样？会丢聊天记录吗？会掉登录吗？
- 3.7 GB 的 `state.vscdb` 能删吗？（不能删，但能压缩）

## 2. 目标用户

- 主力：同时用多个 AI 编程工具的开发者，懂一点技术但不想研究每个工具的目录结构
- 次要：用 Cursor / Trae 等 IDE 的非专业开发者（产品、设计、学生）

## 3. 范围（v1）

**包含**
- 扫描 `~` 下各 Agent 工具自己的目录（`~/.xxx`、`~/Library/Application Support/xxx`、`~/Library/Caches/xxx`、`~/Library/Logs/xxx`）
- 共享开发缓存：npx、bun、uv、pip、HuggingFace（单独分组为「开发缓存」，并提示会影响其他项目）
- 已卸载工具的残留检测（App 不在了但数据还在）
- 会话历史：按时间筛选 → **可导出为 Markdown** → 删除
- SQLite 数据库压缩（VACUUM），不删数据也能回收空间

**不包含（v1）**
- 项目目录内的文件（`<project>/.claude/`、worktree、`node_modules`）
- 非 Agent 相关的系统清理
- Windows / Linux

## 4. 风险分级（核心）

每条规则都有一个等级，UI 用颜色区分，默认勾选策略不同：

| 等级 | 含义 | 默认 | 示例 |
|---|---|---|---|
| 🟢 safe | 缓存/日志/临时文件，删了会自动重建 | 默认勾选 | npx 缓存、logs、`*.tmp`、`CachedExtensionVSIXs`、GPUCache |
| 🟡 history | 会话/历史，删了不可恢复但不影响使用 | 默认勾选「早于 30 天」 | `~/.codex/sessions`、`~/.claude/projects`、`file-history` |
| 🟠 compact | 数据库，**不能删**，只能压缩 | 不勾选，单独入口 | Cursor `state.vscdb`、Codex `thread_history_1.sqlite` |
| 🔴 protected | 配置/凭证/技能，绝不触碰 | 锁定，不可勾选 | `auth.json`、`settings.json`、`oauth_creds.json`、`skills/`、`mcp.json` |
| 👻 orphan | 工具已卸载的残留 | 默认勾选 | `~/Library/Application Support/Trae`（Trae.app 不存在） |

**原则：** 规则未覆盖的文件一律视为 protected，默认不动。白名单思维，不是黑名单。

## 5. 核心流程

1. **首次启动**：引导开启「完全磁盘访问权限」→ 进入主界面
2. **扫描**：检测已安装工具 → 并发计算各规则命中的大小 → 实时动画呈现
3. **结果**：按「工具」或「风险等级」两种视图浏览；每项展示路径、大小、最后修改时间、一句人话解释
4. **会话历史**：列出会话（标题/项目/日期/大小），可多选 → 导出 Markdown → 删除
5. **清理前检查**：相关工具正在运行 → 提示退出（数据库操作强制要求退出）
6. **执行清理**：默认移到废纸篓；数据库先备份再 VACUUM；完成后显示释放空间
7. **历史记录**：每次清理留日志，可从废纸篓恢复

## 6. 会话导出

| 工具 | 来源 | 格式 |
|---|---|---|
| Claude Code | `~/.claude/projects/<proj>/<id>.jsonl` | JSONL，`type=user/assistant` 消息 |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl` | JSONL，`session_meta` 带 `cwd` |
| Cursor | `state.vscdb` 中 `cursorDiskKV` 表 `composerData:*` | SQLite KV + JSON |
| Gemini / Qwen | `~/.gemini/tmp/<hash>/chats`、`~/.qwen/projects` | JSON |
| opencode | `~/.local/share/opencode/opencode.db` + `storage/` | SQLite |

导出为 `<导出目录>/<工具>/<项目>/<日期>-<标题>.md`，只保留用户/助手消息和工具调用摘要。

## 7. 规则库

- 规则以 JSON 描述（见 `Sources/AgentSweepCore/Resources/rules.json`；另可在 `~/Library/Application Support/AgentSweep/rules.d/` 放本地规则），App 内置一份，启动时从 GitHub 拉取更新（签名校验）
- 每条规则：`id`、`tool`、`paths`（支持 glob 和 `~`）、`risk`、`action`（trash / age-filter / vacuum / none）、`explain`（中英文人话解释）
- 工具检测：App bundle id、CLI 可执行文件、目录是否存在

## 8. 视觉与交互（重点）

产品气质：**深色、科技、精致**，像一台“扫描仪”，而不是一个“文件管理器”。

- **扫描动画**：中央一个雷达/轨道环，每个 Agent 工具是环上的一颗星球，扫到哪个工具，哪个就亮起来，并飞出发光粒子汇入中心的容量数字；数字滚动增长
- **结果可视化**：同心环形图（sunburst）。内圈是工具，外圈是分类，颜色对应风险等级；悬停时高亮并显示解释
- **清理动画**：选中的块像碎片一样被吸入中心黑洞，环形图收缩，释放的容量数字倒数；完成后给一个柔和的光爆和「已释放 xx GB」
- **材质**：毛玻璃（`.ultraThinMaterial`）、细描边、渐变光晕；每个工具一种品牌主题色
- **动效原则**：弹簧动画、120Hz 流畅；支持系统「减弱动态效果」设置，自动降级为淡入淡出

## 9. 技术方案

- SwiftUI + Swift 6，macOS 14+（Apple Silicon 优先）
- 动画：SwiftUI `Canvas` + `TimelineView` 实现粒子；`Metal` shader（`.colorEffect` / `.distortionEffect`）做黑洞吸入与光晕
- 扫描：`FileManager` + `URLResourceKey.totalFileAllocatedSizeKey`，结构化并发，按规则分片
- SQLite：系统自带 `libsqlite3`
- 分发：Developer ID 签名 + 公证的 DMG，Sparkle 自动更新；**不上架 App Store**（沙盒无法访问 `~/.codex` 等目录）

## 10. 里程碑

| 阶段 | 内容 |
|---|---|
| M0 | 视觉原型（HTML）确认风格与动效 |
| M1 | 规则引擎 + 扫描 + 结果列表（无炫技 UI），在本机验证规则准确性 |
| M2 | 主视觉：扫描动画、环形图、清理动画 |
| M3 | 会话导出（Claude Code、Codex、Cursor 优先） |
| M4 | SQLite 压缩、运行进程检测、废纸篓恢复、清理日志 |
| M5 | 规则远程更新、签名公证、DMG 分发 |

## 11. 待定

- 产品名（暂定 AgentSweep）
- 是否做菜单栏常驻 + 超阈值提醒（v2）
- 是否收费 / 开源
