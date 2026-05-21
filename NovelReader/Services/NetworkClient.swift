import Foundation

actor NetworkClient {
    static let shared = NetworkClient()

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 5
        self.session = URLSession(configuration: config)
    }

    func fetchString(url: String, method: String = "GET", body: String? = nil, headers: [String: String]? = nil, encoding: String.Encoding? = nil) async throws -> String {
        guard let requestURL = URL(string: url) else {
            throw NetworkError.invalidURL
        }
        var request = URLRequest(url: requestURL)
        request.httpMethod = method
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")

        if let body = body {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            }
        }

        if let headers = headers {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw NetworkError.requestFailed
        }

        if let encoding = encoding {
            return String(data: data, encoding: encoding) ?? String(decoding: data, as: UTF8.self)
        }

        let detectedEncoding = detectEncoding(from: httpResponse, data: data)
        return String(data: data, encoding: detectedEncoding) ?? String(decoding: data, as: UTF8.self)
    }

    private func detectEncoding(from response: HTTPURLResponse, data: Data) -> String.Encoding {
        if let contentType = response.value(forHTTPHeaderField: "Content-Type"),
           contentType.lowercased().contains("gbk") || contentType.lowercased().contains("gb2312") || contentType.lowercased().contains("gb18030") {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        if let head = String(data: data.prefix(1024), encoding: .ascii),
           head.lowercased().contains("charset=gbk") || head.lowercased().contains("charset=gb2312") {
            return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        }
        return .utf8
    }
}

enum NetworkError: Error, LocalizedError {
    case invalidURL
    case requestFailed

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "无效的URL"
        case .requestFailed: return "请求失败"
        }
    }
}
