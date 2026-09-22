# Issue #3 上游接收审核

日期：2026-09-22。结论：先选择性移植 Kimi 查询修复与 Codex 刷新稳定性修复，暂不全量升级或安装。

## 范围与证据

- 入口：[fork issue #3](https://github.com/allgemeiner-intellekt/CodexBar/issues/3)。它是更新提醒，不是单一故障报告。
- 本地基线：`cc0e49c22b75f680769604a43cf43b8f37c113d0`。
- 固定上游：`e57e52c06c190fab22a6d7073060773e6d1c80d1`。本轮不追随后续 main 变化。
- 比较命令：`git diff cc0e49c22...e57e52c06`；提交清单：`git log --no-merges --oneline cc0e49c22..e57e52c06`。
- 总差异为 398 个非合并提交、1,780 个文件，其中 833 个文件位于 Sources。这是候选范围，不表示逐行审核了所有文件。
- 五个独立子任务分别审核 Kimi 解析、Kimi 认证与地区、Codex 刷新、Standards、Spec；主审复核关键发现及跨提交依赖。
- 需求依据为 [personal-requirements](../.agents/skills/personal-requirements/SKILL.md)：OpenAI、Kimi 订阅用量是核心需求，Cursor 当前非核心，偏好简单维护。
- 本轮读取了源码、测试、原始 issue/PR，并做 Git 合并树模拟。没有运行应用、Swift 构建或测试，没有请求真实用量、读取凭据、安装、合并分支、推送或发表 GitHub 评论。

## 建议接收范围

以下是移植候选，不是已经接收的提交。优先移植必要生产逻辑及对应隔离测试，避免直接复制上游最新文件而带入无关重构。

| 候选 | 接收范围 | 原因与边界 |
| --- | --- | --- |
| `51ed16bdd` / #3697 + `fd2414d29` / #3755 | 成组接收 ratio pools 解析和严格零占位修正 | API key 与 CLI credential 查询可能成功返回 HTTP 200，却缺少旧的必填 `usage` 字段。新 parser 接受 5h、weekly、monthly total；后续修复避免零 ratio 占位覆盖可靠的非零计数。Web GetUsages 是另一条路径，不能据此认定用户原故障已解决。 |
| `9f4f544a5` / #3543 | 自动窗口选择与模型测试 | 已获取的月额度耗尽时，Automatic 菜单栏优先显示它；显式窗口选择不变。此改动不能补齐缺失的月用量或认证来源。 |
| `d987dd59a` / #3758 | 仅 Kimi 数字转换及边界测试 | 用 `Int64(exactly:)` 避免超大浮点数字转换触发 trap。无需连带接收其他供应商的修改。 |
| `babfb51da` / #3414 | 仅 Desktop JWT 过期检查、失效会话恢复、去重、取消与显式来源保护 | 自动来源的过期/被拒绝 Desktop 会话不再挡住可用浏览器会话。会员名抓取、CLI 版本显示和相关 enrichment 重构不属于本轮最小范围。 |
| `dc2e01ea9` / #3809 | 来源 policy 和 enrichment resolver 的 Auto gate，以及测试 | Manual 空值/无效值与 Off 不应自动发现 Desktop/浏览器凭据。显式环境或手动来源保留原有权威性。 |
| `46b8840b2` / #3466 | 401/403 区分及认证 HTTP transport 逻辑 | 403 表示权限拒绝时不应按 token 过期触发 CLI 恢复。接收时须补下方 Spec 发现的错误分类边界。 |
| `b76508292` | 失败发布时保留有效账号快照，以及隔离测试 | 网络波动时保留原数据、来源和测量时间；不把旧数据记成新历史样本。账号移除、配置/凭据变化、旧刷新代际仍按原规则失效。 |
| `68a9005a2` / #3667 + `034e01379` / #3672 的共享取消部分 | 成组移植错误解包、保留/重试/hooks 分类和 Codex 取消测试 | 网络错误可能包在 OAuth 错误中；取消也必须解包，否则会进入失败计数。仅接收 #3667 不完整。若保留 #3672 整提交，则需扩大其他供应商回归覆盖。 |

解析需求的原始证据见 [#3694](https://github.com/steipete/CodexBar/issues/3694) 与 [#3754](https://github.com/steipete/CodexBar/issues/3754)。#3754 明确限定无 monthly pool、可靠计数、窗口相同和 reset 近似一致的混合响应；不能把所有零 ratio 一律替换成 count。

### 可避免的前置依赖

- #3697 的原补丁建立在 #3414 新会员模型和 enrichment 上，但 ratio 解析在业务上不依赖会员名。移植时保留基线会员处理即可。
- `ISO8601DateParser` 来自 `12e3cc2dd` 的共享重构。基线已有日期解析逻辑，可复用或提取小 helper，不必接收整批 148 文件重构。
- #3809 邻近 importer 重构影响补丁上下文，不构成必须接收 `c46e90701` 整批共享重构的理由。
- `b76508292` 的父版本含 extra-credit 成功分支修改。失败快照保留不依赖该逻辑，移植时保留基线成功分支即可。
- #3667/#3672 的共享错误分类不要求同步中途所有公共重构。
- 原生截图 proof 测试需要专门宿主和环境，通常默认跳过。本轮移植应以 parser、来源策略、刷新状态及菜单模型测试为主，不把存在 proof 文件算成 UI 验证成功。
- 以上是源码依赖分析，未通过实际移植编译证明无冲突。后续仍需适配测试 API，按最终代码更新架构计数断言，不能机械覆盖上游计数。

## 暂缓与条件接收

| 候选 | 建议 |
| --- | --- |
| `7618b4fdd` / #3826 Kimi 地区支持 | 若使用国际站，应进入接收范围；否则暂缓。默认中国、API/Web/Cookie/链接一起随地区切换，并限制无 host 元数据的 CLI 凭据只用于中国默认地址。接收时处理 Standards 发现的 AppKit 测试依赖。用户使用的地区本轮未确认。 |
| #3414 会员名与 CLI 版本 | 暂缓。基线 `KimiUsageFetcher.swift:98–141` 已用 BoundedTaskJoin 对可选订阅统计做超时及失败降级；新增双任务保护主要服务于本提交新增的 plan 请求，不应当作基线必须修复的缺陷。认证恢复不依赖它。 |
| `588ccdca6` / #3560 可见账号重新认证 | 有局部修复价值，但多账号/混合凭据来源尚未确认是需求；可在遇到来源路由问题时单独接收。测试需要适配基线登录 runner 类型。 |
| `410a55471` / #3373 订阅日期 | 引入可选 WebView 捕获、任务及缓存状态，暂不为核心额度百分比查询接收。 |
| `b07fd2ea4` / #3296 extra credits | 这是余额/月度 cap 正确性修复，不是无关成本历史功能；购买额外 credits 或使用相应 Business cap 时有价值，当前场景未知。 |
| 新供应商、Cursor 专属功能、Linux 桌面、分享和历史统计 | 不作为这次核心修复的前置目标；共享安全或稳定性修复仍按实际影响评估。 |
| Quotio | 是参考项目，不是本 fork 的直接合并来源。本轮不审核它的全部 214 个时间窗口提交。 |

## Standards

独立审核发现 1 项仓库规范偏离，最高 P2；未确认跨供应商身份串用或必需/可选 sibling async let 违规。

**[P2] 普通地区设置测试创建真实菜单栏控制器。**

`7618b4fdd` 在目标树 [KimiRegionSettingsTests.swift:56–58](https://github.com/steipete/CodexBar/blob/e57e52c06c190fab22a6d7073060773e6d1c80d1/Tests/CodexBarTests/KimiRegionSettingsTests.swift#L56-L58) 为断言地区 Dashboard URL 调用 `withStatusItemControllerForTesting`。该 helper 默认使用 `NSStatusBar.system`，创建真实控制器。

AGENTS.md 要求："Prefer covering menu behavior through stable state/model seams … instead of constructing live NSStatusBar/NSMenu flows unless the AppKit wiring itself is the thing under test"。地区到 URL 的映射不需要真实状态栏，增加 headless CI 不稳定风险。最小处理是提取可直接测试的 URL resolver，保留地区设置持久化断言。此项是测试指南偏离，不是已复现的应用运行故障。

没有另列 Fowler 启发式风格建议。Standards 共 1 项，最高 P2。

## Spec

原先九个候选提交对各自限定需求未发现确定违约。扩大到 `46b8840b2` 后，发现 1 项 P2 错误分类缺口。

**[P2] 403 响应正文可能让权限失败被误判为取消或超时。**

#3466 的目标是将 403 保留为 terminal server error，只有 401 进入认证恢复。目标树实际路径为：

1. [CodexAuthenticatedHTTPTransport.swift:24–28](https://github.com/steipete/CodexBar/blob/e57e52c06c190fab22a6d7073060773e6d1c80d1/Sources/CodexBarCore/Providers/Codex/CodexAuthenticatedHTTPTransport.swift#L24-L28) 将 403 和响应正文保存为 `serverError`。
2. [CodexOAuthUsageFetcher.swift:348–350](https://github.com/steipete/CodexBar/blob/e57e52c06c190fab22a6d7073060773e6d1c80d1/Sources/CodexBarCore/Providers/Codex/CodexOAuth/CodexOAuthUsageFetcher.swift#L348-L350) 将正文包含在错误描述中。OAuth strategy 不对 serverError fallback，fetch plan 及失败发布路径保留原错。
3. [UsageStore+ClaudeHistoryFallback.swift:61–74](https://github.com/steipete/CodexBar/blob/e57e52c06c190fab22a6d7073060773e6d1c80d1/Sources/CodexBar/UsageStore%2BClaudeHistoryFallback.swift#L61-L74) 按描述是否包含 `cancelled` 判断取消；同文件 108–113 按 `timeout` 等文字决定保留旧快照。
4. [UsageStore+Refresh.swift:834–841](https://github.com/steipete/CodexBar/blob/e57e52c06c190fab22a6d7073060773e6d1c80d1/Sources/CodexBar/UsageStore%2BRefresh.swift#L834-L841) 在发布失败之前先抑制取消。

因此，在账号与刷新代际稳定时，合成响应 `HTTP 403`、正文 `subscription cancelled` 会被当作取消而跳过错误发布；正文含 `timeout` 也会误中保留逻辑。此路径由代码静态确认，未在线观察或运行测试复现。接收时应让已知 HTTP/认证错误优先于文本 fallback，并增加 403 正文含取消/超时词的负例。不能宣称这组补丁已经保证所有权限失败都不会被缓存掩盖。

需求范围另有两处需要准确表述，但不计作缺陷：

- [#3536](https://github.com/steipete/CodexBar/issues/3536) 的 Desktop Local Storage JWT 采集没有被 #3543 完整解决；#3543 本来就只承诺已取得月额度后的自动展示。
- [#3500](https://github.com/steipete/CodexBar/issues/3500) 的广泛唤醒问题、更新后旧 widget 进程问题不等同于本轮账户缓存与错误包装修复，相关提交明确保留这些未解决范围。

Spec 共 1 项，最高 P2。未确认 P0/P1 问题；静态审核不构成运行正确性证明。

## Kimi 仍保留的使用边界

- 自动恢复会进入浏览器读取路径。现有 importer 使用默认浏览器顺序，没有在 Kimi 层固定 Chrome-only，也会收集多个候选来源。访问 gate 仍生效，但不能承诺自动恢复绝不提示。移植时需核对本 fork 的 Chrome 优先约定，测试使用注入 token，不能为审核调用真实 Cookie 读取。
- API/CLI 调用会在核心 API 请求前同步解析可选 Web enrichment token。两秒网络等待限制不覆盖这段凭据发现过程；基线已有此行为。
- API key 与自动取得的 Web token 没有同账户校验。不同 Kimi 账号时，已有余额拼接可能混合数据；#3414 完整接收还会扩大到会员名。这是基线局限，当前用户是否触发未知。本轮不新增跨来源会员字段拼接，后续若需补充数据应明确来源并验证归属。
- 未确认用户当前 Kimi 数据来源与地区。解析问题、会话问题、地区路由问题分别适用于不同路径，不能只凭上游修复存在就认定用户故障已定位。

## 为什么暂不全量同步

在不改变工作树和分支的前提下，执行了 `git merge-tree --write-tree --name-only cc0e49c22 e57e52c06`。Git 仅报告六个已由个人维护整理删除的文档存在 modify/delete 冲突：DEVELOPMENT、DEVELOPMENT_SETUP、FORK_QUICK_START、FORK_ROADMAP、FORK_SETUP、UPSTREAM_STRATEGY。没有执行真正的合并，模拟也不包括未提交的个人需求修改。

因此，全量同步的主要成本不是文本冲突，而是行为和验证范围。它会同时引入大量非核心功能，以及 swift-crypto 3.15.1 → 4.5.2、KeyboardShortcuts 2.4.0 → 3.1.0 等依赖升级。上游 CI 已选择 Xcode 26.6，个人工作流仍优先 26.3/26.2，若全量同步应重新核对工具链；这里没有证明旧工具链一定失败。

静态查看打包逻辑后，临时签名分支仍支持官方更新关闭与 iCloud 不可用的个人选择。全量同步仍须保留个人 workflow、产物来源验证、应用标识和当前需求文档，并进行新的 fork 云端验证。上游测试记录或过去安装记录不能替代本次验证。

## 后续实施顺序与验收

1. 先做 Kimi 最小组：ratio 兼容与零占位、数值边界、耗尽月额度自动展示、认证恢复与 Manual/Off 边界。保留现有可选统计的失败降级，不引入会员名或新地区设置，国际站需求明确时再扩展地区范围。
2. 再做 Codex 最小组：401/403 区分、失败快照保留、包装网络错误与取消分类；同时修正本次发现的 403 文本误判。
3. 测试使用脱敏 JSON、注入 transport/token 和内存 settings。覆盖比例与计数优先级、缺失窗口、超大数字、显式来源不回退、取消后不再读取来源、连续断网、原测量时间保留、401/403 不被误保留、账号/凭据/配置/刷新代际改变不复用错误快照。
4. 按个人云端流程执行对应回归、`make check`、完整 `make test` 和打包，记录最终 source SHA 与 run。此处是下一阶段建议，本轮没有触发工作流。
5. 通过后再按安装任务验证真实 Kimi/OpenAI 用量和菜单行为。真实账户、浏览器 Cookie、钥匙串及应用重启均未在本轮执行。

审核结果支持小范围移植，但不支持立即安装或宣称原故障已修复。
