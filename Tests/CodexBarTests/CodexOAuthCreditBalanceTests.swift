import Foundation
import Testing
@testable import CodexBarCore

struct CodexOAuthCreditBalanceTests {
    @Test(arguments: ["NaN", "Infinity", "-Infinity", "1e999"])
    func `nonfinite balances remain unread without discarding usage`(balance: String) throws {
        let data = Self.payload(balanceJSON: "\"\(balance)\"")
        let response = try CodexOAuthUsageFetcher._decodeUsageResponseForTesting(data)
        #expect(response.credits?.balance == nil)

        let result = try CodexOAuthFetchStrategy._mapResultForTesting(data, credentials: Self.credentials)
        let credits = try #require(result.credits)
        #expect(result.usage.primary?.usedPercent == 22)
        #expect(credits.remaining == 0)
        #expect(!credits.balanceReadSucceeded)
        #expect(credits.creditsAvailable == true)
        // Nonfinite balances previously made the account snapshot cache unencodable.
        _ = try JSONEncoder().encode(credits)
        _ = try JSONEncoder().encode(result.usage)
    }

    @Test(arguments: ["0", "14.5", "-2.5"], [false, true])
    func `finite numeric and string balances preserve their values`(balance: String, quoted: Bool) throws {
        let data = Self.payload(balanceJSON: quoted ? "\"\(balance)\"" : balance)
        let response = try CodexOAuthUsageFetcher._decodeUsageResponseForTesting(data)
        #expect(response.credits?.balance == Double(balance))

        let result = try CodexOAuthFetchStrategy._mapResultForTesting(data, credentials: Self.credentials)
        let credits = try #require(result.credits)
        #expect(credits.remaining == Double(balance))
        #expect(credits.balanceReadSucceeded)
        #expect(result.usage.primary?.usedPercent == 22)
    }

    private static var credentials: CodexOAuthCredentials {
        CodexOAuthCredentials(
            accessToken: "test-access",
            refreshToken: "test-refresh",
            idToken: nil,
            accountId: nil,
            lastRefresh: Date(timeIntervalSince1970: 1_766_948_068))
    }

    private static func payload(balanceJSON: String) -> Data {
        Data("""
        {
          "rate_limit": {
            "primary_window": {
              "used_percent": 22,
              "reset_at": 1766948068,
              "limit_window_seconds": 18000
            }
          },
          "credits": {
            "has_credits": true,
            "unlimited": false,
            "balance": \(balanceJSON)
          }
        }
        """.utf8)
    }
}
