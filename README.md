# Network Kit vs RCP vs Axios — 对比与替换可行性验证

> 验证 RCP (Remote Communication Kit, `@kit.RemoteCommunicationKit`) 是否可以取代
> Network Kit 的 HTTP 能力 (`@ohos.net.http` / `@kit.NetworkKit`)，并顺带对比最流行的
> 三方 HTTP 库 `@ohos/axios`（OpenHarmony 版 Axios，底层封装 `@ohos.net.http`）在同一
> 批场景上的行为差异。

本仓库包含两个独立工程（后续还会继续添加其他工程）：

| 目录 | 工程 | 说明 |
|------|------|------|
| [`network-compare/`](./network-compare) | HarmonyOS 移动 App | 同一套场景分别用 Network Kit、RCP 与 Axios 实现，UI 上三列并排展示结果 |
| [`mock-server/`](./mock-server) | Node.js Mock Server | 同时提供 HTTP/1.1（8080 明文）与 HTTP/2（8443 TLS/ALPN） |

详细的逐项对比矩阵与可行性结论见 [COMPARISON.md](./COMPARISON.md)。

## 为什么要做这个对比

HarmonyOS NEXT 提供两套 HTTP 能力：

- **Network Kit (`@ohos.net.http`)**：从 API 9 起提供的经典 HTTP 数据请求模块，生态与
  文档成熟，但部分能力（如 multipart、cookie 管理、缓存策略）需要开发者自行组装。
- **Remote Communication Kit (RCP, `@kit.RemoteCommunicationKit`)**：API 11 起引入的
  新一代远场通信框架，自带会话管理、Cookie 仓库、磁盘缓存、拦截器、流量统计等
  "开箱即用"能力，被官方定位为更现代、更完整的网络栈。

项目目标是：在同一个 App 里用三套框架（Network Kit / RCP / Axios）打同一批接口，
量化对比它们在协议覆盖、方法支持、Header 正规化、Cookie、Cache、二进制上传上的差异，
从而判断 RCP 能否平滑替换 Network Kit（http），并看清 Axios 在鸿蒙上的行为边界。

## 对比场景（App 内一键运行）

| # | 场景 | Network Kit 做法 | RCP 做法 | Axios 做法 |
|---|------|------------------|----------|------------|
| 1 | 协议协商 HTTP/1.1 | `usingProtocol: HttpProtocol.HTTP1_1` | 无显式开关（API 26 前），ALPN 自动协商 | `usingProtocol`（同 Network Kit） |
| 2 | HTTP/2 (TLS/ALPN) | `usingProtocol: HTTP2` + `caData` | 自动协商；`response.httpVersion` 可读 | `usingProtocol` + `caPath`（无 caData） |
| 3 | REST 方法 GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS | `RequestMethod` 枚举全支持 | `session.get/post/put/head/delete` + `Request(method)` | axios 动词全支持（.d.ts 漏 `patch`，用 `request`） |
| 4 | Header 正规化（HTTP/2 全小写 vs HTTP/1.1 大小写不敏感） | 透传 header，h1 实测转小写 | 同左；保留传入大小写 | AxiosHeaders 保留大小写，底层 net.http 行为同 Network Kit |
| 5 | Cookie | 手动：读 `response.cookies`（Netscape 格式）再回填 | `CookieRepository` (API 23) 自动存取 | 手动：不透出 cookies 字段，解析 `set-cookie` 头 |
| 6 | Cache (max-age) | `usingCache: true`（默认开启，实测默认未命中缓存） | 需显式配置 `ResponseCache` (API 20) | 无缓存 API（config.cache 仅 HttpClient 适配器生效） |
| 7 | Cache + ETag (条件请求/304) | 实测**未发送 If-None-Match** | 实测 If-None-Match → 304 → 复用缓存 ✅ | 无自动 ETag；304 默认被 validateStatus 拒绝 |
| 8 | Multipart/form-data 上传 | `multiFormDataList` (API 11) | `rcp.MultipartForm`（原生） | `axios.FormData`（内部转 multiFormDataList） |
| 9 | 二进制上传 octet-stream | `extraData: ArrayBuffer` | `ArrayBuffer` 请求体 | `data: ArrayBuffer` |
| 10 | 网络安全配置: trust-anchors | 无代码级 `caData`，纯靠 `network_config.json` 信任锚点（实测✅） | 无代码级 `remoteValidation`（实测❌，需代码级配置） | 无代码级 `caPath`，底层走 net.http（预期同 Network Kit） |
| 11 | 网络安全配置: 明文权限 | `component-config."Network Kit"` 默认受控 | `component-config."Remote Communication Kit"` 默认不受控（API 23 起可配置） | 底层走 net.http，受 `"Network Kit"` 组件配置约束 |

## 快速开始

### 1. 启动 Mock Server

```bash
cd mock-server
npm run certs   # 首次：生成自签名证书
npm start       # 监听 :8080 (HTTP/1.1) 和 :8443 (HTTP/2 + HTTP/1.1)
```

### 2. 构建并运行 App

```bash
cd network-compare
devecocli build
devecocli emulator start "Pura 90"   # 或连接真机
devecocli run
```

App 首页顶部可修改服务器地址：

- 模拟器：默认 `10.0.2.2`（模拟器访问宿主机回环地址）
- 真机：改为开发机局域网 IP，如 `192.168.1.5`

### 3. 逐场景点击 "Network Kit" / "RCP" / "Axios" 按钮对比结果

## 已知关键差异（初步结论）

> 以下为代码设计结论，具体数值以 App 实测为准。

1. **协议控制**：Network Kit 可显式指定 HTTP/1.1 / HTTP/2 / HTTP/3；RCP 在 API 26
   之前没有协议开关，完全依赖 ALPN 协商，只能通过 `response.httpVersion` 观察结果。
2. **Header 正规化**：HTTP/2 规范要求 header 名全小写（RFC 7540 §8.1.2）；HTTP/1.1
   大小写不敏感。Mock Server 的 `/api/headers` 通过 `rawHeaders` 回显 h1 上的原始大小写、
   通过 h2 收到的小写名，可直接观察两套框架的行为差异。
3. **Cookie**：Network Kit 无 cookie 管理，需开发者自行解析/拼装；RCP 的
   `CookieRepository` 自动存、自动带，明显更省事。
4. **Cache**：Network Kit 默认开启缓存（`usingCache: true`），并提供
   `createHttpResponseCache()` 手动刷盘/清理；RCP 需要显式创建 `ResponseCache` 并配置
   `CacheControl`，但能力更完整（过期策略、LRU、持久化）。
5. **Multipart**：两者均有原生支持（Network Kit `multiFormDataList` 自 API 11、
   RCP `MultipartForm`），但 RCP 的 API 更贴近"表单"心智，且支持 `keys` 控制字段顺序。
6. **Binary 上传**：两者都能直接发 `ArrayBuffer`；Network Kit 需在 header 中自行声明
   `Content-Type: application/octet-stream`，RCP 同样需要（或依赖 content-type 推导）。

## 模拟器实测状态（HarmonyOS 6.1.1 / API 24, Pura 90 emulator）

✅ 全部 11 个场景已在本机模拟器上端到端跑通（App → Mock Server，两个框架并排对比）。
实测发现的四个关键差异（详见 [COMPARISON.md](./COMPARISON.md)）：

1. **HTTP/1.1 下 header 大小写行为不同**：Network Kit 会把自定义 header 名统一转成
   小写再发送（服务端收到 `x-allcaps-hdr`）；RCP 保留开发者传入的大小写
   （`X-ALLCAPS-HDR`）。HTTP/2 下两者均小写（协议强制）。
2. **缓存命中相反（含 ETag）**：
   - max-age 场景：RCP 显式配置的 `ResponseCache` 第二次请求命中缓存（服务端计数
     不再增加）；Network Kit 默认 `usingCache: true` 下第二次请求仍打到网络。
   - **ETag 场景**（`Cache-Control: no-cache` + ETag）：RCP 第 2 次请求正确携带
     `If-None-Match`，服务端回 `304`，RCP 复用缓存（`servedFromCache=true`）；
     **Network Kit 两次请求均未携带 If-None-Match**（服务端 `ifNoneMatchSeen=0`），
     ETag 重新验证未生效。
3. **Network Kit 的 cookies 字段是 Netscape cookie-file 格式**（tab 分隔），不是
   `name=value;` 格式，手动解析时需特殊处理（RCP 的 CookieRepository 无此问题）。
4. **网络安全配置（network_config.json）支持不同**：
   - **trust-anchors（应用级信任 CA）**：Network Kit **遵循**（base-config 与
     domain-config 都需配置，无代码级 `caData` 时 HTTPS 成功）；RCP **不遵循**，
     必须用代码级 `remoteValidation` 指定 CA。
   - **明文控制（component-config）**：两框架都受系统明文禁令约束，但
     `"Network Kit"` 默认受控（true）、`"Remote Communication Kit"` 默认**不受控**
     （false，API 23 起支持配置）——默认配置下全局禁明文只拦截 Network Kit。

## 目录结构

```
.
├── README.md
├── AGENTS.md                     # 仓库根代理指南（含新增子工程规范）
├── COMPARISON.md                 # 对比矩阵 + 模拟器实测结果 + 可行性结论
├── mock-server/                  # Node.js mock server（零依赖）
│   ├── server.mjs                # HTTP/1.1 (:8080) + TLS/ALPN (:8443)
│   ├── gen-certs.mjs             # 自签名证书生成
│   ├── README.md                 # 面向使用者
│   └── AGENTS.md                 # 面向代理
└── network-compare/              # HarmonyOS App（独立工程）
    ├── README.md                 # 面向使用者
    ├── AGENTS.md                 # 面向代理
    ├── oh-package.json5          # 依赖（含 @ohos/axios）
    ├── entry/src/main/resources/
    │   ├── base/profile/network_config.json   # 网络安全配置（明文/信任锚点）
    │   └── resfile/mock-ca/                   # 应用级信任 CA 证书（cert.pem + <hash>.0）
    └── entry/src/main/ets/
        ├── pages/Index.ets              # 对比 UI
        ├── common/AppConfig.ets         # 服务器地址 + 内嵌 CA
        ├── model/ScenarioResult.ets     # 结果模型
        ├── netkit/NetKitScenarios.ets   # Network Kit 场景实现
        ├── rcp/RcpScenarios.ets         # RCP 场景实现
        └── axios/AxiosScenarios.ets     # @ohos/axios 场景实现
```

每个子工程均按规范分层维护 `README.md`（面向使用者）+ `AGENTS.md`（面向代理），
新增子工程时的完整流程见 [AGENTS.md](./AGENTS.md) 的「新增子工程的标准流程」。
