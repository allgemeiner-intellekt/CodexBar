# Kimi 完整订阅数据的替代获取方式

2026-09-24，补充公开文档、官方源码和其他工具实现的调查。本轮未读取真实凭据、未启动本地 Kimi 服务、未调用刷新接口。之前的账号实测见 [验证报告](kimi-live-validation-2026-09-24.md)。

本文为历史调查，候选方案尚未选定。源码链接中的 `main` 指向可变内容，原调查未记录对应 SHA，故未追补为未经核验的固定提交。实现前需重新核对目标版本与接口行为。

## 官方 CLI 本地用量服务

[官方 Server API 文档](https://www.kimi.com/code/docs/en/kimi-code-cli/reference/server-api.html)提供 `GET /api/v1/oauth/usage`，由 `kimi web` 启动的本地服务接收请求，返回包括 `limit5h`、`limit7d`、`monthTotal`、`monthCode` 在内的用量结构。请求需要本地服务认证；此 API 官方标记为实验性，不保证接口稳定。

[官方 managed-usage 实现](https://github.com/MoonshotAI/kimi-code/blob/main/packages/oauth/src/managed-usage.ts)实际仍请求 `https://api.kimi.com/coding/v1/usages`，使用托管 OAuth 登录态，解析可选的 `limit_month_total` 与 `limit_month_code`。没有发现用来开启月额度的特殊请求头或查询参数。

这是一条值得先验证的路径：让官方 CLI 管理自己的认证与续期，CodexBar 只读取官方本地服务的用量结果。但本地服务不会凭空补齐云端缺失的月额度；之前实测的是 API key，此处 OAuth 登录态下同一账号是否得到完整月分项仍未知。文档有字段不等于所有账号都返回字段。需要运行本地服务，安装版本兼容性也需核对。

## 在应用内使用官方订阅网页会话

候选方案是让 CodexBar 使用独立持久化 WebView 加载官方订阅页，由官网自己的代码处理续期，获取用量结果。用户初次登录后，由应用按刷新周期加载页面；不需要要求用户反复手动访问 Brave，也不需要自行实现网页 refresh token 的轮换协议。

先前实测已经证明普通浏览器重新加载独立订阅页能恢复认证，但没有证明同样流程在 WKWebView、后台运行、应用重启和休眠恢复后都成立。官网兼容性、内存开销与网页变化仍需验证；不能称为已经验证稳定的方案。

仓库已有可参考的基础：`Sources/CodexBarCore/OpenAIWeb/OpenAIDashboardWebsiteDataStore.swift` 使用按账号隔离的持久化网站数据，`OpenAIDashboardWebViewCache.swift` 管理后台 WebView。这说明该模式可以融入现有应用，不代表这些供应商专用实现能直接套用于 Kimi。获取时应限于订阅用量页面和结构化用量响应，避免聊天路径。

另一种是浏览器扩展或受控标签页执行官方查询，其代价是依赖外部浏览器运行。它能主动触发官网更新，区别于被动读取磁盘 token，但不能满足完全退出浏览器后的独立运行。

## 其他工具没有自动证明问题已解决

[Token Monitor #221](https://github.com/Javis603/token-monitor/pull/221)实现了月共享池与 Kimi/Code 分项，但使用手动 web token/Cookie。[当前 Kimi provider](https://github.com/Javis603/token-monitor/blob/main/src/shared/providers/kimi/limits.js)接收 webAccessToken，认证失败返回 unauthorized，没有在该路径实现网页 token 自动刷新。其月度 UI 已完成，不代表持续认证已完成。

[onWatch 的 Kimi 文档](https://github.com/onllm-dev/onWatch/blob/main/docs/KIMI_SETUP.md)描述 Code OAuth 续期，但明确不追踪会员网页的总用量。换成另一个工具也不能据此保证满足完整订阅需求。

本地 Code 日志不能覆盖 App、网页等其他设备的会员池消耗，也不能可靠反推出官方共享额度；Moonshot Open Platform 余额与会员订阅不是同一项数据，不适合作为替代。

## 当前建议

先核实官方 CLI/OAuth 路径在这个账号上是否返回真实月总量和分项；如果仍缺失，则验证由官方网页自主管理认证的独立 WebView。两条路径都比被动复制短期 token 更值得验证，但目前没有足够证据承诺其中任一条已能长期稳定覆盖该账号的完整订阅数据。
