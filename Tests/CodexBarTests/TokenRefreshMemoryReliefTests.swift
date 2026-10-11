import CodexBarCore
import Foundation
import Testing
@testable import CodexBar

@MainActor
struct TokenRefreshMemoryReliefTests {
    @Test
    func `an empty refresh sequence does not schedule memory relief`() async {
        let store = Self.makeStore(providers: [])
        defer { Self.cancelRelief(store) }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(store.memoryPressureReliefTask == nil)
    }

    @Test
    func `disabled cost usage still clears cached state without scheduling relief`() async {
        let store = Self.makeStore()
        defer { Self.cancelRelief(store) }
        store.settings.costUsageEnabled = false
        store._setTokenSnapshotForTesting(Self.snapshot(), provider: .codex)
        store.tokenErrors[.codex] = "Previous failure"
        store.lastTokenFetchAt[.codex] = Date()
        store.lastTokenFetchScope[.codex] = "previous-scope"
        var loads = 0
        store._test_tokenUsageRefreshOverride = { _, _ in loads += 1 }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(loads == 0)
        #expect(store.tokenSnapshotPublications[.codex] == nil)
        #expect(store.tokenErrors[.codex] == nil)
        #expect(store.lastTokenFetchAt[.codex] == nil)
        #expect(store.lastTokenFetchScope[.codex] == nil)
        #expect(store.memoryPressureReliefTask == nil)
    }

    @Test
    func `reusing a fresh cost snapshot does not schedule memory relief`() async {
        let store = Self.makeStore()
        defer { Self.cancelRelief(store) }
        store._setTokenSnapshotForTesting(Self.snapshot(), provider: .codex)
        store.lastTokenFetchAt[.codex] = Date()
        store.lastTokenFetchScope[.codex] = store.tokenSnapshotScopeSignature(for: .codex)
        var loads = 0
        store._test_tokenUsageRefreshOverride = { _, _ in loads += 1 }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(loads == 0)
        #expect(store.tokenSnapshotPublications[.codex] != nil)
        #expect(store.memoryPressureReliefTask == nil)
    }

    @Test
    func `a cost load schedules memory relief after the sequence`() async {
        let store = Self.makeStore()
        defer { Self.cancelRelief(store) }
        var loads = 0
        store._test_tokenUsageRefreshOverride = { _, _ in loads += 1 }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(loads == 1)
        #expect(store.memoryPressureReliefTask != nil)
    }

    @Test(arguments: [false, true])
    func `failed and cancelled cost loads still schedule memory relief`(cancelled: Bool) async {
        let store = Self.makeStore()
        defer { Self.cancelRelief(store) }
        store._test_tokenUsageRefreshOverride = nil
        var loads = 0
        store._test_tokenUsageSnapshotLoaderOverride = { _, _, _, _, _ in
            loads += 1
            if cancelled { throw CancellationError() }
            throw URLError(.badServerResponse)
        }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(loads == 1)
        #expect(store.memoryPressureReliefTask != nil)
    }

    @Test
    func `cancelling a running sequence retains relief for its attempted load`() async {
        let store = Self.makeStore()
        defer { Self.cancelRelief(store) }
        var loads = 0
        store._test_tokenUsageRefreshOverride = { _, _ in
            loads += 1
            withUnsafeCurrentTask { $0?.cancel() }
        }

        await store.refreshTokenUsageSequenceNow(force: false)

        #expect(loads == 1)
        #expect(store.memoryPressureReliefTask != nil)
    }

    private static func makeStore(providers: Set<UsageProvider> = [.codex]) -> UsageStore {
        let settings = testSettingsStore(
            suiteName: "TokenRefreshMemoryReliefTests",
            userDefaults: InMemoryUserDefaults(),
            keychainAccessPolicy: .init(setDisabled: { _ in }, isExplicitlyDisabled: { true }))
        settings._test_codexAccountSnapshotLoader = { _ in
            CodexAccountReconciliationSnapshot(
                storedAccounts: [],
                activeStoredAccount: nil,
                liveSystemAccount: nil,
                matchingStoredAccountForLiveSystemAccount: nil,
                activeSource: .liveSystem,
                hasUnreadableAddedAccountStore: false)
        }
        settings.providerDetectionCompleted = true
        settings.refreshFrequency = .fiveMinutes
        settings.statusChecksEnabled = false
        settings.costUsageEnabled = true
        settings.codexLocalSessionCostLedgerEnabled = false
        settings.openAIWebAccessEnabled = false
        settings.providerStorageFootprintsEnabled = false
        enableTestProviders(providers, settings: settings)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let environment = [
            "HOME": root.path,
            "CODEX_HOME": root.appendingPathComponent(".codex").path,
            "XDG_CONFIG_HOME": root.appendingPathComponent(".config").path,
        ]
        let store = UsageStore(
            fetcher: UsageFetcher(environment: environment),
            browserDetection: BrowserDetection(cacheTTL: 0),
            settings: settings,
            startupBehavior: .testing,
            environmentBase: environment)
        store._test_tokenUsageRefreshOverride = { _, _ in }
        store._test_widgetSnapshotSaveOverride = { _ in }
        return store
    }

    private static func snapshot() -> CostUsageTokenSnapshot {
        CostUsageTokenSnapshot(
            sessionTokens: 1,
            sessionCostUSD: 0.01,
            last30DaysTokens: 1,
            last30DaysCostUSD: 0.01,
            daily: [],
            updatedAt: Date())
    }

    private static func cancelRelief(_ store: UsageStore) {
        store.memoryPressureReliefTask?.cancel()
        store.memoryPressureReliefTask = nil
    }
}
