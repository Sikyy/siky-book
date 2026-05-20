import Foundation

struct EncodingDetector {
    static func decodeToString(_ data: Data) -> String {
        if data.isEmpty { return "" }

        if data.count >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF {
            return String(data: data.dropFirst(3), encoding: .utf8) ?? ""
        }

        if let str = String(data: data, encoding: .utf8) {
            return str
        }

        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        if let str = String(data: data, encoding: gb18030) {
            return str
        }

        return String(data: data, encoding: .isoLatin1) ?? ""
    }
}
