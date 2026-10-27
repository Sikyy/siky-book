import Foundation
import JavaScriptCore
import CryptoKit

enum JSExecutor {

    static func evalSearchUrl(_ jsCode: String, baseUrl: String, keyword: String, page: Int) -> String? {
        let ctx = makeContext()
        ctx.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "key" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "keyword" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "searchKey" as NSString)
        ctx.setObject(page, forKeyedSubscript: "page" as NSString)
        ctx.setObject(page, forKeyedSubscript: "searchPage" as NSString)
        setupJavaBridge(ctx, baseUrl: baseUrl)

        let result = ctx.evaluateScript(jsCode)
        if let ex = ctx.exception { ctx.exception = nil; _ = ex }

        if let str = result?.toString(), str != "undefined", !str.isEmpty {
            return str
        }
        if let url = ctx.objectForKeyedSubscript("url")?.toString(), url != "undefined", !url.isEmpty {
            return url
        }
        if let r = ctx.objectForKeyedSubscript("result")?.toString(), r != "undefined", !r.isEmpty {
            return r
        }
        return nil
    }

    static func postProcess(_ jsCode: String, result: String, baseUrl: String) -> String? {
        let ctx = makeContext()
        ctx.setObject(result, forKeyedSubscript: "result" as NSString)
        ctx.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        setupJavaBridge(ctx, content: result, baseUrl: baseUrl)

        let val = ctx.evaluateScript(jsCode)
        if let ex = ctx.exception { ctx.exception = nil; _ = ex }

        if let str = val?.toString(), str != "undefined", !str.isEmpty {
            return str
        }
        if let r = ctx.objectForKeyedSubscript("result")?.toString(), r != "undefined", !r.isEmpty {
            return r
        }
        return nil
    }

    private static func makeContext() -> JSContext {
        let ctx = JSContext()!
        ctx.exceptionHandler = { _, _ in }
        return ctx
    }

    private static func setupJavaBridge(_ ctx: JSContext, content: String = "", baseUrl: String = "") {
        let native: @convention(block) (String) -> String = { url in syncFetch(url: url, method: "GET", body: nil, headers: nil) }
        ctx.setObject(native, forKeyedSubscript: "__ajax" as NSString)
        let post: @convention(block) (String, String) -> String = { url, body in syncFetch(url: url, method: "POST", body: body, headers: nil) }
        ctx.setObject(post, forKeyedSubscript: "__post" as NSString)
        let md5: @convention(block) (String) -> String = { s in
            let d = Insecure.MD5.hash(data: Data(s.utf8)); return d.map { String(format: "%02x", $0) }.joined()
        }
        ctx.setObject(md5, forKeyedSubscript: "__md5" as NSString)
        let b64d: @convention(block) (String) -> String = { s in
            guard let d = Data(base64Encoded: s, options: .ignoreUnknownCharacters) else { return "" }
            return String(data: d, encoding: .utf8) ?? ""
        }
        ctx.setObject(b64d, forKeyedSubscript: "__b64d" as NSString)
        let b64e: @convention(block) (String) -> String = { s in Data(s.utf8).base64EncodedString() }
        ctx.setObject(b64e, forKeyedSubscript: "__b64e" as NSString)
        let timeFmt: @convention(block) (Double, String) -> String = { ms, fmt in
            let f = DateFormatter(); f.dateFormat = fmt; f.locale = Locale(identifier: "en_US_POSIX")
            return f.string(from: Date(timeIntervalSince1970: ms / 1000))
        }
        ctx.setObject(timeFmt, forKeyedSubscript: "__timeFmt" as NSString)
        let getStr: @convention(block) (String, String) -> String = { html, rule in
            (try? RuleExecutor().getString(html: html, rule: rule, baseURL: baseUrl)) ?? ""
        }
        ctx.setObject(getStr, forKeyedSubscript: "__getString" as NSString)
        let getStrList: @convention(block) (String, String) -> [String] = { html, rule in
            guard let els = try? RuleExecutor().getElements(html: html, rule: rule, baseURL: baseUrl) else { return [] }
            return els.compactMap { try? $0.text() }
        }
        ctx.setObject(getStrList, forKeyedSubscript: "__getStringList" as NSString)
        let getEls: @convention(block) (String, String) -> [String] = { html, rule in
            guard let els = try? RuleExecutor().getElements(html: html, rule: rule, baseURL: baseUrl) else { return [] }
            return els.compactMap { try? $0.outerHtml() }
        }
        ctx.setObject(getEls, forKeyedSubscript: "__getElements" as NSString)
        ctx.setObject(content, forKeyedSubscript: "__content" as NSString)
        ctx.evaluateScript("""
            var java = (function() {
                var _store = {};
                var _content = __content;
                var j = {
                    put: function(key, value) { _store[key] = value; return value; },
                    get: function(key) { return _store[key] || ""; },
                    ajax: function(url) { if (Array.isArray(url)) url = url[0]; return __ajax(String(url).split(",{")[0]); },
                    ajaxAll: function(urls) { return urls.map(function(u) { return __ajax(String(u)); }); },
                    post: function(url, body, headers) { return { body: function() { return __post(String(url), String(body)); } }; },
                    connect: function(url) { return { body: function() { return __ajax(String(url)); } }; },
                    md5Encode: function(s) { return __md5(String(s)); },
                    md5Encode16: function(s) { return __md5(String(s)).substring(8, 24); },
                    base64Decode: function(s) { return __b64d(String(s)); },
                    base64Encode: function(s) { return __b64e(String(s)); },
                    encodeURI: function(s) { return encodeURIComponent(String(s)); },
                    timeFormat: function(ms) { return __timeFmt(Number(ms), "yyyy/MM/dd HH:mm"); },
                    timeFormatUTC: function(ms, fmt, off) { return __timeFmt(Number(ms), String(fmt)); },
                    log: function(x) { return x; },
                    toast: function(x) {}, longToast: function(x) {},
                    setContent: function(c) { _content = c; },
                    getString: function(rule) { return __getString(_content, String(rule)); },
                    getStringList: function(rule) { return __getStringList(_content, String(rule)); },
                    getElements: function(rule) { return __getElements(_content, String(rule)); },
                    getElement: function(rule) { var a = __getElements(_content, String(rule)); return a.length ? a[0] : null; }
                };
                return j;
            })();
            var source = { getKey: function() { return baseUrl; }, getVariable: function() { return ""; },
                           setVariable: function() {}, getLoginInfoMap: function() { return {}; },
                           putLoginHeader: function() {}, getLoginHeader: function() { return ""; } };
            var cookie = { removeCookie: function() {}, getCookie: function() { return ""; }, setCookie: function() {} };
            var cache = { get: function() { return null; }, put: function() {} };
        """)
    }

    private static func syncFetch(url: String, method: String, body: String?, headers: [String: String]?) -> String {
        guard let u = URL(string: url) else { return "" }
        var req = URLRequest(url: u, timeoutInterval: 6)
        req.httpMethod = method
        req.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        if let body { req.httpBody = Data(body.utf8); req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type") }
        let sem = DispatchSemaphore(value: 0)
        var out = ""
        URLSession.shared.dataTask(with: req) { data, _, _ in
            if let data { out = String(data: data, encoding: .utf8) ?? "" }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 7)
        return out
    }
}
