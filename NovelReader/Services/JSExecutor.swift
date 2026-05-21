import Foundation
import JavaScriptCore

enum JSExecutor {

    static func evalSearchUrl(_ jsCode: String, baseUrl: String, keyword: String, page: Int) -> String? {
        let ctx = makeContext()
        ctx.setObject(baseUrl, forKeyedSubscript: "baseUrl" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "key" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "keyword" as NSString)
        ctx.setObject(keyword, forKeyedSubscript: "searchKey" as NSString)
        ctx.setObject(page, forKeyedSubscript: "page" as NSString)
        ctx.setObject(page, forKeyedSubscript: "searchPage" as NSString)
        setupJavaBridge(ctx)

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
        setupJavaBridge(ctx)

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

    private static func setupJavaBridge(_ ctx: JSContext) {
        ctx.evaluateScript("""
            var java = (function() {
                var _store = {};
                return {
                    put: function(key, value) { _store[key] = value; },
                    get: function(key) { return _store[key] || ""; },
                    ajax: function(url) { return ""; },
                    ajaxAll: function(urls) { return "[]"; }
                };
            })();
        """)
    }
}
