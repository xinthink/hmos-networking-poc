# cj-network-compare — Cangjie 版 Network Kit 对比实验

纯 **Cangjie**（仓颉）HarmonyOS App，把 `network-compare/` 的 11 个 HTTP 对比场景用
Cangjie 语言 + Network Kit（`import kit.NetworkKit.*`）全部实现一遍，验证 Cangjie 生态
下的网络能力，并与 ArkTS 版 Network Kit 的行为对齐。

> 本工程**没有 RCP / Axios**：Remote Communication Kit **没有 Cangjie 绑定**
> （`kit.RemoteCommunicationKit` 不存在），Axios 是 ArkTS/JS 库。Cangjie 侧网络框架
> 只有 Network Kit 可选。详见根目录 `COMPARISON.md`「Cangjie 语言视角」章节。

## 快速开始

```bash
# 1. 启动 mock server（必须先于 App）
cd ../mock-server && npm start        # :8080 (HTTP/1.1) + :8443 (HTTPS/HTTP2)

# 2. 构建 + 部署到模拟器
cd ../cj-network-compare
devecocli build
devecocli run --device "Pura 90" --skip-build --uninstall
```

模拟器访问宿主机用 `10.0.2.2`（App 内已固定；真机需改为开发机局域网 IP）。

## 11 个场景（与 ArkTS 版一一对应）

| # | 场景 | Cangjie Network Kit 实测结论 |
|---|------|------------------------------|
| 1 | 协议协商 HTTP/1.1 | ✅ server saw HTTP/1.1（`usingProtocol: HttpProtocol.Http1_1`） |
| 2 | HTTP/2 TLS/ALPN (8443) | ✅ server saw HTTP/2（`HttpProtocol.Http2` + `caPath` 自签证书） |
| 3 | REST 方法覆盖 | ✅ GET/POST/PUT/DELETE/HEAD/OPTIONS 全 200；**PATCH 不可用**（Cangjie `RequestMethod` 无 Patch、无 `customMethod`） |
| 4 | Header 正规化 | ⚠️ h1 下发送即转小写（`x-allcaps-hdr`）；h2 全小写（RFC 7540），与 ArkTS 版一致 |
| 5 | Cookie 手动往返 | ✅ `response.cookies` 为 **Netscape cookie-file 格式**（tab 分隔），手动解析回填 `Cookie` header 后 server 收到 |
| 6 | Cache (max-age) | ⚠️ `usingCache: true` 未命中（服务端 delta=2），与 ArkTS 版一致 |
| 7 | Cache + ETag | ❌ 未发送 If-None-Match（delta 0/0），两次 200，与 ArkTS 版一致 |
| 8 | Multipart 上传 | ✅ partCount=2（文本 + 二进制 part）；**必须显式设 `Content-Type: multipart/form-data`** |
| 9 | 二进制上传 | ✅ 4096 bytes，服务端 sha256 与客户端 payload 完全一致 |
| 10 | trust-anchors | ✅ 无 `caPath` 时 HTTPS 成功（network_config.json 应用级信任锚点生效） |
| 11 | 明文控制 | ✅ `component-config."Network Kit"` 生效（明文 HTTP 200） |

## 关键配置

- **host / 端口**：`entry/src/main/cangjie/index.cj` 顶部常量
  `HTTP1_BASE = http://10.0.2.2:8080`、`HTTPS_BASE = https://10.0.2.2:8443`。
- **自签 CA**：`entry/src/main/resources/resfile/mock-ca/`（`cert.pem` + `<hash>.0`），
  `CA_PATH` 指向 bundle 只读路径
  `/data/storage/el1/bundle/entry/resources/resfile/mock-ca/cert.pem`。
  ⚠️ mock server 重新生成证书后必须同步替换本目录文件。
- **网络安全配置**：`entry/src/main/resources/base/profile/network_config.json`
  （trust-anchors + `component-config."Network Kit": true`），与
  `network-compare/` 保持一致。

## Cangjie 特有难点（写代码前必读）

- **@State 跨线程崩溃**：Network Kit 回调在后台线程，回调里直接写 `@State` 会崩
  （`[MTHRD1433]`）。场景函数全部写成异步回调风格（`done(text)`），结果经
  `launch({ ... })`（`ohos.base` 顶层函数，`import kit.ArkUI.*` 可用）调度回主线程
  后更新 `@State`。**无 Monitor、无 spawn、无阻塞原语**，UI 不阻塞。
- **lambda 捕获 var 不能作为参数传递**：跨回调的状态放类字段（如 `MethodRunner`），
  用方法递归代替递归闭包。
- **无 JSON 库**：标准库/kit 无 JSON 解析声明，`index.cj` 手写极简提取器
  （`jStr`/`jInt`/`jObjEntries`/`jArrElemStr`），仅适用于 mock server 的扁平响应。
- **`Byte` 即 `UInt8`**：数值转换一律用类型构造函数（`UInt8(x)`），无 `.toUInt8()`。
- 更多约束见本工程 `AGENTS.md` 踩坑清单。

## 验证

构建 → `devecocli run` 部署 → `hdc shell uitest dumpLayout` + `uitest uiInput click`
逐场景点击，对照 mock server 的 `[req]` 日志与计数端点（`/api/cache/stats`、
`/api/cache/etag/stats`）验证。注意 `dumpLayout` 对长文本只导出 ~100 字符（多行 Text
的 bounds 高度仍是真实高度）。
