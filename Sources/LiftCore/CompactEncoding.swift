import Foundation
import Compression

/// The shared byte-and-text plumbing under every wire link format
/// (`PlanLink.swift`, `ShareLink.swift`): raw DEFLATE plus base64url.
///
/// Kept as one place so an encoder and a decoder living in different modules
/// (or different apps) can never drift on how bytes get packed — the same
/// divergence bug this task exists to prevent, one level lower.
public enum CompactEncoding {

    /// Raw DEFLATE, no zlib wrapper. `COMPRESSION_ZLIB` is Apple's name for
    /// RFC 1951, which is the same bytes as the browser's
    /// CompressionStream('deflate-raw') and Android's Deflater(nowrap: true).
    /// That equivalence is the only reason one decoder can read all three.
    public static func deflateRaw(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = max(data.count, 128)
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { destination.deallocate() }

        let written = data.withUnsafeBytes { raw -> Int in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(destination, capacity, base, data.count,
                                             nil, COMPRESSION_ZLIB)
        }
        // Zero means it did not fit, which for a log this size means something
        // is wrong. The caller falls back to sending it uncompressed.
        guard written > 0 else { return nil }
        return Data(bytes: destination, count: written)
    }

    public static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Grows the output buffer and retries — `compression_decode_buffer` gives
    /// no way to ask "how big will this be", unlike a streaming API.
    public static func inflateRaw(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var capacity = max(data.count * 4, 4096)
        let maxCapacity = 16 * 1024 * 1024

        while capacity <= maxCapacity {
            let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { destination.deallocate() }

            let written = data.withUnsafeBytes { raw -> Int in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destination, capacity, base, data.count, nil, COMPRESSION_ZLIB
                )
            }

            if written > 0 && written < capacity {
                return Data(bytes: destination, count: written)
            }
            capacity *= 2
        }
        return nil
    }

    public static func base64URLDecode(_ string: String) -> Data? {
        guard !string.isEmpty else { return nil }
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        return Data(base64Encoded: base64)
    }
}
