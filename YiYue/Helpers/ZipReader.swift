import Foundation
import Compression

/// Minimal read-only ZIP reader (stored + deflate), enough for EPUB containers.
struct ZipReader {
    enum ZipError: Error { case invalid, unsupported, missing(String) }

    private struct Entry { let method: UInt16; let compressedSize: Int; let size: Int; let offset: Int }
    private let data: Data
    private var entries: [String: Entry] = [:]

    init(data: Data) throws {
        self.data = data
        guard data.count >= 22 else { throw ZipError.invalid }
        // Find End Of Central Directory record
        var eocd = -1
        var i = data.count - 22
        let lowest = max(0, data.count - 22 - 65_535)
        while i >= lowest {
            if data.u32(i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.invalid }
        let count = Int(data.u16(eocd + 10))
        var p = Int(data.u32(eocd + 16))
        for _ in 0..<count {
            guard p + 46 <= data.count, data.u32(p) == 0x02014b50 else { throw ZipError.invalid }
            let method = data.u16(p + 10)
            let csize = Int(data.u32(p + 20))
            let usize = Int(data.u32(p + 24))
            let nlen = Int(data.u16(p + 28)), elen = Int(data.u16(p + 30)), clen = Int(data.u16(p + 32))
            let off = Int(data.u32(p + 42))
            guard p + 46 + nlen <= data.count else { throw ZipError.invalid }
            let nameData = data.subdata(in: (p + 46)..<(p + 46 + nlen))
            let name = String(data: nameData, encoding: .utf8) ?? String(decoding: nameData, as: UTF8.self)
            entries[name] = Entry(method: method, compressedSize: csize, size: usize, offset: off)
            p += 46 + nlen + elen + clen
        }
    }

    var names: [String] { Array(entries.keys) }
    func has(_ name: String) -> Bool { entries[name] != nil }

    func read(_ name: String) throws -> Data {
        guard let e = entries[name] else { throw ZipError.missing(name) }
        guard e.offset + 30 <= data.count, data.u32(e.offset) == 0x04034b50 else { throw ZipError.invalid }
        let nlen = Int(data.u16(e.offset + 26)), elen = Int(data.u16(e.offset + 28))
        let start = e.offset + 30 + nlen + elen
        guard start + e.compressedSize <= data.count else { throw ZipError.invalid }
        let raw = data.subdata(in: start..<(start + e.compressedSize))
        switch e.method {
        case 0: return raw
        case 8:
            if e.size == 0 { return Data() }
            let out = try (raw as NSData).decompressed(using: .zlib) as Data
            return out
        default: throw ZipError.unsupported
        }
    }
}

private extension Data {
    func u16(_ o: Int) -> UInt16 { UInt16(self[startIndex + o]) | UInt16(self[startIndex + o + 1]) << 8 }
    func u32(_ o: Int) -> UInt32 {
        UInt32(self[startIndex + o]) | UInt32(self[startIndex + o + 1]) << 8 |
        UInt32(self[startIndex + o + 2]) << 16 | UInt32(self[startIndex + o + 3]) << 24
    }
}
