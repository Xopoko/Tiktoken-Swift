import Foundation

final class CoreBPE: @unchecked Sendable {
    private let encoder: [Data: Rank]
    private let specialTokensEncoder: [String: Rank]
    private let decoder: [Rank: Data]
    private let specialTokensDecoder: [Rank: Data]
    private let regex: NSRegularExpression
    private let specialRegex: NSRegularExpression
    private let sortedTokenBytes: [Data]

    init(encoder: [Data: Rank], specialTokensEncoder: [String: Rank], pattern: String) throws {
        self.encoder = encoder
        self.specialTokensEncoder = specialTokensEncoder

        self.regex = try NSRegularExpression(pattern: pattern, options: [])

        if specialTokensEncoder.isEmpty {
            self.specialRegex = try NSRegularExpression(pattern: "(?!x)x", options: [])
        } else {
            let escaped = specialTokensEncoder.keys.map { NSRegularExpression.escapedPattern(for: $0) }
            let specialPattern = escaped.joined(separator: "|")
            self.specialRegex = try NSRegularExpression(pattern: specialPattern, options: [])
        }

        var decoder: [Rank: Data] = [:]
        decoder.reserveCapacity(encoder.count)
        for (bytes, token) in encoder {
            decoder[token] = bytes
        }
        if decoder.count != encoder.count {
            throw TiktokenError.invalidResource("Encoder and decoder must be of equal length. Duplicate token indices in encoder?")
        }
        self.decoder = decoder

        var specialDecoder: [Rank: Data] = [:]
        specialDecoder.reserveCapacity(specialTokensEncoder.count)
        for (tokenString, tokenValue) in specialTokensEncoder {
            specialDecoder[tokenValue] = Data(tokenString.utf8)
        }
        self.specialTokensDecoder = specialDecoder

        var sortedBytes = Array(encoder.keys)
        sortedBytes.sort { $0.lexicographicallyPrecedes($1) }
        self.sortedTokenBytes = sortedBytes
    }

    func specialTokens() -> Set<String> {
        return Set(specialTokensEncoder.keys)
    }

    func encodeOrdinary(_ text: String) -> [Rank] {
        return encodeOrdinaryInternal(text, metrics: nil)
    }

    func encodeOrdinary(_ text: String, metrics: inout EncodingMetrics) -> [Rank] {
        return encodeOrdinaryInternal(text, metrics: &metrics)
    }

    private func encodeOrdinaryInternal(_ text: String, metrics: UnsafeMutablePointer<EncodingMetrics>?) -> [Rank] {
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        let matches = regex.matches(in: text, range: fullRange)

        var tokens: [Rank] = []
        for match in matches {
            if match.range.length == 0 { continue }
            let piece = nsText.substring(with: match.range)
            let pieceBytes = Data(piece.utf8)
            metrics?.pointee.regexMatches += 1
            metrics?.pointee.inputBytes += pieceBytes.count

            if let token = encoder[pieceBytes] {
                tokens.append(token)
                metrics?.pointee.directTokenHits += 1
            } else {
                let encoded = BytePairEncoder.encode(piece: pieceBytes, ranks: encoder)
                tokens.append(contentsOf: encoded)
                metrics?.pointee.bpeMerges += encoded.count
            }
        }
        metrics?.pointee.tokensProduced += tokens.count
        return tokens
    }

    func encode(_ text: String, allowedSpecial: Set<String>) throws -> (tokens: [Rank], lastPieceTokenLen: Int) {
        return try encodeInternal(text, allowedSpecial: allowedSpecial, metrics: nil)
    }

    func encode(_ text: String, allowedSpecial: Set<String>, metrics: inout EncodingMetrics) throws -> (tokens: [Rank], lastPieceTokenLen: Int) {
        return try encodeInternal(text, allowedSpecial: allowedSpecial, metrics: &metrics)
    }

    private func encodeInternal(_ text: String, allowedSpecial: Set<String>, metrics: UnsafeMutablePointer<EncodingMetrics>?) throws -> (tokens: [Rank], lastPieceTokenLen: Int) {
        if allowedSpecial.isEmpty {
            return (encodeOrdinaryInternal(text, metrics: metrics), 0)
        }

        let nsText = text as NSString
        let textLength = nsText.length

        var tokens: [Rank] = []
        var start = 0
        var lastPieceTokenLen = 0

        while start < textLength {
            let nextSpecial = findNextSpecial(in: text, start: start, allowedSpecial: allowedSpecial)
            let end = nextSpecial?.range.location ?? textLength

            if end > start {
                let range = NSRange(location: start, length: end - start)
                let segmentMatches = regex.matches(in: text, range: range)
                for match in segmentMatches {
                    if match.range.length == 0 { continue }
                    let piece = nsText.substring(with: match.range)
                    let pieceBytes = Data(piece.utf8)
                    metrics?.pointee.regexMatches += 1
                    metrics?.pointee.inputBytes += pieceBytes.count

                    if let token = encoder[pieceBytes] {
                        tokens.append(token)
                        lastPieceTokenLen = 1
                        metrics?.pointee.directTokenHits += 1
                    } else {
                        let encoded = BytePairEncoder.encode(piece: pieceBytes, ranks: encoder)
                        tokens.append(contentsOf: encoded)
                        lastPieceTokenLen = encoded.count
                        metrics?.pointee.bpeMerges += encoded.count
                    }
                }
            }

            guard let special = nextSpecial else { break }
            let tokenString = nsText.substring(with: special.range)
            guard let token = specialTokensEncoder[tokenString] else {
                throw TiktokenError.encodeFailure("Missing special token mapping for \(tokenString)")
            }
            tokens.append(token)
            metrics?.pointee.specialTokens += 1
            start = special.range.location + special.range.length
            lastPieceTokenLen = 0
        }

        metrics?.pointee.tokensProduced += tokens.count
        return (tokens, lastPieceTokenLen)
    }

    func encodeWithSpecialTokens(_ text: String) throws -> [Rank] {
        let allowed = specialTokens()
        return try encode(text, allowedSpecial: allowed).tokens
    }

    func encodeSingleToken(_ bytes: Data) throws -> Rank {
        if let token = encoder[bytes] {
            return token
        }
        if let pieceString = String(data: bytes, encoding: .utf8) {
            if let token = specialTokensEncoder[pieceString] {
                return token
            }
        }
        throw TiktokenError.invalidTokenBytes
    }

    func encodeSinglePiece(_ bytes: Data) -> [Rank] {
        if let token = encoder[bytes] {
            return [token]
        }
        return BytePairEncoder.encode(piece: bytes, ranks: encoder)
    }

    func decodeBytes(_ tokens: [Rank]) throws -> Data {
        var output = Data()
        output.reserveCapacity(tokens.count * 2)
        for token in tokens {
            if let bytes = decoder[token] {
                output.append(bytes)
            } else if let bytes = specialTokensDecoder[token] {
                output.append(bytes)
            } else {
                throw TiktokenError.invalidToken(token)
            }
        }
        return output
    }

    func decodeSingleTokenBytes(_ token: Rank) throws -> Data {
        if let bytes = decoder[token] {
            return bytes
        }
        if let bytes = specialTokensDecoder[token] {
            return bytes
        }
        throw TiktokenError.invalidToken(token)
    }

    func encodeBytes(_ bytes: Data) throws -> [Rank] {
        if let text = String(data: bytes, encoding: .utf8) {
            return encodeOrdinary(text)
        }

        let rawBytes = [UInt8](bytes)
        let validUpTo = Utf8Validator.validPrefixLength(rawBytes)
        let prefixBytes = Array(rawBytes[0..<validUpTo])
        let suffixBytes = Array(rawBytes[validUpTo..<rawBytes.count])

        let prefixText = String(decoding: prefixBytes, as: UTF8.self)
        var (tokens, lastPieceTokenLen) = try encode(prefixText, allowedSpecial: [])
        let adjusted = increaseLastPieceTokenLen(tokens: tokens, lastPieceTokenLen: lastPieceTokenLen)
        tokens = adjusted.tokens
        lastPieceTokenLen = adjusted.lastPieceTokenLen

        var unstableBytes = Data(suffixBytes)
        if !tokens.isEmpty && lastPieceTokenLen > 0 {
            let tailStart = tokens.count - lastPieceTokenLen
            let tailTokens = Array(tokens[tailStart..<tokens.count])
            var decodedTail = try decodeBytes(tailTokens)
            decodedTail.append(contentsOf: suffixBytes)
            unstableBytes = decodedTail
            tokens.removeLast(lastPieceTokenLen)
        }

        if !unstableBytes.isEmpty {
            if let token = encoder[unstableBytes] {
                tokens.append(token)
            } else {
                tokens.append(contentsOf: BytePairEncoder.encode(piece: unstableBytes, ranks: encoder))
            }
        }

        return tokens
    }

    func encodeWithUnstable(_ text: String, allowedSpecial: Set<String>) throws -> (stableTokens: [Rank], completions: [[Rank]]) {
        var (tokens, lastPieceTokenLen) = try encode(text, allowedSpecial: allowedSpecial)
        if lastPieceTokenLen == 0 {
            return (tokens, [])
        }

        let adjusted = increaseLastPieceTokenLen(tokens: tokens, lastPieceTokenLen: lastPieceTokenLen)
        tokens = adjusted.tokens
        lastPieceTokenLen = adjusted.lastPieceTokenLen

        let unstableSliceStart = tokens.count - lastPieceTokenLen
        let unstableTokens = Array(tokens[unstableSliceStart..<tokens.count])
        let unstableBytes = try decodeBytes(unstableTokens)
        tokens.removeLast(lastPieceTokenLen)

        if unstableBytes.isEmpty {
            return (tokens, [])
        }

        var completions = Set<TokenSequence>()

        var point = partitionPoint(sortedTokenBytes) { $0.lexicographicallyPrecedes(unstableBytes) }
        while point < sortedTokenBytes.count && sortedTokenBytes[point].starts(with: unstableBytes) {
            if let token = encoder[sortedTokenBytes[point]] {
                completions.insert(TokenSequence(tokens: [token]))
            }
            point += 1
        }

        if unstableBytes.count > 1 {
            for splitIndex in 1..<unstableBytes.count {
                let prefix = unstableBytes.slice(0, splitIndex)
                let suffix = unstableBytes.slice(splitIndex, unstableBytes.count)

                var suffixPoint = partitionPoint(sortedTokenBytes) { $0.lexicographicallyPrecedes(suffix) }
                while suffixPoint < sortedTokenBytes.count && sortedTokenBytes[suffixPoint].starts(with: suffix) {
                    var possibility = Data(prefix)
                    possibility.append(sortedTokenBytes[suffixPoint])

                    let encoded: [Rank]
                    if let string = String(data: possibility, encoding: .utf8) {
                        encoded = encodeOrdinary(string)
                    } else {
                        encoded = BytePairEncoder.encode(piece: possibility, ranks: encoder)
                    }

                    var seq: [Rank] = []
                    var seqLen = 0
                    for token in encoded {
                        seq.append(token)
                        if let bytes = decoder[token] {
                            seqLen += bytes.count
                        }
                        if seqLen >= unstableBytes.count {
                            break
                        }
                    }
                    completions.insert(TokenSequence(tokens: seq))
                    suffixPoint += 1
                }
            }

            let lastDecoded = Utf8Validator.decodeLastScalar(unstableBytes)
            if lastDecoded.length > 0, let scalar = lastDecoded.scalar, scalar.properties.isWhitespace {
                let prefix = unstableBytes.slice(0, unstableBytes.count - lastDecoded.length)
                let suffix = unstableBytes.slice(unstableBytes.count - lastDecoded.length, unstableBytes.count)

                var reencoded = BytePairEncoder.encode(piece: prefix, ranks: encoder)
                reencoded.append(contentsOf: BytePairEncoder.encode(piece: suffix, ranks: encoder))
                completions.insert(TokenSequence(tokens: reencoded))
            }
        }

        return (tokens, completions.map { $0.tokens })
    }

    private func findNextSpecial(in text: String, start: Int, allowedSpecial: Set<String>) -> NSTextCheckingResult? {
        let nsText = text as NSString
        var searchStart = start
        while searchStart < nsText.length {
            let range = NSRange(location: searchStart, length: nsText.length - searchStart)
            guard let match = specialRegex.firstMatch(in: text, range: range) else {
                return nil
            }
            let tokenString = nsText.substring(with: match.range)
            if allowedSpecial.contains(tokenString) {
                return match
            }
            searchStart = match.range.location + 1
        }
        return nil
    }

    private func increaseLastPieceTokenLen(tokens: [Rank], lastPieceTokenLen: Int) -> (tokens: [Rank], lastPieceTokenLen: Int) {
        var lastPieceTokenLen = lastPieceTokenLen
        if lastPieceTokenLen == 0 || tokens.isEmpty {
            return (tokens, lastPieceTokenLen)
        }

        func tokenIsAllSpace(_ token: Rank) -> Bool {
            guard let bytes = decoder[token] else { return false }
            for byte in bytes.reversed() {
                if byte != 0x20 && byte != 0x0A && byte != 0x09 {
                    return false
                }
            }
            return true
        }

        if tokenIsAllSpace(tokens[tokens.count - lastPieceTokenLen]) {
            while lastPieceTokenLen < tokens.count && tokenIsAllSpace(tokens[tokens.count - lastPieceTokenLen - 1]) {
                lastPieceTokenLen += 1
            }
        }

        return (tokens, lastPieceTokenLen)
    }

    private func partitionPoint(_ array: [Data], predicate: (Data) -> Bool) -> Int {
        var low = 0
        var high = array.count
        while low < high {
            let mid = (low + high) / 2
            if predicate(array[mid]) {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

struct TokenSequence: Hashable {
    let tokens: [Rank]

    func hash(into hasher: inout Hasher) {
        hasher.combine(tokens.count)
        for token in tokens {
            hasher.combine(token)
        }
    }

    static func == (lhs: TokenSequence, rhs: TokenSequence) -> Bool {
        return lhs.tokens == rhs.tokens
    }
}

enum Utf8Validator {
    static func validPrefixLength(_ bytes: [UInt8]) -> Int {
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                index += 1
                continue
            }
            if byte < 0xC2 {
                return index
            } else if byte < 0xE0 {
                if index + 1 >= bytes.count { return index }
                if !isContinuation(bytes[index + 1]) { return index }
                index += 2
            } else if byte < 0xF0 {
                if index + 2 >= bytes.count { return index }
                let b1 = bytes[index + 1]
                let b2 = bytes[index + 2]
                if !isContinuation(b1) || !isContinuation(b2) { return index }
                if byte == 0xE0 && b1 < 0xA0 { return index }
                if byte == 0xED && b1 >= 0xA0 { return index }
                index += 3
            } else if byte < 0xF5 {
                if index + 3 >= bytes.count { return index }
                let b1 = bytes[index + 1]
                let b2 = bytes[index + 2]
                let b3 = bytes[index + 3]
                if !isContinuation(b1) || !isContinuation(b2) || !isContinuation(b3) { return index }
                if byte == 0xF0 && b1 < 0x90 { return index }
                if byte == 0xF4 && b1 >= 0x90 { return index }
                index += 4
            } else {
                return index
            }
        }
        return bytes.count
    }

    static func decodeLastScalar(_ bytes: Data) -> (scalar: UnicodeScalar?, length: Int) {
        guard !bytes.isEmpty else { return (nil, 0) }
        let array = [UInt8](bytes)
        var start = array.count - 1
        var length = 1
        while start > 0 && isContinuation(array[start]) && length < 4 {
            start -= 1
            length += 1
        }

        let slice = Array(array[start..<array.count])
        if let string = String(bytes: slice, encoding: .utf8), let scalar = string.unicodeScalars.first {
            return (scalar, slice.count)
        }
        return (nil, 1)
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        return (byte & 0xC0) == 0x80
    }
}
