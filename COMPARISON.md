# Network Kit vs RCP vs Axios — 对比矩阵

> 对比对象：`@kit.NetworkKit` 的 HTTP 模块（`@ohos.net.http`，Network Kit）、
> `@kit.RemoteCommunicationKit` 的 `rcp` 模块（Remote Communication Kit），以及
> **`@ohos/axios`**（OpenHarmony 版 Axios，2.2.13，基于 Axios v1.3.4 适配，底层封装
> `@ohos.net.http`）。
> 目标：验证 RCP 取代 Network Kit（http）的可行性，并观察最流行的三方 HTTP 库
> Axios 在鸿蒙上的行为差异。
> 版本基准：API 24 (HarmonyOS 6.1.1)。

| 能力维度 | Network Kit (`@ohos.net.http`) | RCP (`@kit.RemoteCommunicationKit`) | Axios (`@ohos/axios` 2.2.13) | 结论 |
|----------|-------------------------------|--------------------------------------|------------------------------|------|
| 引入方式 | `import { http } from '@kit.NetworkKit'` | `import { rcp } from '@kit.RemoteCommunicationKit'` | `import axios from '@ohos/axios'`（ohpm 三方库） | 均可 |
| 底层传输 | 自研 HTTP 栈 | 自研 HTTP 栈 | **封装 `@ohos.net.http`**（Network Kit 的糖衣） | axios 网络行为跟随 Network Kit |
| HTTP/1.1 | ✅ `usingProtocol: HttpProtocol.HTTP1_1` | ✅ 自动（无显式开关，API 26 前） | ✅ `usingProtocol`（同 Network Kit） | 均可 |
| HTTP/2 | ✅ `usingProtocol: HttpProtocol.HTTP2`（TLS/ALPN） | ✅ 自动协商，`response.httpVersion` 可读 | ✅ `usingProtocol`（TLS/ALPN） | 均可 |
| HTTP/3 | ✅ `HttpProtocol.HTTP3`（需 TLS1.3） | 支持（`assumesHTTP3Capable`） | 同 Network Kit（透传 `usingProtocol`） | 均可 |
| GET/POST/PUT/DELETE/HEAD/OPTIONS | ✅ `RequestMethod` 枚举 | ✅ `session.get/post/put/head/delete` + `Request(method)` | ✅ axios 动词 | 均可 |
| PATCH | ⚠️ 枚举自 API 26 才有；API 24 需 `customMethod: 'PATCH'` | ✅ 类型内置 `'PATCH'` | ⚠️ **运行时支持，但 2.2.13 的 .d.ts 漏了 `patch`**，需 `request({method:'PATCH'})` | **RCP 最直接** |
| 自定义方法 | ✅ `customMethod` (API 23) | ✅ HttpMethod 允许任意字符串 | ✅ `request({method: ...})` | 均可 |
| Header 大小写 | 透传；h1 实测转小写 | 透传；h1 保留原大小写 | AxiosHeaders 保留传入大小写，但交给 net.http → **h1 实测同 Network Kit 全小写** | 见 Header 正规化实验 |
| Header 正规化（HTTP/2 全小写） | 发送端给定大小写，h2 线上小写化；h1 实测小写 | h1 保留；h2 线上小写 | 同 Network Kit（h1/h2 均小写） | RCP h1 保留，其余一致 |
| Cookie 自动管理 | ❌ 无 cookie 仓库，需手动解析 `response.cookies` 再回填 | ✅ `CookieRepository` (API 23) 自动存/带 | ❌ 无 cookie jar，且 **`response.cookies` 不透出**，只能解析 `set-cookie` 响应头 | **RCP 优势明显** |
| Cache | ⚠️ `usingCache: true` 默认开启，但实测默认配置下 max-age 缓存与 ETag 条件请求均未生效 | ✅ 需显式 `ResponseCache` (API 20) + `CacheControl`，实测 max-age 命中 + ETag 304 均正常 | ❌ **无缓存 API**（`config.cache` 仅 HttpClient 适配器生效），`usingCache` 从不设置（net.http 默认）→ 实测未命中 | **RCP 缓存能力最强** |
| ETag / 304 | ❌ 不发送 If-None-Match | ✅ If-None-Match → 304 → 复用缓存 | ❌ 无自动；手动 If-None-Match 可用，但 **默认 `validateStatus` 拒绝 304**（promise reject） | 仅 RCP 开箱即用 |
| Multipart/form-data | ✅ `multiFormDataList` (API 11)，`data` 支持 string/ArrayBuffer/文件路径 | ✅ `rcp.MultipartForm`（原生，支持字段顺序 `keys`） | ✅ `axios.FormData`（内部转 `multiFormDataList` + `requestInStream`） | 均可 |
| 二进制上传 (octet-stream) | ✅ `extraData: ArrayBuffer` + header 声明 content-type | ✅ ArrayBuffer 请求体 + content-type | ✅ `data: ArrayBuffer` + content-type | 均可 |
| 响应体类型 | `result` 按 content-type/`expectDataType` 自动转 string/Object/ArrayBuffer | `body: ArrayBuffer` + `toString()`/`toJSON()` | 默认 **自动 JSON 解析**（`forcedJSONParsing`）；`responseType: 'string'` 关掉 | axios 最省事 |
| 协议版本观察 | ✅ `connectionExtraInfo.networkProtocolName` (API 24) | ✅ `response.httpVersion` ('1.0'/'1.1'/'2'/'3') | ❌ **不暴露** connectionExtraInfo/httpVersion（仅 `performanceTiming`） | **axios 可观测性最弱** |
| 超时控制 | ✅ `connectTimeout` / `readTimeout` | ✅ `Configuration.transfer.timeout` | ✅ `connectTimeout` / `readTimeout` / `timeout` | 均可 |
| 重定向 | ✅ `maxRedirects` | ✅ `autoRedirect` | ✅ `maxRedirects` (API 23+) | 均可 |
| 证书/CA | ✅ `caData`/`caPath`/`certificatePinning` | ✅ `security.remoteValidation` / `certificate` | ⚠️ **无 `caData`，只有 `caPath`**（需把 PEM 写文件）；另有 `certificatePinning` | RCP 最灵活 |
| 会话/连接复用 | 每次 `createHttp()` 一个请求任务 | ✅ `Session` 生命周期管理 + 连接池 | ⚠️ 每个请求一个 `createHttp()`（`enableHttpRequestReuse` API 26+） | **RCP 更工程化** |
| 拦截器 | ✅ 全局 HTTP 拦截器（API 24，只读/可修改） | ✅ `Interceptor`（请求/响应） | ✅ `interceptors.request/response`（经典 Axios） | 均可 |
| 取消请求 | `destroy()` | ✅ `session.cancel(request)` | ✅ `AbortController`（signal） | RCP / axios 更灵活 |
| 流量统计/调试 | ⚠️ `performanceTiming` | ✅ `tracing` + `timeInfo` + `debugInfo` | ⚠️ `performanceTiming` | **RCP 更完整** |

## 关键差异总结

1. **协议开关**：需要"强制指定协议版本"时 Network Kit 有显式枚举；RCP 在 API 26 之前
   只能依赖 ALPN 自动协商（26 起才有 `httpVersionSelectCallback`）。axios 与 Network Kit
   一样可用 `usingProtocol`。日常使用无影响。
2. **Cookie**：这是 RCP 明显优于 Network Kit 的点。Network Kit 需要手动解析
   `Set-Cookie` 并回填 `Cookie` header；RCP 的 `CookieRepository` 自动完成。axios 同样
   需要手动，且比 Network Kit 更"裸"——连 `response.cookies` 都不透出，只能解析
   `set-cookie` 响应头。
3. **Cache**：Network Kit "零配置默认开启"，但控制能力弱（只能 flush/delete）；
   RCP 默认不缓存，配置 `ResponseCache` 后能力完整（过期策略、LRU、持久化、`noCache`/`noStore` 等）。
   axios **完全没有缓存层**（`config.cache` 只对 HttpClient 适配器生效），实测两次请求
   都走网络，与 Network Kit 默认行为一致。
4. **PATCH 等方法的 API 表面**：RCP 的 `HttpMethod` 从一开始就包含 PATCH；
   Network Kit 的 `RequestMethod.PATCH` 到 API 26 才加入，API 24 需 `customMethod`；
   axios 运行时支持但 **2.2.13 的 .d.ts 漏了 `patch`**，需 `request({method:'PATCH'})`。
5. **Header 正规化**：HTTP/1.1 下三框架并不一致——**Network Kit 与 axios 都统一转小写
   （axios 因底层走 net.http），只有 RCP 保留原大小写**；HTTP/2 下三者全小写（协议强制）。
   对依赖 header 名大小写的旧服务端，RCP 最贴近原始发送。
6. **axios 本质是 Network Kit 的"糖衣"**：适配器内部调用 `@ohos.net.http` 的
   `httpRequest.request(...)`，因此协议协商、h1 header 小写化、trust-anchors、明文管控
   等网络行为与 Network Kit 一致；差异来自 axios 层：自动 JSON 解析、拦截器、
   `validateStatus` 错误模型、响应字段裁剪、无 `caData`、.d.ts 缺 `patch`。
7. **304 在 axios 里默认是"错误"**：默认 `validateStatus` 只接受 `200 <= status < 300`，
   服务端回 304 时 promise 会 reject（`AxiosError`，`err.response.status === 304`）；
   要消费 304 必须自定义 `validateStatus`。三框架中只有 axios 把 304 当异常（RCP 静默
   消费并复用缓存，Network Kit 根本不发条件请求）。
8. **axios 可观测性最弱**：响应没有协议版本、没有 `isCacheHit`、没有 `cookies` 字段
   （只有 `performanceTiming`），做 HTTP 诊断时信息最少。

## 模拟器实测结果（HarmonyOS 6.1.1 / API 24, Pura 90 emulator）

> 通过 App 内逐场景点击 "Network Kit" / "RCP" / "Axios" 按钮，Mock Server 记录每次请求。

| 场景 | Network Kit 实测 | RCP 实测 | Axios 实测 |
|------|------------------|----------|-----------|
| 协议协商 HTTP/1.1 | ✅ server saw HTTP/1.1, client "HTTP/1.1" | ✅ client HTTP/1.1 | ✅ server saw HTTP/1.1；**client 侧无观测字段**（不暴露 connectionExtraInfo/httpVersion） |
| HTTP/2 (TLS/ALPN) | ✅ server saw HTTP/2, client "HTTP/2" | ✅ client HTTP/2 (自动协商) | ✅ server saw HTTP/2（`caPath` 文件方式信任自签 CA 生效） |
| REST 方法 (7 个) | ✅ 全 200，含 PATCH（经 `customMethod`） | ✅ 全 200，PATCH 原生支持 | ✅ 全 200（PATCH 经 `request({method:'PATCH'})` 绕过 .d.ts 缺失） |
| Header 大小写 h1 | ⚠️ **发送时全部转小写**：`x-allcaps-hdr` | ✅ **保留原始大小写**：`X-ALLCAPS-HDR` | ⚠️ **同 Network Kit 全小写**：`x-allcaps-hdr` |
| Header 大小写 h2 | ✅ 全小写（RFC 7540） | ✅ 全小写（RFC 7540） | ✅ 全小写（RFC 7540） |
| Cookie | ✅ 需手动解析（**Netscape cookie-file 格式**，非 `name=value;`） | ✅ CookieRepository 自动存取 | ✅ 手动解析 `set-cookie` 响应头成功往返（**无 response.cookies 字段**） |
| Cache | ⚠️ `usingCache: true` 下第二次请求**未命中缓存**（服务端 delta=2） | ✅ `ResponseCache` 第二次请求命中缓存（delta=1, `servedFromCache=true`） | ❌ **无缓存层**：两次都走网络（服务端 delta=2） |
| Cache + ETag | ❌ **未发送 If-None-Match**（`ifNoneMatchSeen=0`），两次均 200 走网络 | ✅ **If-None-Match → 304 → 复用缓存**（`ifNoneMatchSeen=1, notModified304=1`，`servedFromCache=true`） | ❌ 无自动（auto delta 0/0）；**手动 If-None-Match 可用但 304 默认被 validateStatus 拒绝**（`Request failed with status code 304`），自定义 validateStatus 后可消费 |
| Multipart 上传 | ✅ 2 parts（文本 + 二进制文件） | ✅ 2 parts | ✅ 2 parts（文本字段 contentType 未设置 → 服务端 `type=undefined`，同 RCP） |
| 二进制上传 | ✅ 4096 bytes, sha256 一致 | ✅ 4096 bytes, sha256 一致 | ✅ 4096 bytes, sha256 一致 |
| 网络安全配置: trust-anchors | ✅ **系统级信任锚点生效**：无代码级 `caData` 时 HTTPS 成功（需同时在 base-config 与 domain-config 配置） | ❌ **不遵循应用级 trust-anchors**：network_config.json 配置后仍报 SSL 证书错误，必须用代码级 `remoteValidation` | ✅ **生效**（无代码级 `caPath` 时 HTTPS 成功）——底层走 net.http，同 Network Kit |
| 网络安全配置: 明文控制 | ✅ **受系统明文禁令约束**（`component-config."Network Kit"` 默认 true=受控） | ✅ **同样受约束**（`component-config."Remote Communication Kit"` 默认 **false=不受控**，设为 true 后生效） | ✅ 当前允许（受 `component-config."Network Kit"` 约束，因底层是 net.http） |

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

### Axios 实测要点（相对 Network Kit / RCP 的新差异）

Axios 实测全部 11 个场景通过（`AxiosScenarios.ets`），以下是它相对两套官方框架
**额外引入**的行为差异：

1. **Header 大小写跟随 Network Kit（h1 全小写）**：虽然 AxiosHeaders 会保留开发者传入
   的 header 名大小写，但底层 net.http 在 HTTP/1.1 上仍统一转小写（实测服务端收到
   `x-allcaps-hdr`），与 Network Kit 相同、与 RCP 不同。即**从 RCP 迁到 axios，h1
   header 大小写会从"保留"变回"全小写"**。
2. **没有缓存也没有 ETag，且 304 默认是错误**：axios 无缓存层（`config.cache` 仅
   HttpClient 适配器生效；`usingCache` 从不设置），两次 GET 都走网络（服务端 delta=2）。
   手动携带 `If-None-Match` 可以触发服务端 304，但默认 `validateStatus`（
   `200 <= s < 300`）会把 304 变成 `AxiosError`（`Request failed with status code 304`）；
   必须自定义 `validateStatus` 才能消费 304。业务若依赖 HTTP 条件请求，axios 需要
   自己实现"存 ETag → 带 If-None-Match → 吞 304"的完整逻辑。
3. **Cookie 手动程度最高**：连 `response.cookies` 都不透出（适配器只映射
   `result/responseCode/header/performanceTiming`），只能从 `set-cookie` 响应头手动
   解析。实测 `/api/cookie/set` 的 set-cookie 以独立条目返回，解析后回填 `Cookie` 头
   可正常往返。
4. **证书只有 `caPath`**：没有 `caData`，HTTPS 自签证书需先把 PEM 写到
   `${filesDir}/mock-ca.pem` 再传路径（`AxiosScenarios.ensureCaFile()`）。trust-anchors
   场景（不带 caPath）实测**遵循** network_config.json 应用级信任锚点（跟随 net.http，
   同 Network Kit，异于 RCP）。
5. **明文管控跟随 Network Kit**：底层是 net.http，`component-config."Network Kit"`
   对它生效（当前配置允许明文，实测 200）。
6. **可观测性最弱**：客户端看不到协议版本（无 connectionExtraInfo / httpVersion），
   只能依赖服务端 `/api/protocol` 回显；没有 `isCacheHit`、没有 `cookies` 字段。
7. **API 表面小坑**：2.2.13 的 .d.ts 漏了 `patch`（运行时存在）；泛型默认值是
   `any/unknown`，ArkTS 严格模式要求三个类型参数全写（`AxiosJsonResp` 等别名缓解）。
8. **自动 JSON 解析**：默认（不设 `responseType`）会把 JSON 响应自动解析成对象，
   这是三框架中唯一的"开箱即用"体验；设 `responseType: 'string'` 可拿回原始字符串。

### 网络安全配置（network_config.json）实测详析

工程已接入系统网络安全配置：`entry/src/main/resources/base/profile/network_config.json`
（证书预置于 `entry/src/main/resources/resfile/mock-ca/`）。实测两种能力：

**① trust-anchors（应用级信任 CA）**

| 配置 | Network Kit | RCP |
|------|-------------|-----|
| 仅 base-config 配 trust-anchors | ❌ SSL 错误（被 domain-config 覆盖） | ❌ SSL 错误 |
| base-config + domain-config 都配 | ✅ HTTPS 成功（无代码级 caData） | ❌ 仍报 SSL 错误 |

- **Network Kit 遵循 network_config.json 的应用级信任锚点**：base-config 与
  domain-config（`10.0.2.2`）都配置 `trust-anchors` 后，不带 `caData` 的 HTTPS 请求
  成功（连接信息显示 HTTP/2）。
- **RCP 不遵循应用级 trust-anchors**：同样的 network_config.json 下仍报
  `SSL peer certificate ... was not OK`。RCP 的 `remoteValidation: 'system'` 只信任
  系统/用户 CA，应用级 trust-anchors 必须通过代码级
  `remoteValidation: { content / folderPath }` 指定（即 `RcpScenarios.newSession()`）。
- 注意点：trust-anchors 的证书目录同时放 `cert.pem` 与 `openssl x509 -hash` 命名的
  副本（`<hash>.0`），以兼容不同加载实现。

**② cleartextTrafficPermitted / component-config（明文 HTTP 控制）**

| 配置 | Network Kit | RCP |
|------|-------------|-----|
| 全局禁明文 + 组件受控 | ✅ 拦截：`Cleartext traffic not permitted` | ✅ 拦截：`Plaintext transmission is forbidden` |
| 全局禁明文 + 组件不受控 | — | ✅ 明文仍可用（HTTP 200） |

- 两框架**都受** `component-config` 明文控制，语义为"该组件是否受系统明文禁令约束"：
  - `component-config."Network Kit"` 默认 **true**（受控）。
  - `component-config."Remote Communication Kit"` 默认 **false**（不受控，API 23 起
    支持配置）；设为 true 后与 Network Kit 行为一致。
- 即：默认配置下全局禁明文时，Network Kit 会被拦截而 RCP 不受影响；这是迁移到 RCP
  时**需要显式配置** `component-config."Remote Communication Kit": true` 才能获得同等
  明文管控的关键差异。

## Cangjie 语言视角：RCP 无 Cangjie 绑定，仅 Network Kit 可用

> 子工程 `cj-network-compare/`（纯 Cangjie App）验证了 Cangjie 生态下网络框架的选择面。
> 结论先行：**Remote Communication Kit 目前没有 Cangjie 绑定**。

- **RCP 无 Cangjie 绑定（已确认）**：API 24 Cangjie SDK（6.1.1，`~/.cangjie-sdk/6.1/cangjie`）
  的 `kit/` 声明文件共 26 个 kit（`kit.AbilityKit`、`kit.NetworkKit`、`kit.BasicServicesKit`、
  `kit.CoreFileKit` 等），**没有 `kit.RemoteCommunicationKit`**；`ohos/` 模块下也没有
  `ohos.net.rcp`。因此 Cangjie 应用**无法使用 RCP**（RCP 仅有 ArkTS 绑定），也就没有
  "Cangjie 版 RCP" 对比一说——Cangjie 侧只能选 Network Kit（`import kit.NetworkKit.*`，
  重导出 `ohos.net.http.*`）。
- Cangjie 版 Network Kit 场景实现于 `cj-network-compare/entry/src/main/cangjie/index.cj`，
  全部 11 个场景（protocol / protocol2 / methods / headers / cookies / cache / etag /
  multipart / binary / nscTrust / nscCleartext）在模拟器上实测，行为与 ArkTS 版
  Network Kit **完全一致**（见下表）。

| 场景 | Cangjie Network Kit 实测（cj-network-compare） | 与 ArkTS 版一致 |
|------|-----------------------------------------------|-----------------|
| 协议协商 HTTP/1.1 | ✅ server saw HTTP/1.1（`usingProtocol: HttpProtocol.Http1_1`） | ✅ |
| HTTP/2 (TLS/ALPN) | ✅ server saw HTTP/2（`usingProtocol: HttpProtocol.Http2` + `caPath`） | ✅ |
| REST 方法 | ✅ GET/POST/PUT/DELETE/HEAD/OPTIONS 全 200；**PATCH 无法发送** | ⚠️ 见下 |
| Header 大小写 h1 | ⚠️ 发送时转小写（server 收到 `x-allcaps-hdr`） | ✅ 同 ArkTS |
| Header 大小写 h2 | ✅ 全小写（RFC 7540） | ✅ |
| Cookie | ✅ 手动往返；`response.cookies` 为 **Netscape cookie-file 格式** | ✅ 同 ArkTS |
| Cache (max-age) | ⚠️ 未命中（服务端 delta=2） | ✅ 同 ArkTS |
| Cache + ETag | ❌ 未发送 If-None-Match（delta 0/0），两次 200 | ✅ 同 ArkTS |
| Multipart | ✅ partCount=2（文本 + 二进制 part，Network Kit 自动 boundary） | ✅ |
| 二进制上传 | ✅ 4096 bytes，sha256 与客户端 payload 一致 | ✅ |
| trust-anchors | ✅ 无 `caPath` 时 HTTPS 成功（network_config.json 生效） | ✅ 同 ArkTS |
| 明文控制 | ✅ `component-config."Network Kit"` 生效（明文 HTTP 200） | ✅ 同 ArkTS |

**Cangjie Network Kit 与 ArkTS 版的差异（写代码前必读）**：

1. **无 PATCH 且无 customMethod**：Cangjie `RequestMethod` 只有
   Options/Get/Head/Post/Put/Delete/Trace/Connect，`HttpRequestOptions` 也没有
   `customMethod` 字段（ArkTS API 24 至少可用 `customMethod` 发 PATCH）。Cangjie 下
   PATCH 请求**无法发出**，只能等服务端/客户端扩展。
2. **无 `connectionExtraInfo`**：Cangjie `HttpResponse` 没有 ArkTS 的
   `connectionExtraInfo`（`networkProtocolName` / `isCacheHit`）。协议版本只能靠
   mock server `/api/protocol` 回显（server saw），缓存命中只能靠服务端计数 delta。
3. **无 `caData`（内存 PEM），只有 `caPath`（文件路径）**：HTTPS 自签证书场景需要把
   PEM 放进 `resfile/mock-ca/`，`caPath` 指向 bundle 只读路径
   `/data/storage/el1/bundle/entry/resources/resfile/mock-ca/cert.pem`（无需写文件）。
4. **跨线程更新 @State 会崩溃**：Network Kit 回调在后台线程执行，回调里直接写
   `@State` 变量触发 `[MTHRD1433]` 崩溃（`null assertThread`）。正确模式（
   `index.cj`）：场景函数写成**异步回调风格**（`func runXxx(done: (String) ->
   Unit)`），`runScenario` 传入的 done 内部用 `launch({ ... })`（`ohos.base` 顶层
   函数，"Submit the task to the main thread"，`import kit.ArkUI.*` 可用）调度回
   主线程后再更新 `@State`。**无 Monitor、无 spawn、无任何阻塞原语**，UI 全程不
   阻塞。注意 Cangjie 限制：lambda 捕获 var 后不能作为参数传递，跨回调的状态需
   放进类字段（如 `MethodRunner` 用方法递归串行多请求）。
5. **无 JSON 库**：Cangjie 标准库/kit 无 JSON 解析声明（`ohos.encoding.json` 只有
   二进制无 `.cj.d`），`index.cj` 手写了一个针对 mock server 扁平响应的极简提取器
   （`jStr`/`jInt`/`jObjEntries`/`jArrElemStr`），不适合通用 JSON。
6. **`Byte` 即 `UInt8`**：`public type Byte = UInt8`；整数转字节用类型构造函数
   `UInt8(x)`（Cangjie 无 `.toUInt8()` 方法，数值转换一律用类型构造语法）。

## stdx.net.http（Cangjie 原生扩展库）实测对比

> 在 `cj-network-compare` 中新增了 **stdx.net.http** 对比组（S1–S11 按钮）：Cangjie
> 官方扩展标准库（`cangjie_stdx`，v0.60.5.1 源码本地构建 for OHOS aarch64），纯 Cangjie
> socket 实现 + OpenSSL dlopen。与 Network Kit 组镜像同一批场景，实测结论如下。

| 场景 | stdx.net.http 实测 | 与 Network Kit 对比 |
|------|---------------------|---------------------|
| 协议协商 HTTP/1.1 | ✅ HTTP 200，`rsp.version` 直接可读（HTTP/1.1） | 均可 |
| HTTP/2 (TLS/ALPN) | ❌ **TlsException: Can not load openssl library** | Network Kit ✅（HTTPS 可用） |
| REST 方法 | ✅ 7 个方法全 200，**含 PATCH**（任意 method 字符串） | stdx ✅ PATCH；Network Kit ❌ 无 Patch |
| Header 大小写 h1 | ⚠️ 发送即小写（server 收到 `x-mixed-case-hdr`） | 与 Network Kit 一致（RCP 保留） |
| Cookie | ✅ 手动；`Set-Cookie` 是**标准 `name=value;` 格式** | stdx 标准格式；Network Kit 是 **Netscape cookie-file 格式** |
| Cache (max-age) | ⚠️ 无 HTTP 缓存（delta=2） | 与 Network Kit 一致（未命中） |
| Cache + ETag | ❌ 未发送 If-None-Match | 与 Network Kit 一致 |
| Multipart | ✅ 手工拼 body，partCount=2 | 均可（stdx 需手工构造） |
| 二进制上传 | ✅ 4096 bytes，sha256 与客户端 payload 一致 | 均可 |
| HTTPS 信任 | ❌ 同上 TlsException（CustomCA 需 OpenSSL） | Network Kit ✅（trust-anchors/caPath） |
| 明文权限 | ✅ 明文 HTTP 可用 | stdx 原生 socket，**不经过** network_config.json 管控（架构结论） |

**stdx.net.http 在 OHOS 上的关键结论**：

1. **明文 HTTP 完全可用**：HTTP/1.1 客户端（`ClientBuilder().build()` + `client.get()`）在
   模拟器实测全部通过。**同步阻塞 API**（`send(req): HttpResponse`），比 Network Kit 的
   异步回调简单，但会阻塞调用线程（`index.cj` 用 `runStdx` 放到 spawn 线程执行）。
2. **HTTPS 不可用（硬限制）**：stdx 的 TLS 通过 **dlopen 系统 OpenSSL**（OHOS 上
   `libssl_openssl.z.so`）加载符号，而**模拟器系统没有该库** → 所有 HTTPS 场景报
   `TlsException: Can not load openssl library or function CRYPTO_get_ex_new_index`。
   真机若有 OpenSSL 系统库可能可用，但 NDK 无 OpenSSL 头文件/库，stdx 的编译也依赖
   OpenSSL 头文件（`opensslSymbols.h`），集成成本高。**结论：stdx.net.http 适合明文
   场景，HTTPS 场景仍必须用 Network Kit**。
3. **API 形态**：`HttpRequestBuilder().method("PATCH")` 支持任意方法（**PATCH 可用**，
   对比 Network Kit 无 Patch/customMethod）；`HttpResponse.version` 直接读协议版本
   （对比 Network Kit 无 connectionExtraInfo）；`HttpHeaders` 多值访问。
4. **Cookie 格式不同**：stdx 的 `Set-Cookie` 响应头是标准 `name=value; Path=/; HttpOnly`
   格式；Network Kit 的 `response.cookies` 是 Netscape cookie-file 格式（tab 分隔）。
   两者都需手动解析回填（stdx 无自动 cookie jar 接入）。
5. **Header 发送小写化**：stdx 发送 header 名转小写（server 实测 `x-mixed-case-hdr`），
   与 Network Kit 一致（RCP 保留原大小写）。
6. **构建成本极高**：stdx for OHOS 需本地交叉编译（OpenSSL 头文件 + cjc 1.1.3 兼容
   patch），且 DevEco 6.1 的 cangjie schema 扩展依赖 `@ohos/cangjie-build-support`
   （从 DevEco 插件提取 6.1.280 版）。**不建议常规工程引入**；本仓库集成仅为对比验证。

## 可行性结论（模拟器实测后更新）

- **可平滑替换**：REST 方法、HTTP/1.1/2 协议、Multipart、二进制上传等核心 HTTP
  能力，RCP 均覆盖且 API 更统一，实测全部通过。
- **需注意**：若现有代码依赖 Network Kit 的"零配置缓存"（`usingCache: true`），
  实测在默认配置下并未命中缓存，RCP 反而需要显式配置 `ResponseCache` 才能生效——
  迁移时两者都要重新审视缓存配置。
- **网络安全配置（迁移重点）**：
  - 应用级 CA 信任（trust-anchors）：Network Kit 读 network_config.json，RCP **不读**，
    迁移后需改用代码级 `remoteValidation` 指定 CA（本工程已封装于
    `RcpScenarios.newSession()`）；axios 跟随 net.http，读 network_config.json。
  - 明文管控：RCP 的 `component-config."Remote Communication Kit"` 默认不受控，需要
    明文禁令时须显式置 true，否则全局禁明文只对 Network Kit（与 axios）生效。
- **Header 大小写**：若业务或服务端对 header 名大小写敏感（如某些网关做签名校验），
  从 Network Kit 迁到 RCP 后 HTTP/1.1 上的 header 名会从"全小写"变成"保留原大小写"，
  需确认服务端兼容；axios 与 Network Kit 一样全小写，无此变化。
- **Axios 视角**：若现有代码是 axios 风格（拦截器、自动 JSON 解析、Promise 链），
  迁到 RCP 需要接受：无自动 JSON 解析（改 `toJSON()`）、无拦截器（改用
  `Interceptor`/全局拦截器）、缓存需显式配置、304 需自定义处理；迁到 Network Kit
  则注意 axios 特有的自动 JSON 解析与 `validateStatus` 语义会消失。反之，从 RCP/
  Network Kit 迁到 axios：获得拦截器与自动 JSON 解析，但要自担 Cookie、Cache/ETag、
  304 处理，并接受可观测性最弱与 `.d.ts` 缺 `patch` 的坑。
- **收益**：Cookie 自动管理（CookieRepository）、会话/连接池、拦截器、流量统计等
  工程能力，RCP 明显更省心。
