package ohos_app_cangjie_entry

import kit.ArkUI.*
import kit.NetworkKit.*
import std.core.*
import std.collection.HashMap
import std.collection.ArrayList
import ohos.arkui.state_macro_manage.Entry
import ohos.arkui.state_macro_manage.Component
import ohos.arkui.state_macro_manage.State

// ============ Mock Server 常量 ============
let HTTP1_BASE = "http://10.0.2.2:8080"
let HTTPS_BASE = "https://10.0.2.2:8443"
// 自签名 CA：随包 resfile 分发，Network Kit 的 caPath 直接读 bundle 只读路径
let CA_PATH = "/data/storage/el1/bundle/entry/resources/resfile/mock-ca/cert.pem"

// ============ 字节/子串工具 ============
func bAt(s: String, i: Int64): Int64 {
    if (let Some(b) <- s.get(i)) {
        return Int64(b)
    }
    return -1
}

func isWs(b: Int64): Bool {
    return b == 32 || b == 9 || b == 10 || b == 13
}

func substr(s: String, start: Int64, len: Int64): String {
    if (len <= 0) {
        return ""
    }
    let bytes = s.toArray()
    if (start >= bytes.size) {
        return ""
    }
    let part = bytes.slice(start, len)
    let u8 = Array<UInt8>(part.size) { i => part[i] }
    return String.fromUtf8(u8)
}

// ============ 极简 JSON 提取（mock server 响应均为简单扁平结构）============
// 找 `"key"` 后的 `:` 位置（含跳过空白），找不到返回 -1
func jFindKey(s: String, key: String, from: Int64): Int64 {
    let q = "\"${key}\""
    var i = from
    while (i < s.size) {
        if (let Some(pos) <- s.indexOf(q, i)) {
            var j = pos + q.size
            while (j < s.size && isWs(bAt(s, j))) {
                j += 1
            }
            if (j < s.size && bAt(s, j) == 58) { // ':'
                return j + 1
            }
            i = j + 1
        } else {
            return -1
        }
    }
    return -1
}

// 提取字符串值（mock 响应值内无转义）
func jStr(s: String, key: String): String {
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return ""
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    if (i >= s.size || bAt(s, i) != 34) { // '"'
        return ""
    }
    let start = i + 1
    var j = start
    while (j < s.size && bAt(s, j) != 34) {
        j += 1
    }
    return substr(s, start, j - start)
}

// 提取整数值
func jInt(s: String, key: String): Int64 {
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return 0
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    var neg = false
    if (i < s.size && bAt(s, i) == 45) { // '-'
        neg = true
        i += 1
    }
    var n: Int64 = 0
    while (i < s.size) {
        let b = bAt(s, i)
        if (b < 48 || b > 57) {
            break
        }
        n = n * 10 + (b - 48)
        i += 1
    }
    if (neg) {
        n = -n
    }
    return n
}

class Kv {
    let k: String
    let v: String
    init(k: String, v: String) {
        this.k = k
        this.v = v
    }
}

// 提取嵌套对象的全部 (字符串key, 字符串值)；非字符串值跳过
func jObjEntries(s: String, key: String): ArrayList<Kv> {
    let out = ArrayList<Kv>()
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return out
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    if (i >= s.size || bAt(s, i) != 123) { // '{'
        return out
    }
    i += 1
    while (i < s.size) {
        while (i < s.size && isWs(bAt(s, i))) {
            i += 1
        }
        if (i >= s.size || bAt(s, i) == 125) {
            break
        }
        if (bAt(s, i) != 34) {
            i += 1
            continue
        }
        var j = i + 1
        while (j < s.size && bAt(s, j) != 34) {
            j += 1
        }
        let k = substr(s, i + 1, j - i - 1)
        i = j + 1
        while (i < s.size && isWs(bAt(s, i))) {
            i += 1
        }
        if (i >= s.size || bAt(s, i) != 58) {
            break
        }
        i += 1
        while (i < s.size && isWs(bAt(s, i))) {
            i += 1
        }
        if (i >= s.size) {
            break
        }
        if (bAt(s, i) == 34) {
            var m = i + 1
            while (m < s.size && bAt(s, m) != 34) {
                m += 1
            }
            let v = substr(s, i + 1, m - i - 1)
            out.add(Kv(k, v))
            i = m + 1
        } else {
            while (i < s.size && bAt(s, i) != 44 && bAt(s, i) != 125) {
                i += 1
            }
        }
        if (i < s.size && bAt(s, i) == 44) {
            i += 1
        }
    }
    return out
}

// 数组元素个数（元素为对象）
func jArrLen(s: String, key: String): Int64 {
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return 0
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    if (i >= s.size || bAt(s, i) != 91) { // '['
        return 0
    }
    var depth: Int64 = 0
    var n: Int64 = 0
    i += 1
    while (i < s.size) {
        let b = bAt(s, i)
        if (b == 34) {
            i += 1
            while (i < s.size && bAt(s, i) != 34) {
                i += 1
            }
        } else if (b == 123) {
            if (depth == 0) {
                n += 1
            }
            depth += 1
        } else if (b == 125) {
            depth -= 1
        } else if (b == 93) {
            break
        }
        i += 1
    }
    return n
}

// 第 idx 个数组元素的 sub 字符串值
func jArrElemStr(s: String, key: String, idx: Int64, sub: String): String {
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return ""
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    if (i >= s.size || bAt(s, i) != 91) {
        return ""
    }
    var cur: Int64 = 0
    i += 1
    while (i < s.size) {
        let b = bAt(s, i)
        if (b == 34) {
            i += 1
            while (i < s.size && bAt(s, i) != 34) {
                i += 1
            }
        } else if (b == 123) {
            if (cur == idx) {
                var j = i + 1
                var d: Int64 = 1
                while (j < s.size && d > 0) {
                    let c = bAt(s, j)
                    if (c == 34) {
                        j += 1
                        while (j < s.size && bAt(s, j) != 34) {
                            j += 1
                        }
                    } else if (c == 123) {
                        d += 1
                    } else if (c == 125) {
                        d -= 1
                    }
                    j += 1
                }
                let elem = substr(s, i, j - i)
                return jStr(elem, sub)
            }
            cur += 1
        }
        i += 1
    }
    return ""
}

// 第 idx 个数组元素的 sub 整数值
func jArrElemInt(s: String, key: String, idx: Int64, sub: String): Int64 {
    let p = jFindKey(s, key, 0)
    if (p < 0) {
        return 0
    }
    var i = p
    while (i < s.size && isWs(bAt(s, i))) {
        i += 1
    }
    if (i >= s.size || bAt(s, i) != 91) {
        return 0
    }
    var cur: Int64 = 0
    i += 1
    while (i < s.size) {
        let b = bAt(s, i)
        if (b == 34) {
            i += 1
            while (i < s.size && bAt(s, i) != 34) {
                i += 1
            }
        } else if (b == 123) {
            if (cur == idx) {
                var j = i + 1
                var d: Int64 = 1
                while (j < s.size && d > 0) {
                    let c = bAt(s, j)
                    if (c == 34) {
                        j += 1
                        while (j < s.size && bAt(s, j) != 34) {
                            j += 1
                        }
                    } else if (c == 123) {
                        d += 1
                    } else if (c == 125) {
                        d -= 1
                    }
                    j += 1
                }
                let elem = substr(s, i, j - i)
                return jInt(elem, sub)
            }
            cur += 1
        }
        i += 1
    }
    return 0
}

// ============ 请求辅助（纯回调风格，无阻塞原语） ============
// 发请求；fmt 在回调线程格式化响应，结果经 onDone 回调。
// onDone 由 runScenario 传入：内部用 launch() 调度回主线程后再更新 @State。
func asyncRequest(url: String, opt: HttpRequestOptions, fmt: (HttpResponse) -> String, onDone: (String) -> Unit) {
    let req = createHttp()
    req.request(url, opt) {
        err, resp =>
        var text = ""
        if (let Some(e) <- err) {
            text = "ERROR ${e}"
        } else if (let Some(v) <- resp) {
            text = fmt(v)
        } else {
            text = "no response"
        }
        onDone(text)
        req.destroy()
    }
}

func strBody(v: HttpResponse): String {
    return match (v.result) {
        case HttpData.StringData(s) => s
        case _ => ""
    }
}

func acceptHeader(): HashMap<String, String> {
    let h = HashMap<String, String>()
    h.add("Accept", "application/json")
    return h
}

// ============ 场景 1/2: 协议协商 ============
func runProtocol1(done: (String) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingProtocol: HttpProtocol.Http1_1,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTP1_BASE}/api/protocol", opt, {
        v =>
        let s = strBody(v)
        "HTTP ${v.responseCode} | server saw: ${jStr(s, "protocol")} (httpVersion ${jStr(s, "httpVersion")})"
    }, done)
}

func runProtocol2(done: (String) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingProtocol: HttpProtocol.Http2,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader(),
        caPath: CA_PATH
    )
    asyncRequest("${HTTPS_BASE}/api/protocol", opt, {
        v =>
        let s = strBody(v)
        "HTTP ${v.responseCode} | server saw: ${jStr(s, "protocol")} (httpVersion ${jStr(s, "httpVersion")})\n(client uses caPath=${CA_PATH})"
    }, done)
}

// ============ 场景 3: REST 方法覆盖 ============
// Cangjie Network Kit 的 RequestMethod 无 Patch（也无 customMethod），因此 PATCH 无法发出
func methodName(m: RequestMethod): String {
    return match (m) {
        case RequestMethod.Get => "GET"
        case RequestMethod.Post => "POST"
        case RequestMethod.Put => "PUT"
        case RequestMethod.Delete => "DELETE"
        case RequestMethod.Head => "HEAD"
        case RequestMethod.Options => "OPTIONS"
        case RequestMethod.Trace => "TRACE"
        case RequestMethod.Connect => "CONNECT"
        case _ => "?"
    }
}

// 6 个方法串行请求：用类封装状态（Cangjie 不允许 lambda 捕获 var 后作为参数传递，
// 因此用方法递归代替递归闭包）
class MethodRunner {
    let methods = [RequestMethod.Get, RequestMethod.Post, RequestMethod.Put,
                   RequestMethod.Delete, RequestMethod.Head, RequestMethod.Options]
    let sb = StringBuilder()
    var idx: Int64 = 0
    let done: (String) -> Unit

    init(done: (String) -> Unit) {
        this.done = done
    }

    func next(): Unit {
        if (idx >= methods.size) {
            sb.append("PATCH     -> N/A (Cangjie Network Kit 无 RequestMethod.Patch / customMethod)\n")
            done(sb.toString())
            return
        }
        let m = methods[idx]
        idx += 1
        let opt = HttpRequestOptions(
            method: m,
            expectDataType: HttpDataType.StringValue,
            readTimeout: 15000,
            connectTimeout: 15000
        )
        asyncRequest("${HTTP1_BASE}/api/methods", opt, {
            v =>
            let s = strBody(v)
            if (s.isEmpty()) {
                "${v.responseCode}  server echoed: (no body)"
            } else {
                "${v.responseCode}  server echoed: ${jStr(s, "method")}"
            }
        }) {
            line =>
            sb.append("${methodName(m).padEnd(8)} -> ${line}\n")
            this.next()
        }
    }
}

func runMethods(done: (String) -> Unit) {
    MethodRunner(done).next()
}

// ============ 场景 4: Header 正规化（大小写） ============
func headersForTarget(label: String, base: String, proto: HttpProtocol, done: (String) -> Unit) {
    let h = HashMap<String, String>()
    h.add("Accept", "application/json")
    h.add("X-MiXeD-CaSe-Hdr", "MixedCaseValue")
    h.add("x-lowercase-hdr", "lower")
    h.add("X-ALLCAPS-HDR", "upper")
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingProtocol: proto,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: h,
        caPath: CA_PATH
    )
    asyncRequest("${base}/api/headers", opt, {
        v =>
        let s = strBody(v)
        let entries = jObjEntries(s, "wireHeaders")
        let sb2 = StringBuilder()
        for (kv in entries) {
            let k = kv.k.toAsciiLower()
            if (k.startsWith("x-")) {
                sb2.append("    ${kv.k} = ${kv.v}\n")
            }
        }
        sb2.toString()
    }) {
        line =>
        done("[${label}] server received header names:\n${line}")
    }
}

func runHeaders(done: (String) -> Unit) {
    headersForTarget("HTTP/1.1", HTTP1_BASE, HttpProtocol.Http1_1) {
        line1 =>
        headersForTarget("HTTP/2", HTTPS_BASE, HttpProtocol.Http2) {
            line2 =>
            done("${line1}${line2}")
        }
    }
}

// ============ 场景 5: Cookie 手动往返 ============
// Network Kit 无 cookie jar：Set-Cookie 需手动解析（Netscape cookie-file 格式），
// 再手动回填 Cookie header
func extractCookieHeader(raw: String): String {
    if (raw.isEmpty()) {
        return ""
    }
    let parts = ArrayList<String>()
    for (line in raw.split("\n")) {
        let ln = line.trimAscii()
        if (ln.isEmpty()) {
            continue
        }
        let cleaned = ln.removePrefix("#")
        let fields = cleaned.split("\t")
        if (fields.size >= 7) {
            let name = fields[5]
            let value = fields[6]
            if (!name.isEmpty()) {
                parts.add("${name}=${value}")
                continue
            }
        }
        if (let Some(eq) <- ln.indexOf("=")) {
            let name = substr(ln, 0, eq).trimAscii()
            let rest = substr(ln, eq + 1, ln.size - eq - 1)
            let value = if (let Some(semi) <- rest.indexOf(";")) {
                substr(rest, 0, semi).trimAscii()
            } else {
                rest.trimAscii()
            }
            if (!name.isEmpty()) {
                parts.add("${name}=${value}")
            }
        }
    }
    return String.join(parts.toArray(), delimiter: "; ")
}

func runCookies(done: (String) -> Unit) {
    let getOpt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTP1_BASE}/api/cookie/set", getOpt, { v => v.cookies }) {
        rawCookies =>
        let cookieHeader = extractCookieHeader(rawCookies)
        let h = HashMap<String, String>()
        h.add("Cookie", cookieHeader)
        let readOpt = HttpRequestOptions(
            method: RequestMethod.Get,
            expectDataType: HttpDataType.StringValue,
            readTimeout: 15000,
            connectTimeout: 15000,
            header: h
        )
        asyncRequest("${HTTP1_BASE}/api/cookie/read", readOpt, {
            v =>
            let s = strBody(v)
            "server saw Cookie: ${jStr(s, "cookieHeader")}"
        }) {
            readLine =>
            let rawTrim = if (rawCookies.size > 50) { substr(rawCookies, 0, 50) } else { rawCookies }
            done("Set-Cookie(raw,trim): ${rawTrim}\n${readLine}")
        }
    }
}

// ============ 场景 6: Cache（服务端计数 delta 判断是否命中） ============
func getCacheStats(onDone: (Int64) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTP1_BASE}/api/cache/stats", opt, { v => strBody(v) }) {
        body =>
        onDone(jInt(body, "networkHits"))
    }
}

func runCache(done: (String) -> Unit) {
    let sb = StringBuilder()
    let cacheOpt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingCache: true,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    getCacheStats {
        before =>
        asyncRequest("${HTTP1_BASE}/api/cache", cacheOpt, { v => "req #1: status=${v.responseCode}" }) {
            line1 =>
            sb.append("${line1}\n")
            asyncRequest("${HTTP1_BASE}/api/cache", cacheOpt, { v => "req #2: status=${v.responseCode}" }) {
                line2 =>
                sb.append("${line2}\n")
                getCacheStats {
                    after =>
                    let delta = after - before
                    sb.append("server network hits: before=${before} after=${after} delta=${delta}\n")
                    sb.append("(delta=0 => 第 2 次请求由客户端缓存服务；delta=1 => 两次都打到网络)")
                    done(sb.toString())
                }
            }
        }
    }
}

// ============ 场景 7: Cache + ETag（条件请求 / 304） ============
class EtagStats {
    let full200: Int64
    let notModified304: Int64
    let ifNoneMatchSeen: Int64
    init(full200: Int64, notModified304: Int64, ifNoneMatchSeen: Int64) {
        this.full200 = full200
        this.notModified304 = notModified304
        this.ifNoneMatchSeen = ifNoneMatchSeen
    }
}

func getEtagStats(onDone: (EtagStats) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTP1_BASE}/api/cache/etag/stats", opt, { v => strBody(v) }) {
        body =>
        onDone(EtagStats(jInt(body, "full200"), jInt(body, "notModified304"), jInt(body, "ifNoneMatchSeen")))
    }
}

func runEtag(done: (String) -> Unit) {
    let sb = StringBuilder()
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingCache: true,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    getEtagStats {
        before =>
        asyncRequest("${HTTP1_BASE}/api/cache/etag", opt, { v => "req #1: status=${v.responseCode}" }) {
            line1 =>
            sb.append("${line1}\n")
            asyncRequest("${HTTP1_BASE}/api/cache/etag", opt, { v => "req #2: status=${v.responseCode}" }) {
                line2 =>
                sb.append("${line2}\n")
                getEtagStats {
                    after =>
                    let dInm = after.ifNoneMatchSeen - before.ifNoneMatchSeen
                    let d304 = after.notModified304 - before.notModified304
                    sb.append("server stats before: 200=${before.full200} 304=${before.notModified304} inm=${before.ifNoneMatchSeen}\n")
                    sb.append("server stats after : 200=${after.full200} 304=${after.notModified304} inm=${after.ifNoneMatchSeen}\n")
                    sb.append("delta: ifNoneMatchSeen=${dInm} notModified304=${d304}\n")
                    if (dInm > 0 && d304 > 0) {
                        sb.append("=> ETag 条件请求生效（客户端发了 If-None-Match，服务端回 304）")
                    } else {
                        sb.append("=> ETag 未生效（未发送 If-None-Match）")
                    }
                    done(sb.toString())
                }
            }
        }
    }
}

// ============ 场景 8: Multipart/form-data 上传 ============
func runMultipart(done: (String) -> Unit) {
    let bin = Array<Byte>(256) { i => UInt8(i % 128) }
    let h = HashMap<String, String>()
    h.add("Content-Type", "multipart/form-data")
    let opt = HttpRequestOptions(
        method: RequestMethod.Post,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 30000,
        connectTimeout: 15000,
        header: h,
        multiFormDataList: [
            MultiFormData("field1", "text/plain", data: HttpData.StringData("hello-from-cangjie")),
            MultiFormData("file1", "application/octet-stream", remoteFileName: "cangjie.bin", data: HttpData.ArrayData(bin))
        ]
    )
    asyncRequest("${HTTP1_BASE}/api/upload/multipart", opt, {
        v =>
        let s = strBody(v)
        let sb = StringBuilder()
        let partCount = jInt(s, "partCount")
        sb.append("HTTP ${v.responseCode} | partCount=${partCount} totalBytes=${jInt(s, "totalBytes")} boundary=${jStr(s, "boundary")}\n")
        for (i in 0..partCount) {
            sb.append("  part name=${jArrElemStr(s, "parts", i, "name")} filename=${jArrElemStr(s, "parts", i, "filename")} size=${jArrElemInt(s, "parts", i, "size")} type=${jArrElemStr(s, "parts", i, "contentType")}\n")
        }
        sb.toString()
    }, done)
}

// ============ 场景 9: 二进制上传（octet-stream） ============
func runBinary(done: (String) -> Unit) {
    let payload = Array<Byte>(4096) { i => UInt8((i * 31) % 128) }
    let opt = HttpRequestOptions(
        method: RequestMethod.Post,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 30000,
        connectTimeout: 15000,
        extraData: HttpData.ArrayData(payload)
    )
    asyncRequest("${HTTP1_BASE}/api/upload/binary", opt, {
        v =>
        let s = strBody(v)
        "HTTP ${v.responseCode} | bytes=${jInt(s, "bytes")} sha256=${jStr(s, "sha256")}\nserver saw content-type: ${jStr(s, "contentType")}"
    }, done)
}

// ============ 场景 10: 网络安全配置 trust-anchors ============
// 不发代码级 caPath —— 信任来自 network_config.json base-config.trust-anchors
func runNscTrust(done: (String) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        usingProtocol: HttpProtocol.Http2,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTPS_BASE}/api/protocol", opt, {
        v =>
        let s = strBody(v)
        "HTTP ${v.responseCode} | server saw: ${jStr(s, "protocol")}\nnote: 未传 caPath，信任来自 network_config.json trust-anchors"
    }, done)
}

// ============ 场景 11: 网络安全配置 明文权限 ============
// component-config."Network Kit"=true 时允许明文 HTTP；被禁时 Network Kit 报 2300997
func runNscCleartext(done: (String) -> Unit) {
    let opt = HttpRequestOptions(
        method: RequestMethod.Get,
        expectDataType: HttpDataType.StringValue,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: acceptHeader()
    )
    asyncRequest("${HTTP1_BASE}/api/protocol", opt, {
        v =>
        let s = strBody(v)
        "HTTP ${v.responseCode} | server saw: ${jStr(s, "protocol")}\nnote: cleartextTrafficPermitted=true + component-config.'Network Kit'=true"
    }, done)
}

// ============ UI ============
@Entry
@Component
class EntryView {
    @State
    var status: String = "tap a scenario"
    @State
    var result: String = "-"
    let scroller = Scroller()

    // 异步场景入口：fn(done) 在后台线程完成网络请求（UI 不阻塞）；
    // done 内部经 launch()（ohos.base 顶层函数）调度回主线程后再更新 @State
    // （@State 只能在主线程修改，Network Kit 回调线程直接写会崩 [MTHRD1433]）。
    func runScenario(label: String, fn: ((String) -> Unit) -> Unit) {
        this.status = label
        this.result = "running..."
        let that = this
        fn({
            text =>
            launch({
                =>
                that.status = "done"
                that.result = text
                that.scroller.scrollTo(xOffset: 0, yOffset: 0)
            })
        })
    }

    func build() {
        Scroll(this.scroller) {
            Column {
                Text("Cangjie Network Kit")
                    .fontSize(26)
                    .fontWeight(FontWeight.Bold)
                Text(this.status)
                    .fontSize(14)
                Text("11 个对比场景（仅 Network Kit；RCP 无 Cangjie 绑定）")
                    .fontSize(12)
                    .fontColor(0xff888888)
                Text(this.result)
                    .fontSize(12)
                    .width(95.percent)
                    .maxLines(200)
                Button("1. 协议协商 · HTTP/1.1")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: protocol1", { done => runProtocol1(done) }) })
                Button("2. HTTP/2 · TLS/ALPN (8443)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: protocol2", { done => runProtocol2(done) }) })
                Button("3. REST 方法覆盖 (GET/POST/PUT/DELETE/HEAD/OPTIONS)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: methods", { done => runMethods(done) }) })
                Button("4. Header 正规化 (大小写, h1 vs h2)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: headers", { done => runHeaders(done) }) })
                Button("5. Cookie 手动往返")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: cookies", { done => runCookies(done) }) })
                Button("6. Cache (max-age, 服务端计数)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: cache", { done => runCache(done) }) })
                Button("7. Cache + ETag (条件请求 / 304)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: etag", { done => runEtag(done) }) })
                Button("8. Multipart/form-data 上传")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: multipart", { done => runMultipart(done) }) })
                Button("9. 二进制上传 (octet-stream)")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: binary", { done => runBinary(done) }) })
                Button("10. 网络安全配置: trust-anchors")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: nscTrust", { done => runNscTrust(done) }) })
                Button("11. 网络安全配置: 明文权限")
                    .fontSize(14)
                    .onClick({ evt => this.runScenario("run: nscCleartext", { done => runNscCleartext(done) }) })
            }.width(100.percent)
        }.height(100.percent).scrollable(ScrollDirection.Vertical)
    }
}
