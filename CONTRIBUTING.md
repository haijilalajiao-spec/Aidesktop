# 参与贡献

感谢你愿意改进 AI 工作台。

## 开发环境

- macOS 13 或更高版本
- Xcode 15 或更高版本
- Swift 5.9 或更高版本

## 本地构建

```bash
swift build
./build.sh
open "dist/AI 工作台.app"
```

桌面应用停靠功能依赖 macOS 辅助功能权限。重新构建采用临时签名时，系统可能要求重新授权。

## 提交改动

1. Fork 仓库并创建功能分支。
2. 保持改动聚焦，避免提交 `.build/`、`dist/`、日志或本机配置。
3. 至少运行一次 `swift build -c release`。
4. 涉及窗口停靠时，请验证窗口首次打开、应用间切换、工作台缩放和窗口还原。
5. 提交 Pull Request，说明问题、解决方式和验证结果。

## 报告问题

请附上 macOS 版本、目标应用名称、复现步骤和相关日志片段。日志位于 `~/Library/Logs/AI-Workbench.log`，公开前请删除账号、网址或其他私人信息。
