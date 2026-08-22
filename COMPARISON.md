# Network Kit vs RCP — 对比矩阵

> 对比对象：`@kit.NetworkKit` 的 HTTP 模块（`@ohos.net.http`，Network Kit）与
> `@kit.RemoteCommunicationKit` 的 `rcp` 模块（Remote Communication Kit）。
> 目标：验证 RCP 取代 Network Kit（http）的可行性。
> 版本基准：API 24 (HarmonyOS 6.1.1)。

| 能力维度 | Network Kit (`@ohos.net.http`) | RCP (`@kit.RemoteCommunicationKit`) | 结论 |
|----------|-------------------------------|--------------------------------------|------|
| 引入方式 | `import { http } from '@kit.NetworkKit'` | `import { rcp } from '@kit.RemoteCommunicationKit'` | 均可 |
| HTTP/1.1 | ✅ `usingProtocol: HttpProtocol.HTTP1_1` | ✅ 自动（无显式开关，API 26 前） | 均可 |
| HTTP/2 | ✅ `usingProtocol: HttpProtocol.HTTP2`（TLS/ALPN） | ✅ 自动协商，`response.httpVersion` 可读 | 均可，RCP 无强制开关 |
| HTTP/3 | ✅ `HttpProtocol.HTTP3`（需 TLS1.3） | 支持（`assumesHTTP3Capable`） | 均可 |
| GET/POST/PUT/DELETE/HEAD/OPTIONS | ✅ `RequestMethod` 枚举 | ✅ `session.get/post/put/head/delete` + `Request(method)` | 均可 |
| PATCH | ⚠️ 枚举自 API 26 才有；API 24 需 `customMethod: 'PATCH'` | ✅ 类型内置 `'PATCH'` | **RCP 更直接** |
| 自定义方法 | ✅ `customMethod` (API 23) | ✅ HttpMethod 允许任意字符串 | 均可 |
| Header 大小写 | 透传；h2 下由框架/协议转小写 | 透传；`RequestHeaders` 类型键约束 | 见 Header 正规化实验 |
| Header 正规化（HTTP/2 全小写） | 发送端给定大小写，h2 线上小写化；h1 保留 | 同左 | 行为一致，均由协议层保证 |
| Cookie 自动管理 | ❌ 无 cookie 仓库，需手动解析 `response.cookies` 再回填 | ✅ `CookieRepository` (API 23) 自动存/带 | **RCP 优势明显** |
| Cache | ⚠️ `usingCache: true` 默认开启，但实测默认配置下 max-age 缓存与 ETag 条件请求均未生效 | ✅ 需显式 `ResponseCache` (API 20) + `CacheControl`，实测 max-age 命中 + ETag 304 均正常 | **RCP 缓存能力更强** |
| Multipart/form-data | ✅ `multiFormDataList` (API 11)，`data` 支持 string/ArrayBuffer/文件路径 | ✅ `rcp.MultipartForm`（原生，支持字段顺序 `keys`） | 均可，RCP 心智更贴近表单 |
| 二进制上传 (octet-stream) | ✅ `extraData: ArrayBuffer` + header 声明 content-type | ✅ ArrayBuffer 请求体 + content-type | 均可 |
| 响应体类型 | `result` 按 content-type/`expectDataType` 自动转 string/Object/ArrayBuffer | `body: ArrayBuffer` + `toString()`/`toJSON()` | 均可 |
| 协议版本观察 | ✅ `connectionExtraInfo.networkProtocolName` (API 24) | ✅ `response.httpVersion` ('1.0'/'1.1'/'2'/'3') | 均可 |
| 超时控制 | ✅ `connectTimeout` / `readTimeout` | ✅ `Configuration.transfer.timeout` | 均可 |
| 重定向 | ✅ `maxRedirects` | ✅ `autoRedirect` | 均可 |
| 证书/CA | ✅ `caData`/`caPath`/`certificatePinning` | ✅ `security.remoteValidation` / `certificate` | 均可 |
| 会话/连接复用 | 每次 `createHttp()` 一个请求任务 | ✅ `Session` 生命周期管理 + 连接池 | **RCP 更工程化** |
| 拦截器 | ✅ 全局 HTTP 拦截器（API 24，只读/可修改） | ✅ `Interceptor`（请求/响应） | 均可 |
| 取消请求 | `destroy()` | ✅ `session.cancel(request)` | RCP 更灵活 |
| 流量统计/调试 | ⚠️ `performanceTiming` | ✅ `tracing` + `timeInfo` + `debugInfo` | **RCP 更完整** |

## 关键差异总结

1. **协议开关**：需要"强制指定协议版本"时 Network Kit 有显式枚举；RCP 在 API 26 之前
   只能依赖 ALPN 自动协商（26 起才有 `httpVersionSelectCallback`）。日常使用无影响。
2. **Cookie**：这是 RCP 明显优于 Network Kit 的点。Network Kit 需要手动解析
   `Set-Cookie` 并回填 `Cookie` header；RCP 的 `CookieRepository` 自动完成。
3. **Cache**：Network Kit "零配置默认开启"，但控制能力弱（只能 flush/delete）；
   RCP 默认不缓存，配置 `ResponseCache` 后能力完整（过期策略、LRU、持久化、`noCache`/`noStore` 等）。
4. **PATCH 等方法的 API 表面**：RCP 的 `HttpMethod` 从一开始就包含 PATCH；
   Network Kit 的 `RequestMethod.PATCH` 到 API 26 才加入，API 24 需 `customMethod`。
5. **Header 正规化**：两套框架行为一致——HTTP/1.1 线上保留大小写、HTTP/2 线上全小写，
   均由 HTTP 协议栈保证，开发者无需特殊处理（本仓库的 `/api/headers` 实验可验证）。

## 模拟器实测结果（HarmonyOS 6.1.1 / API 24, Pura 90 emulator）

> 通过 App 内逐场景点击 "Network Kit" / "RCP" 按钮，Mock Server 记录每次请求。

| 场景 | Network Kit 实测 | RCP 实测 |
|------|------------------|----------|
| 协议协商 HTTP/1.1 | ✅ server saw HTTP/1.1, client "HTTP/1.1" | ✅ client HTTP/1.1 |
| HTTP/2 (TLS/ALPN) | ✅ server saw HTTP/2, client "HTTP/2" | ✅ client HTTP/2 (自动协商) |
| REST 方法 (7 个) | ✅ 全 200，含 PATCH（经 `customMethod`） | ✅ 全 200，PATCH 原生支持 |
| Header 大小写 h1 | ⚠️ **发送时全部转小写**：`x-allcaps-hdr` | ✅ **保留原始大小写**：`X-ALLCAPS-HDR` |
| Header 大小写 h2 | ✅ 全小写（RFC 7540） | ✅ 全小写（RFC 7540） |
| Cookie | ✅ 需手动解析（**Netscape cookie-file 格式**，非 `name=value;`） | ✅ CookieRepository 自动存取 |
| Cache | ⚠️ `usingCache: true` 下第二次请求**未命中缓存**（服务端 delta=2） | ✅ `ResponseCache` 第二次请求命中缓存（delta=1, `servedFromCache=true`） |
| Cache + ETag | ❌ **未发送 If-None-Match**（`ifNoneMatchSeen=0`），两次均 200 走网络 | ✅ **If-None-Match → 304 → 复用缓存**（`ifNoneMatchSeen=1, notModified304=1`，`servedFromCache=true`） |
| Multipart 上传 | ✅ 2 parts（文本 + 二进制文件） | ✅ 2 parts |
| 二进制上传 | ✅ 4096 bytes, sha256 一致 | ✅ 4096 bytes, sha256 一致 |

### 实测发现的三个关键差异

1. **Header 正规化在 HTTP/1.1 上就有差异**：Network Kit 在 HTTP/1.1 下也会把自定义
   header 名**统一转成小写**再发送（服务端 rawHeaders 收到 `x-allcaps-hdr`），而 RCP
   会**保留开发者传入的大小写**（`X-ALLCAPS-HDR`）。HTTP/2 下两者都小写（协议强制）。
   对依赖 header 名大小写的旧服务端（罕见但存在），RCP 更贴近原始发送；Network Kit
   更"规范"但会改变线上大小写。

2. **缓存命中行为相反（含 ETag 条件请求）**：
   - **max-age 场景**（`Cache-Control: public, max-age=60`）：RCP 显式配置的
     `ResponseCache` 第二次请求命中缓存（服务端计数不再增加）；Network Kit 默认
     `usingCache: true` 下第二次请求**仍打到网络**（服务端计数 +1）。
   - **ETag 场景**（`Cache-Control: no-cache` + `ETag`，强制每次重新验证）：RCP 第 2
     次请求正确携带 `If-None-Match`，服务端回 `304 Not Modified`，RCP 消费 304 并复用
     缓存（`servedFromCache=true`，状态码仍透传 200）；**Network Kit 两次请求都没有
     携带 If-None-Match**（服务端 `ifNoneMatchSeen=0`），每次都是完整 200 走网络，
     即默认配置下**不支持/未启用 ETag 重新验证**。
   - 结论：若业务依赖 HTTP 缓存语义（max-age / ETag / 304），RCP 的 `ResponseCache`
     开箱即用；Network Kit 可能需要配合 `http.createHttpResponseCache()` 与 `flush()`
     手动管理，且默认配置下实测缓存与条件请求均未生效，值得进一步验证。

3. **Network Kit 的 cookies 字段格式**：`response.cookies` 返回的是 **Netscape
   cookie-file 格式**（`#HttpOnly_10.0.2.2\tFALSE\t/\tFALSE\t0\tmock_session\tabc...`），
   不是 `name=value; name=value`，开发者自行解析时需按 tab 分隔处理（本工程
   `NetKitScenarios.extractCookieHeader()` 演示了两种格式的兼容解析）。

## 可行性结论（模拟器实测后更新）

- **可平滑替换**：REST 方法、HTTP/1.1/2 协议、Multipart、二进制上传等核心 HTTP
  能力，RCP 均覆盖且 API 更统一，实测全部通过。
- **需注意**：若现有代码依赖 Network Kit 的"零配置缓存"（`usingCache: true`），
  实测在默认配置下并未命中缓存，RCP 反而需要显式配置 `ResponseCache` 才能生效——
  迁移时两者都要重新审视缓存配置。
- **Header 大小写**：若业务或服务端对 header 名大小写敏感（如某些网关做签名校验），
  从 Network Kit 迁到 RCP 后 HTTP/1.1 上的 header 名会从"全小写"变成"保留原大小写"，
  需确认服务端兼容。
- **收益**：Cookie 自动管理（CookieRepository）、会话/连接池、拦截器、流量统计等
  工程能力，RCP 明显更省心。
