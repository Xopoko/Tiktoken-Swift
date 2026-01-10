import Foundation

enum TiktokenDataLoader {
    static func loadTiktokenBPE(_ path: String, expectedHash: String? = nil) throws -> [Data: Rank] {
        let contents = try readFileCached(path, expectedHash: expectedHash)
        var ranks: [Data: Rank] = [:]
        ranks.reserveCapacity(contents.count / 8)
        for line in contents.split(separator: 0x0A) { // \n
            if line.isEmpty { continue }
            let parts = line.split(separator: 0x20)
            guard parts.count == 2 else {
                throw TiktokenError.invalidResource("Invalid line in \(path)")
            }
            guard let tokenData = Data(base64Encoded: Data(parts[0])) else {
                throw TiktokenError.invalidResource("Invalid base64 token in \(path)")
            }
            guard let rank = Int(String(decoding: parts[1], as: UTF8.self)) else {
                throw TiktokenError.invalidResource("Invalid rank in \(path)")
            }
            ranks[tokenData] = rank
        }
        return ranks
    }

    static func dataGymToMergeableBPETokens(
        vocabBpeFile: String,
        encoderJsonFile: String,
        vocabBpeHash: String? = nil,
        encoderJsonHash: String? = nil,
        clobberOneByteTokens: Bool = false
    ) throws -> [Data: Rank] {
        var rankToIntByte: [UInt8] = []
        rankToIntByte.reserveCapacity(256)
        let firstRange = Array(33...126)
        let secondRange = Array(161...172)
        let thirdRange = Array(174...255)
        rankToIntByte.append(contentsOf: firstRange.map(UInt8.init))
        rankToIntByte.append(contentsOf: secondRange.map(UInt8.init))
        rankToIntByte.append(contentsOf: thirdRange.map(UInt8.init))
        let byteSet = Set(rankToIntByte)

        var dataGymByteToByte: [UnicodeScalar: UInt8] = [:]
        dataGymByteToByte.reserveCapacity(512)
        for byte in rankToIntByte {
            dataGymByteToByte[UnicodeScalar(UInt32(byte))!] = byte
        }

        var n = 0
        for b in 0..<256 {
            let byte = UInt8(b)
            if byteSet.contains(byte) { continue }
            rankToIntByte.append(byte)
            dataGymByteToByte[UnicodeScalar(UInt32(256 + n))!] = byte
            n += 1
        }

        if rankToIntByte.count != 256 {
            throw TiktokenError.invalidResource("Invalid byte rank mapping")
        }

        let vocabData = try readFileCached(vocabBpeFile, expectedHash: vocabBpeHash)
        let vocabString = String(decoding: vocabData, as: UTF8.self)
        let lines = vocabString.split(separator: "\n", omittingEmptySubsequences: false)
        let mergeLines = lines.dropFirst().dropLast()

        func decodeDataGym(_ value: Substring) throws -> Data {
            var bytes: [UInt8] = []
            bytes.reserveCapacity(value.count)
            for scalar in value.unicodeScalars {
                guard let byte = dataGymByteToByte[scalar] else {
                    throw TiktokenError.invalidResource("Invalid data gym byte in vocab")
                }
                bytes.append(byte)
            }
            return Data(bytes)
        }

        var bpeRanks: [Data: Rank] = [:]
        bpeRanks.reserveCapacity(mergeLines.count + 256)
        for (index, byte) in rankToIntByte.enumerated() {
            bpeRanks[Data([byte])] = index
        }

        var rank = bpeRanks.count
        for line in mergeLines {
            if line.isEmpty { continue }
            let parts = line.split(separator: " ")
            if parts.count != 2 { continue }
            let first = try decodeDataGym(parts[0])
            let second = try decodeDataGym(parts[1])
            var merged = Data(first)
            merged.append(second)
            bpeRanks[merged] = rank
            rank += 1
        }

        let encoderData = try readFileCached(encoderJsonFile, expectedHash: encoderJsonHash)
        let jsonObject = try JSONSerialization.jsonObject(with: encoderData, options: [])
        guard let encoderMap = jsonObject as? [String: Int] else {
            throw TiktokenError.invalidResource("Invalid encoder.json format")
        }

        var encoderLoaded: [Data: Rank] = [:]
        encoderLoaded.reserveCapacity(encoderMap.count)
        for (key, value) in encoderMap {
            let data = try decodeDataGym(Substring(key))
            encoderLoaded[data] = value
        }
        encoderLoaded.removeValue(forKey: Data("<|endoftext|>".utf8))
        encoderLoaded.removeValue(forKey: Data("<|startoftext|>".utf8))

        if clobberOneByteTokens {
            for (data, value) in encoderLoaded where data.count == 1 {
                bpeRanks[data] = value
            }
        }

        if bpeRanks.count != encoderLoaded.count || bpeRanks != encoderLoaded {
            throw TiktokenError.invalidResource("BPE ranks mismatch with encoder.json")
        }

        return bpeRanks
    }

    static func readFileCached(_ path: String, expectedHash: String? = nil) throws -> Data {
        let env = ProcessInfo.processInfo.environment
        let cacheDir: String
        let userSpecifiedCache: Bool

        if let value = env["TIKTOKEN_CACHE_DIR"] {
            cacheDir = value
            userSpecifiedCache = true
        } else if let value = env["DATA_GYM_CACHE_DIR"] {
            cacheDir = value
            userSpecifiedCache = true
        } else {
            cacheDir = (NSTemporaryDirectory() as NSString).appendingPathComponent("data-gym-cache")
            userSpecifiedCache = false
        }

        if cacheDir.isEmpty {
            return try readFile(path)
        }

        let cacheKey = TiktokenUtils.sha1Hex(Data(path.utf8))
        let cachePath = (cacheDir as NSString).appendingPathComponent(cacheKey)
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: cachePath) {
            let data = try Data(contentsOf: URL(fileURLWithPath: cachePath))
            if let expectedHash {
                let actual = TiktokenUtils.sha256Hex(data)
                if actual == expectedHash {
                    return data
                }
                try? fileManager.removeItem(atPath: cachePath)
            } else {
                return data
            }
        }

        let contents = try readFile(path)
        if let expectedHash {
            let actual = TiktokenUtils.sha256Hex(contents)
            if actual != expectedHash {
                throw TiktokenError.hashMismatch(expected: expectedHash, actual: actual)
            }
        }

        do {
            try fileManager.createDirectory(atPath: cacheDir, withIntermediateDirectories: true, attributes: nil)
            let tmpName = cachePath + "." + UUID().uuidString + ".tmp"
            try contents.write(to: URL(fileURLWithPath: tmpName), options: .atomic)
            try? fileManager.removeItem(atPath: cachePath)
            try fileManager.moveItem(atPath: tmpName, toPath: cachePath)
        } catch {
            if userSpecifiedCache {
                throw TiktokenError.ioFailure("Failed to write cache: \(error)")
            }
        }

        return contents
    }

    static func readFile(_ path: String) throws -> Data {
        if path.contains("://") {
            guard let url = URL(string: path) else {
                throw TiktokenError.invalidResource("Invalid URL: \(path)")
            }
            if let resourceData = try? loadBundledResource(path: url.lastPathComponent) {
                return resourceData
            }
            return try Data(contentsOf: url)
        }

        if let resourceData = try? loadBundledResource(path: path) {
            return resourceData
        }

        let url = URL(fileURLWithPath: path)
        return try Data(contentsOf: url)
    }

    static func loadBundledResource(path: String) throws -> Data {
        let nsPath = path as NSString
        let ext = nsPath.pathExtension
        let name = nsPath.deletingPathExtension
        let resourceURL = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "encodings")
        guard let resourceURL else {
            throw TiktokenError.invalidResource("Resource not found for \(path)")
        }
        return try Data(contentsOf: resourceURL)
    }
}
