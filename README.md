# AI 工作台

一个原生 macOS AI 工具聚合器。左侧选择工具，右侧直接使用网页 AI，或把已安装的桌面应用窗口停靠到工作台内容区。

完整的产品定位、权限说明和数据存储说明见 [软件说明](SOFTWARE.md)。

## 功能

- 内嵌 ChatGPT、Claude、Gemini、Grok、DeepSeek 等网页 AI
- 停靠 Cherry Studio、Claude、ChatGPT、Gemini、Magpie 等 macOS 应用窗口
- 自动适配工作台尺寸，并在切换工具时还原原窗口位置
- 支持添加自定义网页和 `.app`
- 支持分组、排序、隐藏和恢复工具
- 保留网页登录状态和工作台布局
- 无第三方依赖

## 系统要求

- macOS 13 或更高版本
- Xcode 15 或更高版本
- Swift 5.9 或更高版本

## 构建

```bash
git clone https://github.com/haijilalajiao-spec/Aidesktop.git
cd Aidesktop
./build.sh
open "dist/AI 工作台.app"
```

`build.sh` 会执行 Release 编译、组装 `.app` 并进行本地签名。若钥匙串中有稳定的签名身份，可以这样构建：

```bash
WORKBENCH_SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./build.sh
```

## 使用

- 点击侧栏条目切换工具。
- 网页工具支持刷新、回到首页和使用默认浏览器打开。
- 桌面应用会停靠到右侧，并随工作台窗口调整尺寸。
- 点击红色关闭按钮会收起工作台，`⌘Q` 才会退出。
- `⌘⇧L` 启动侧栏中的全部桌面应用。
- `⌘R` 刷新当前网页。

### 辅助功能权限

macOS 不支持跨进程窗口真正嵌入。AI 工作台通过辅助功能 API 移动和缩放目标应用窗口，实现视觉上的停靠。

首次使用桌面应用停靠时，请前往“系统设置 → 隐私与安全性 → 辅助功能”，添加并启用 AI 工作台。

临时签名与具体构建产物绑定。重新构建后，macOS 可能要求重新授权。长期使用建议通过 `WORKBENCH_SIGN_IDENTITY` 使用稳定签名身份。

## 项目结构

```text
Sources/AIWorkbench/
├── AIWorkbenchApp.swift   # 应用生命周期和主窗口
├── ContentView.swift      # 侧栏、工具栏和内容区
├── WindowDocker.swift     # 桌面窗口停靠与还原
├── WebView.swift          # WKWebView 管理
├── ServiceStore.swift     # 工具、分组和持久化
├── Models.swift           # 内置服务模型
├── AddServiceSheet.swift  # 添加网页或桌面应用
└── SelfTest.swift         # 窗口停靠回归测试
```

## 已知限制

- 固定尺寸窗口会保留原尺寸并靠在内容区左上角。
- 无法移动进内容区的窗口会恢复原位置并单独打开。
- 部分网站会拒绝在 `WKWebView` 中登录，可改用默认浏览器或桌面应用。
- 网页内容和第三方应用受各自服务条款约束。

## 贡献

欢迎提交 Issue 和 Pull Request。开发与验证约定见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 许可证

本项目使用 [MIT License](LICENSE)。
