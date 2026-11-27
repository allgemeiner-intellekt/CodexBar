import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import CodexBarCore

private final class AccessLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func add(_ event: String) { self.lock.withLock { self.events.append(event) } }
    var all: [String] {
        self.lock.withLock { self.events }
    }

    func credentials() -> QuotaCredentials {
        QuotaCredentials(
            codex: {
                self.add("read CodexBar Codex grant")
                return CodexGrant(accessToken: "test-a", refreshToken: "test-r", accountID: "selected")
            },
            saveCodex: { _ in self.add("save CodexBar Codex grant") },
            kimi: {
                self.add("read CodexBar Kimi key")
                return KimiGrant(key: "test-k", region: .china)
            },
            google: {
                self.add("read CodexBar Google grant")
                return AntigravityOAuthCredentials(accessToken: "test-g", refreshToken: nil, expiryDate: nil)
            },
            saveGoogle: { _ in self.add("save CodexBar Google grant") })
    }

    func http(_ reply: @escaping @Sendable (URLRequest) throws -> (Int, String)) -> ProviderHTTPTransportHandler {
        ProviderHTTPTransportHandler { request in
            let url = try #require(request.url)
            self.add("\(request.httpMethod ?? "") \(url.host ?? "")\(url.path)")
            #expect(!request.httpShouldHandleCookies)
            let (status, body) = try reply(request)
            return (
                Data(body.utf8),
                HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
}

struct QuotaServiceTests {
    @Test
    func `core refresh reads each selected grant and contacts only its quota service`() async throws {
        let log = AccessLog()
        let http = log.http { request in
            switch request.url?.path {
            case "/backend-api/wham/usage":
                #expect(request.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "selected")
                return (200, #"{"rate_limit":{"primary_window":{"used_percent":24}}}"#)
            case "/coding/v1/usages":
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-k")
                return (200, #"{"usage":{"used":1,"limit":4}}"#)
            case "/v1internal:loadCodeAssist":
                return (200, #"{"cloudaicompanionProject":{"id":"selected-project"}}"#)
            case "/v1internal:retrieveUserQuotaSummary":
                let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
                #expect(body["project"] == "selected-project")
                return (200, #"{"groups":[{"name":"Models","buckets":[{"id":"weekly","remainingFraction":0.45}]}]}"#)
            default: throw URLError(.unsupportedURL)
            }
        }
        let service = QuotaService(credentials: log.credentials(), transport: http)
        var percents: [Decimal] = []
        for provider in QuotaSubscription.allCases {
            percents += try await service.fetch(provider).map(\.usedPercent)
        }
        #expect(percents == [24, 25, 55])
        #expect(log.all == [
            "read CodexBar Codex grant", "GET chatgpt.com/backend-api/wham/usage",
            "read CodexBar Kimi key", "GET api.kimi.com/coding/v1/usages",
            "read CodexBar Google grant", "POST cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
            "save CodexBar Google grant", "POST cloudcode-pa.googleapis.com/v1internal:retrieveUserQuotaSummary",
        ])
    }

    @Test
    func `invalid grants stop after first party requests without another credential source`() async {
        let log = AccessLog()
        let service = QuotaService(credentials: log.credentials(), transport: log.http { _ in (401, "{}") })
        for provider in QuotaSubscription.allCases {
            await #expect(throws: QuotaError.unauthorized) { try await service.fetch(provider) }
        }
        #expect(log.all == [
            "read CodexBar Codex grant", "GET chatgpt.com/backend-api/wham/usage", "POST auth.openai.com/oauth/token",
            "read CodexBar Kimi key", "GET api.kimi.com/coding/v1/usages",
            "read CodexBar Google grant", "POST cloudcode-pa.googleapis.com/v1internal:loadCodeAssist",
        ])
    }

    @Test
    func `device approval is exchanged once and persisted only by CodexBar`() async throws {
        let log = AccessLog()
        let service = QuotaService(credentials: log.credentials(), transport: log.http { request in
            switch request.url?.path {
            case "/api/accounts/deviceauth/usercode": (
                    200,
                    #"{"device_auth_id":"test","user_code":"123","interval":"1"}"#)
            case "/api/accounts/deviceauth/token": (200, #"{"authorization_code":"test","code_verifier":"fixture"}"#)
            case "/oauth/token": (200, #"{"access_token":"test-access","refresh_token":"test-refresh"}"#)
            default: throw URLError(.unsupportedURL)
            }
        })
        try await service.connectCodex { code in
            #expect(code == "123")
            log.add("present device code")
        }
        #expect(log.all == [
            "POST auth.openai.com/api/accounts/deviceauth/usercode", "present device code",
            "POST auth.openai.com/api/accounts/deviceauth/token", "POST auth.openai.com/oauth/token",
            "save CodexBar Codex grant",
        ])
    }
}

extension QuotaServiceTests {
    @Test
    func `new Google grant obtains a project then reads measured legacy model quotas`() async throws {
        let log = AccessLog()
        let service = QuotaService(credentials: log.credentials(), transport: log.http { request in
            let path = request.url?.lastPathComponent
            if path == "v1internal:loadCodeAssist" {
                return (200, #"{"allowedTiers":[{"id":"starter","isDefault":true}]}"#)
            }
            let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
            if path == "v1internal:onboardUser" {
                #expect(body?["tierId"] as? String == "starter")
                return (200, #"{"response":{"cloudaicompanionProject":{"id":"personal"}}}"#)
            }
            #expect(body?["project"] as? String == "personal")
            if path == "v1internal:fetchAvailableModels" {
                return (
                    200,
                    #"{"models":{"example":{"displayName":"Example","quotaInfo":{"remainingFraction":0.42}}}}"#)
            }
            return (404, "{}")
        })
        let windows = try await service.fetch(.antigravity)
        #expect(windows.map(\.usedPercent) == [58])
        #expect(windows.map(\.title) == ["Example"])
        #expect(log.all.contains("save CodexBar Google grant"))
    }

    @Test
    func `existing Google project survives client warning and placeholder model list`() async throws {
        let log = AccessLog()
        let old = log.credentials()
        let credentials = QuotaCredentials(
            codex: old.codex,
            saveCodex: old.saveCodex,
            kimi: old.kimi,
            google: {
                AntigravityOAuthCredentials(
                    accessToken: "test",
                    refreshToken: nil,
                    expiryDate: nil,
                    projectID: "saved")
            },
            saveGoogle: old.saveGoogle)
        let service = QuotaService(credentials: credentials, transport: log.http { request in
            switch request.url?.lastPathComponent {
            case "v1internal:loadCodeAssist":
                return (200, #"{"ineligibleTiers":[{"reasonCode":"GOOGLE_TOS_NOT_SUPPORTED_BY_CLIENT"}]}"#)
            case "v1internal:retrieveUserQuotaSummary":
                return (404, "{}")
            case "v1internal:fetchAvailableModels":
                return (200, #"{"models":{"example":{"quotaInfo":{"remainingFraction":1}}}}"#)
            case "v1internal:retrieveUserQuota":
                let project = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
                #expect(project["project"] == "saved")
                return (200, #"{"buckets":[{"modelId":"example","remainingFraction":0.75}]}"#)
            default: throw URLError(.unsupportedURL)
            }
        })
        #expect(try await service.fetch(.antigravity).map(\.usedPercent) == [25])
    }

    @Test
    func `expired Codex access renews only its own token and retries with the rotated grant`() async throws {
        let log = AccessLog()
        let service = QuotaService(credentials: log.credentials(), transport: log.http { req in
            if req.url?.path == "/oauth/token" {
                return (200, #"{"access_token":"renewed","refresh_token":"rotated"}"#)
            }
            if req.value(forHTTPHeaderField: "Authorization") == "Bearer renewed" {
                #expect(req.value(forHTTPHeaderField: "ChatGPT-Account-Id") == "selected")
                return (200, #"{"rate_limit":{"secondary_window":{"used_percent":28}}}"#)
            }
            return (401, "{}")
        })
        #expect(try await service.fetch(.codex).map(\.usedPercent) == [28])
        #expect(log.all == [
            "read CodexBar Codex grant",
            "GET chatgpt.com/backend-api/wham/usage",
            "POST auth.openai.com/oauth/token",
            "save CodexBar Codex grant",
            "GET chatgpt.com/backend-api/wham/usage",
        ])
    }
}

extension QuotaServiceTests {
    @Test
    func `missing and disconnected grants stay inside the owned directory`() async throws {
        let fm = FileManager.default
        let temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fm.removeItem(at: temporary) }
        let files = QuotaCredentialFiles(
            directory: temporary.appendingPathComponent("personal", isDirectory: true),
            googleStore: AntigravityOAuthCredentialsStore(fileURL: temporary.appendingPathComponent("google-grant")))
        let log = AccessLog()
        let service = QuotaService(credentials: files.credentials, transport: log.http { request in
            #expect(request.url?.host == "api.kimi.ai")
            return (200, #"{"usage":{"limit":20,"used":0}}"#)
        })
        for provider in QuotaSubscription.allCases {
            await #expect(throws: QuotaError.missingCredential) { try await service.fetch(provider) }
        }
        #expect(log.all.isEmpty)
        try files.saveKimi(KimiGrant(key: "fixture", region: .international))
        let path = temporary.appendingPathComponent("personal/kimi").path
        let attributes = try fm.attributesOfItem(atPath: path)
        #expect(attributes[.posixPermissions] as? Int == 0o600)
        #expect(try await service.fetch(.kimi).map(\.usedPercent) == [0])
        try files.disconnect(.kimi)
        await #expect(throws: QuotaError.missingCredential) { try await service.fetch(.kimi) }
        #expect(log.all == ["GET api.kimi.ai/coding/v1/usages"])
    }
}
