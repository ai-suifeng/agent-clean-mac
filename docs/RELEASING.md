# 发版与更新策略

AgentSweep 通过 GitHub 发版，用户在应用内收到更新。整条链路不需要服务器，也不收费。

## 用户这一侧

- 应用内置 [Sparkle](https://sparkle-project.org) 2.10.0，每 24 小时检查一次更新清单：
  `https://github.com/ai-suifeng/agent-clean-mac/releases/latest/download/appcast.xml`
  （GitHub 会把 `latest/download/<文件名>` 重定向到最新一个正式 Release 的同名附件。）
- 发现新版本时弹窗，显示 CHANGELOG 里这一版的说明，用户一键安装并重启。
- 「设置」（⌘,）里可以关闭自动检查，或开启「自动下载并安装」（下次退出时静默安装）。
- 菜单「AgentSweep → 检查更新…」和侧边栏底部的「检查更新」可以手动检查。
- 安装前 Sparkle 会用应用里的公钥校验更新包的 EdDSA 签名，签名不对直接拒绝（已实测：篡改一个字节即被拒绝）。
- 0.1.0 没有内置更新，需要用户手动下载一次 0.2.0。

## 密钥

| 内容 | 位置 |
|---|---|
| 公钥 | 写在 `scripts/build-app.sh` 的 `SPARKLE_PUBLIC_KEY`，打包进 `Info.plist` 的 `SUPublicEDKey`，可以公开 |
| 私钥 | 作者电脑的钥匙串（账户 `agentsweep`）和 `~/.config/agentsweep/sparkle_private_key`；GitHub 仓库 Secret `SPARKLE_PRIVATE_KEY` |

**私钥丢了，已安装的所有用户都无法再收到更新**（新版本签名对不上），只能让大家重新手动下载。请把私钥文件备份到密码管理器里。

需要在新电脑上签名时：

```bash
generate_keys --account agentsweep -f ~/.config/agentsweep/sparkle_private_key   # 导入到钥匙串
```

## 首次配置（只做一次）

1. 仓库 Settings → Secrets and variables → Actions → New repository secret：
   名字 `SPARKLE_PRIVATE_KEY`，内容是 `~/.config/agentsweep/sparkle_private_key` 文件里的那一行。
   或者在终端：`gh secret set SPARKLE_PRIVATE_KEY < ~/.config/agentsweep/sparkle_private_key`
2. 仓库 Settings → Pages → Build and deployment → Source 选 **GitHub Actions**（官网用）。

## 发一个新版本

1. 在 `CHANGELOG.md` 顶部加一节 `## 0.3.0`，每条用 `- ` 开头。这一节会原样出现在用户的更新弹窗里。
2. 提交并推送到 `main`。
3. 打标签并推送：

   ```bash
   git tag -a v0.3.0 -m "AgentSweep 0.3.0"
   git push origin v0.3.0
   ```

4. GitHub Actions（`.github/workflows/build.yml`）会自动：
   - 跑测试，构建通用版（Apple 芯片 + Intel），版本号取自标签；
   - 生成 `AgentSweep-0.3.0.dmg/.zip`，以及固定名字的 `AgentSweep.dmg/.zip`（官网下载按钮用）；
   - 用私钥给 `.zip` 签名，生成 `appcast.xml`；
   - 把这些文件发布到 Release。

   缺少 `SPARKLE_PRIVATE_KEY` 时这一步会失败并提示，不会发出一个老用户收不到的版本。
5. 发布完成后，老用户在 24 小时内会看到更新提示；官网的下载按钮自动指向新版本。

版本号用 `主.次.修订`，必须比上一版大（Sparkle 按版本号比较）。只改规则也值得发一个修订版，新工具的规则就是这样送到用户手上的。

## 签名说明

安装包只做了本机签名（ad-hoc），没有苹果开发者证书。为了让 Sparkle 认出新旧版本是同一个应用，签名时把「指定要求」固定成 Bundle ID：

```
designated => identifier "app.agentsweep.mac"
```

以后如果申请了 Developer ID，换成正式签名和公证即可：首次打开不再有「无法验证开发者」的提示，EdDSA 更新签名照旧使用。

## 本地验证一次更新

```bash
# 旧版：指向本地清单，调试版支持 --quit-after
VERSION=0.1.9 FEED_URL=http://127.0.0.1:8765/appcast.xml scripts/build-app.sh --debug
# 新版并签名
VERSION=0.2.0 FEED_URL=http://127.0.0.1:8765/appcast.xml scripts/build-app.sh --debug --dist
SPARKLE_BIN=<Sparkle>/bin scripts/make-appcast.sh 0.2.0 build/AgentSweep-0.2.0.zip \
  http://127.0.0.1:8765/AgentSweep-0.2.0.zip ~/.config/agentsweep/sparkle_private_key > <server>/appcast.xml
# 启动旧版：--check-updates 立即在后台检查，--quit-after 30 让它退出时安装
open <旧版>.app --args --check-updates --quit-after 30
```
