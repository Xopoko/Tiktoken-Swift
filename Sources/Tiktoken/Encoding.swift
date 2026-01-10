import Foundation

public enum AllowedSpecial: Sendable {
    case all
    case none
    case set(Set<String>)

    fileprivate func resolve(using specialTokens: Set<String>) -> Set<String> {
        switch self {
        case .all:
            return specialTokens
        case .none:
            return []
        case .set(let tokens):
            return tokens
        }
    }
}

public enum DisallowedSpecial: Sendable {
    case all
    case none
    case set(Set<String>)

    fileprivate func resolve(using specialTokens: Set<String>, allowed: Set<String>) -> Set<String> {
        switch self {
        case .all:
            return specialTokens.subtracting(allowed)
        case .none:
            return []
        case .set(let tokens):
            return tokens
        }
    }
}

public enum DecodeErrorMode: Sendable {
    case replace
    case strict
    case ignore
}

public struct Encoding: CustomStringConvertible, @unchecked Sendable {
    public let name: String
    public let maxTokenValue: Int
    public let nVocab: Int
    public let specialTokens: [String: Int]
    public let specialTokensSet: Set<String>
    public let eotToken: Int?

    private let coreBPE: CoreBPE
    private let patStr: String

    init(definition: EncodingDefinition) throws {
        self.name = definition.name
        self.specialTokens = definition.specialTokens
        self.specialTokensSet = Set(definition.specialTokens.keys)
        self.patStr = definition.patStr

        let mergeableMax = definition.mergeableRanks.values.max() ?? 0
        let specialMax = definition.specialTokens.values.max() ?? 0
        self.maxTokenValue = max(mergeableMax, specialMax)

        if let explicit = definition.explicitNVocab {
            if definition.mergeableRanks.count + definition.specialTokens.count != explicit {
                throw TiktokenError.invalidResource("Explicit n_vocab mismatch for \(definition.name)")
            }
            if self.maxTokenValue != explicit - 1 {
                throw TiktokenError.invalidResource("Explicit n_vocab max token mismatch for \(definition.name)")
            }
            self.nVocab = explicit
        } else {
            self.nVocab = self.maxTokenValue + 1
        }

        self.eotToken = definition.specialTokens["<|endoftext|>"]
        self.coreBPE = try CoreBPE(encoder: definition.mergeableRanks, specialTokensEncoder: definition.specialTokens, pattern: definition.patStr)
    }

    public var description: String { "<Encoding \(name)>" }

    public func encodeOrdinary(_ text: String) -> [Int] {
        return coreBPE.encodeOrdinary(text)
    }

    public func encodeOrdinary(_ text: String, metrics: inout EncodingMetrics) -> [Int] {
        return coreBPE.encodeOrdinary(text, metrics: &metrics)
    }

    public func encode(
        _ text: String,
        allowedSpecial: AllowedSpecial = .none,
        disallowedSpecial: DisallowedSpecial = .all
    ) throws -> [Int] {
        var metrics: EncodingMetrics? = nil
        return try encodeInternal(text, allowedSpecial: allowedSpecial, disallowedSpecial: disallowedSpecial, metrics: &metrics)
    }

    public func encode(
        _ text: String,
        allowedSpecial: AllowedSpecial = .none,
        disallowedSpecial: DisallowedSpecial = .all,
        metrics: inout EncodingMetrics
    ) throws -> [Int] {
        var metricsOptional: EncodingMetrics? = metrics
        let tokens = try encodeInternal(text, allowedSpecial: allowedSpecial, disallowedSpecial: disallowedSpecial, metrics: &metricsOptional)
        if let updated = metricsOptional {
            metrics = updated
        }
        return tokens
    }

    public func encodeWithUnstable(
        _ text: String,
        allowedSpecial: AllowedSpecial = .none,
        disallowedSpecial: DisallowedSpecial = .all
    ) throws -> (stableTokens: [Int], completions: [[Int]]) {
        let allowed = allowedSpecial.resolve(using: specialTokensSet)
        let disallowed = disallowedSpecial.resolve(using: specialTokensSet, allowed: allowed)
        if !disallowed.isEmpty {
            try throwIfDisallowed(text: text, disallowed: disallowed)
        }
        return try coreBPE.encodeWithUnstable(text, allowedSpecial: allowed)
    }

    public func encodeSingleToken(_ text: String) throws -> Int {
        return try encodeSingleTokenBytes(Data(text.utf8))
    }

    public func encodeSingleTokenBytes(_ bytes: Data) throws -> Int {
        return try coreBPE.encodeSingleToken(bytes)
    }

    public func encodeSinglePiece(_ text: String) -> [Int] {
        return coreBPE.encodeSinglePiece(Data(text.utf8))
    }

    public func encodeSinglePieceBytes(_ bytes: Data) -> [Int] {
        return coreBPE.encodeSinglePiece(bytes)
    }

    public func encodeBytes(_ bytes: Data) throws -> [Int] {
        return try coreBPE.encodeBytes(bytes)
    }

    public func decodeBytes(_ tokens: [Int]) throws -> Data {
        return try coreBPE.decodeBytes(tokens)
    }

    public func decode(_ tokens: [Int], errors: DecodeErrorMode = .replace) throws -> String {
        let bytes = try decodeBytes(tokens)
        switch errors {
        case .replace:
            return String(decoding: bytes, as: UTF8.self)
        case .strict:
            if let string = String(data: bytes, encoding: .utf8) {
                return string
            }
            throw TiktokenError.decodeFailure("Invalid UTF-8 sequence")
        case .ignore:
            return Utf8Decoder.decodeIgnoringInvalid(bytes)
        }
    }

    public func decodeSingleTokenBytes(_ token: Int) throws -> Data {
        return try coreBPE.decodeSingleTokenBytes(token)
    }

    public func encodeBatch(
        _ texts: [String],
        numThreads: Int = 8,
        allowedSpecial: AllowedSpecial = .none,
        disallowedSpecial: DisallowedSpecial = .all
    ) throws -> [[Int]] {
        let allowed = allowedSpecial.resolve(using: specialTokensSet)
        let disallowed = disallowedSpecial.resolve(using: specialTokensSet, allowed: allowed)
        if !disallowed.isEmpty {
            for text in texts {
                try throwIfDisallowed(text: text, disallowed: disallowed)
            }
        }

        let resultsBox = LockedBox(Array(repeating: [Int](), count: texts.count))
        let queue = DispatchQueue(label: "tiktoken.encode.batch", attributes: .concurrent)
        let group = DispatchGroup()
        let chunkSize = max(1, texts.count / max(1, numThreads))
        let errorBox = LockedBox<Error?>(nil)

        for chunkStart in stride(from: 0, to: texts.count, by: chunkSize) {
            group.enter()
            queue.async {
                let chunkEnd = min(chunkStart + chunkSize, texts.count)
                for idx in chunkStart..<chunkEnd {
                    do {
                        let tokens = try self.coreBPE.encode(texts[idx], allowedSpecial: allowed).tokens
                        resultsBox.withValue { results in
                            results[idx] = tokens
                        }
                    } catch {
                        errorBox.withValue { stored in
                            if stored == nil {
                                stored = error
                            }
                        }
                    }
                }
                group.leave()
            }
        }

        group.wait()
        if let error = errorBox.withValue({ $0 }) {
            throw error
        }
        return resultsBox.withValue { $0 }
    }

    public func encodeOrdinaryBatch(_ texts: [String], numThreads: Int = 8) -> [[Int]] {
        if texts.isEmpty { return [] }
        let resultsBox = LockedBox(Array(repeating: [Int](), count: texts.count))
        let queue = DispatchQueue(label: "tiktoken.encode.ordinary.batch", attributes: .concurrent)
        let group = DispatchGroup()
        let chunkSize = max(1, texts.count / max(1, numThreads))

        for chunkStart in stride(from: 0, to: texts.count, by: chunkSize) {
            group.enter()
            queue.async {
                let chunkEnd = min(chunkStart + chunkSize, texts.count)
                for idx in chunkStart..<chunkEnd {
                    let tokens = self.coreBPE.encodeOrdinary(texts[idx])
                    resultsBox.withValue { results in
                        results[idx] = tokens
                    }
                }
                group.leave()
            }
        }

        group.wait()
        return resultsBox.withValue { $0 }
    }

    private func encodeInternal(
        _ text: String,
        allowedSpecial: AllowedSpecial,
        disallowedSpecial: DisallowedSpecial,
        metrics: inout EncodingMetrics?
    ) throws -> [Int] {
        let allowed = allowedSpecial.resolve(using: specialTokensSet)
        let disallowed = disallowedSpecial.resolve(using: specialTokensSet, allowed: allowed)
        if !disallowed.isEmpty {
            try throwIfDisallowed(text: text, disallowed: disallowed)
        }

        if let metricsValue = metrics {
            var localMetrics = metricsValue
            let tokens = try coreBPE.encode(text, allowedSpecial: allowed, metrics: &localMetrics).tokens
            metrics = localMetrics
            return tokens
        }
        return try coreBPE.encode(text, allowedSpecial: allowed).tokens
    }

    private func throwIfDisallowed(text: String, disallowed: Set<String>) throws {
        guard !disallowed.isEmpty else { return }
        let regex = try SpecialTokenRegexCache.shared.regex(for: disallowed)
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        if let match = regex.firstMatch(in: text, range: range) {
            let token = nsText.substring(with: match.range)
            throw TiktokenError.disallowedSpecialToken(token)
        }
    }
}

struct EncodingDefinition {
    let name: String
    let patStr: String
    let mergeableRanks: [Data: Rank]
    let specialTokens: [String: Rank]
    let explicitNVocab: Int?
}

final class SpecialTokenRegexCache: @unchecked Sendable {
    static let shared = SpecialTokenRegexCache()
    private var cache: [String: NSRegularExpression] = [:]
    private let lock = NSLock()

    func regex(for tokens: Set<String>) throws -> NSRegularExpression {
        if tokens.isEmpty {
            return try NSRegularExpression(pattern: "(?!x)x", options: [])
        }
        let key = tokens.sorted().joined(separator: "\u{0}")
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let pattern = tokens.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let regex = try NSRegularExpression(pattern: pattern, options: [])
        cache[key] = regex
        return regex
    }
}
