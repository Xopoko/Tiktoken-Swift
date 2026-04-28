# ``Tiktoken``

Native Swift implementation of OpenAI’s tiktoken tokenizer.

## Overview
Use ``Tiktoken`` to load an encoding and tokenize text in pure Swift. The implementation mirrors the reference BPE algorithm and regex‑based splitting from the upstream tiktoken project.

This package targets `openai/tiktoken` `0.12.0`, plus the upstream GitHub `main` large-input BPE fix for long merge pieces.

```swift
import Tiktoken

let enc = try Tiktoken.getEncoding("cl100k_base")
let tokens = try enc.encode("hello world")
let decoded = try enc.decode(tokens)
```

## Topics

### Encodings
- ``Tiktoken/getEncoding(_:)``
- ``Tiktoken/listEncodingNames()``
- ``Tiktoken/referenceVersion``
- ``Encoding``

### Model Mapping
- ``Tiktoken/encodingName(forModel:)``
- ``Tiktoken/encoding(forModel:)``

### Encoding & Decoding
- ``Encoding/encode(_:allowedSpecial:disallowedSpecial:)``
- ``Encoding/encodeOrdinary(_:)``
- ``Encoding/encodeBatch(_:numThreads:allowedSpecial:disallowedSpecial:)``
- ``Encoding/decode(_:errors:)``
- ``Encoding/decodeBytes(_:)``
- ``Encoding/decodeTokensBytes(_:)``
- ``Encoding/decodeWithOffsets(_:)``
- ``Encoding/decodeBatch(_:errors:numThreads:)``
- ``Encoding/decodeBytesBatch(_:numThreads:)``

### Token Inspection
- ``Encoding/tokenByteValues()``
- ``Encoding/isSpecialToken(_:)``

### Metrics
- ``EncodingMetrics``
