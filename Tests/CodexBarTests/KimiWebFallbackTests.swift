import Foundation
import Testing
@testable import CodexBarCore

struct KimiWebFallbackTests {
    @Test(arguments: ["KIMI_AUTH_TOKEN", "kimi_auth_token"], [false, true])
    func `environment JWT overrides automatic accounts after normalization`(key: String, quoted: Bool) async throws {
        let calls = KimiFallbackCalls()
        let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJmaXh0dXJlIn0.fixture"
        let context = Self.context(environment: [key: quoted ? " \"\(token)\" " : token])
        let strategy = Self.strategy(calls: calls) { _ in Self.usage() }

        #expect(await strategy.isAvailable(context))
        _ = try await strategy.fetch(context)

        #expect(calls.snapshot == ["fetch:\(token)"])
    }

    @Test(arguments: ["uppercase", "manual environment", "manual settings"])
    func `explicit cookie precedence is preserved with lowercase environment alias`(source: String) async throws {
        let calls = KimiFallbackCalls()
        var environment = [
            "KIMI_AUTH_TOKEN": "kimi-auth=uppercase",
            "kimi_auth_token": "kimi-auth=lowercase",
        ]
        if source != "uppercase" {
            environment["KIMI_MANUAL_COOKIE"] = "kimi-auth=manual-environment"
        }
        let manual = source == "manual settings" ? "kimi-auth=manual-settings" : nil
        let context = Self.context(
            source: manual == nil ? .auto : .manual,
            manual: manual,
            environment: environment)
        let expected = switch source {
        case "manual settings": "manual-settings"
        case "manual environment": "manual-environment"
        default: "uppercase"
        }

        _ = try await Self.strategy(calls: calls) { _ in Self.usage() }.fetch(context)

        #expect(calls.snapshot == ["fetch:\(expected)"])
    }

    @Test
    func `rejected lowercase environment JWT does not switch to automatic accounts`() async {
        let calls = KimiFallbackCalls()
        let token = "eyJhbGciOiJub25lIn0.eyJzdWIiOiJmaXh0dXJlIn0.fixture"
        let strategy = Self.strategy(calls: calls) { _ in throw KimiAPIError.invalidToken }

        do {
            _ = try await strategy.fetch(Self.context(environment: ["kimi_auth_token": token]))
            Issue.record("Expected authoritative token rejection")
        } catch KimiAPIError.invalidToken {} catch {
            Issue.record("Unexpected error: \(error)")
        }

        #expect(calls.snapshot == ["fetch:\(token)"])
    }

    @Test(arguments: KimiRegion.allCases)
    func `web strategy passes selected region to automatic sources and requests`(region: KimiRegion) async throws {
        let calls = KimiFallbackCalls()
        let strategy = KimiWebFetchStrategy(
            fetchUsage: { token, selected in
                #expect(selected == region)
                calls.add(token)
                return Self.usage()
            },
            desktopToken: { selected in
                #expect(selected == region)
                return nil
            },
            browserTokens: { selected in
                #expect(selected == region)
                return ["regional-browser-token"]
            })
        #expect(await strategy.isAvailable(Self.context(region: region)))
        _ = try await strategy.fetch(Self.context(region: region))
        #expect(calls.snapshot == ["regional-browser-token"])
    }

    @Test(arguments: ["manual", "environment"])
    func `explicit tokens remain authoritative when rejected`(source: String) async {
        let calls = KimiFallbackCalls()
        let strategy = Self.strategy(calls: calls) { _ in throw KimiAPIError.invalidToken }
        let context = Self.context(
            source: .manual,
            manual: source == "manual" ? "kimi-auth=explicit" : nil,
            environment: source == "environment" ? ["KIMI_AUTH_TOKEN": "kimi-auth=explicit"] : [:])
        do {
            _ = try await strategy.fetch(context)
            Issue.record("Expected authoritative token rejection")
        } catch KimiAPIError.invalidToken {} catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(calls.snapshot == ["fetch:explicit"])
    }

    @Test(arguments: [ProviderCookieSource.off, .manual], ["", "not-a-token"])
    func `disabled or invalid manual cookies never resolve automatic credentials`(
        source: ProviderCookieSource,
        manual: String) async
    {
        let calls = KimiFallbackCalls()
        let strategy = Self.strategy(calls: calls) { _ in Self.usage() }
        do {
            _ = try await strategy.fetch(Self.context(source: source, manual: manual))
            Issue.record("Expected missing token")
        } catch KimiAPIError.missingToken {} catch {
            Issue.record("Unexpected error: \(error)")
        }
        #expect(calls.snapshot.isEmpty)
    }

    @Test
    func `production web strategy skips repeated tokens and retries rejected browser profiles`() async throws {
        let calls = KimiFallbackCalls()
        let strategy = Self.strategy(calls: calls) { token in
            guard token == "browser-current" else { throw KimiAPIError.invalidToken }
            return Self.usage()
        }
        let result = try await strategy.fetch(Self.context())
        #expect(result.usage.primary?.usedPercent == 25)
        #expect(calls.snapshot == [
            "desktop", "fetch:desktop", "browser", "fetch:browser-old", "fetch:browser-current",
        ])
    }

    @Test
    func `successful desktop usage does not inspect browsers`() async throws {
        let calls = KimiFallbackCalls()
        _ = try await Self.strategy(calls: calls) { _ in Self.usage() }.fetch(Self.context())
        #expect(calls.snapshot == ["desktop", "fetch:desktop"])
    }

    @Test
    func `network errors do not advance to another account`() async {
        let calls = KimiFallbackCalls()
        do {
            _ = try await Self.strategy(calls: calls) { _ in throw URLError(.notConnectedToInternet) }
                .fetch(Self.context())
            Issue.record("Expected network failure")
        } catch {
            #expect((error as? URLError)?.code == .notConnectedToInternet)
        }
        #expect(calls.snapshot == ["desktop", "fetch:desktop"])
    }

    @Test(arguments: ["desktop", "browser-old"])
    func `cancellation racing token rejection stops further credential reads and requests`(cancelAt: String) async {
        let calls = KimiFallbackCalls()
        let task = Task {
            try await Self.strategy(calls: calls) { token in
                if token == cancelAt {
                    withUnsafeCurrentTask { $0?.cancel() }
                }
                throw KimiAPIError.invalidToken
            }.fetch(Self.context())
        }
        do {
            _ = try await task.value
            Issue.record("Expected cancellation")
        } catch {
            #expect(error is CancellationError)
        }
        let expected = cancelAt == "desktop"
            ? ["desktop", "fetch:desktop"]
            : ["desktop", "fetch:desktop", "browser", "fetch:browser-old"]
        #expect(calls.snapshot == expected)
    }

    private static func strategy(
        calls: KimiFallbackCalls,
        fetch: @escaping @Sendable (String) async throws -> KimiUsageSnapshot) -> KimiWebFetchStrategy
    {
        KimiWebFetchStrategy(
            fetchUsage: { token, _ in calls.add("fetch:\(token)"); return try await fetch(token) },
            desktopToken: { _ in calls.add("desktop"); return "desktop" },
            browserTokens: { _ in calls.add("browser"); return ["desktop", "browser-old", "browser-current"] })
    }

    private static func usage() -> KimiUsageSnapshot {
        KimiUsageSnapshot(
            weekly: .init(limit: "100", used: "25", remaining: "75", resetTime: nil),
            rateLimit: nil,
            updatedAt: Date(timeIntervalSince1970: 100))
    }

    private static func context(
        region: KimiRegion = .china,
        source: ProviderCookieSource = .auto,
        manual: String? = nil,
        environment: [String: String] = [:]) -> ProviderFetchContext
    {
        ProviderFetchContext(
            runtime: .app,
            sourceMode: .web,
            includeCredits: false,
            webTimeout: 1,
            webDebugDumpHTML: false,
            verbose: false,
            env: environment,
            settings: .make(kimi: .init(cookieSource: source, manualCookieHeader: manual, region: region)),
            fetcher: UsageFetcher(environment: environment),
            claudeFetcher: KimiFallbackClaudeStub(),
            browserDetection: BrowserDetection(cacheTTL: 0))
    }
}

private final class KimiFallbackCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [String] = []

    func add(_ call: String) {
        self.lock.withLock { self.calls.append(call) }
    }

    var snapshot: [String] {
        self.lock.withLock { self.calls }
    }
}

private struct KimiFallbackClaudeStub: ClaudeUsageFetching {
    func loadLatestUsage(model _: String) async throws -> ClaudeUsageSnapshot {
        throw ClaudeUsageError.parseFailed("fixture")
    }

    func debugRawProbe(model _: String) async -> String {
        "fixture"
    }

    func detectVersion() -> String? {
        nil
    }
}
