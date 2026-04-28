import Foundation

typealias Rank = Int

enum BytePairEncoder {
    struct Part {
        var start: Int
        var rank: Rank
    }

    private struct Merge {
        let start: Int
        let rank: Rank
    }

    private struct MergeHeap {
        private var storage: [Merge] = []

        mutating func push(_ merge: Merge) {
            storage.append(merge)
            siftUp(from: storage.count - 1)
        }

        mutating func pop() -> Merge? {
            guard !storage.isEmpty else { return nil }
            if storage.count == 1 {
                return storage.removeLast()
            }

            let result = storage[0]
            storage[0] = storage.removeLast()
            siftDown(from: 0)
            return result
        }

        private func orderedBefore(_ lhs: Merge, _ rhs: Merge) -> Bool {
            if lhs.rank != rhs.rank {
                return lhs.rank < rhs.rank
            }
            return lhs.start < rhs.start
        }

        private mutating func siftUp(from index: Int) {
            var child = index
            while child > 0 {
                let parent = (child - 1) / 2
                if !orderedBefore(storage[child], storage[parent]) {
                    break
                }
                storage.swapAt(child, parent)
                child = parent
            }
        }

        private mutating func siftDown(from index: Int) {
            var parent = index
            while true {
                let left = parent * 2 + 1
                let right = left + 1
                var candidate = parent

                if left < storage.count, orderedBefore(storage[left], storage[candidate]) {
                    candidate = left
                }
                if right < storage.count, orderedBefore(storage[right], storage[candidate]) {
                    candidate = right
                }
                if candidate == parent {
                    return
                }
                storage.swapAt(parent, candidate)
                parent = candidate
            }
        }
    }

    private struct MergeState {
        var previous: Int
        var end: Int
        var nextEnd: Int
        var nextRank: Rank
        var currentRank: Rank
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

    static func encodeSmallReference(piece: Data, ranks: [Data: Rank]) -> [Rank] {
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

    static func bytePairMergeLarge(ranks: [Data: Rank], piece: Data) -> [Rank] {
        let bytes = [UInt8](piece)
        let length = bytes.count
        precondition(length >= 2, "piece must have at least 2 bytes")

        var state: [MergeState] = []
        state.reserveCapacity(length)
        state.append(MergeState(previous: Int.max, end: 1, nextEnd: 2, nextRank: Rank.max, currentRank: Rank.max))

        var heap = MergeHeap()
        for index in 0..<(length - 1) {
            let key = Data(bytes[index..<(index + 2)])
            if let rank = ranks[key] {
                heap.push(Merge(start: index, rank: rank))
                state[index].nextRank = rank
            }

            state.append(MergeState(
                previous: index,
                end: index + 2,
                nextEnd: index + 3,
                nextRank: Rank.max,
                currentRank: Rank.max
            ))
        }

        func rankedBytes(_ start: Int, _ end: Int) -> Rank? {
            guard end <= length else { return nil }
            return ranks[Data(bytes[start..<end])]
        }

        func potentialMerge(start: Int, nextEnd: Int) {
            state[start].nextEnd = nextEnd
            state[start].nextRank = Rank.max
            if let rank = rankedBytes(start, nextEnd) {
                heap.push(Merge(start: start, rank: rank))
                state[start].nextRank = rank
            }
        }

        while let left = heap.pop() {
            if left.rank == Rank.max {
                break
            }
            if left.rank != state[left.start].nextRank {
                continue
            }

            let leftStart = left.start
            let rightStart = state[leftStart].end
            let rightEnd = state[leftStart].nextEnd
            let rightNextEnd = state[rightStart].nextEnd

            state[leftStart].currentRank = state[leftStart].nextRank
            state[leftStart].end = rightEnd
            potentialMerge(start: leftStart, nextEnd: rightNextEnd)

            if rightEnd < state.count {
                state[rightEnd].previous = leftStart
            }
            if leftStart > 0 {
                let previousStart = state[leftStart].previous
                potentialMerge(start: previousStart, nextEnd: rightEnd)
            }
            state[rightStart].nextRank = Rank.max
        }

        var tokens: [Rank] = []
        var index = 0
        while index < state.count {
            if state[index].currentRank != Rank.max {
                tokens.append(state[index].currentRank)
            } else if let rank = rankedBytes(index, state[index].end) {
                tokens.append(rank)
            }
            index = state[index].end
        }
        return tokens
    }

    static func encode(piece: Data, ranks: [Data: Rank]) -> [Rank] {
        if piece.count == 1 {
            guard let rank = ranks[piece] else {
                return []
            }
            return [rank]
        }

        if piece.count < 100 {
            return encodeSmallReference(piece: piece, ranks: ranks)
        }

        return bytePairMergeLarge(ranks: ranks, piece: piece)
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
