import Foundation

enum OpenAIEncodings {
    static let ENDOFTEXT = "<|endoftext|>"
    static let FIM_PREFIX = "<|fim_prefix|>"
    static let FIM_MIDDLE = "<|fim_middle|>"
    static let FIM_SUFFIX = "<|fim_suffix|>"
    static let ENDOFPROMPT = "<|endofprompt|>"

    static let r50kPatStr = #"'(?:[sdmt]|ll|ve|re)| ?\p{L}++| ?\p{N}++| ?[^\s\p{L}\p{N}]++|\s++$|\s+(?!\S)|\s"#

    static func gpt2() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.dataGymToMergeableBPETokens(
            vocabBpeFile: "https://openaipublic.blob.core.windows.net/gpt-2/encodings/main/vocab.bpe",
            encoderJsonFile: "https://openaipublic.blob.core.windows.net/gpt-2/encodings/main/encoder.json",
            vocabBpeHash: "1ce1664773c50f3e0cc8842619a93edc4624525b728b188a9e0be33b7726adc5",
            encoderJsonHash: "196139668be63f3b5d6574427317ae82f612a97c5d1cdaf36ed2256dbf636783"
        )
        return EncodingDefinition(
            name: "gpt2",
            patStr: r50kPatStr,
            mergeableRanks: mergeableRanks,
            specialTokens: [ENDOFTEXT: 50256],
            explicitNVocab: 50257
        )
    }

    static func r50kBase() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.loadTiktokenBPE(
            "https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken",
            expectedHash: "306cd27f03c1a714eca7108e03d66b7dc042abe8c258b44c199a7ed9838dd930"
        )
        return EncodingDefinition(
            name: "r50k_base",
            patStr: r50kPatStr,
            mergeableRanks: mergeableRanks,
            specialTokens: [ENDOFTEXT: 50256],
            explicitNVocab: 50257
        )
    }

    static func p50kBase() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.loadTiktokenBPE(
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            expectedHash: "94b5ca7dff4d00767bc256fdd1b27e5b17361d7b8a5f968547f9f23eb70d2069"
        )
        return EncodingDefinition(
            name: "p50k_base",
            patStr: r50kPatStr,
            mergeableRanks: mergeableRanks,
            specialTokens: [ENDOFTEXT: 50256],
            explicitNVocab: 50281
        )
    }

    static func p50kEdit() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.loadTiktokenBPE(
            "https://openaipublic.blob.core.windows.net/encodings/p50k_base.tiktoken",
            expectedHash: "94b5ca7dff4d00767bc256fdd1b27e5b17361d7b8a5f968547f9f23eb70d2069"
        )
        let specialTokens: [String: Rank] = [
            ENDOFTEXT: 50256,
            FIM_PREFIX: 50281,
            FIM_MIDDLE: 50282,
            FIM_SUFFIX: 50283
        ]
        return EncodingDefinition(
            name: "p50k_edit",
            patStr: r50kPatStr,
            mergeableRanks: mergeableRanks,
            specialTokens: specialTokens,
            explicitNVocab: nil
        )
    }

    static func cl100kBase() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.loadTiktokenBPE(
            "https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken",
            expectedHash: "223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7"
        )
        let specialTokens: [String: Rank] = [
            ENDOFTEXT: 100257,
            FIM_PREFIX: 100258,
            FIM_MIDDLE: 100259,
            FIM_SUFFIX: 100260,
            ENDOFPROMPT: 100276
        ]
        let patStr = #"'(?i:[sdmt]|ll|ve|re)|[^\r\n\p{L}\p{N}]?+\p{L}++|\p{N}{1,3}+| ?[^\s\p{L}\p{N}]++[\r\n]*+|\s++$|\s*[\r\n]|\s+(?!\S)|\s"#
        return EncodingDefinition(
            name: "cl100k_base",
            patStr: patStr,
            mergeableRanks: mergeableRanks,
            specialTokens: specialTokens,
            explicitNVocab: nil
        )
    }

    static func o200kBase() throws -> EncodingDefinition {
        let mergeableRanks = try TiktokenDataLoader.loadTiktokenBPE(
            "https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken",
            expectedHash: "446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d"
        )
        let specialTokens: [String: Rank] = [
            ENDOFTEXT: 199999,
            ENDOFPROMPT: 200018
        ]
        let patStr = [
            #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]*[\p{Ll}\p{Lm}\p{Lo}\p{M}]+(?i:'s|'t|'re|'ve|'m|'ll|'d)?"#,
            #"[^\r\n\p{L}\p{N}]?[\p{Lu}\p{Lt}\p{Lm}\p{Lo}\p{M}]+[\p{Ll}\p{Lm}\p{Lo}\p{M}]*(?i:'s|'t|'re|'ve|'m|'ll|'d)?"#,
            #"\p{N}{1,3}"#,
            #" ?[^\s\p{L}\p{N}]+[\r\n/]*"#,
            #"\s*[\r\n]+"#,
            #"\s+(?!\S)"#,
            #"\s+"#
        ].joined(separator: "|")

        return EncodingDefinition(
            name: "o200k_base",
            patStr: patStr,
            mergeableRanks: mergeableRanks,
            specialTokens: specialTokens,
            explicitNVocab: nil
        )
    }

    static func o200kHarmony() throws -> EncodingDefinition {
        let base = try o200kBase()
        var specialTokens = base.specialTokens
        specialTokens["<|startoftext|>"] = 199998
        specialTokens["<|endoftext|>"] = 199999
        specialTokens["<|reserved_200000|>"] = 200000
        specialTokens["<|reserved_200001|>"] = 200001
        specialTokens["<|return|>"] = 200002
        specialTokens["<|constrain|>"] = 200003
        specialTokens["<|reserved_200004|>"] = 200004
        specialTokens["<|channel|>"] = 200005
        specialTokens["<|start|>"] = 200006
        specialTokens["<|end|>"] = 200007
        specialTokens["<|message|>"] = 200008
        specialTokens["<|reserved_200009|>"] = 200009
        specialTokens["<|reserved_200010|>"] = 200010
        specialTokens["<|reserved_200011|>"] = 200011
        specialTokens["<|call|>"] = 200012
        for value in 200013..<201088 {
            specialTokens["<|reserved_\(value)|>"] = value
        }

        return EncodingDefinition(
            name: "o200k_harmony",
            patStr: base.patStr,
            mergeableRanks: base.mergeableRanks,
            specialTokens: specialTokens,
            explicitNVocab: nil
        )
    }
}
