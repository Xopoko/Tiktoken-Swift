import Foundation

public enum TiktokenError: Error, CustomStringConvertible, Sendable {
    case invalidToken(Int)
    case invalidTokenBytes
    case decodeFailure(String)
    case encodeFailure(String)
    case unknownEncoding(String)
    case unknownModel(String)
    case disallowedSpecialToken(String)
    case invalidResource(String)
    case hashMismatch(expected: String, actual: String)
    case ioFailure(String)

    public var description: String {
        switch self {
        case .invalidToken(let token):
            return "Invalid token for decoding: \(token)"
        case .invalidTokenBytes:
            return "Invalid token bytes"
        case .decodeFailure(let message):
            return "Could not decode tokens: \(message)"
        case .encodeFailure(let message):
            return "Could not encode string: \(message)"
        case .unknownEncoding(let name):
            return "Unknown encoding \(name)"
        case .unknownModel(let model):
            return "Unknown model \(model)"
        case .disallowedSpecialToken(let token):
            return "Disallowed special token encountered: \(token)"
        case .invalidResource(let message):
            return "Invalid resource: \(message)"
        case .hashMismatch(let expected, let actual):
            return "Hash mismatch (expected \(expected), got \(actual))"
        case .ioFailure(let message):
            return "I/O failure: \(message)"
        }
    }
}
