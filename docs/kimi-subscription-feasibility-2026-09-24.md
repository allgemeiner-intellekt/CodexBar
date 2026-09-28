# Kimi 订阅体验可行性调查

调查日期：2026-09-24。范围为公开资料和源码探索，没有请求真实账号接口、读取本机浏览器凭据、构建或修改应用代码。

后续经用户授权完成了[真实账号及一次认证过期恢复验证](kimi-live-validation-2026-09-24.md)。该记录补充了本笔记最初尚未确认的字段语义、实际浏览器来源和认证持续性边界。

本文保留调查当日的判断与未知项，后续实测见上方链接。2026-09-28 整理时仓库基准为 `d50dc861f1c613c26439ce37350813cc025147b7`；原调查未记录源码 SHA，不能将此基准视为当时已核验版本。本文中的“当前”和上游状态均指调查当日，未在整理时重新验证。

## 判断

用户希望将提供商呈现为 Kimi，先展示整个订阅的月额度，再展示 Code 的 5 小时和 7 天限额。这个信息结构与官网当前共享额度模型一致，代码也已有部分数据结构和展示基础。名称、排序、总量和分段进度条可实现。真正需要验证的是持续取得正确网页登录会话，以及分项额度和续费字段的具体语义。

不能把一次成功读取 Local Storage token 等同于长期自动刷新。现有上游修复没有完成这一点。

## 用户截图作为验收参照

用户提供的官网截图包含套餐名称、共享月总量、Kimi 和 Code 两段进度，以及月额度重置日、下一次自动续费日和 Code 两个短窗口。2026-09-28 整理时省略了个人套餐、实际百分比和日期。截图未提供两个分段各自的精确百分比，不能按像素推算。

## 官方产品语义

[官方会员额度规则](https://www.kimi.com/help/membership/membership-update-rules)说明，Kimi 会员功能共享额度池，Code 另有只作用于 Code 的 5 小时和周限额。月度和年度会员均按订阅周期刷新月额度，不能按自然月推算重置时间。[官方会员说明](https://www.kimi.com/en/help/membership/membership-overview)说明网页和 App 均能查询额度百分比、下一次刷新时间与使用明细。

因此，截图中的三个百分比不能相加。月总量是整个会员池已用比例，5 小时和 7 天数值是两个独立 Code 限额的已用比例。月度 Code 分项也不能由 5 小时或 7 天数值推导。

产品规则还在变化。[官方国际站 Code 权益说明](https://www.kimi.ai/help/kimi-code/benefits)预告未来拆分 Kimi 与 Code 购买，并称现有订阅不受影响。实现应针对当前账号实际返回的数据，不能将所有未来套餐写死为同一个共享池。当前用户截图仍是此次需求的直接参照。

## 上游结论

- [Issue #3536](https://github.com/steipete/CodexBar/issues/3536)记录 Desktop 登录状态迁入 Local Storage 后，月额度缺失的问题。它也指出月额度耗尽而 Code 短窗口重置时，原有自动选择会误导用户。
- [PR #3543](https://github.com/steipete/CodexBar/pull/3543)已合并，只修复已取得月额度时的耗尽优先显示。其说明明确将认证问题留在未关闭的 issue 中。
- [PR #3414](https://github.com/steipete/CodexBar/pull/3414)已合并，处理套餐信息、超时隔离、被拒绝的 Desktop Cookie 向浏览器 Cookie 回退。维护者明确没有成功真实浏览器恢复的验证记录，因此它不能证明 Local Storage 或长期刷新已解决。
- [维护者 9 月 21 日更新](https://github.com/steipete/CodexBar/issues/3536#issuecomment-5759421146)明确指出，固定版本的 Local Storage 读取器尚不能依据 LevelDB sequence 顺序确定当前有效记录。某些 Code API 响应已经可提供月额度，但 Desktop Local Storage 凭据获取仍未解决。

## 当前代码与需要的工作

| 需求 | 当前基础 | 需要补充 |
| --- | --- | --- |
| Kimi 名称与订阅优先 | `Sources/CodexBarCore/Providers/Kimi/KimiProviderDescriptor.swift` | 改用户可见名称、说明和排序，保留内部 provider ID 与已有配置兼容 |
| 月总量 | `KimiModels.swift` 解码 `limit_month_total`、`subscriptionBalance.amountUsedRatio`；`KimiUsageSnapshot.swift` 已使用共享池总量 | 获取失败时明确显示不可用；不能把缺失当作 0%；允许只有订阅额度而没有 Code 用量 |
| Kimi / Code 分段 | `KimiModels.swift` 已解码 `kimiCodeUsedRatio`，snapshot 未保留分项 | 验证分项分母和同一周期，然后传到 UI；只有确认同一共享池后才能用总量减 Code 得到 Kimi 分项 |
| 月重置日期 | `subscriptionBalance.expireTime` 已存在 | 保留接口实际日期，避免固定 30 天或下月 1 日 |
| 套餐和自动续费 | `Sources/CodexBar/MenuCardView.swift` 已有套餐呈现；通用模型已有续费字段 | 对接真实订阅元数据；不能将额度到期日冒充自动扣款日期，也不能从未知套餐等级猜名称 |
| 分段进度条 | `MenuCardView.swift` 的普通额度条目前为单色 | 扩展数据和条形渲染，保留系统深浅色及其他 provider 行为 |
| 持续获取网页登录态 | `KimiCookieImporter.swift`、`KimiDesktopAuthToken.swift`、`KimiUsageFetcher.swift` | 解决 Local Storage 当前记录识别、过期检查、账号一致性及刷新生命周期 |

上述相对路径除注明外位于 `Sources/CodexBarCore/Providers/Kimi/`。背景实现说明见 [现有 Kimi 文档](kimi.md)。当前 web fetch 把 Code 数据作为必需结果、会员信息作为补充，这与订阅优先目标不完全一致。需要让月总量独立成功，不能因为 Code 不可用而丢掉已取得的会员额度。

## 登录与持续刷新的边界

仓库已有 Windsurf 的 Chromium Local Storage 导入可参考，不能据此断言直接复用就安全可用。上游已经发现当前记录与历史记录的选择问题，读取器必须正确处理记录顺序和删除状态，不能扫描出一个未过期 JWT 就认为它是当前会话。

读取现有 access token 属于会话复用；token 更新由浏览器或 Desktop 完成时，CodexBar 才能重新导入新值。浏览器关闭后是否还能无人值守更新，本次没有证据。自行管理 refresh token 或增加独立登录流程属于进一步方案，需要验证凭据归属、刷新轮换、退出登录及账户切换行为。不能直接刷新别的客户端持有的 refresh token。

历史 issue 中的约 15 分钟有效期是当时观察，不是本次验证的固定官方合同。公开会员文档没有承诺网页私有 RPC、Local Storage 键或 token 刷新协议的长期稳定性。本次没有做完整网页脚本逆向，也没有真实账号响应，不能宣称已经确定所有字段及认证生命周期。

## 建议的后续验收

先确认同一账号下的官网、Code API 与会员接口数据，验证总量、Code 分项、套餐、额度到期与自动续费日期。再对已选会话来源跨越 token 过期边界，检查浏览器打开及关闭时的表现。认证失效时应保留带时间的旧值或显示月额度不可用，并给出重新登录入口；不应静默只剩短窗口。

待确认的实现候选包括 Kimi 名称、订阅总量优先、准确缺失状态和分段 UI；持续认证验证应作为宣布问题解决的必要条件。不要用一次性 token 粘贴成功关闭问题。实现阶段再使用合成响应和隔离测试覆盖无 Code 数据、月额度缺失、分项不一致、账号切换、过期 token、套餐未知及日期分离等情况。
