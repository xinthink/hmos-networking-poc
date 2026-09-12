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

## 场景清单（App 首页逐张卡片，Network Kit / RCP / Axios 三列运行）

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
| 10 | 网络安全配置: trust-anchors | 无代码级 CA，验证应用级信任锚点是否生效（RCP 实测不遵循） |
| 11 | 网络安全配置: 明文权限 | 探测 component-config 明文管控是否生效 |
| 12 | NSC × RCP: `remoteValidation='system'` | 显式系统 CA 库：证明 RCP 不读应用级 NSC trust-anchors |
| 13 | NSC × RCP: 代码级 CA 覆盖默认 | `remoteValidation={content}` 覆盖默认 `'system'` |
| 14 | NSC × RCP: `remoteValidation='skip'` | RCP 独有：绕过全部证书校验（Network Kit/Axios 为 N/A） |
| 15 | NSC × RCP: `ValidationCallback` | RCP 独有：自定义校验完全替换默认信任逻辑 |

> 场景 10–15 可一次跑完：点首页顶部 **「自检 NSC × RCP 组（结果写 hilog）」** 按钮，
> 结果同时写入 hilog（关键字 `NSCTEST`），便于无头验证：
> `devecocli log --device "Pura 90" --bundle-name com.example.networkcompare --keyword NSCTEST --from 5m --tail 100`
> ⚠️ 这些场景依赖 `network_config.json`，改配置需重新构建部署；矩阵与变体实验见
> [`AGENTS.md`](AGENTS.md) 与 [`../COMPARISON.md`](../COMPARISON.md)。

## 配置

- **服务器地址**：App 首页顶部可改。默认 `10.0.2.2`（模拟器访问宿主机回环）；
  真机改为开发机局域网 IP。
- **端口**：8080（HTTP/1.1 明文）/ 8443（HTTP/2 TLS），定义于
  `entry/src/main/ets/common/AppConfig.ets`。
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
├── netkit/NetKitScenarios.ets    # Network Kit scenarios
├── rcp/RcpScenarios.ets          # RCP scenarios
└── axios/AxiosScenarios.ets      # @ohos/axios scenarios
```

## 与 mock-server 的协作

- 本 App 是 mock server 的唯一客户端，通过其 HTTP 端点消费所有测试数据。
- 新增对比场景：先加 mock server 端点（含 `/stats` 计数），再按
  `NetKitScenarios.xxx` ↔ `RcpScenarios.xxx` ↔ `AxiosScenarios.xxx` 镜像实现，最后在
  `Index.ets` 加卡片（详见 [`AGENTS.md`](AGENTS.md)）。
