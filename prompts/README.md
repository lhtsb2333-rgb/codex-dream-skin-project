# Prompt 模板库

> 内容声明：本文档及其说明的 Prompt 模板由 AI 生成或经 AI 编辑，不代表任何个人的个人观点、政治立场或社会观点。

本目录从项目现有维护手册、安全规则、QA 清单和代理说明中复制并规范化提示词。所有原文件均保留原样；当前运行代码和业务逻辑尚未引用本模板库。

## 模板统一结构

每个模板必须包含以下六部分：

1. 角色
2. 输入
3. 任务
4. 约束
5. 输出格式
6. 验收标准

输入变量使用 `{{placeholder}}` 格式。结构化输出必须符合对应 JSON Schema，并包含强制的 AI/非个人观点 `contentNotice` 字段。为保持程序兼容，JSON 字段名继续使用英文，但说明、枚举含义和示例内容均使用中文表达。

## 模板清单

| 模板 | 用途 | 主要输入 | 结构化输出 | 合格示例 |
| --- | --- | --- | --- | --- |
| [`common/content-safety-review.md`](common/content-safety-review.md) | 发布前检查隐私、凭据、许可、政治/社会敏感内容、视觉素材和 AI 声明 | 文件清单、发布标识、法律文本白名单、例外 | [`content-safety-report.schema.json`](../schemas/content-safety-report.schema.json) | [`content-safety-report.example.json`](../examples/content-safety-report.example.json) |
| [`common/change-scope-review.md`](common/change-scope-review.md) | 证明变更仅影响 Dream Skin 自有文件、进程、快捷方式、配置和回环端点 | 请求、差异、目标、允许根目录、测试证据 | [`change-scope-report.schema.json`](../schemas/change-scope-report.schema.json) | [`change-scope-report.example.json`](../examples/change-scope-report.example.json) |
| [`coding/compatibility-diagnosis.md`](coding/compatibility-diagnosis.md) | 按固定八层顺序诊断更新兼容故障，诊断阶段不改代码 | 现象、包/状态/CDP 事实、基线、日志、DOM 与计算样式证据 | [`compatibility-diagnosis.schema.json`](../schemas/compatibility-diagnosis.schema.json) | [`compatibility-diagnosis.example.json`](../examples/compatibility-diagnosis.example.json) |
| [`coding/implementation-and-regression.md`](coding/implementation-and-regression.md) | 实施已批准的最小修复，并报告真实回归证据 | 诊断、授权范围、源码/基线、测试、真实测试权限 | [`implementation-report.schema.json`](../schemas/implementation-report.schema.json) | [`implementation-report.example.json`](../examples/implementation-report.example.json) |
| [`coding/release-readiness.md`](coding/release-readiness.md) | 检查源码、产物、快捷方式、安全审查和回滚是否同步 | 版本/提交、产物、测试、目标、内容审查、哈希 | [`release-readiness-report.schema.json`](../schemas/release-readiness-report.schema.json) | [`release-readiness-report.example.json`](../examples/release-readiness-report.example.json) |
| [`novel/narrative-draft.md`](novel/narrative-draft.md) | 提供带连续性记录和内容声明的中性原创小说模板 | 前提、设定、角色、风格控制、情节点、连续性 | [`narrative-output.schema.json`](../schemas/narrative-output.schema.json) | [`narrative-output.example.json`](../examples/narrative-output.example.json) |

## 推荐工作流

处理一次兼容更新时，按以下顺序使用模板：

1. `common/change-scope-review.md`
2. `coding/compatibility-diagnosis.md`
3. `coding/implementation-and-regression.md`
4. `common/content-safety-review.md`
5. `coding/release-readiness.md`

不得把诊断和实现合并为一步。前一门禁失败或无法确定时，后续工作必须停止。

## 维护规则

- 原始说明新增、删除或改变约束时，同步更新来源映射。
- 跨领域隐私、内容与系统边界规则放在 `common`；渲染器、CDP、CSS 规则放在 `coding`。
- 输出契约变化时，模板、Schema 和示例必须在同一次修改中更新。
- 未标明原始来源并经过审查，不得弱化已复制的约束。
- 未单独批准和测试前，不得把本模板库接入运行代码。

完整对应关系见 [`SOURCE_MAP.md`](SOURCE_MAP.md)。
