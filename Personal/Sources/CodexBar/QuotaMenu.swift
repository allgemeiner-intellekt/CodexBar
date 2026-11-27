import AppKit
import CodexBarCore
import SwiftUI

struct QuotaMenu: View {
    let store: QuotaStore
    @AppStorage(QuotaDisplayPreference.key) private var showUsed = QuotaDisplayPreference.personalDefault

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(QuotaMenuDescriptor(
                        windows: self.store.windows, errors: self.store.errors, showUsed: self.showUsed).cards)
                    { card in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(card.provider.title).font(.headline)
                            ForEach(Array(card.rows.enumerated()), id: \.offset) { _, row in
                                self.row(row)
                            }
                            if let message = card.message {
                                Text(message).foregroundStyle(.secondary).font(.callout)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(idealHeight: 360, maxHeight: 500)
            Divider()
            Toggle("显示已用额度", isOn: self.$showUsed)
            HStack {
                Button("刷新") { Task { await self.store.refreshAll() } }
                SettingsLink { Text("设置…") }
                    .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
    }

    private func row(_ row: QuotaMenuRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(row.title).font(.callout)
                Spacer()
                Text(row.label).monospacedDigit()
            }
            ProgressView(value: row.fill, total: 100)
                .accessibilityLabel(row.title)
                .accessibilityValue(row.label)
            if let reset = row.resetsAt {
                Text("重置时间 \(reset.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct QuotaSettings: View {
    let store: QuotaStore
    @State private var key = ""
    @State private var region = KimiRegion.china

    var body: some View {
        Form {
            ForEach(QuotaSubscription.allCases) { provider in
                Section(provider.title) {
                    switch provider {
                    case .codex:
                        Button("使用 ChatGPT 登录") { self.store.connectCodex() }
                            .disabled(self.store.busy.contains(.codex))
                        if let code = self.store.deviceCode {
                            Text("在 OpenAI 页面输入此代码：\(code)").textSelection(.enabled)
                            Button("取消登录") { self.store.codexLogin?.cancel() }
                        }
                    case .kimi:
                        Picker("Kimi Code 地区", selection: self.$region) {
                            ForEach(KimiRegion.allCases, id: \.self) { region in
                                Text(region.displayName).tag(region)
                            }
                        }
                        SecureField("Kimi Code 订阅 API Key", text: self.$key)
                        Button("保存并查询") { self.saveKimi() }
                            .disabled(self.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || self.store.busy.contains(.kimi))
                    case .antigravity:
                        Text("登录时读取 Antigravity 应用的 OAuth 客户端配置。之后使用 CodexBar 自己保存的 Google 授权。")
                            .font(.caption)
                        Button("使用 Google 登录") { Task { await self.store.connectGoogle() } }
                            .disabled(self.store.busy.contains(.antigravity))
                    }
                    if let error = self.store.errors[provider] {
                        Text(error).foregroundStyle(.secondary)
                    }
                    if self.store.windows[provider] != nil || self.store.errors[provider] != nil {
                        Button("断开连接") { self.store.disconnect(provider) }
                            .disabled(self.store.busy.contains(provider))
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 540)
    }

    private func saveKimi() {
        guard !self.store.busy.contains(.kimi) else { return }
        do {
            let key = self.key.trimmingCharacters(in: .whitespacesAndNewlines)
            try self.store.files.saveKimi(KimiGrant(key: key, region: self.region))
            self.key = ""
            self.store.windows[.kimi] = nil
            Task { await self.store.refresh(.kimi) }
        } catch {
            self.store.errors[.kimi] = error.localizedDescription
        }
    }
}
