# Kimi Code 本地 token 历史可行性

调查日期：2026-09-27。只读检查官方文档、源码和本机日志结构；没有调用账户接口、读取密钥、修改配置或运行模型请求。

本文为调查当日的可行性记录，本地 token 历史与云端订阅额度属于不同需求，尚未据此批准开发。已固定到提交的源码链接保留原版本；其他官方文档及上游状态未在整理时重新验证。

## 结论

有可用数据。Kimi Code CLI 已将模型用量写入本地会话事件日志，可据此开发类似 Codex 的本机 token 历史统计。当前缺口是 CodexBar 的读取、归属、去重与计价接入，并非 Kimi 只有额度百分比可供读取。费用仍应称为标价估算，不能据此恢复真实订阅账单或全部设备用量。

## 新版数据

官方说明会话保存在 `$KIMI_CODE_HOME/sessions/<workDirKey>/<sessionId>/`，默认根目录 `~/.kimi-code`。`state.json` 保存会话元数据，`agents/*/wire.jsonl` 保存主代理和子代理事件。[官方会话文档](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/sessions)

本机只读检查发现 CLI 版本 2.1.0 的多个新版 wire 文件含 `usage.record`，包含 `model`、`time`、`usageScope` 和以下用量字段；部分会话 state 文件有 `cwd`。2026-09-28 整理时省略了个人日志数量和使用日期范围。没有记录聊天内容、具体项目路径或具体模型名称。

| 字段 | 解释 |
| --- | --- |
| `inputOther` | 非缓存输入 |
| `inputCacheRead` | 缓存读取输入 |
| `inputCacheCreation` | 缓存创建输入 |
| `output` | 输出 |

官方 `inputTotal` 明确将三类输入相加，`grandTotal` 再加输出。统一类型没有单独 reasoning 字段；不能承诺与 Codex 页面每个分类一一对应。[固定提交的 TokenUsage 与求和定义](https://github.com/MoonshotAI/kimi-code/blob/be7d5f5fea7800778e4660cd5f36780ba783bddd/packages/agent-core-v2/src/human/llm/usage.ts)

官方累加实现将每条 record 加入总量、按模型和按 turn 汇总，说明记录是参与累加的用量，不是当前上下文占用。不能把 `contextTokens` 当累计消费，也不能同时累加原始 records 与已汇总的 status。[固定提交的累加实现](https://github.com/MoonshotAI/kimi-code/blob/be7d5f5fea7800778e4660cd5f36780ba783bddd/packages/agent-core-v2/src/human/usage/usage.ts)；[上下文与用量状态字段](https://github.com/MoonshotAI/kimi-code/blob/be7d5f5fea7800778e4660cd5f36780ba783bddd/packages/agent-core-v2/src/agent/usage/usageEvents.ts)

本机 `llm.request` 还有 `provider`、`model`、`modelAlias`、`turnStep` 和 `time`，有助于确认模型及供应商归属。但记录中同时存在 model 字符串含 kimi 的值，以及其他或未解析值。CLI 支持其他供应商，不能把整个目录直接归入 Kimi 订阅；模型名包含 kimi 也不能单独证明来自 Kimi Code 订阅而非开放平台。

## 旧版兼容

本机还存在 `~/.kimi/sessions`，旧 wire 文件中同时发现顶层 `message.payload.token_usage` 和嵌套 `event.payload.token_usage`，使用 snake_case。官方旧 Wire 文档将 `StatusUpdate.token_usage` 定义为当前 step 用量，并支持从 wire.jsonl 重放历史。这为旧记录接入提供了入口，但嵌套事件与顶层事件的关系、模型关联及去重应单独核对，不能把两类计数直接相加当消费次数。[旧 Wire 文档](https://moonshotai.github.io/kimi-cli/en/customization/wire-mode.html)

## 接入前必须处理的边界

- 版本：本机新版 wire 协议 1.0、1.2、1.3、1.4、1.5 并存。当前上游 main 还在改变持久化事件实现，读取器应按实际文件兼容，不能只依赖最新类型。
- 去重：本机另有 `context.append_loop_event.event.type=step.end` 记录 携带相同类别的 usage，不能与 `usage.record` 再相加。应选一种权威记录，其余用于核对。本次检查的新版 records 按完整 JSON 比较没有完全重复，但这不证明语义无重复。官方 fork 会生成独立会话副本。必须验证目标版本 fork 是否复制用量、旧版迁移是否同时保留源日志、子代理是否另有汇总，防止重复收费。此次未完成端到端 fork/copy 写入路径审计。[官方 fork 行为](https://www.kimi.com/code/docs/en/kimi-code-cli/guides/sessions#forking-a-session)
- 覆盖：仅涵盖保存下来的本机客户端记录；无法推断其他设备、浏览器或第三方客户端未落盘的请求。日志中没有 usage 的失败请求也不能补算。
- 价格：token 明细足以做数量统计；金额还需模型及服务版本对应的价格规则。不能用订阅月费乘额度比例，不能默认 API 标价就是订阅扣额算法。
- 安全读取：只解析统计所需字段，不导出 prompts、工具参数或源码内容。

新版本地 Server API 也提供 session snapshot 的用量结构，可作为运行中数据入口；普通会话列表的默认零值不能直接用作历史总量。文件读取可避免依赖服务运行。此接口不是完整云端订阅账单 API。[官方 Server API](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)

因此，token、日期、模型和会话/项目维度已有实际数据基础。若决定开发，需先兼容新旧日志、严格区分供应商和订阅来源，并验证增量与副本去重。是否添加标价估算应单独确认。
