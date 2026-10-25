# Changelog

每个版本一节，标题写成 `## <版本号>`。发版时 `scripts/make-appcast.sh` 会把对应一节作为应用内更新提示里的说明。

## 0.2.0
- 新增应用内自动更新：每天检查一次 GitHub 上的新版本，下载前校验 EdDSA 签名
- 新增设置窗口（⌘,）：可关闭自动检查，或开启自动下载并安装
- 新增 Kimi Code、MiniMax Code、ZCode、DeepSeek Harness 的清理规则，补上 Codex 桌面版缓存和 Antigravity
- 新增本地规则文件夹和「可能还没收录的工具」提示
- 结果列表可以按分组全选、反选
- 官网上线：ai-suifeng.github.io/agent-clean-mac

## 0.1.0
- 首个版本：扫描、风险分级、移到废纸篓与恢复、会话导出、数据库压缩
