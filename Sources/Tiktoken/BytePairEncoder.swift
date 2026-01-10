import Foundation

typealias Rank = Int

enum BytePairEncoder {
    struct Part {
        var start: Int
        var rank: Rank
    }

    static func bytePairMerge(ranks: [Data: Rank], piece: Data) -> [Part] {
        let bytes = [UInt8](piece)
        let length = bytes.count
        precondition(length >= 2, "piece must have at least 2 bytes")

        var parts: [Part] = []
        parts.reserveCapacity(length + 1)

        var minRank: (rank: Rank, index: Int) = (Rank.max, Int.max)
        for i in 0..<(length - 1) {
            let key = Data(bytes[i..<(i + 2)])
            let rank = ranks[key] ?? Rank.max
            if rank < minRank.rank {
                minRank = (rank, i)
            }
            parts.append(Part(start: i, rank: rank))
        }

        parts.append(Part(start: length - 1, rank: Rank.max))
        parts.append(Part(start: length, rank: Rank.max))

        func getRank(_ parts: [Part], _ i: Int) -> Rank {
            if (i + 3) < parts.count {
                let start = parts[i].start
                let end = parts[i + 3].start
                let key = Data(bytes[start..<end])
                return ranks[key] ?? Rank.max
            }
            return Rank.max
        }

        while minRank.rank != Rank.max {
            let i = minRank.index
            if i > 0 {
                parts[i - 1].rank = getRank(parts, i - 1)
            }
            parts[i].rank = getRank(parts, i)
            parts.remove(at: i + 1)

            minRank = (Rank.max, Int.max)
            for (index, part) in parts[..<(parts.count - 1)].enumerated() {
                if part.rank < minRank.rank {
                    minRank = (part.rank, index)
                }
            }
        }

        return parts
    }

    static func encode(piece: Data, ranks: [Data: Rank]) -> [Rank] {
        if piece.count == 1 {
            guard let rank = ranks[piece] else {
                return []
            }
            return [rank]
        }

        let parts = bytePairMerge(ranks: ranks, piece: piece)
        guard parts.count >= 2 else { return [] }

        var tokens: [Rank] = []
        tokens.reserveCapacity(parts.count - 1)
        for idx in 0..<(parts.count - 1) {
            let start = parts[idx].start
            let end = parts[idx + 1].start
            let tokenBytes = piece.slice(start, end)
            if let rank = ranks[tokenBytes] {
                tokens.append(rank)
            }
        }
        return tokens
    }

    static func split(piece: Data, ranks: [Data: Rank]) -> [Data] {
        let parts = bytePairMerge(ranks: ranks, piece: piece)
        guard parts.count >= 2 else { return [] }
        return (0..<(parts.count - 1)).map { idx in
            let start = parts[idx].start
            let end = parts[idx + 1].start
            return piece.slice(start, end)
        }
    }
}
