import Foundation

enum Utf8Decoder {
    static func decodeIgnoringInvalid(_ data: Data) -> String {
        let bytes = [UInt8](data)
        var scalars: [UnicodeScalar] = []
        scalars.reserveCapacity(bytes.count)

        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            if byte < 0x80 {
                scalars.append(UnicodeScalar(UInt32(byte))!)
                index += 1
                continue
            }

            if byte < 0xC2 {
                index += 1
                continue
            } else if byte < 0xE0 {
                guard index + 1 < bytes.count else { break }
                let b1 = bytes[index + 1]
                guard isContinuation(b1) else {
                    index += 1
                    continue
                }
                let value = UInt32(byte & 0x1F) << 6 | UInt32(b1 & 0x3F)
                if let scalar = UnicodeScalar(value) {
                    scalars.append(scalar)
                }
                index += 2
            } else if byte < 0xF0 {
                guard index + 2 < bytes.count else { break }
                let b1 = bytes[index + 1]
                let b2 = bytes[index + 2]
                guard isContinuation(b1), isContinuation(b2) else {
                    index += 1
                    continue
                }
                if byte == 0xE0 && b1 < 0xA0 {
                    index += 1
                    continue
                }
                if byte == 0xED && b1 >= 0xA0 {
                    index += 1
                    continue
                }
                let value = UInt32(byte & 0x0F) << 12 | UInt32(b1 & 0x3F) << 6 | UInt32(b2 & 0x3F)
                if let scalar = UnicodeScalar(value) {
                    scalars.append(scalar)
                }
                index += 3
            } else if byte < 0xF5 {
                guard index + 3 < bytes.count else { break }
                let b1 = bytes[index + 1]
                let b2 = bytes[index + 2]
                let b3 = bytes[index + 3]
                guard isContinuation(b1), isContinuation(b2), isContinuation(b3) else {
                    index += 1
                    continue
                }
                if byte == 0xF0 && b1 < 0x90 {
                    index += 1
                    continue
                }
                if byte == 0xF4 && b1 >= 0x90 {
                    index += 1
                    continue
                }
                let value = UInt32(byte & 0x07) << 18 | UInt32(b1 & 0x3F) << 12 | UInt32(b2 & 0x3F) << 6 | UInt32(b3 & 0x3F)
                if let scalar = UnicodeScalar(value) {
                    scalars.append(scalar)
                }
                index += 4
            } else {
                index += 1
            }
        }

        return String(String.UnicodeScalarView(scalars))
    }

    private static func isContinuation(_ byte: UInt8) -> Bool {
        return (byte & 0xC0) == 0x80
    }
}
