import Foundation
import Testing
@testable import CodexBar
@testable import CodexBarCore

struct KimiMenuBarWindowTests {
    @Test(arguments: [false, true])
    func `semantic windows ignore absent and synthetic lanes and use extra windows`(placeholder: Bool) {
        let primary = placeholder ? RateWindow(
            usedPercent: 0,
            windowMinutes: 10080,
            resetsAt: nil,
            resetDescription: nil,
            isSyntheticPlaceholder: true) : nil
        let session = Self.window(used: 25, minutes: 300)
        let weekly = Self.window(used: 50, minutes: 10080)
        let snapshot = UsageSnapshot(
            primary: primary,
            secondary: nil,
            extraRateWindows: [
                NamedRateWindow(id: "session", title: "Session", window: session),
                NamedRateWindow(id: "weekly", title: "Weekly", window: weekly),
            ],
            updatedAt: Date())
        let windows = KimiProviderDescriptor.descriptor.presentation.semanticWindows(snapshot: snapshot)
        #expect(windows.session == session)
        #expect(windows.weekly == weekly)
    }

    @Test
    func `exhausted membership takes precedence over reset Code windows`() throws {
        let monthly = Self.monthly(used: 100)
        let weekly = Self.window(used: 0, minutes: 10080)
        let session = Self.window(used: 0, minutes: 300)
        #expect(try Self.resolve(primary: weekly, secondary: session, extra: monthly) == monthly.window)
    }

    @Test(arguments: [
        nil,
        Self.monthly(used: 99),
        Self.monthly(used: 100, known: false),
        NamedRateWindow(id: "unrelated", title: "Other", window: Self.window(used: 100, minutes: nil)),
    ])
    func `only known exhausted monthly usage overrides the session`(extra: NamedRateWindow?) throws {
        let session = Self.window(used: 25, minutes: 300)
        #expect(try Self.resolve(
            primary: Self.window(used: 50, minutes: 10080),
            secondary: session,
            extra: extra) == session)
    }

    @Test(arguments: [false, true])
    func `Code exhaustion still takes precedence over partial membership`(weeklyExhausted: Bool) throws {
        let weekly = Self.window(used: weeklyExhausted ? 100 : 0, minutes: 10080)
        let session = Self.window(used: weeklyExhausted ? 0 : 100, minutes: 300)
        #expect(try Self.resolve(primary: weekly, secondary: session, extra: Self.monthly(used: 50)) ==
            (weeklyExhausted ? weekly : session))
    }

    @Test(arguments: [
        ProviderMenuBarMetric.primary,
        .secondary,
        .primaryAndSecondary,
        .tertiary,
        .extraUsage,
        .average,
        .monthlyPlan,
    ])
    func `explicit metrics keep their standard resolution`(metric: ProviderMenuBarMetric) {
        let resolution = Self.resolution(
            metric: metric,
            primary: Self.window(used: 0, minutes: 10080),
            secondary: Self.window(used: 0, minutes: 300),
            extra: Self.monthly(used: 100))
        guard case .unhandled = resolution else {
            Issue.record("Kimi must leave explicit metric selection to the standard resolver")
            return
        }
    }

    @Test
    func `status indicator resolves monthly automatically and preserves explicit Code windows`() {
        let weekly = Self.window(used: 20, minutes: 10080)
        let session = Self.window(used: 0, minutes: 300)
        let monthly = Self.monthly(used: 100)
        let snapshot = UsageSnapshot(
            primary: weekly, secondary: session, extraRateWindows: [monthly], updatedAt: Date())
        for (preference, expected) in [
            (MenuBarMetricPreference.automatic, monthly.window), (.primary, weekly), (.secondary, session),
        ] {
            #expect(MenuBarMetricWindowResolver.rateWindow(
                preference: preference, provider: .kimi, snapshot: snapshot, supportsAverage: false) == expected)
        }
    }

    private static func resolve(
        primary: RateWindow?, secondary: RateWindow?, extra: NamedRateWindow?) throws -> RateWindow?
    {
        guard case let .resolved(window) = resolution(
            metric: .automatic, primary: primary, secondary: secondary, extra: extra)
        else {
            Issue.record("Kimi automatic metric should resolve")
            return nil
        }
        return window
    }

    private static func resolution(
        metric: ProviderMenuBarMetric, primary: RateWindow?, secondary: RateWindow?, extra: NamedRateWindow?)
        -> ProviderMenuBarWindowResolution
    {
        let now = Date(timeIntervalSince1970: 1_788_000_000)
        return KimiProviderDescriptor.descriptor.presentation.menuBarWindow(context: .init(
            metric: metric,
            snapshot: UsageSnapshot(
                primary: primary, secondary: secondary, extraRateWindows: extra.map { [$0] }, updatedAt: now),
            supportsAverage: false,
            prioritizesExhaustedQuotas: false,
            now: now))
    }

    private static func monthly(used: Double, known: Bool = true) -> NamedRateWindow {
        NamedRateWindow(
            id: "kimi-monthly",
            title: "Total usage",
            window: self.window(used: used, minutes: ProviderPaceCapability.monthlyWindowSentinelMinutes),
            usageKnown: known)
    }

    private static func window(used: Double, minutes: Int?) -> RateWindow {
        RateWindow(usedPercent: used, windowMinutes: minutes, resetsAt: nil, resetDescription: nil)
    }
}
