# Kimi 真实账号用量与认证验证

2026-09-24，经用户明确授权读取与 Kimi 用量查询有关的登录凭据和调用用量接口。不读取聊天内容，不输出或保存凭据。没有修改应用代码、设置或安装。

此记录描述当日观察，不代表当前服务或登录状态。2026-09-28 整理时删减了个人套餐、实际用量、续费日期和精确操作时间，保留字段语义与认证验证结果。历史授权不代表后续凭据访问或认证改造已获授权。

## 用量与套餐

| 查询 | HTTP | 实际结果 |
| --- | --- | --- |
| 配置中的 Code API key → `/coding/v1/usages` | 200 | 有 5 小时和 7 天窗口，无 `limit_month_total` |
| Brave 当时的网页登录态 → `GetSubscriptionStats` | 200 | 共享月总量、Code 月分项、Code 5 小时及 7 天窗口齐全 |
| 同一网页登录态 → `GetUsages`，仅 `FEATURE_CODING` | 200 | Code 计数与 API key 查询一致，重置时间一致 |
| 同一网页登录态 → `GetSubscription` | 200 | 返回套餐名称、有效付费订阅状态和下一次续费时间 |
| Brave 独立订阅页面 `/m/membership/subscription` | 已显示 | 月总量、两个 Code 短窗口和续费日期与接口结果相符 |

`GetSubscriptionStats` 的关键字段及语义：

- `subscriptionBalance.feature = FEATURE_OMNI`
- `subscriptionBalance.type = SUBSCRIPTION`
- `amountUsedRatio` 为共享月池已用比例
- `kimiCodeUsedRatio` 为 Code 月分项比例
- `expireTime` 为额度到期时间
- `ratelimitCode5h.ratio`、`ratelimitCode7d.ratio` 分别为 Code 两个独立短窗口的已用比例

调查时的[官网前端脚本](https://statics.moonshot.cn/kimi-web-seo/assets/index-Dpa7_0A5.js)中，`formatCreditUsage` 以月总量减去 Code 月分项计算 Kimi 月分项。两个分项之和为月总量，不能把 5 小时或 7 天比例加到月总量上。该带哈希的脚本链接可能随官网部署失效。

Code API ratio 的精度高于旧整数计数，按官网精度显示后与网页一致。旧整数计数计算的比例与有效 ratio 有差异，不能用整数计数替代有效比例。

`GetSubscription` 返回 `goods.title`、`status = SUBSCRIPTION_STATUS_ACTIVE`、`type = TYPE_PURCHASE` 和 `nextBillingTime`。本次观察中，续费时间与余额的 `expireTime` 不同，虽然北京时间落在同一天。必须保留字段区别。

## 登录来源

- 当时 CodexBar 配置为 API key 数据源、Automatic Cookie 来源；该安装的自动浏览器读取仅包括 Chrome。
- Brave Default 的 Kimi Local Storage 有有效 access token，JWT 的 `exp - iat = 900` 秒。
- Chrome Default 与 Kimi Desktop 的 Local Storage 中 access token 已过期。通过 JWT `sub` 在内存中比较，它们与 Brave 指向相同账号；未输出账号标识。
- Kimi Desktop 的 Cookies 表没有 `kimi-auth`。Chrome 存在加密 `kimi-auth` Cookie，其 Cookie 到期日尚未到；本次没有解密，所以不能将其 Cookie 到期日当作内部 JWT 仍有效的证据，也不能断言它的服务端状态。
- 当时应用不会读取 Brave 的有效 Local Storage 登录态。这是已确认的来源覆盖缺口；此次没有改动应用设置或声称已经修复。
- API key 响应未提供可直接对照的账号 ID；上述 API/web 用量一致不能替代完整的 API key 账号身份校验。全部会员统计来自同一个有效 web token，无需拼接不同会话。

读取时，仅对 Kimi 的 origin 和认证键提取值。临时验证读取器使用 CURRENT/MANIFEST 指定的活动 LevelDB 文件，比较记录 sequence 和删除标记，并检查读取前后文件是否变化；没有使用字符串扫描出的任意 JWT。它只是本次验证工具，不是已经完成生产验收的存储实现。

## 认证持续性

已完成一次真实过期与恢复验证，以基准 token 的 JWT 过期时刻为参照：

| 阶段 | 操作和观察 | 结论 |
| --- | --- | --- |
| 过期前 | 基准 token 查询会员统计和 Code 用量均返回 200 | 初始凭据有效 |
| 过期前约 55 秒 | 再读 Brave 存储，仍是基准 token | 未提前轮换 |
| 过期后约 16 秒起 | 使用内存保留的旧 token 查询两个用量接口，均返回 401 | 服务端实际拒绝过期凭据 |
| 过期后约 28 秒 | 再读 Brave 存储，仍是旧 token | 这段空闲时间内没有自行更新 |
| 过期后约 53 秒 | 正常打开不含聊天侧栏的独立订阅页面；无需用户重新登录，页面取得更新后的月总量 | 官网能够恢复认证 |
| 页面恢复后 | 再读 Brave 存储，access token 和 refresh token 都已变更；新 access token 有效期仍为 900 秒 | 官方客户端更新了两种凭据 |
| 重新导入后 | 使用新 token 独立调用会员统计和 Code 用量，均返回 200 | 新凭据可供独立用量查询使用 |

恢复后的月总量与 Kimi 月分项增加，Code 月分项和两个短窗口比例不变；官网和直接接口一致。这体现了月总池变化不一定伴随 Code 短窗口变化；没有读取或推断具体聊天、任务或消费来源。

两次临时订阅标签页均已关闭。用户原有浏览器标签页和应用保持原状。该观察只证明“官方网页恢复认证 → 重新导入新凭据 → 独立查询成功”，没有证明 CodexBar 自身能后台续期，也没有验证完全退出浏览器后的持续性。空闲观察持续到过期后约 28 秒，不能据此断言官网永远不会再后台更新。900 秒是此次观察值，不是官方长期合同。

调查时的[官网认证脚本](https://statics.moonshot.cn/kimi-web-seo/assets/token-I1aJzqBo.js)遇到认证失效会调用刷新流程，随后将返回的 access token 和 refresh token 同时写回 Local Storage。本次不主动调用该刷新接口，也不改写浏览器存储；通过正常订阅页面行为观察官方客户端自己的更新。该脚本链接可能随部署失效。

## 验证结论与尚未确定的方案

1. 当日真实账号的数据满足订阅优先界面的需要。会员统计接口本身提供共享月总量、Kimi/Code 拆分所需数据和两个 Code 短窗口，不必依赖 Code API 补齐这张卡片。
2. 本账号当日 Code API 响应没有月总量，不能只改展示或解析就补出它。有效网页登录来源是 Brave，而当时应用只有 Chrome Cookie 自动导入，且没有 Local Storage 认证路径。
3. 只增加 Local Storage 读取仍不足以保证持续自动更新。旧 token 在本次 15 分钟有效期结束后实际失效；浏览器重新发起官网查询后更新凭据，重新导入才恢复。
4. 已有证据支持探索独立网页登录会话，或者明确依赖浏览器官方会话更新的方案。前者的会话持久化、刷新与退出登录行为尚未验证；后者不能承诺浏览器关闭时也持续工作。
5. 没有测试借用浏览器 refresh token 自行刷新。实际观察已确认 refresh token 也会变化，跨客户端轮换和会话归属不能忽略。此次用户授权范围是读取相关凭据和用量查询，故没有为了证明后台刷新而自行轮换浏览器凭据。

用户要求先报告验证结果，再确定实现方案；因此本轮未选择或实施认证改造。候选路径见[替代数据源调查](kimi-data-source-alternatives-2026-09-24.md)。
