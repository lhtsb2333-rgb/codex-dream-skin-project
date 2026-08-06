# ChatGPT Dream Skin 兼容维护方法论

本手册供后续维护模型使用，包括 Terra、Luna 等能力较轻的模型。目标不是“尽快补一个选择器”，而是用固定流程判断故障属于哪一层，再做最小修复。

## 一、不可破坏的边界

1. 只允许修改 Dream Skin 自身目录、主题文件、精确命名的快捷方式和 Dream Skin 专用启动配置。
2. 不修改 ChatGPT 安装包、资源文件、账号数据、聊天数据、项目文件、插件数据或系统安全设置。
3. 不使用会改变官方布局几何的 CSS：不得覆盖原生标题栏、侧边栏按钮、输入框、建议卡片的 `position`、`z-index`、宽高、内边距或 Flex 排列。
4. 不把随机哈希类名作为唯一锚点，例如 `_MainContentSurface_zbk1f_63`。哈希类只能用于诊断，不能作为身份判断的唯一条件。
5. 不用界面文字做主选择器。文字会因语言和版本变化。
6. 辅助窗口必须保持透明且不注入皮肤。主窗口身份至少由三个独立事实确认：`app:` 协议、语义 `main`、Dream Skin 已知侧边栏，以及输入框或 `[role="main"]`。
7. 不宣称完成了未实际执行的测试。不能操作 ChatGPT UI 时，应明确区分“真实注入测试”和“隔离状态转换测试”。

## 二、历次反复故障的共同原因

| 故障表现 | 实际层级 | 常见根因 |
| --- | --- | --- |
| 官方更新后完全没有皮肤 | 身份识别层 | 注入器在注入前只认旧类名，安全校验拒绝新版页面 |
| 首页有配色但没有背景 | 页面分类层 | 首页或空项目标记变化，页面落入 generic 状态 |
| 切换对话后背景消失 | 页面分类层 | 旧消息属性消失，没有识别新的对话滚动容器 |
| 新项目标题、卡片、输入框错位 | CSS 层 | 使用多层 `div:first-child`、固定高度或强制 Flex 布局 |
| 侧边栏隐藏按钮消失 | CSS 层 | 修改固定标题栏的定位、层级或裁剪方式 |
| Chat/Work 或 Classic 功能异常 | 作用域层 | CSS 选择器过宽，把主题规则应用到非 Codex 页面状态 |
| 更新后反复重启 | 生命周期层 | 更新守护与开机守护互相拉起，或旧注入器退出确认存在竞态 |
| 更新包有效但桌面仍启动旧版 | 发布层 | E 盘当前程序、压缩包、安装包或快捷方式没有同步 |

最重要的规律：官方更新通常改变实现类名和 DOM 包装层，但语义元素、功能控件和多个独立行为标记更稳定。

## 三、固定诊断顺序

任何兼容更新必须按以下顺序执行。前一层未通过时，不要修改后一层。

### 1. 安装发现层

- 读取 `%LOCALAPPDATA%\CodexDreamSkin\update-watcher.json` 的 `lastSeenVersion`。
- 确认当前 ChatGPT/Codex 可执行文件和包版本。
- 不要沿用旧 `WindowsApps` 路径。

### 2. 启动与 CDP 层

- 确认 `http://127.0.0.1:9335/json/version` 和 `/json/list` 可访问。
- 调试端口不可用时，先检查启动参数和进程；不要改 CSS。
- 调试端口只允许绑定回环地址。

### 3. 主窗口身份层

优先从当前状态文件定位正在使用的运行时；不要假设注入器一定来自 `engine` 目录：

```powershell
$state = Get-Content "$env:LOCALAPPDATA\CodexDreamSkin\state.json" -Raw | ConvertFrom-Json
$diagnose = Join-Path (Split-Path -Parent $state.injectorPath) 'diagnose-shell.mjs'
& $state.nodePath $diagnose --port $state.port
```

如果状态文件不存在，再从 E 盘当前源码或最新便携缓存中的 `dream-skin\scripts\diagnose-shell.mjs` 运行。

重点字段：

- `compatibleTargetCount` 应为 1。
- 主窗口应同时具有 `semanticMainElement`、`sidebar`，并具有 `composer` 或 `routeMain`。
- `avatar-overlay` 等辅助目标必须是 `compatibleIdentity: false`。
- 如果 `legacyShellClass` 变成 false，但 `semanticMainElement` 为 true，只修改兼容身份规则，不要引用新哈希类。

### 4. 注入层

- `injected`、`stylePresent`、`skinVersion` 用于区分“没有注入”和“注入后渲染错误”。
- `injector-error.log` 非空时先处理异常。
- 只有身份校验通过后才运行一次性注入或启动守护。

### 5. 页面状态层

当前状态机只有四种：

- `auxiliary`：无主侧边栏，不注入。
- `home-or-empty-project`：无对话标记，具有首页建议、首页容器或首页工具栏标记。
- `thread`：具有 `.thread-scroll-container`、`data-thread-scroll-footer` 或兼容消息标记。
- `generic`：主窗口存在，但不是首页或对话；保留基础配色，不启用沉浸式背景。

页面状态必须能在同一个渲染器中动态切换，不能要求重启。

### 6. CSS 层

选择器优先级：

1. HTML 语义标签与 ARIA 角色；
2. 多个功能标记的组合；
3. 官方稳定 `data-testid` 或公开类；
4. 类名片段，仅用于兼容视觉层；
5. 禁止把随机哈希类或连续 `first-child/nth-child` 当作核心锚点。

修复 CSS 时先问：这条规则只改颜色与背景，还是会改变官方布局？如果会改变布局，默认删除，而不是继续调整数值。

### 7. 生命周期层

- 一次启动只能有一个注入器和一个更新守护。
- 旧注入器停止后最多轮询 5 秒确认，不要在退出瞬间直接判失败。
- 更新守护不得通过登录启动项反复恢复皮肤。
- 导入主题不重启 ChatGPT；只有“应用主题”可以按设置重启。

### 8. 发布层

每次发布必须同步：

- `E:\Codex Dream Skin\当前程序`
- `E:\Codex Dream Skin\安装与分发`
- `E:\Codex Dream Skin\项目资料\vX.Y.Z-source`
- 桌面“ChatGPT 皮肤管理器”
- 桌面和开始菜单“ChatGPT（带皮肤启动）”
- 开机启动“ChatGPT（带皮肤自动启动）”

旧发布包先校验哈希，再移入 `旧数据归档`。安装与分发目录只保留当前版本。

## 四、最低测试矩阵

每次兼容更新必须全部通过：

1. `renderer-inject.test.mjs`：旧外壳、新语义外壳、首页、空项目、首条对话切换、普通页面、折叠侧边栏、辅助窗口。
2. `injector-bootstrap.test.mjs`：旧 `main.main-surface` 和新版语义 `main` 都能启动；无侧边栏的辅助窗口不能启动。
3. `run-tests.ps1`：配置事务、卸载范围、CDP 安全、参数引用、更新生命周期。
4. `diagnose-shell.mjs`：真实主窗口兼容目标恰好为 1，辅助目标为 0。
5. 真实一次性注入：验证版本、样式、输入框、侧边栏、页面溢出。
6. 至少一张真实截图：检查顶部按钮、侧边栏按钮、输入框、建议卡片没有遮挡。
7. 重新启动守护：确认新状态文件中的注入器存活且错误日志为空。

## 五、选择器变更规则

如果官方更新导致旧标记消失：

1. 先运行诊断脚本记录新旧差异。
2. 找到至少两个不依赖文字或哈希的功能标记。
3. 新标记以“旧 OR 新”方式加入，保留一个版本的向后兼容。
4. 给旧结构和新结构各加一个隔离夹具。
5. 确认辅助窗口仍被排除。
6. 禁止直接把截图中看到的 `_Abc_123_45` 写进身份校验。

## 六、推荐给后续模型的任务提示词

```text
请先阅读 MAINTENANCE_PLAYBOOK.md，并严格按八层顺序诊断。
先运行 diagnose-shell.mjs，确定问题属于安装、CDP、身份、注入、页面状态、CSS、生命周期或发布层。
不要用哈希类名、界面文字或多层 first-child 做核心选择器。
修复必须同时添加旧结构、新结构、辅助窗口和状态切换测试。
完成后运行完整测试、真实一次性注入和截图验证，再同步 E 盘当前程序、安装包、压缩包、源码及快捷方式。
不要修改 ChatGPT 安装文件、聊天数据、项目数据或系统设置。
```

## 七、当前兼容基线

- ChatGPT 包版本：`26.727.6591.0`
- 旧外壳类 `main.main-surface`：已消失。
- 新稳定外壳：语义 `main`。
- 侧边栏：`aside.app-shell-left-panel`。
- 首页/空项目：`[container-name:home-main-content]`、`group/home-suggestions` 或首页工具栏。
- 对话：`.thread-scroll-container` 等功能标记。
- 辅助头像窗口：有 `main`，但没有侧边栏、输入框和 `[role="main"]`，必须排除。

机器可读版本见 `compatibility-baseline.json`。
