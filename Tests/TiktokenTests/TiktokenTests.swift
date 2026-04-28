import XCTest
@testable import Tiktoken

final class TiktokenTests: XCTestCase {
    func testSimpleEncodings() throws {
        let gpt2 = try Tiktoken.getEncoding("gpt2")
        XCTAssertEqual(gpt2.encodeOrdinary("hello world"), [31373, 995])
        XCTAssertEqual(try gpt2.decode([31373, 995]), "hello world")
        XCTAssertEqual(try gpt2.encode("hello <|endoftext|>", allowedSpecial: .all), [31373, 220, 50256])

        let cl100k = try Tiktoken.getEncoding("cl100k_base")
        XCTAssertEqual(cl100k.encodeOrdinary("hello world"), [15339, 1917])
        XCTAssertEqual(try cl100k.decode([15339, 1917]), "hello world")
        XCTAssertEqual(try cl100k.encode("hello <|endoftext|>", allowedSpecial: .all), [15339, 220, 100257])
    }

    func testEncodeRepeatedZeros() throws {
        let enc = try Tiktoken.getEncoding("gpt2")
        XCTAssertEqual(try enc.encode("0"), [15])
        XCTAssertEqual(try enc.encode("00"), [405])
        XCTAssertEqual(try enc.encode("000"), [830])
        XCTAssertEqual(try enc.encode("0000"), [2388])
        XCTAssertEqual(try enc.encode("00000"), [20483])
        XCTAssertEqual(try enc.encode("000000"), [10535])
        XCTAssertEqual(try enc.encode("0000000"), [24598])
        XCTAssertEqual(try enc.encode("00000000"), [8269])
        XCTAssertEqual(try enc.encode("000000000"), [10535, 830])
        XCTAssertEqual(try enc.encode("0000000000"), [8269, 405])
        XCTAssertEqual(try enc.encode("00000000000"), [8269, 830])
        XCTAssertEqual(try enc.encode("000000000000"), [8269, 2388])
        XCTAssertEqual(try enc.encode("0000000000000"), [8269, 20483])
        XCTAssertEqual(try enc.encode("00000000000000"), [8269, 10535])
        XCTAssertEqual(try enc.encode("000000000000000"), [8269, 24598])
        XCTAssertEqual(try enc.encode("0000000000000000"), [25645])
        XCTAssertEqual(try enc.encode("00000000000000000"), [8269, 10535, 830])
    }

    func testRegexParityCases() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        XCTAssertEqual(try enc.encode("rer"), [38149])
        XCTAssertEqual(try enc.encode("'rer"), [2351, 81])
        XCTAssertEqual(try enc.encode("today\n "), [31213, 198, 220])
        XCTAssertEqual(try enc.encode("today\n \n"), [31213, 27907])
        XCTAssertEqual(try enc.encode("today\n  \n"), [31213, 14211])
    }

    func testSpecialTokenDisallowed() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        let eot = try enc.encodeSingleToken("<|endoftext|>")
        let fimPrefix = try enc.encodeSingleToken("<|fim_prefix|>")
        let fimMiddle = try enc.encodeSingleToken("<|fim_middle|>")
        let text = "<|endoftext|> hello <|fim_prefix|>"
        XCTAssertThrowsError(try enc.encode(text))
        XCTAssertThrowsError(try enc.encode(text, disallowedSpecial: .all))
        XCTAssertThrowsError(try enc.encode(text, disallowedSpecial: .set(["<|endoftext|>"])))
        XCTAssertThrowsError(try enc.encode(text, disallowedSpecial: .set(["<|fim_prefix|>"])))
        XCTAssertNoThrow(try enc.encode(text, disallowedSpecial: .none))

        let mixedText = "<|endoftext|> hello <|fim_prefix|> there <|fim_middle|>"
        let ordinaryTokens = try enc.encode(mixedText, disallowedSpecial: .none)
        XCTAssertFalse(ordinaryTokens.contains(eot))
        XCTAssertFalse(ordinaryTokens.contains(fimPrefix))
        XCTAssertFalse(ordinaryTokens.contains(fimMiddle))

        let allAllowed = try enc.encode(mixedText, allowedSpecial: .all, disallowedSpecial: .none)
        XCTAssertTrue(allAllowed.contains(eot))
        XCTAssertTrue(allAllowed.contains(fimPrefix))
        XCTAssertTrue(allAllowed.contains(fimMiddle))

        let allAllowedAndDisallowed = try enc.encode(mixedText, allowedSpecial: .all, disallowedSpecial: .all)
        XCTAssertTrue(allAllowedAndDisallowed.contains(eot))
        XCTAssertTrue(allAllowedAndDisallowed.contains(fimPrefix))
        XCTAssertTrue(allAllowedAndDisallowed.contains(fimMiddle))

        let fimPrefixOnly = try enc.encode(mixedText, allowedSpecial: .set(["<|fim_prefix|>"]), disallowedSpecial: .none)
        XCTAssertFalse(fimPrefixOnly.contains(eot))
        XCTAssertTrue(fimPrefixOnly.contains(fimPrefix))
        XCTAssertFalse(fimPrefixOnly.contains(fimMiddle))

        let eotOnly = try enc.encode(mixedText, allowedSpecial: .set(["<|endoftext|>"]), disallowedSpecial: .none)
        XCTAssertTrue(eotOnly.contains(eot))
        XCTAssertFalse(eotOnly.contains(fimPrefix))
        XCTAssertFalse(eotOnly.contains(fimMiddle))

        let fimMiddleOnly = try enc.encode(mixedText, allowedSpecial: .set(["<|fim_middle|>"]), disallowedSpecial: .none)
        XCTAssertFalse(fimMiddleOnly.contains(eot))
        XCTAssertFalse(fimMiddleOnly.contains(fimPrefix))
        XCTAssertTrue(fimMiddleOnly.contains(fimMiddle))
    }

    func testEncodeDecodeRoundtrip() throws {
        let encodings = Tiktoken.listEncodingNames()
        let samples = [
            "hello",
            "hello ",
            "hello  ",
            " hello",
            " hello ",
            "hello world",
            "请考试我的软件！12345"
        ]
        for name in encodings {
            let enc = try Tiktoken.getEncoding(name)
            for sample in samples {
                let tokens = try enc.encode(sample)
                XCTAssertEqual(try enc.decode(tokens), sample)
            }
        }
    }

    func testEncodeBytesRoundtrip() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        XCTAssertEqual(try enc.encodeBytes(Data([0x20, 0xec, 0x8b, 0xa4, 0xed])), [62085])
        for length in 0..<32 {
            let bytes = [UInt8](repeating: 0x80, count: length)
            let data = Data(bytes)
            let tokens = try enc.encodeBytes(data)
            let decoded = try enc.decodeBytes(tokens)
            XCTAssertEqual(decoded, data)
        }
    }

    func testEncodeSingleTokenRoundtrip() throws {
        let enc = try Tiktoken.getEncoding("gpt2")
        for token in 0..<10_000 {
            let bytes = try enc.decodeSingleTokenBytes(token)
            let roundtrip = try enc.encodeSingleTokenBytes(bytes)
            XCTAssertEqual(roundtrip, token)
        }
    }

    func testEncodingForModel() throws {
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt2"), "gpt2")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "text-davinci-003"), "p50k_base")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "text-davinci-edit-001"), "p50k_edit")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt-3.5-turbo-0301"), "cl100k_base")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt-4"), "cl100k_base")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt-4o"), "o200k_base")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt-5"), "o200k_base")
        XCTAssertEqual(try Tiktoken.encodingName(forModel: "gpt-oss-120b"), "o200k_harmony")
    }

    func testEncodeBatchMatchesSequential() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        let texts = ["hello world", "goodbye world", "こんにちは世界"]
        let batch = try enc.encodeBatch(texts)
        let sequential = try texts.map { try enc.encode($0) }
        XCTAssertEqual(batch, sequential)
    }

    func testDecodeBatchMatchesSequential() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        let texts = ["hello world", "goodbye world", "こんにちは世界"]
        let encoded = try enc.encodeBatch(texts)

        XCTAssertEqual(try enc.decodeBatch(encoded), texts)
        XCTAssertEqual(try enc.decodeBytesBatch(encoded), try encoded.map { try enc.decodeBytes($0) })
    }

    func testDecodeTokensBytesAndTokenInspection() throws {
        let enc = try Tiktoken.getEncoding("gpt2")

        XCTAssertEqual(try enc.decodeTokensBytes([31373, 995]), [Data("hello".utf8), Data(" world".utf8)])
        XCTAssertEqual(try enc.decodeSingleTokenBytes(31373), Data("hello".utf8))
        XCTAssertTrue(enc.tokenByteValues().contains(Data("hello".utf8)))
        XCTAssertTrue(enc.isSpecialToken(enc.eotToken ?? -1))
        XCTAssertFalse(enc.isSpecialToken(31373))
        XCTAssertEqual(Tiktoken.referenceVersion, "0.12.0")
    }

    func testDecodeWithOffsets() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")

        var prompt = "hello world"
        var decoded = try enc.decodeWithOffsets(try enc.encode(prompt))
        XCTAssertEqual(decoded.text, prompt)
        XCTAssertEqual(decoded.offsets, [0, 5])

        prompt = "hello world<|endoftext|> green cow"
        decoded = try enc.decodeWithOffsets(try enc.encode(prompt, allowedSpecial: .all))
        XCTAssertEqual(decoded.text, prompt)
        XCTAssertEqual(decoded.offsets, [0, 5, 11, 24, 30])

        prompt = "我非常渴望与人工智能一起工作"
        decoded = try enc.decodeWithOffsets(try enc.encode(prompt))
        XCTAssertEqual(decoded.text, prompt)
        XCTAssertEqual(decoded.offsets, [0, 1, 2, 3, 3, 4, 4, 5, 6, 7, 8, 8, 9, 10, 11, 12, 13])

        prompt = "நடிகர் சூர்யா"
        decoded = try enc.decodeWithOffsets(try enc.encode(prompt))
        XCTAssertEqual(decoded.text, prompt)
        XCTAssertEqual(decoded.offsets, [0, 0, 1, 1, 2, 3, 4, 4, 5, 6, 7, 8, 8, 9, 9, 10, 11, 12, 12])

        prompt = " Ġ除"
        decoded = try enc.decodeWithOffsets(try enc.encode(prompt))
        XCTAssertEqual(decoded.text, prompt)
        XCTAssertEqual(decoded.offsets, [0, 1])
    }

    func testStrictDecodeRejectsInvalidUTF8() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")

        XCTAssertEqual(try enc.decodeSingleTokenBytes(169), Data([0xed]))
        XCTAssertThrowsError(try enc.decode([169], errors: .strict))
        XCTAssertThrowsError(try enc.decodeWithOffsets([169]))
    }

    func testLargePieceBPEMatchesSmallReference() throws {
        var ranks: [Data: Rank] = [:]
        for byte in UInt8.min...UInt8.max {
            ranks[Data([byte])] = Int(byte)
        }
        ranks[Data("aa".utf8)] = 1_000
        ranks[Data("aaa".utf8)] = 900
        ranks[Data("aaaa".utf8)] = 800
        ranks[Data("ab".utf8)] = 700
        ranks[Data("ba".utf8)] = 710
        ranks[Data("abc".utf8)] = 600
        ranks[Data("bca".utf8)] = 610

        let pieces = [
            Data(String(repeating: "a", count: 140).utf8),
            Data(String(repeating: "abc", count: 45).utf8),
            Data(("abca" + String(repeating: "a", count: 120) + "bcab").utf8)
        ]

        for piece in pieces {
            XCTAssertEqual(BytePairEncoder.encode(piece: piece, ranks: ranks), BytePairEncoder.encodeSmallReference(piece: piece, ranks: ranks))
        }
    }

    func testLargeInputEncodingDoesNotRaise() throws {
        let enc = try Tiktoken.getEncoding("o200k_base")
        let text = String(repeating: "x", count: 10_000)
        let tokens = try enc.encode(text)

        XCTAssertFalse(tokens.isEmpty)
        XCTAssertEqual(try enc.decode(tokens), text)
    }

    func testMetricsCapture() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        var metrics = EncodingMetrics()
        let tokens = try enc.encode("hello world", metrics: &metrics)
        XCTAssertFalse(tokens.isEmpty)
        XCTAssertGreaterThan(metrics.tokensProduced, 0)
        XCTAssertGreaterThan(metrics.inputBytes, 0)
    }
}
