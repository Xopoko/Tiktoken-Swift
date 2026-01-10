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
    }

    func testSpecialTokenDisallowed() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        let text = "<|endoftext|> hello <|fim_prefix|>"
        XCTAssertThrowsError(try enc.encode(text))
        XCTAssertThrowsError(try enc.encode(text, disallowedSpecial: .all))
        XCTAssertNoThrow(try enc.encode(text, disallowedSpecial: .none))
        let tokens = try enc.encode(text, allowedSpecial: .all, disallowedSpecial: .none)
        XCTAssertTrue(tokens.contains(enc.eotToken ?? -1))
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
    }

    func testEncodeBatchMatchesSequential() throws {
        let enc = try Tiktoken.getEncoding("cl100k_base")
        let texts = ["hello world", "goodbye world", "こんにちは世界"]
        let batch = try enc.encodeBatch(texts)
        let sequential = try texts.map { try enc.encode($0) }
        XCTAssertEqual(batch, sequential)
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
