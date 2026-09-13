# Network Kit vs RCP vs Axios — 对比与替换可行性验证

> 验证 RCP (Remote Communication Kit, `@kit.RemoteCommunicationKit`) 是否可以取代
> Network Kit 的 HTTP 能力 (`@ohos.net.http` / `@kit.NetworkKit`)，并顺带对比最流行的
> 三方 HTTP 库 `@ohos/axios`（OpenHarmony 版 Axios，底层封装 `@ohos.net.http`）在同一
> 批场景上的行为差异。

本仓库包含以下独立工程（后续还会继续添加其他工程）：

| 目录 | 工程 | 说明 |
|------|------|------|
| [`network-compare/`](./network-compare) | HarmonyOS 移动 App | 同一套场景分别用 Network Kit、RCP 与 Axios 实现，UI 上三列并排展示结果 |
| [`cj-network-compare/`](./cj-network-compare) | 纯 Cangjie App | 11 个场景用 Cangjie Network Kit 实现 + 11 个场景用 `stdx.net.http` 实现（RCP 无 Cangjie 绑定） |
| [`mock-server/`](./mock-server) | Node.js Mock Server | 同时提供 HTTP/1.1（8080 明文）、HTTP/2（8443 TLS/ALPN）与用户 CA 实验用 TLS（9443） |

文档索引：

| 文档 | 内容 |
|------|------|
| [`COMPARISON.md`](./COMPARISON.md) | 逐项对比矩阵与可行性结论（本仓库实测） |
| [`network-compare/NSC-VERIFICATION.md`](./network-compare/NSC-VERIFICATION.md) | **NSC 验证套件文档**：`ets/nsc/` 模块地图、14 场景清单（信任/明文/证书锁定/用户 CA × 三框架 = 42 行）、按系统版本的结果矩阵（含真机）、跨版本手工复验流程、build-variant 实验、已知坑 |
| [`docs/harmonyos-network-libraries.md`](./docs/harmonyos-network-libraries.md) | **技术文档**：四类网络库（Network Kit ArkTS/Cangjie、RCP、Axios、stdx.net.http）的定位、生态、技术原理、优缺点与约束；含架构图与 RCP 进程/内存隔离分析 |

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

另有 **NSC 验证套件 14 个场景**（`network-compare/entry/src/main/ets/nsc/`，卡片排在上述 9 张
常规卡片之后，共 23 张；可用首页顶部「自检 NSC × RCP 组」按钮一次跑完 14 × 3 = **42 行**
并写 hilog）：

| # | 场景 key | 验证内容 | 实测结论 |
|---|----------|----------|----------|
| 10 | `nscTrust` | 无代码级 CA（NK 无 `caData` / RCP 无 `remoteValidation` / axios 无 `caPath`），纯靠 NSC `trust-anchors` | NK ✅ / **RCP ❌ `1007900060`** / axios ✅ |
| 11 | `nscCleartext` | `component-config` 明文开关是否约束该组件（NK 默认受控，RCP API 23 起可配，默认不受控） | 默认配置三方 200；置 true 后被拦 `1007900201` |
| 12 | `nscTrustSystem` | RCP 显式 `remoteValidation='system'`：NSC 与应用级信任谁优先 | RCP ❌ `1007900060` → 两种 config 互不相干 |
| 13 | `nscTrustCa` | 代码级 CA 覆盖默认（`caData` / `remoteValidation.content` / `caPath`） | 三方 200 |
| 14 | `nscTrustSkip` | RCP 独有：`'skip'` 绕过全部链校验（NK/axios 为 N/A） | 200（放弃校验） |
| 15 | `nscTrustCallback` | RCP 独有：`ValidationCallback` 完全替换默认信任逻辑 | 复刻 NSC 语义的唯一手段 |
| 16 | `pinSpki` | pin = 公钥(SPKI) SHA-256 base64（`publicKeyHash` 的摘要语义） | 三方 200 |
| 17 | `pinWrong` | 链正常但 pin 错 → 是否强制锁定 | 三方 FAIL（`2300090` / `1007900090`） |
| 18 | `pinCertHash` | 用**整证书**摘要作 pin | 三方 FAIL（摘要语义必须是 SPKI） |
| 19 | `pinBackup` | `[错误, 正确]` → pin 数组语义 | 三方 200 → 数组是**白名单** |
| 20 | `pinSkipTrust` | RCP 独有：`'skip'` + 错误 pin | FAIL `1007900090` → `'skip'` **不**放弃 pinning |
| 21 | `pinUntrustedTrust` | RCP 独有：`'system'` + 正确 pin | FAIL `1007900060` → 正确 pin 不能救回不受信链（两者是 **AND**） |
| 22 | `userCaTrust` | 不带代码级 CA 访问 `:9443`（证书只由用户 CA 签发）——设备装了代理 CA 时能否被 MITM | 默认三方 200（**都信任用户 CA**）；`trust-*-user-ca: false` 后三方 FAIL → **NSC 此项能保护 RCP** |
| 23 | `userCaByCodeCa` | 同一端点的代码级 CA 对照 | 三方 200（否则核心探针不可解） |

> 每张卡片三列（Network Kit / RCP / Axios）独立可点；套件说明、结果矩阵（含真机）、
> 变体实验与跨版本复验流程见
> [`network-compare/NSC-VERIFICATION.md`](./network-compare/NSC-VERIFICATION.md)。

## 快速开始

### 1. 启动 Mock Server

```bash
cd mock-server
npm run certs     # 首次：生成自签名证书
npm run user-ca   # 首次：生成"用户 CA"实验材料（:9443 用；证书入库、私钥 gitignore）
npm start         # :8080 (HTTP/1.1) + :8443 (HTTP/2) + :9443 (用户 CA 实验)
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
- 真机：`hdc -t <serial> rport tcp:8080 tcp:8080`（8443/9443 同理）做反向转发后填
  `127.0.0.1`（本机真机与宿主同网段但 ping 不通）。
  ⚠️ 真机（零售机）安装需华为签发的调试 profile：用 DevEco
  `File ▸ Project Structure ▸ Signing Configs ▸ 自动签名` 配一次；它会改写
  `network-compare/build-profile.json5`，**提交前请还原**。完整步骤见
  [`network-compare/NSC-VERIFICATION.md`](./network-compare/NSC-VERIFICATION.md) §11。

### 3. 逐场景点击 "Network Kit" / "RCP" / "Axios" 按钮对比结果

NSC 那 14 张卡片不用逐张点：点首页顶部 **「自检 NSC × RCP 组（结果写 hilog）」** 一次跑完
42 行，结果既回填 UI 三列，也写进 hilog（关键字 `NSCTEST`），便于无头验证：

```bash
devecocli log --device "Pura 90" --bundle-name com.example.networkcompare \
  --keyword NSCTEST --from 5m --tail 100 | grep NSCTEST
```

> ⚠️ 跑 UI 自动化时不要并行执行其它 `hdc`/`uitest` 命令（两个 uitest 会话会互相阻塞）。

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

## 实测状态（模拟器 + 真机）

✅ **9 个常规场景**已在本机模拟器与真机上端到端跑通（App → Mock Server，**三框架并排对比**），
另有 **NSC 验证套件 14 场景**（42 行）在模拟器与真机上逐行一致。
实测发现的关键差异（详见 [COMPARISON.md](./COMPARISON.md)）：

1. **HTTP/1.1 下 header 大小写行为不同**：Network Kit 会把自定义 header 名统一转成
   小写再发送（服务端收到 `x-allcaps-hdr`）；RCP 保留开发者传入的大小写
   （`X-ALLCAPS-HDR`）；**axios 与 Network Kit 一样全小写**（底层走 net.http）。
   HTTP/2 下三者均小写（协议强制）。
2. **缓存命中相反（含 ETag）**：
   - max-age 场景：RCP 显式配置的 `ResponseCache` 第二次请求命中缓存（服务端计数
     不再增加）；Network Kit 默认 `usingCache: true` 下第二次请求仍打到网络；
     **axios 无缓存层，两次都走网络**（服务端 delta=2）。
   - **ETag 场景**（`Cache-Control: no-cache` + ETag）：RCP 第 2 次请求正确携带
     `If-None-Match`，服务端回 `304`，RCP 复用缓存（`servedFromCache=true`）；
     **Network Kit 两次请求均未携带 If-None-Match**（服务端 `ifNoneMatchSeen=0`）；
     **axios 也无自动 ETag，且默认 `validateStatus` 把 304 当错误 reject**（需自定义
     validateStatus 才能消费）。
3. **Network Kit 的 cookies 字段是 Netscape cookie-file 格式**（tab 分隔），不是
   `name=value;` 格式，手动解析时需特殊处理（RCP 的 CookieRepository 无此问题；
   axios 更"裸"——连 `response.cookies` 都不透出，只能解析 `set-cookie` 响应头）。
4. **网络安全配置（network_config.json）支持不同**：
   - **trust-anchors（应用级信任 CA）**：Network Kit **遵循**（base-config 与
     domain-config 都需配置，无代码级 `caData` 时 HTTPS 成功）；RCP **不遵循**，
     必须用代码级 `remoteValidation` 指定 CA；**axios 遵循**（跟随 net.http）。
   - **明文控制（component-config）**：三框架都受系统明文禁令约束，但
     `"Network Kit"` 默认受控（true）、`"Remote Communication Kit"` 默认**不受控**
     （false，API 23 起支持配置）——默认配置下全局禁明文只拦截 Network Kit 与
     axios（axios 底层是 net.http）。
5. **axios 可观测性最弱**：响应不暴露协议版本、`isCacheHit`、`cookies` 字段
   （只有 `performanceTiming`），客户端看不到连接信息，只能靠服务端回显。
6. **NSC 遵守度的规律（RCP）**：**遵守收紧性开关**（`component-config` 明文开关、顶层
   `trust-*-user-ca` 用户 CA opt-out），**忽略补充性配置**（应用级 `trust-anchors`、静态
   `pin-set`）。→ 从 Network Kit 迁到 RCP 会丢掉 NSC 里的 CA 信任锚点与证书锁定，
   需要在代码里用 `remoteValidation` / `certificatePinning` 重新配置；明文则必须显式给
   RCP 打开组件开关。

### 真机复测（2026-09，HUAWEI Pocket 2 / LEM-AL00，华为 6.1.0.135，API 24）

NSC 自检 **42 行与模拟器逐行一致**，域匹配用主机名（`localhost`）或 IP（`10.0.2.2` /
`127.0.0.1`）结论相同。由于提交版配置里没有静态 `pin-set`，又补跑了带错误 `pin-set` 的
**V4/V7 变体构建**：RCP 列仍与基线逐行一致（`pinSpki` 200、`nscTrust` 1007900060），
而同一次运行里 netkit/axios 被静态 pin 全面拦死（`2300090`）；V7 里
**rcp 明文被拦 `1007900201`** 更证明这份 NSC 在该构建中确实对 RCP 生效。
→ **"RCP 忽略 NSC `trust-anchors`、忽略 `pin-set`、遵守用户 CA opt-out"三条结论均已在真机成立**。
官方文档称"RCP 也读 `network_config.json`"与实测的冲突仍未定位（"模拟器镜像不完整"与
"RCP 只认主机名"两种解释均已被排除）。细节见
[`network-compare/NSC-VERIFICATION.md`](./network-compare/NSC-VERIFICATION.md) §11。

## 目录结构

```
.
├── README.md
├── AGENTS.md                     # repo-root agent guide (new-subproject rules)
├── COMPARISON.md                 # comparison matrix + emulator results + verdict
├── docs/
│   └── harmonyos-network-libraries.md   # technical doc: 4 HTTP libs, principles, pros/cons + diagrams
├── mock-server/                  # Node.js mock server (zero dependencies)
│   ├── server.mjs                # HTTP/1.1 (:8080) + TLS/ALPN (:8443) + user-CA TLS (:9443)
│   ├── gen-certs.mjs             # self-signed certificate generation
│   ├── gen-user-ca.mjs           # user-CA (MITM) experiment material -> certs/user-ca.pem
│   ├── gen-pins.mjs              # recompute SPKI/cert SHA-256 pins for NscPins.ets
│   ├── README.md                 # for users
│   └── AGENTS.md                 # for agents
├── network-compare/              # HarmonyOS app (standalone project, ArkTS)
│   ├── README.md                 # for users
│   ├── AGENTS.md                 # for agents
│   ├── NSC-VERIFICATION.md       # NSC suite: modules, 14-scenario matrix, variants, real-device run
│   ├── oh-package.json5          # dependencies (incl. @ohos/axios)
│   ├── entry/src/main/resources/
│   │   ├── base/profile/network_config.json   # network security config (cleartext / trust anchors)
│   │   └── resfile/mock-ca/                   # app-level trust anchors (cert.pem + <hash>.0)
│   └── entry/src/main/ets/
│       ├── pages/Index.ets                # comparison UI (9 regular cards + NSC suite cards)
│       ├── common/AppConfig.ets           # server address + embedded CA
│       ├── model/ScenarioResult.ets       # result model
│       ├── model/ScenarioDef.ets          # card interface + runner/sink types
│       ├── netkit/NetKitScenarios.ets     # Network Kit scenarios
│       ├── rcp/RcpScenarios.ets           # RCP scenarios
│       ├── axios/AxiosScenarios.ets       # @ohos/axios scenarios
│       └── nsc/                           # NSC verification suite (self-contained)
│           ├── NscSuite.ets               # card registry + headless self-test runner
│           ├── NscRcp.ets / NscNetKit.ets / NscAxios.ets
│           ├── NscPins.ets                # pin digests of the mock cert
│           └── NscEnv.ets                 # OS/API version stamp
└── cj-network-compare/           # pure-Cangjie app (standalone project)
    ├── README.md                 # for users (stdx submodule pull/update steps)
    ├── AGENTS.md                 # for agents (stdx integration, cjpm, build pitfalls)
    ├── scripts/build-stdx.sh     # stdx cross-compile script
    └── vendor/cangjie_stdx/      # git submodule (stdx source, pinned)
```

每个子工程均按规范分层维护 `README.md`（面向使用者）+ `AGENTS.md`（面向代理），
新增子工程时的完整流程见 [AGENTS.md](./AGENTS.md) 的「新增子工程的标准流程」。
