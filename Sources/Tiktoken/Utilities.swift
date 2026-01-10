import Foundation
import CryptoKit

enum TiktokenUtils {
    static func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha1Hex(_ data: Data) -> String {
        let digest = Insecure.SHA1.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func isPrintable(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .surrogate, .privateUse, .unassigned:
            return false
        default:
            return true
        }
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T

    init(_ value: T) {
        self.value = value
    }

    func withValue<R>(_ body: (inout T) throws -> R) rethrows -> R {
        lock.lock()
        defer { lock.unlock() }
        return try body(&value)
    }
}

extension Data {
    func slice(_ start: Int, _ end: Int) -> Data {
        return subdata(in: start..<end)
    }

    func starts(with other: Data) -> Bool {
        guard count >= other.count else { return false }
        return prefix(other.count) == other
    }
}

extension Array where Element == UInt8 {
    func dataSlice(_ start: Int, _ end: Int) -> Data {
        return Data(self[start..<end])
    }
}
