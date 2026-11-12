# DedsiCodexUsageBar

macOS 菜单栏小工具，用来查看本机 **OpenAI Codex** 的额度使用情况。

不占用 Dock，只出现在屏幕右上角菜单栏；点击后可查看当前窗口用量、刷新数据，并快捷打开本机 ChatGPT / Codex Resets 页面。

## 功能

- 菜单栏显示用量摘要（例如 `C 55%`）
- 按套餐动态展示额度窗口（如 Plus 常见「5 小时 + 每周」，Pro 通常只有「每周」）
- 进度条、重置倒计时
- 手动刷新（`⌘R`）
- 打开本机 ChatGPT App
- 打开 [Codex Resets](https://codex-resets.com/)
- 可选「登录时打开」

主题色：`#3A86FF`。界面文案为中文。

## 前提条件

使用前需要满足：

1. **macOS 14+**
2. 已安装 **Swift 工具链**（Xcode 或 Command Line Tools）
3. 已安装并登录 **Codex CLI**（ChatGPT 账号登录，不是纯 API Key）

### Codex 前提

本工具读取本机 Codex CLI 的登录态，调用与 Codex 相同的用量接口：

```text
~/.codex/auth.json
→ GET https://chatgpt.com/backend-api/wham/usage
```

因此需要：

| 要求 | 说明 |
|------|------|
| 安装 Codex CLI | 本机可执行 `codex` |
| 完成 `codex login` | 使用 ChatGPT Plus / Pro 等账号登录 |
| 存在 `auth.json` | 默认在 `~/.codex/auth.json`；若设置了 `CODEX_HOME`，则为 `$CODEX_HOME/auth.json` |
| ChatGPT OAuth 登录 | 仅有 `OPENAI_API_KEY`、没有 ChatGPT access token 时，无法查询套餐额度 |

可选：

- 本机安装 [ChatGPT 桌面版](https://chatgpt.com/)（`/Applications/ChatGPT.app`），用于菜单里的「ChatGPT」快捷打开

### 安装 Codex CLI（示例）

若尚未安装，可参考 OpenAI 官方 Codex CLI 安装方式，例如：

```bash
npm install -g @openai/codex
# 或按你当前环境使用官方推荐的安装命令
```

然后登录：

```bash
codex login
```

确认登录文件存在：

```bash
ls ~/.codex/auth.json
```

## 图标

App 图标来源：`Assets/logo-source.png`（当前为桌面 `DCUB-logo.png`）  

已生成：

- `Assets/logo-square.png`（正方形黑底适配）
- `Resources/AppIcon.iconset/`（各尺寸 PNG）
- `Resources/AppIcon.icns`（打包进 `.app`）

如需更换 logo：

```bash
cp ~/Desktop/DCUB-logo.png Assets/logo-source.png
./scripts/generate-icons.sh
./scripts/build-app.sh
```

## 打包

在项目根目录执行：

```bash
./scripts/build-app.sh
```

脚本会：

1. `swift build -c release --product DedsiCodexUsageBar`
2. 组装 `dist/DedsiCodexUsageBar.app`
3. 写入 `Info.plist`（菜单栏 App，不显示 Dock）并嵌入 `AppIcon.icns`
4. 进行本地 ad-hoc 签名（个人使用，不上架 App Store）

产物路径：

```text
dist/DedsiCodexUsageBar.app
```

## 运行

```bash
open dist/DedsiCodexUsageBar.app
```

或先打包再打开：

```bash
./scripts/build-app.sh && open dist/DedsiCodexUsageBar.app
```

启动后看菜单栏是否出现 `C …`：

- 正常：显示百分比，如 `C 55%`
- 未登录 / 无额度数据：显示 `C —`，点开面板可看错误提示

退出：点开面板 →「退出」。

## 开发说明

- 语言：Swift + AppKit
- 构建：Swift Package Manager
- 最低系统：macOS 14
- Bundle ID：`com.dedsi.dedsicodexusagebar`

仅本地调试也可直接跑二进制（无 `.app` 包装时，「登录时打开」可能不可用）：

```bash
swift build -c release
.build/release/DedsiCodexUsageBar
```

## 隐私

- 凭证只读取本机 `auth.json`
- 网络请求只发往 OpenAI / ChatGPT 相关域名
- 不会上传到第三方服务器

## 许可证

个人 / 团队内部使用。按需补充正式许可证文本。
