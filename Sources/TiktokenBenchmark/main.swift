import Foundation
import Tiktoken

struct BenchmarkConfig {
    let iterations: Int
    let text: String
}

let config = BenchmarkConfig(
    iterations: 50,
    text: """
    Swift tokenization benchmark. This sentence is repeated to warm caches and exercise Unicode. 🚀
    The quick brown fox jumps over the lazy dog. Привет мир. こんにちは世界。
    """
)

let encodings = Tiktoken.listEncodingNames()
print("Tiktoken-Swift Benchmark")
print("Iterations: \(config.iterations)")
print("Input bytes: \(config.text.utf8.count)\n")

for name in encodings {
    do {
        let encoding = try Tiktoken.getEncoding(name)
        var lastCount = 0
        let start = CFAbsoluteTimeGetCurrent()
        for _ in 0..<config.iterations {
            let tokens = try encoding.encode(config.text)
            lastCount = tokens.count
        }
        let elapsed = CFAbsoluteTimeGetCurrent() - start
        let tokensPerSec = Double(lastCount * config.iterations) / max(0.0001, elapsed)
        let bytesPerSec = Double(config.text.utf8.count * config.iterations) / max(0.0001, elapsed)
        let line = String(format: "%-14@  tokens=%-6d  %.2f tok/s  %.2f B/s", name as NSString, lastCount, tokensPerSec, bytesPerSec)
        print(line)
    } catch {
        print("\(name): benchmark failed with error \(error)")
    }
}
