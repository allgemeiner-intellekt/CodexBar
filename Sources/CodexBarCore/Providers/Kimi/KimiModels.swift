import Foundation

struct KimiUsageResponse: Codable {
    let usages: [KimiUsage]
}

struct KimiCodeAPIUsageResponse: Codable {
    let usage: KimiUsageDetail?
    let usages: KimiCodeUsagePools?
    let limits: [KimiRateLimit]?
}

struct KimiCodeUsagePools: Codable, Sendable {
    let session: KimiRatioPool?
    let weekly: KimiRatioPool?
    let monthly: KimiRatioPool?

    private enum CodingKeys: String, CodingKey {
        case session = "limit_5h"
        case weekly = "limit_7d"
        case monthly = "limit_month_total"
    }
}

struct KimiRatioPool: Codable, Sendable {
    let usedRatio: Double?
    let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case usedRatio = "used_ratio"
        case resetTime = "reset_time"
    }

    func window(minutes: Int) -> RateWindow? {
        guard let usedRatio, usedRatio.isFinite, usedRatio >= 0 else { return nil }
        return RateWindow(
            usedPercent: min(1, usedRatio) * 100,
            windowMinutes: minutes,
            resetsAt: KimiUsageSnapshot.parseDate(self.resetTime),
            resetDescription: nil)
    }
}

struct KimiSubscriptionStatsResponse: Codable {
    let subscriptionBalance: KimiSubscriptionBalance?
    let ratelimitCode7d: KimiSubscriptionRateLimit?
}

struct KimiSubscriptionBalance: Codable, Sendable {
    let feature: String?
    let type: String?
    let amountUsedRatio: Double?
    let kimiCodeUsedRatio: Double?
    let expireTime: String?
}

struct KimiSubscriptionRateLimit: Codable, Sendable {
    let ratio: Double?
    let enabled: Bool?
    let resetTime: String?
}

struct KimiUsage: Codable {
    let scope: String
    let detail: KimiUsageDetail
    let limits: [KimiRateLimit]?
}

public struct KimiUsageDetail: Codable, Sendable {
    public let limit: String
    public let used: String?
    public let remaining: String?
    public let resetTime: String?

    private enum CodingKeys: String, CodingKey {
        case limit
        case used
        case remaining
        case resetTime
        case resetAt
        case resetTimeSnake = "reset_time"
        case resetAtSnake = "reset_at"
    }

    public init(limit: String, used: String?, remaining: String?, resetTime: String?) {
        self.limit = limit
        self.used = used
        self.remaining = remaining
        self.resetTime = resetTime
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let limit = Self.stringValue(in: container, forKey: .limit) else {
            throw DecodingError.keyNotFound(
                CodingKeys.limit,
                DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Kimi usage limit is missing"))
        }

        self.limit = limit
        self.used = Self.stringValue(in: container, forKey: .used)
        self.remaining = Self.stringValue(in: container, forKey: .remaining)
        self.resetTime =
            Self.stringValue(in: container, forKey: .resetTime) ??
            Self.stringValue(in: container, forKey: .resetAt) ??
            Self.stringValue(in: container, forKey: .resetTimeSnake) ??
            Self.stringValue(in: container, forKey: .resetAtSnake)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.limit, forKey: .limit)
        try container.encodeIfPresent(self.used, forKey: .used)
        try container.encodeIfPresent(self.remaining, forKey: .remaining)
        try container.encodeIfPresent(self.resetTime, forKey: .resetTime)
    }

    private static func stringValue(
        in container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys) -> String?
    {
        if let value = try? container.decode(String.self, forKey: key) {
            return value
        }
        if let value = try? container.decode(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? container.decode(Double.self, forKey: key) {
            if let integer = Int64(exactly: value) {
                return String(integer)
            }
            return String(value)
        }
        return nil
    }
}

struct KimiRateLimit: Codable, Sendable {
    let window: KimiWindow
    let detail: KimiUsageDetail
}

struct KimiWindow: Codable, Sendable {
    let duration: Int
    let timeUnit: String

    var durationMinutes: Int? {
        guard self.duration > 0 else { return nil }
        let multiplier: Int
        switch self.timeUnit {
        case "TIME_UNIT_MINUTE":
            multiplier = 1
        case "TIME_UNIT_HOUR":
            multiplier = 60
        case "TIME_UNIT_DAY":
            multiplier = 24 * 60
        default:
            return nil
        }
        let result = self.duration.multipliedReportingOverflow(by: multiplier)
        return result.overflow ? nil : result.partialValue
    }
}
