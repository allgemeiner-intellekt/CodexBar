import Foundation

/// Reads account hints from a token. The service authenticates the original bearer token.
enum JWTClaims {
    static func decode(_ idToken: String?) -> [String: Any]? {
        guard let idToken else { return nil }
        let parts = idToken.components(separatedBy: ".")
        guard parts.count >= 2 else { return nil }
        var payload = parts[1]
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        guard let data = Data(base64Encoded: payload, options: .ignoreUnknownCharacters),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return json
    }
}
