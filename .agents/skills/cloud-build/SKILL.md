---
name: cloud-build
description: CodexBar 需要编译、测试、检查、打包或获取构建产物时，使用 GitHub 云端流程并核对源码与产物来源。
---

# 云端构建与产物

## 执行偏好

尽可能把编译、测试、检查和打包放在 GitHub 云端执行，避免占用本机设备。代码编辑、提交和推送沿用普通开发流程。文档及工作流准备只需静态验证，不因此启动完整构建。

fork 是 `allgemeiner-intellekt/CodexBar`，上游是 `steipete/CodexBar`。自用工作流、产物和运行查询均针对 fork。

## 构建与下载

默认使用 `.github/workflows/personal-macos.yml`，手动触发，macOS arm64 runner。检查和两路完整测试均成功后才打包，产物保留 7 天，失败上传日志。工作流不发布 Release、不推送代码、不使用个人账户凭据。

1. 明确本次源版本。Actions 只构建已提交并推送的版本，未提交修改不会自动上传；将需要的本地修改纳入版本后，按用户授权提交和推送。工作流首次使用须先进入 fork 的默认分支 `main`。仅准备流程不代表已经推送或远端验证成功。
2. 所有 `gh` 命令显式指定 `--repo allgemeiner-intellekt/CodexBar`，本机 `gh` 的默认仓库可能是上游。用 `gh workflow run personal-macos.yml --repo allgemeiner-intellekt/CodexBar --ref BRANCH` 触发所选分支。用 `gh run list --repo allgemeiner-intellekt/CodexBar --workflow personal-macos.yml --branch BRANCH --json databaseId,headSha,status,conclusion,url` 查询运行，匹配分支及预期完整 head SHA，记录 run ID；不要直接采用“最近一次”运行。
3. 用 `gh run view RUN_ID --repo allgemeiner-intellekt/CodexBar` 查看所选运行结果，等待其成功。下载 `CodexBar-personal-arm64-SHA` 产物到全新目录，例如 `gh run download RUN_ID --repo allgemeiner-intellekt/CodexBar --name CodexBar-personal-arm64-SHA --dir DESTINATION`。占位符替换为已核对值。失败时读取对应日志，不跳过测试或取失败运行的包安装。
4. 在下载目录运行 `shasum -a 256 -c SHA256SUMS`。检查 `build.json` 的完整 commit、run URL、attempt 与所选成功运行一致。用 `ditto -x -k CodexBar-personal-arm64.zip STAGING` 解压，再验证 `codesign --verify --deep --strict STAGING/CodexBar.app`。
5. 核对解压后主程序 SHA-256 与 manifest 一致，Info.plist 的版本、提交、构建时间及应用身份一致，官方更新源为空且自动检查关闭。保留下载来源和校验结果。下载包可能带有隔离属性；遇到 Gatekeeper 提示如实报告并由用户处理，不自动删除隔离属性。

## 入口与产物限制

- 工作流入口：[Personal macOS build](https://github.com/allgemeiner-intellekt/CodexBar/actions/workflows/personal-macos.yml)。本仓库的 [personal-macos.yml](../../../.github/workflows/personal-macos.yml) 维护检查、测试、打包命令及参数，当前一次运行包括全部任务。
- [prepare_personal_artifact.py](../../../Scripts/prepare_personal_artifact.py) 生成 zip、`SHA256SUMS` 和 `build.json`，检查源码、应用身份、更新设置、架构和签名。[verify_personal_resources.py](../../../Scripts/verify_personal_resources.py) 执行隔离资源验证。
- 分发入口为所选成功运行页面的 Artifacts，面向用户 Apple Silicon Mac，产物为 arm64 release 临时签名应用。产物到期后需重新构建；本流程不创建公开 Release。
- 沿用 `com.steipete.codexbar` 与设置位置，关闭官方自动更新，iCloud 同步不可用。临时签名不提供原作者的签名身份；权限和 widget 可用性按运行验证结果报告。
- 获得产物不代表已安装。本地安装或更新按用户的具体任务处理，完成开发不自动安装或重启。

## 验证状态

2026-09-22 的 [run 35708094643](https://github.com/allgemeiner-intellekt/CodexBar/actions/runs/35708094643)，attempt 1，对应源码 `8d661b1431cf9ef3dd0de14342719efbec143427`，检查、两路全量测试、打包和产物核验成功。用户授权安装后确认原问题已解决。版本仍为 `0.56.4 (135)`，应以源码 SHA 区分构建。

产物 hash、安装核验和使用边界见 [本轮实施与安装记录](../../../docs/upstream-issue-3-review-2026-09-22.md#实施与安装结果)。记录表示该次验证结果，不保证历史产物仍可下载，也不替代未来构建的验证。
