import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

struct QuotaMenuTests {
    private let reset = "2026-11-27T00:00:00Z"

    @Test
    func `menu uses one direction for the label and gauge across all three cards`() throws {
        let codex = try CodexQuota.windows(Data("""
        {"rate_limit":{"primary_window":{"used_percent":25,"limit_window_seconds":18000,"reset_at":1795737600}}}
        """.utf8))
        let kimi = try KimiQuota.windows(Data("""
        {"usage":{"limit":"20","remaining":"15","reset_time":"\(self.reset)"},
         "usages":{"limit_5h":{"used_ratio":0.25,"reset_time":"\(self.reset)"}}}
        """.utf8))
        let google = try AntigravityQuota.summary(Data("""
        {"response":{"groups":[{"name":"Gemini","buckets":[{"id":"weekly","remaining":{"case":"remainingFraction",
         "value":0.75},"resetTime":"\(self.reset)"}]}]}}
        """.utf8))
        #expect(QuotaSubscription.allCases.map(\.rawValue) == ["codex", "kimi", "antigravity"])
        #expect(kimi.map(\.title) == ["5 小时", "每周"])
        #expect(google.map(\.title) == ["Gemini · weekly"])
        #expect(codex.map(\.title) == ["Codex · 5 小时"])
        let snapshots: [QuotaSubscription: [QuotaWindow]] = [.codex: codex, .kimi: kimi, .antigravity: google]
        for showUsed in [true, false] {
            let menu = QuotaMenuDescriptor(windows: snapshots, errors: [:], showUsed: showUsed)
            #expect(menu.cards.map(\.provider) == [.codex, .kimi, .antigravity])
            #expect(menu.cards.map(\.rows.count) == [1, 2, 1])
            for row in menu.cards.flatMap(\.rows) {
                #expect(row.label == (showUsed ? "25% 已用" : "75% 剩余"))
                #expect(row.fill == (showUsed ? 25 : 75))
                #expect(row.resetsAt == ISO8601DateParser.parse(self.reset))
            }
        }
    }

    @Test
    func `fresh display defaults to used and upgrades honor an explicit false`() {
        let defaults = MemoryDefaults()
        #expect(QuotaDisplayPreference.showUsed(in: defaults))
        defaults.values["usageBarsShowUsed"] = false
        defaults.values["providerOrder"] = ["claude", "kimi"]
        #expect(!QuotaDisplayPreference.showUsed(in: defaults))
        #expect(QuotaSubscription.allCases.count == 3)
        #expect(QuotaSubscription(rawValue: "claude") == nil)
    }

    @Test
    func `missing readings never become zero and optional malformed month is isolated`() throws {
        let data = Data("""
        {"usage":{"limit":"100"},"usages":{"limit_month_total":{"used_ratio":"unknown"},"limit_7d":{"used_ratio":0}},
         "limits":[{"window":{"duration":2,"timeUnit":"TIME_UNIT_HOUR"},"detail":{"limit":50,"used":30}},
                   {"window":{"duration":300,"timeUnit":"TIME_UNIT_MINUTE"},"detail":{"limit":20,"remaining":0}}]}
        """.utf8)
        let rows = try KimiQuota.windows(data)
        #expect(rows.map(\.usedPercent) == [100, 0])
        #expect(rows.map(\.title) == ["5 小时", "每周"])
        #expect(try KimiQuota.windows(Data(#"{"usage":{"limit":5}}"#.utf8)).isEmpty)
        let google = Data(#"{"groups":[{"buckets":[{"id":"unknown"},{"id":"empty","remainingFraction":0}]}]}"#.utf8)
        #expect(try AntigravityQuota.summary(google).map(\.usedPercent) == [100])
        let codex = Data(#"{"rate_limit":{"primary_window":{"reset_at":1},"secondary_window":{"used_percent":0}}}"#
            .utf8)
        #expect(try CodexQuota.windows(codex).map(\.usedPercent) == [0])
    }

    @Test
    func `matched Kimi reset uses exhausted counter and monthly comes only from the same reply`() throws {
        let data = Data("""
        {"limits":[{"window":{"duration":5,"timeUnit":"TIME_UNIT_HOUR"},
         "detail":{"limit":"10","used":"10","resetTime":"2026-11-27T00:00:01Z"}}],
         "usages":{"limit_5h":{"used_ratio":0,"reset_time":"\(self.reset)"}, "limit_month_total":{"used_ratio":0.12}}}
        """.utf8)
        #expect(try KimiQuota.windows(data).map(\.usedPercent) == [100, 12])
    }
}

private final class MemoryDefaults: UserDefaults {
    var values: [String: Any] = [:]
    override func object(forKey key: String) -> Any? { self.values[key] }
}

extension QuotaMenuTests {
    @Test
    func `decimal conversion keeps nearly full and nearly empty distinct from their endpoints`() throws {
        let google = Data(#"{"groups":[{"buckets":[{"id":"weekly","remainingFraction":0.99999999999999999}]}]}"#.utf8)
        let row = try #require(AntigravityQuota.summary(google).first)
        #expect(row.usedPercent == Decimal(string: "0.000000000000001"))
        #expect(QuotaMenuRow(row, showUsed: true).label == "<0.01% 已用")
        #expect(QuotaMenuRow(row, showUsed: false).label == ">99.99% 剩余")
    }
}

extension QuotaMenuTests {
    @Test
    func `Codex shows one additional row per feature and period when product labels vary`() throws {
        let data = Data("""
        {"additional_rate_limits":[
          {"limit_name":"Example","metered_feature":"one","rate_limit":{"primary_window":
            {"used_percent":12,"limit_window_seconds":18000,"reset_at":0}}},
          {"limit_name":"Example duplicate","metered_feature":"one","rate_limit":{"primary_window":
            {"used_percent":99,"limit_window_seconds":18000,"reset_at":0}}},
          {"limit_name":"Example weekly","metered_feature":"one","rate_limit":{"primary_window":
            {"used_percent":45,"limit_window_seconds":604800,"reset_at":1795737600}}}]}
        """.utf8)
        let windows = try CodexQuota.windows(data)
        #expect(windows.map(\.usedPercent) == [12, 45])
        #expect(windows.first?.resetsAt == nil)
        #expect(windows.last?.resetsAt == ISO8601DateParser.parse(self.reset))
    }
}
