# Codex Dream Skin 中文说明

> 内容声明：本说明、发布记录、示例和示例元数据由 AI 生成或经 AI 编辑，不代表任何个人的个人观点、政治立场或社会观点。详见 [CONTENT_NOTICE.md](CONTENT_NOTICE.md)。

[English](README.md) · [Prompt 模板库](prompts/README.md) · [安全范围](SECURITY.md) · [上游归属](UPSTREAM.md)

Codex Dream Skin 是一个面向 Microsoft Store 版 ChatGPT/Codex 桌面应用的非官方、可恢复主题层。它通过仅绑定本机回环地址的 Chromium DevTools Protocol 注入视觉样式；不会修改 `WindowsApps`、`app.asar`、应用签名、聊天记录、项目或登录数据。

## 这个仓库包含什么

- PowerShell 运行时、注入器、CSS、自动测试和维护文档。
- Windows 主题管理器、安装器和卸载器源码。
- 一张中性的原创抽象演示背景图。
- 用于维护与发布审核的中文版 Prompt 模板库和 JSON Schema。

这是可公开审查的源码版，不包含用户图片、人物素材、日志、账号/项目/聊天数据、配置档案、官方二进制、Node.js、安装 EXE 或压缩发布包。

## 快速开始

### 系统要求

- Windows 10 或 Windows 11。
- 已为当前用户安装 Microsoft Store 版 ChatGPT/Codex。
- PowerShell 5.1 或更高版本。
- 已安装并加入 `PATH` 的 Node.js 22 或更高版本。

### 打开主题管理器

下载或克隆仓库后，在根目录双击：

[`START-CODEX-DREAM-SKIN.cmd`](START-CODEX-DREAM-SKIN.cmd)

该入口使用相对路径，移动整个目录后仍可使用；它只会打开主题管理器，不会在未选择“应用主题”或“恢复主题”前主动重启 ChatGPT。

如需为当前下载目录创建桌面快捷方式，请运行：

[`CREATE-DESKTOP-SHORTCUT.ps1`](CREATE-DESKTOP-SHORTCUT.ps1)

快捷方式会记录当前目录路径；将文件夹复制到另一台电脑或新位置后，请在新位置重新运行一次该脚本。

## 使用前须知

- 这是源码版。公开仓库刻意不提交预编译 EXE、安装包、捆绑运行时和用户主题，以便审查来源与内容安全。
- 使用前请先阅读 [`dream-skin/README.md`](dream-skin/README.md)、[`dream-skin/MAINTENANCE_PLAYBOOK.md`](dream-skin/MAINTENANCE_PLAYBOOK.md) 和 [`SECURITY.md`](SECURITY.md)。
- 主题层只负责颜色、背景、圆角、阴影和字体；不得接管官方控件的尺寸、位置、网格、Flex 排列或交互。
- 调试端点仅监听 `127.0.0.1`，但同一 Windows 用户下的其他本地程序仍可能访问 Chromium 调试会话。皮肤启用时请勿运行不受信任的本地程序，并在不需要时使用恢复功能关闭会话。
- 官方 ChatGPT/Codex 更新可能改变渲染标记。遇到问题请先按维护手册诊断安装、CDP、身份、注入、页面状态、CSS、生命周期和发布层，而不是直接添加哈希类选择器。

## Prompt 模板库

项目已将散落在维护手册、安全规则、QA 清单和代理说明中的提示词式约束整理为中文版模板库：

- [`prompts/common`](prompts/common)：内容安全审查、变更范围审查。
- [`prompts/coding`](prompts/coding)：兼容性诊断、最小修复与回归、发布验收。
- [`prompts/novel`](prompts/novel)：独立的原创叙事模板，未接入当前运行逻辑。
- [`schemas`](schemas)：结构化输出的 JSON Schema。
- [`examples`](examples)：每类模板的合格示例。

具体用途、输入和输出格式见 [`prompts/README.md`](prompts/README.md)，原提示词与新模板的对应关系见 [`prompts/SOURCE_MAP.md`](prompts/SOURCE_MAP.md)。

## 贡献与测试

修改兼容层前，先运行诊断并保持变更最小。基础自动检查可在仓库根目录运行：

```powershell
node .\dream-skin\tests\renderer-inject.test.mjs
node .\dream-skin\tests\injector-bootstrap.test.mjs
powershell -NoProfile -ExecutionPolicy RemoteSigned -File .\dream-skin\tests\run-tests.ps1
```

真实 Windows 验收仍需检查官方包身份、重启授权、截图和 CDP 关闭状态。不要把未执行的真实 UI 测试写成已通过。

## 归属与许可

本项目是 [Fei-Away/Codex-Dream-Skin](https://github.com/Fei-Away/Codex-Dream-Skin) 的独立维护衍生项目，遵循 MIT 许可证并保留必要归属；不是 OpenAI 官方项目，也不是上游项目的替代品。详见 [UPSTREAM.md](UPSTREAM.md)、[LICENSE](LICENSE) 和 [NOTICE.md](NOTICE.md)。
