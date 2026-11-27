import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AntigravityQuota {
    static func fetch(
        _ grant: AntigravityOAuthCredentials,
        http: QuotaHTTP,
        save: @Sendable (AntigravityOAuthCredentials) throws -> Void) async throws -> [QuotaWindow]
    {
        var credentials = grant
        let token: String
        if let expiry = grant.expiryDate, expiry.timeIntervalSinceNow <= 60 {
            let renewed = try await self.renew(grant, http: http)
            try save(renewed)
            credentials = renewed
            guard let access = renewed.accessToken else { throw QuotaError.unauthorized }
            token = access
        } else {
            guard let access = grant.accessToken?.trimmedNonEmpty else { throw QuotaError.unauthorized }
            token = access
        }

        func loadProject() async throws -> AntigravityRemoteClient.CodeAssistResponse {
            let info = try await self.request(
                "loadCodeAssist", body: ["metadata": AntigravityRemoteClient.clientMetadata], token: token, http: http)
            return try JSONDecoder().decode(AntigravityRemoteClient.CodeAssistResponse.self, from: info)
        }
        let assist = try await loadProject()
        let stored = credentials.projectID?.trimmedNonEmpty
        if stored == nil, assist.rejectsClientForConsumerTier { throw QuotaError.unauthorized }
        let project = try await AntigravityRemoteClient.projectID(
            stored: stored,
            response: assist,
            onboard: { tier in
                let result = try await self.request(
                    "onboardUser",
                    body: ["tierId": tier, "metadata": AntigravityRemoteClient.clientMetadata],
                    token: token,
                    http: http)
                return try JSONDecoder().decode(AntigravityRemoteClient.OnboardResponse.self, from: result).projectID
            }, reload: loadProject)
        if let project, project != stored {
            credentials.projectID = project
            try save(credentials)
        }
        let body = project.map { ["project": $0] } ?? [:]
        do {
            let data = try await self.request("retrieveUserQuotaSummary", body: body, token: token, http: http)
            let windows = try self.summary(data)
            if !windows.isEmpty { return windows }
        } catch QuotaError.unauthorized {
            throw QuotaError.unauthorized
        } catch QuotaError.http(429) {
            throw QuotaError.http(429)
        } catch {
            try Task.checkCancellation()
            if (error as? URLError)?.code == .cancelled { throw error }
            // An unavailable or unrecognized summary can still have measured model quotas.
        }
        return try await self.modelWindows(project: body, token: token, http: http)
    }

    private static func modelWindows(project: [String: String], token: String, http: QuotaHTTP) async throws
        -> [QuotaWindow]
    {
        do {
            let data = try await self.request("fetchAvailableModels", body: project, token: token, http: http)
            let response = try JSONDecoder().decode(
                AntigravityRemoteClient.FetchAvailableModelsResponse.self,
                from: data)
            let rows = (response.models ?? [:]).sorted { $0.key < $1.key }.compactMap { id, model in
                self.window(
                    title: model.displayName?.trimmedNonEmpty ?? model.label?.trimmedNonEmpty ?? id,
                    remaining: model.quotaInfo?.remainingFraction,
                    reset: model.quotaInfo?.resetTime)
            }
            // Some clients receive a full availability list for every model. Require measured buckets for that shape.
            if rows.contains(where: { $0.usedPercent > 0 }) { return rows }
        } catch is DecodingError {
            // The independent bucket endpoint may still have a usable response.
        } catch let QuotaError.http(status) where [403, 404, 501].contains(status) {
            // Older accounts may grant access only to retrieveUserQuota.
        }
        let data = try await self.request("retrieveUserQuota", body: project, token: token, http: http)
        let response = try JSONDecoder().decode(AntigravityRemoteClient.RetrieveUserQuotaResponse.self, from: data)
        return (response.buckets ?? []).compactMap { bucket in
            guard let model = bucket.modelId?.trimmedNonEmpty else { return nil }
            return self.window(title: model, remaining: bucket.remainingFraction, reset: bucket.resetTime)
        }
    }

    private struct Summary: Decodable {
        let code: CodeValue?
        let response: QuotaSummaryPayload?
        let summary: QuotaSummaryPayload?
        let groups: [QuotaSummaryGroupPayload]?
    }

    static func summary(_ data: Data) throws -> [QuotaWindow] {
        let envelope = try JSONDecoder().decode(Summary.self, from: data)
        guard envelope.code?.isOK != false else { return [] }
        let groups = envelope.response?.groups ?? envelope.summary?.groups ?? envelope.groups ?? []
        return groups.flatMap { group in
            (group.buckets ?? []).compactMap { bucket -> QuotaWindow? in
                guard bucket.disabled != true,
                      let name = (bucket.displayName ?? bucket.name ?? bucket.bucketId ?? bucket.id)?.trimmedNonEmpty
                else { return nil }
                let cadence = bucket.window?.trimmedNonEmpty
                let parts = [group.displayName ?? group.name, name, cadence == name ? nil : cadence]
                return self.window(
                    title: parts.compactMap(\.self).joined(separator: " · "),
                    remaining: bucket.remainingFraction ?? bucket.remaining?.remainingFraction,
                    reset: bucket.resetTime)
            }
        }
    }

    private static func window(title: String, remaining: Decimal?, reset: String?) -> QuotaWindow? {
        guard let fraction = remaining, (0...1).contains(fraction)
        else { return nil }
        let date = ISO8601DateParser.parse(reset) ?? reset.flatMap(Double.init).map(Date.init(timeIntervalSince1970:))
        return QuotaWindow(title: title, usedPercent: (1 - fraction) * 100, resetsAt: date)
    }

    private static func request(
        _ method: String, body: [String: Any], token: String, http: QuotaHTTP) async throws -> Data
    {
        var request = URLRequest(url: URL(string: "https://cloudcode-pa.googleapis.com/v1internal:\(method)")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(AntigravityRemoteClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await http.send(request)
    }

    private static func renew(_ grant: AntigravityOAuthCredentials, http: QuotaHTTP) async throws
        -> AntigravityOAuthCredentials
    {
        guard let refresh = grant.refreshToken?.trimmedNonEmpty,
              let client = grant.clientID?.trimmedNonEmpty,
              let secret = grant.clientSecret?.trimmedNonEmpty else { throw QuotaError.unauthorized }
        var request = URLRequest(url: AntigravityOAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = FormURLEncoding.body([
            "client_id": client, "client_secret": secret, "refresh_token": refresh, "grant_type": "refresh_token",
        ])
        struct Token: Decodable {
            let access_token: String
            let expires_in: Double
            let refresh_token: String?
        }
        let data: Data
        do {
            data = try await http.send(request)
        } catch QuotaError.http(400) {
            throw QuotaError.unauthorized
        }
        let response = try JSONDecoder().decode(Token.self, from: data)
        guard let access = response.access_token.trimmedNonEmpty, response.expires_in > 0 else {
            throw QuotaError.unauthorized
        }
        var renewed = grant
        renewed.accessToken = access
        renewed.refreshToken = response.refresh_token?.trimmedNonEmpty ?? refresh
        renewed.expiryDateMilliseconds = Date().addingTimeInterval(response.expires_in).timeIntervalSince1970 * 1000
        return renewed
    }
}
