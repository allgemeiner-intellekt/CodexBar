import Foundation

enum AntigravityRemoteClient {
    /// The model availability listing can return placeholder readings near 100% remaining.
    static let availabilityFractionThreshold: Decimal = 0.999

    static let clientMetadata = [
        "ideType": "ANTIGRAVITY",
        "platform": "PLATFORM_UNSPECIFIED",
        "pluginType": "GEMINI",
    ]

    /// Cloud Code requires the Hub client family for quota access; pin a shared compatibility identity.
    static let userAgent: String = {
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "amd64"
        #endif
        #if os(Linux)
        let platform = "linux"
        #else
        let platform = "darwin"
        #endif
        return "antigravity/hub/2.9.1 \(platform)/\(architecture)"
    }()

    static func projectID(
        stored: String?,
        response: CodeAssistResponse,
        onboard: (String) async throws -> String?,
        reload: () async throws -> CodeAssistResponse) async throws -> String?
    {
        if let project = stored ?? response.projectID { return project }
        guard let tier = Self.pickOnboardTier(from: response) else { return nil }
        if let project = try await onboard(tier) { return project }
        for _ in 0..<5 {
            try await Task.sleep(for: .seconds(2))
            if let project = try await reload().projectID { return project }
        }
        return nil
    }

    private static func pickOnboardTier(from response: CodeAssistResponse) -> String? {
        response.allowedTiers?
            .first(where: { $0.isDefault == true && $0.id?.trimmedNonEmpty != nil })?.id?.trimmedNonEmpty
            ?? response.allowedTiers?.first(where: { $0.id?.trimmedNonEmpty != nil })?.id?.trimmedNonEmpty
            ?? response.paidTier?.id?.trimmedNonEmpty
            ?? response.currentTier?.id?.trimmedNonEmpty
    }
}

extension AntigravityRemoteClient {
    struct ProjectReference: Decodable {
        let value: String?

        init(from decoder: Decoder) throws {
            let single = try decoder.singleValueContainer()
            if let stringValue = try? single.decode(String.self) {
                self.value = stringValue
                return
            }

            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.value = try keyed.decodeIfPresent(String.self, forKey: .id)
                ?? keyed.decodeIfPresent(String.self, forKey: .projectID)
        }

        private enum CodingKeys: String, CodingKey {
            case id
            case projectID = "projectId"
        }
    }

    struct CodeAssistResponse: Decodable {
        let planInfo: CodeAssistPlanInfo?
        let currentTier: TierInfo?
        let paidTier: TierInfo?
        let allowedTiers: [AllowedTier]?
        let ineligibleTiers: [IneligibleTier]?
        let cloudaicompanionProject: ProjectReference?

        var projectID: String? {
            self.cloudaicompanionProject?.value?.trimmedNonEmpty
        }

        /// Consumer accounts are unonboarded when the token's OAuth client is not the consumer sign-in client.
        var rejectsClientForConsumerTier: Bool {
            self.currentTier == nil && self.projectID == nil && self.ineligibleTiers?.contains {
                $0.reasonCode == "GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT"
            } == true
        }
    }

    struct CodeAssistPlanInfo: Decodable {
        let planType: String?
    }

    struct TierInfo: Decodable {
        let id: String?
        let name: String?
    }

    struct AllowedTier: Decodable {
        let id: String?
        let isDefault: Bool?
    }

    struct IneligibleTier: Decodable {
        let reasonCode: String?
    }

    struct OnboardResponse: Decodable {
        let response: OnboardInnerResponse?

        var projectID: String? {
            self.response?.cloudaicompanionProject?.value?.trimmedNonEmpty
        }
    }

    struct OnboardInnerResponse: Decodable {
        let cloudaicompanionProject: ProjectReference?
    }

    struct FetchAvailableModelsResponse: Decodable {
        let models: [String: AntigravityRemoteModel]?
    }

    struct RetrieveUserQuotaResponse: Decodable {
        let buckets: [RetrieveUserQuotaBucket]?
    }

    struct RetrieveUserQuotaBucket: Decodable {
        let modelId: String?
        let remainingFraction: Decimal?
        let resetTime: String?
    }

    struct AntigravityRemoteModel: Decodable {
        let displayName: String?
        let label: String?
        let quotaInfo: AntigravityRemoteQuotaInfo?
    }

    struct AntigravityRemoteQuotaInfo: Decodable {
        let remainingFraction: Decimal?
        let resetTime: String?
    }
}
