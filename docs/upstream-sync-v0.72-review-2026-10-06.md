# 上游 v0.72 同步审核

日期：2026-10-06。本轮将上游 `steipete/CodexBar` 同步进个人 fork，替代 2026-09-22 的选择性移植（见 [upstream-issue-3-review-2026-09-22](upstream-issue-3-review-2026-09-22.md)）。

## 范围与证据

- 本地基线：`fd6949841`（fork `main`，v0.56.4 + 个人补丁）。
- 合并基点：`538866089`（v0.56.4，2026-09-03）。
- 固定上游：`6a26b2e9b`（v0.72.0 后 51 个提交，2026-10-05）。
- 规模：858 个非合并提交，2,585 个文件（+233,782 / −64,888），Kimi 相关 20 个提交、Codex/OpenAI 相关 143 个。
- 需求依据为 [personal-requirements](../.agents/skills/personal-requirements/SKILL.md)：核心场景是菜单栏查看 OpenAI、Kimi 订阅用量，偏好轻量简单。
- 本轮只做静态分析与文本合并，未在本机构建或运行应用；编译与全量测试由云端 personal-macos.yml 执行。

## 接收方式：全量合并

上一轮的选择性移植可行，是因为只跨约 400 个提交且改动集中在解析层。本轮上游把余额抓取迁移到 bundled 插件（QuickJS/JavaScriptCore 双引擎，`Sources/CodexBarCore/Resources/Plugins/`），Kimi/Codex 的可靠性修复与这套新架构及共享 transport、多账号刷新体系深度交织，逐提交挑拣无法保持可编译与语义一致。与使用目的相关的修复无法脱离底层变化独立接收，因此接收范围为 upstream/main 全量，fork 本地行为按下文逐项保留。

## 与个人使用目的直接相关的上游更新

Kimi（上一轮移植的动机是 Kimi 订阅查询失效）：

- 双区域架构：kimi.com（中国区，默认）/ kimi.ai（国际区），API、web、cookie 发现、Dashboard、CLI 凭据全链路区域化（#3826）。
- 新版 Code API ratio quota pools 解析（`limit_5h`/`limit_7d`/`limit_month_total`），与旧计数协议混合对账（#3697、#3755），超大整数安全解码（#3758）。
- 月度 Total usage 成为一等窗口，耗尽时自动上浮菜单栏并显示"被月度限制阻断"（#3543、#4091）。
- membership 等级展示与被拒 web 会话恢复（#3414）；Chromium localStorage 会话导入（#3941）。
- Manual/Off cookie 源严格门禁（#3809）；CLI/Desktop 凭据只读、过期指引（#4086）。
- 带标签多 web 账号、账号间凭据隔离（#3876）。
- Moonshot 开放平台余额切到 bundled 插件，保留 CNY/USD 区域币种（#3877、#3438）。

Codex/OpenAI：

- 共享认证 transport，仅 401 视为凭据失效，403 为终态权限错误（#3466）。
- 包装 transport 错误解包后的保留/重试/hook 分类，并泛化到多供应商（#3667、#3672）。
- 网络中断时保留已验证用量（cacheKey 全匹配才复用缓存）（b76508292）。
- PAT whoami 身份解析、CLI 轮换凭据有界重读、套餐变更作废旧配额证据（#4088）。
- workspace 余额、spend-control/individual-limit 三级额度优先级、`additional_rate_limits` 模型级限额、周配额重置确认抓取（#4218 等）。
- 进程环境脱敏（#4097、#4106）、cookie 不持久化与凭据 staging 安全（#3996）、Keychain 验证有界化（#4089）。

## 本地补丁 superseded 分析

`f25ea718c`（Improve Kimi and Codex usage reliability）经逐项核对已被上游完全覆盖：

- Codex 部分本身就是 #3466/#3667/#3672/b76508292 的回溯移植；上游后续将 `underlyingCodexTransportError` 泛化为 `underlyingProviderTransportError`，语义包含本地补丁（含 403/503 body 文本不得冒充传输错误的陷阱场景）。
- Kimi 部分的七项行为（ratio pools、零占位对账、Int64 安全、空配额显式报错、耗尽月额度上浮、Desktop JWT 过期忽略、auto 门禁）逐一在上游源码中找到对应实现。
- 合并冲突全部采用上游版本；自动合并的测试文件引用的符号在上游均存在（同名移植）。

## 保留的 fork 行为

- Kimi cookie 导入保持 Chrome-only（避免触发其他浏览器密码提示），改用上游惯例 `BrowserCookieImportSupport.chromeOnly` 落地（`KimiProviderDescriptor.swift`）。
- 个人构建/安装工具链不变：`.github/workflows/personal-macos.yml`、`Scripts/prepare_personal_artifact.py`、`Scripts/verify_personal_resources.py`、`.agents/skills/`。
- 2026-09-13 删除的上游 fork 策略文档（docs/FORK_*.md、UPSTREAM_STRATEGY.md 等）保持删除。
- `Makefile` 的 `open -n "$(CURDIR)/CodexBar.app"` 与 `check-documentation-links.mjs` 的 skill 链接白名单自动合并保留。

## 对个人维护选择的影响

- 应用身份不变：adhoc 构建 `APP_TEAM_ID` 默认仍为 Y5PE65HELJ，`APP_GROUP_ID` 计算结果与之前一致；iCloud 同步仍仅限上游团队签名构建，个人构建不可用（与既有取舍一致）。
- 官方自动更新仍关闭，由 `prepare_personal_artifact.py` 在打包时核验。
- 上游 `lint.sh` 新增多项 portable 检查（package resolved、打包启动、release 资产等），`make check` 更重但自举，云端 runner 可执行。

## 验证

本地静态检查（2026-10-06）：

- `node Scripts/check-documentation-links.mjs`：314 个本地链接通过。
- `Scripts/regenerate-provider-manifests.sh --check`：91 个 provider 清单一致。
- `Scripts/regenerate-plugin-js.sh --check`：29 个插件 JS 一致。
- `node Scripts/regenerate-provider-docs.mjs --check`：91 个 provider 文档一致。

云端 personal-macos.yml（check + 双分片全量测试 + 打包核验）的运行记录见对应 PR。本轮不安装、不重启应用、不做公开发行。
