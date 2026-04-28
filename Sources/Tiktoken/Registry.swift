import Foundation

final class EncodingRegistry: @unchecked Sendable {
    static let shared = EncodingRegistry()

    private let lock = NSLock()
    private var encodings: [String: Encoding] = [:]

    private lazy var constructors: [String: () throws -> EncodingDefinition] = [
        "gpt2": { try OpenAIEncodings.gpt2() },
        "r50k_base": { try OpenAIEncodings.r50kBase() },
        "p50k_base": { try OpenAIEncodings.p50kBase() },
        "p50k_edit": { try OpenAIEncodings.p50kEdit() },
        "cl100k_base": { try OpenAIEncodings.cl100kBase() },
        "o200k_base": { try OpenAIEncodings.o200kBase() },
        "o200k_harmony": { try OpenAIEncodings.o200kHarmony() }
    ]

    func getEncoding(_ name: String) throws -> Encoding {
        lock.lock()
        if let cached = encodings[name] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        guard let constructor = constructors[name] else {
            throw TiktokenError.unknownEncoding(name)
        }

        let definition = try constructor()
        let encoding = try Encoding(definition: definition)

        lock.lock()
        encodings[name] = encoding
        lock.unlock()

        return encoding
    }

    func listEncodingNames() -> [String] {
        return Array(constructors.keys).sorted()
    }
}

public enum Tiktoken {
    public static let referenceVersion = "0.12.0"

    public static func getEncoding(_ name: String) throws -> Encoding {
        return try EncodingRegistry.shared.getEncoding(name)
    }

    public static func listEncodingNames() -> [String] {
        return EncodingRegistry.shared.listEncodingNames()
    }

    public static func encodingName(forModel model: String) throws -> String {
        if let exact = ModelEncodingMapping.modelToEncoding[model] {
            return exact
        }
        for (prefix, encoding) in ModelEncodingMapping.modelPrefixToEncoding {
            if model.hasPrefix(prefix) {
                return encoding
            }
        }
        throw TiktokenError.unknownModel(model)
    }

    public static func encoding(forModel model: String) throws -> Encoding {
        return try getEncoding(encodingName(forModel: model))
    }
}
