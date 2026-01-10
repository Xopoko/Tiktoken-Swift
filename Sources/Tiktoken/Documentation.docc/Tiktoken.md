# ``Tiktoken``

Native Swift implementation of OpenAI’s tiktoken tokenizer.

## Overview
Use ``Tiktoken`` to load an encoding and tokenize text in pure Swift. The implementation mirrors the reference BPE algorithm and regex‑based splitting from the upstream tiktoken project.

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
- ``Encoding``

### Model Mapping
- ``Tiktoken/encodingName(forModel:)``
- ``Tiktoken/encoding(forModel:)``

### Encoding & Decoding
- ``Encoding/encode(_:allowedSpecial:disallowedSpecial:)``
- ``Encoding/encodeOrdinary(_:)``
- ``Encoding/decode(_:errors:)``
- ``Encoding/decodeBytes(_:)``

### Metrics
- ``EncodingMetrics``
