---
name: local-install
description: 用户要求在本机安装或更新 CodexBar 时，构建当前工作区、验证应用、备份安装并确认运行版本与回退方式。日常代码修改不触发安装。
---

# 本地安装

## 安装约定

读取 [personal-requirements](../personal-requirements/SKILL.md) 的已确认选择。安装目标为 `/Applications/CodexBar.app`，使用原有 `com.steipete.codexbar` 标识和 release 临时签名。脚本会清空 Sparkle feed 并关闭自动检查；iCloud 同步不可用，临时签名不提供原作者的签名身份。权限是否需要重新确认及 widget 是否可用，安装后按实际结果报告。保留现有登录项状态，不自动开启。

默认安装包含用户所选本地修改的确定版本；远端构建前须将这些修改提交并推送。仅在用户要求拉取或同步时更新代码。初始化最终安装必须取得针对具体构建的授权；日常明确安装请求可授权对应安装，不重复索要同一授权。

## 远端构建与下载

默认使用 `.github/workflows/personal-macos.yml`，手动触发，macOS arm64 runner。检查和两路完整测试均成功后才打包，产物保留 7 天，失败上传日志。工作流不发布 Release、不推送代码、不使用个人账户凭据。

1. 明确本次源版本。Actions 只构建已提交并推送的版本，未提交修改不会自动上传；将需要的本地修改纳入版本后，按用户授权提交和推送。工作流首次使用须先进入 fork 的默认分支 `main`。仅准备流程不代表已经推送或远端验证成功。
2. 所有 `gh` 命令显式指定 `--repo allgemeiner-intellekt/CodexBar`，本机 `gh` 的默认仓库可能是上游。用 `gh workflow run personal-macos.yml --repo allgemeiner-intellekt/CodexBar --ref BRANCH` 触发所选分支。查询运行列表，匹配工作流、分支及预期 head SHA，记录 run ID；不要直接采用“最近一次”运行。
3. 等待该 run 成功。下载 `CodexBar-personal-arm64-SHA` 产物到全新目录，例如 `gh run download RUN_ID --repo allgemeiner-intellekt/CodexBar --name CodexBar-personal-arm64-SHA --dir DESTINATION`。占位符替换为已核对值。失败时读取对应日志，不跳过测试或取失败运行的包安装。
4. 在下载目录运行 `shasum -a 256 -c SHA256SUMS`。检查 `build.json` 的完整 commit、run URL、attempt 与所选成功运行一致。用 `ditto -x -k CodexBar-personal-arm64.zip STAGING` 解压，再验证 `codesign --verify --deep --strict STAGING/CodexBar.app`。
5. 核对解压后主程序 SHA-256 与 manifest 一致，Info.plist 的版本、提交、构建时间及应用身份一致，官方更新源为空且自动检查关闭。保留下载来源和校验结果，按后面的安装步骤操作。下载包可能带有隔离属性；遇到 Gatekeeper 提示如实报告并由用户处理，不自动删除隔离属性。

## 本机备用构建

仅用户明确要求本机完整构建时使用旧路径，构建、测试顺序执行。可使用 `CODEXBAR_SIGNING=adhoc CODEXBAR_SKIP_LAUNCH_SMOKE=1 ./Scripts/package_app.sh release`，随后运行 `python3 Scripts/verify_personal_resources.py`。该脚本仅做隔离资源加载，不启动正常 UI。现有打包脚本尚未接入统一并发限制，不能声称设置了 `--jobs 2` 即限制了整个打包过程。普通增量构建使用 `swift build --jobs 2`；全量测试默认留在远端。

## 安装与版本确认

1. 安装前汇报提交号、未提交差异、构建与检查结果、目标处旧版本、身份与更新行为，以及尚未验证的运行事项。初始化在此请求最终授权。
2. 在用户目录下建立带时间戳的私有备份目录，权限 `700`。若旧应用存在，用 `ditto` 备份整个 bundle。备份存在的 `~/.codexbar`、`~/Library/Application Support/CodexBar`，并通过 `defaults export com.steipete.codexbar` 保存偏好，不输出配置内容。记录原先不存在的路径。检查当前及旧版 app-group 的 CodexBar 数据是否存在，存在时一并备份，不扫描其他应用容器或读取钥匙串。
3. 仅停止已确认的 CodexBar 主进程。将新 bundle 用 `ditto` 复制到目标同目录的临时位置，验证签名及主程序哈希，再替换目标。保留备份，失败时恢复旧 bundle。
4. 用 `open -n /Applications/CodexBar.app` 启动。确认进程持续存活，并用进程路径或 `lsof -a -p PID -d txt` 核实运行的是安装目标。比较安装包与构建包的版本、提交、时间戳和主程序哈希。UI 核查前先截图确认菜单栏图标可见。
5. 不把进程存活写成供应商功能已验证。真实用量查询、cookie 导入和钥匙串读取需用户明确要求；如遇权限弹窗，交由用户处理。报告是否已安装、运行版本、备份路径及剩余验证项。

## 回退

停止本次安装的主进程，将当前 bundle 移入备份目录，再用 `ditto` 恢复上次应用，验证并启动。设置只在确有迁移问题且用户要求时恢复，先保留安装后数据，再用 `defaults import` 和对应文件备份恢复；不覆盖此后新增数据而不说明。首次安装无旧应用时，回退是移出新 bundle 并保留用户数据。任何登录项变化都需记录并恢复到原状态。

## 本次验证记录

2026-09-09，基于 `6790f76d7`，初始工作区干净。未提交差异仅为 AGENTS.md、Makefile 路径修正及这两个仓库 Skill；未修改产品代码。常见安装目录未发现旧版，未发现运行实例。

- arm64 release 打包成功，含 widget；版本 `0.56.3 (134)`，包内构建时间 `2026-09-09T10:12:43Z`。
- 打包脚本的深度严格签名校验通过；应用、CLI、CLI 符号链接在禁止读取仓库时均通过资源 smoke。
- `make check` 通过，SwiftLint 对 2,094 个文件报告零违规；两个 Skill 通过 `quick_validate.py`。系统 Python 缺少 PyYAML，本次使用已有 `/opt/anaconda3/bin/python` 运行该校验，没有安装新依赖。
- Release 编译有现有代码警告，包括弃用 API、URLSession 委托方法签名、未变更变量和类型转换建议，未在初始化中修改。
- 全量 `make test` 未通过：998 个测试选择项分 84 组，前 76 组通过，第 77 组在 180 秒后超时。自动拆分重试时，`UsageStoreCachedTokenHydrationTests` 再次在 180 秒后超时，测试脚本返回 124，make 返回 2；剩余 7 组未执行。根因尚未诊断，不能视为断言失败或证明应用运行异常。需与用户确定修复范围后继续验证。
- 状态为配置与构建完成、测试存在阻塞、尚未安装。未启动正常应用流程；菜单栏、登录项、实际权限及供应商行为仍待安装后按授权范围验证。
- 本次构建信息和日志位于 `.build/personal-setup/`；该目录为本机临时产物，不提交。

2026-09-09 远端方案准备：用户选择 GitHub Actions macOS runner。fork 为公开仓库，Actions 已启用。新增手动工作流及产物验证工具。YAML、任务依赖、分片与嵌入 shell 语法校验通过；产物元数据检查接受现有包并拒绝身份、更新源或提交不匹配；三个隔离资源探测与两个 Skill 结构校验通过。未重新运行本机完整构建或测试。尚未推送或运行该工作流，远端可用性待首次执行确认。之前的超时测试仍为已知阻塞，未修复或跳过。
