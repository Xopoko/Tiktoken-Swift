import Foundation

public struct EncodingMetrics: Sendable {
    public var inputBytes: Int = 0
    public var regexMatches: Int = 0
    public var directTokenHits: Int = 0
    public var bpeMerges: Int = 0
    public var specialTokens: Int = 0
    public var tokensProduced: Int = 0

    public init() {}
}
