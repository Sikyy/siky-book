import XCTest
@testable import YiYue

final class EncodingDetectorTests: XCTestCase {
    func testUTF8String() {
        let data = "第一章 开始\n这是正文内容。".data(using: .utf8)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertTrue(result.contains("第一章"))
    }

    func testUTF8BOM() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append("你好世界".data(using: .utf8)!)
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "你好世界")
    }

    func testGBKString() {
        let gbkEncoding = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
            )
        )
        let original = "第一章 测试内容"
        let data = (original as NSString).data(using: gbkEncoding.rawValue)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertTrue(result.contains("第一章"))
    }

    func testPureASCII() {
        let data = "Hello World".data(using: .utf8)!
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "Hello World")
    }

    func testEmptyData() {
        let data = Data()
        let result = EncodingDetector.decodeToString(data)
        XCTAssertEqual(result, "")
    }
}
