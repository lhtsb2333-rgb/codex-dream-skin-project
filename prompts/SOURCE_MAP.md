# 原提示词到新模板的对应关系

> 内容声明：本映射由 AI 生成或经 AI 编辑，不代表任何个人的个人观点、政治立场或社会观点。

所有原始文件均保留原样。下表记录每类提示词式规则复制和规范化后的位置。

| 原始来源 | 原始规则范围 | 新模板位置 | 整理方式 |
| --- | --- | --- | --- |
| `dream-skin/agents/openai.yaml` | 应用、验证、更新或恢复皮肤的默认请求 | `coding/compatibility-diagnosis.md`、`coding/implementation-and-regression.md`、`coding/release-readiness.md` | 按阶段拆分，避免诊断、实现和发布混为一步 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第一节 | 受保护文件/数据、选择器边界、辅助窗口隔离、测试声明真实性 | `common/change-scope-review.md`、两个兼容诊断/实施模板 | 公共安全规则去重到 Common，渲染器约束保留在 Coding |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第二至三节 | 故障分类和强制八层诊断顺序 | `coding/compatibility-diagnosis.md` | 保留原顺序及首个失败层停止条件 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第三节第 5 层 | 四种页面状态与动态路由切换 | 兼容诊断、最小修复模板 | 分别作为诊断证据和回归不变量保留 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第三节第 6 层及第五节 | 稳定选择器优先级、旧/新 OR 兼容、夹具要求 | 兼容诊断、最小修复模板 | 合并重复表述，保留全部选择器禁令 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第三节第 7 层 | 单注入器/守护、限时退出等待、重启策略 | 最小修复模板、变更范围模板 | 保留生命周期与授权约束 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第三节第 8 层及第四节 | 发布同步和最低测试矩阵 | 发布就绪、最小修复模板 | 拆分为实施证据与发布门禁 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第六节 | 原有“后续模型任务提示词” | 三个 Coding 模板 | 展开为角色、输入、任务、约束、输出和验收，不删除原提示词 |
| `dream-skin/MAINTENANCE_PLAYBOOK.md` 第七节及 `compatibility-baseline.json` | 当前机器可读选择器/状态基线与不变量 | 兼容诊断、最小修复模板 | 基线作为输入，不变量进入输出和测试要求 |
| `dream-skin/SKILL.md` 工作流 | 安装、启动、验证、截图和恢复顺序 | 最小修复、发布就绪模板 | 改写为实际执行证据和发布门禁 |
| `dream-skin/SKILL.md` 安全边界 | 官方包保护、壁纸要求、原生控件交互、导入限制、包/CDP/进程/配置安全 | 变更范围、兼容诊断、最小修复模板 | 跨领域规则放入 Common，实施规则保留在 Coding |
| `dream-skin/references/runtime-notes.md` | Store 身份、回环 CDP、状态/进程身份、UTF-8、互斥锁、更新处理 | 变更范围、兼容诊断、最小修复模板 | 合并操作性重复规则并保留安全失败行为 |
| `dream-skin/references/qa-inventory.md` | 功能、视觉、探索、自动化和真实验收 | 最小修复、发布就绪模板 | 区分测试类型，禁止虚报真实测试 |
| `SECURITY.md` | 允许的受管根目录、禁止区域和审查规则 | 变更范围、发布就绪模板 | 保留精确安全边界 |
| `SECURITY.md`、`CONTENT_NOTICE.md`、`NOTICE.md` | 隐私、凭据、许可、政治/社会敏感内容及 AI 声明 | 内容安全、发布就绪模板、全部输出 Schema | 合并为统一内容门禁；所有结构化输出强制 `contentNotice` |
| 根目录 `README.md` 的安全说明 | 回环端点风险、纯视觉 CSS、稳定选择器 | 变更范围及两个诊断/实施模板 | 与更详细的来源规则合并 |
| 无现有项目来源 | 原创小说提示词 | `novel/narrative-draft.md` | 新增的可选骨架；不接入运行时，也不冒充原有业务流程 |

## 覆盖说明

- 提取模板期间没有删除或修改任何原始文件。
- 当前项目没有小说工作流或小说原提示词，因此 Novel 模板保持隔离。
- 操作命令继续保留在原始运行文档中；模板要求提交证据，不重复复制所有命令。
- 兼容基线变化时，应更新模板输入和验收标准，不能硬编码新的哈希类名。
