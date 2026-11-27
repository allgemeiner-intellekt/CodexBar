import Foundation

enum CodeValue: Decodable {
    case int(Int)
    case string(String)

    var isOK: Bool {
        switch self {
        case let .int(value):
            value == 0
        case let .string(value):
            value.lowercased() == "ok" || value.lowercased() == "success" || value == "0"
        }
    }

    var rawValue: String {
        switch self {
        case let .int(value): "\(value)"
        case let .string(value): value
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported code type")
    }
}
