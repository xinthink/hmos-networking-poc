# network-compare（HarmonyOS App）

Network Kit vs Remote Communication Kit (RCP) vs Axios 对比验证 App。在同一个界面里用
`@kit.NetworkKit`（`@ohos.net.http`）、`@kit.RemoteCommunicationKit`（rcp）与
`@ohos/axios`（OpenHarmony 版 Axios，底层封装 `@ohos.net.http`）各跑一遍同一批 HTTP
场景，三列并排展示结果，用于验证 RCP 取代 Network Kit（http）的可行性，并观察 Axios
这个最流行的三方 HTTP 库在鸿蒙上的行为差异。

本工程是**独立 HarmonyOS 工程**（bundle：`com.example.networkcompare`，
targetSdk：`6.1.1(24)` / API 24），可被 DevEco Studio 单独打开。

> 面向代理的工程指南见 [`AGENTS.md`](AGENTS.md)；仓库总览与跨工程约定见
> [`../README.md`](../README.md)、[`../COMPARISON.md`](../COMPARISON.md)。

## 快速开始

前置：mock server 已启动（`cd ../mock-server && npm start`），模拟器或真机已连接。

```bash
cd network-compare
devecocli build                                  # 编译（ArkTS 严格检查）
devecocli run --device "Pura 90"                 # 构建+安装+启动（debug 无签名可用）
```

> `devecocli build/run` 需要写 `~/.hvigor`、`~/.ohpm`，请在本机终端执行。

**真机（HUAWEI Pocket 2 等零售机）**：需要华为签发的调试 profile —— 用 DevEco 的
`File ▸ Project Structure ▸ Signing Configs ▸ 自动签名` 配一次即可（会改写
`build-profile.json5`，**提交前请还原**）；再用 `hdc -t <serial> rport` 做端口反向转发。
完整步骤与坑见 [`NSC-VERIFICATION.md`](NSC-VERIFICATION.md) §11。真机验证已完成：
NSC 42 行结果与模拟器逐行一致，带静态 `pin-set` 的 V4/V7 变体也在真机上复现
（RCP 忽略 anchors/pin-set，而 netkit/axios 被静态 pin 拦死）。

## 场景清单（App 首页逐张卡片，Network Kit / RCP / Axios 三列运行）

常规场景 9 张（`netkit/` + `rcp/` + `axios/` 三个 runner 镜像实现）：

| # | 场景 | 说明 |
|---|------|------|
| 1 | 协议协商 HTTP/1.1 | 明文 8080，对比三框架看到的协议版本（axios 不暴露客户端连接信息） |
| 2 | HTTP/2 (TLS/ALPN) | 8443 协商 h2；Network Kit 与 axios 可显式 `usingProtocol`，RCP 自动协商 |
| 3 | REST 方法覆盖 | GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS |
| 4 | Header 正规化 | 大小写行为对比（h1 保留 vs h2 小写） |
| 5 | Cookie | Network Kit 手动、RCP CookieRepository 自动、axios 手动（不透出 cookies 字段） |
| 6 | Cache (max-age) | 第二次请求是否命中缓存（服务端计数 delta 判定） |
| 7 | Cache + ETag (304) | 是否发送 If-None-Match 并消费 304（axios 默认把 304 当错误） |
| 8 | Multipart/form-data 上传 | 文本字段 + 二进制文件部分 |
| 9 | 二进制上传 (octet-stream) | 4KB ArrayBuffer，服务端回显字节数与 sha256 |

NSC（网络安全配置）场景 14 张，由独立模块 `entry/src/main/ets/nsc/` 提供
（**NSC 验证套件**，排在常规 9 张之后；说明、结果矩阵、跨版本复验流程与变体实验见
[`NSC-VERIFICATION.md`](NSC-VERIFICATION.md)）：

| # | 场景 key | 说明 |
|---|----------|------|
| 10 | `nscTrust` | 无代码级 CA，纯靠 NSC `trust-anchors`（RCP 实测不遵循 → `1007900060`） |
| 11 | `nscCleartext` | 探测 `component-config` 明文管控是否生效 |
| 12 | `nscTrustSystem` | RCP 显式 `remoteValidation='system'`：证明 RCP 不读应用级 NSC trust-anchors |
| 13 | `nscTrustCa` | 代码级 CA 覆盖默认（`caData` / `remoteValidation.content` / `caPath`） |
| 14 | `nscTrustSkip` | RCP 独有：`'skip'` 绕过全部链校验（Network Kit/Axios 为 N/A） |
| 15 | `nscTrustCallback` | RCP 独有：`ValidationCallback` 完全替换默认信任逻辑 |
| 16 | `pinSpki` | pin = 公钥(SPKI) SHA-256 base64，确认摘要语义 |
| 17 | `pinWrong` | 链正常但 pin 错 → 是否强制锁定（`2300090` / `1007900090`） |
| 18 | `pinCertHash` | 用整证书摘要作 pin → 是否被接受（实测被拒） |
| 19 | `pinBackup` | `[错误, 正确]` → 判定 pin 数组是否为白名单 |
| 20 | `pinSkipTrust` | RCP 独有：`'skip'` + 错误 pin（pinning 是否仍生效） |
| 21 | `pinUntrustedTrust` | RCP 独有：`'system'` + 正确 pin（pin 能否救回不受信链） |
| 22 | `userCaTrust` | 不带代码级 CA 访问 `:9443`（证书只由用户 CA 签发）——测"设备装了代理 CA 时能否被 MITM" |
| 23 | `userCaByCodeCa` | 同一端点的代码级 CA 对照，必须 200（否则核心探针不可解） |

> 这 14 个场景可一次跑完：点首页顶部 **「自检 NSC × RCP 组（结果写 hilog）」** 按钮，
> 一次跑完 14 场景 × 3 框架 = **42 行**，结果同时写入 hilog（关键字 `NSCTEST`），便于无头验证：
> `devecocli log --device "Pura 90" --bundle-name com.example.networkcompare --keyword NSCTEST --from 5m --tail 100`
> ⚠️ 这些场景依赖 `network_config.json`，改配置需重新构建部署；矩阵与变体实验见
> [`AGENTS.md`](AGENTS.md) 与 [`../COMPARISON.md`](../COMPARISON.md)。

## 配置

- **服务器地址**：App 首页顶部可改。默认 `10.0.2.2`（模拟器访问宿主机回环）；
  **真机推荐用 `hdc -t <serial> rport tcp:8080 tcp:8080`（8443/9443 同理）建立反向转发，
  然后填 `127.0.0.1`** —— 本机真机与宿主同网段但 ping 不通（疑似 AP 隔离），
  改用局域网 IP 需先确认可达。
- **端口**：8080（HTTP/1.1 明文）/ 8443（HTTP/2 TLS）/ **9443（用户 CA 实验专用 TLS）**，
  定义于 `entry/src/main/ets/common/AppConfig.ets`。
- **HTTPS 证书**：mock server 自签名证书的 PEM 内嵌在 `AppConfig.MOCK_CA_PEM`。
  Network Kit 用 `caData`、RCP 用 `remoteValidation`、**Axios 用 `caPath`（无 caData，
  运行时把 PEM 写到 `${filesDir}/mock-ca.pem`）**。
  ⚠️ mock server 重新生成证书后，必须同步更新该常量，否则 HTTPS 请求失败。
- **依赖**：`@ohos/axios`（^2.2.13）声明于 `oh-package.json5`。

## 代码结构（entry/src/main/ets/）

```
ets/
├── pages/Index.ets               # comparison UI: scenario cards + three result columns
├── common/AppConfig.ets          # server host/port + embedded CA PEM
├── model/ScenarioResult.ets      # result model (ok/summary/detail/statusCode)
├── model/ScenarioDef.ets         # card interface + runner/sink types
├── netkit/NetKitScenarios.ets    # Network Kit scenarios
├── rcp/RcpScenarios.ets          # RCP scenarios
├── axios/AxiosScenarios.ets      # @ohos/axios scenarios
└── nsc/                          # NSC verification suite (self-contained)
    ├── NscSuite.ets              # card registry + headless self-test runner
    ├── NscRcp.ets / NscNetKit.ets / NscAxios.ets   # three columns, 14 scenarios
    ├── NscPins.ets               # pin digests of the mock cert (npm run pins)
    └── NscEnv.ets                # OS/API-level stamp for cross-version comparison
```

> 改 NSC 验证只需动 `ets/nsc/`；`Index.ets` 只调用 `NscSuite.cards()` 与
> `NscSuite.runSelfTest()`。

## 与 mock-server 的协作

- 本 App 是 mock server 的唯一客户端，通过其 HTTP 端点消费所有测试数据。
- 新增对比场景：先加 mock server 端点（含 `/stats` 计数），再按
  `NetKitScenarios.xxx` ↔ `RcpScenarios.xxx` ↔ `AxiosScenarios.xxx` 镜像实现，最后在
  `Index.ets` 加卡片（详见 [`AGENTS.md`](AGENTS.md)）。
