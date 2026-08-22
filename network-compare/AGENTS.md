# AGENTS.md — network-compare

HarmonyOS App（bundle `com.example.networkcompare`，targetSdk `6.1.1(24)` / API 24），
对比 UI + 双框架 runner。改动前先读本文件，并读仓库根 `../AGENTS.md` 的
"跨工程约定"与"已实测结论"。

## 目录结构（entry/src/main/ets/）

```
ets/
├── pages/Index.ets               # 对比 UI：场景卡片列表 + Network Kit/RCP 并排结果
├── common/AppConfig.ets          # 服务器 host/端口 + 内嵌 CA PEM（MOCK_CA_PEM）
├── model/ScenarioResult.ets      # 场景结果模型（ok/summary/detail/statusCode）
├── netkit/NetKitScenarios.ets    # Network Kit (@kit.NetworkKit) 场景实现
└── rcp/RcpScenarios.ets          # RCP (@kit.RemoteCommunicationKit) 场景实现
```

## 常用命令（在 network-compare/ 下执行）

```bash
devecocli build                                  # 编译（ArkTS 严格检查）
devecocli run --device "Pura 90"                 # 构建+安装+启动（无签名，debug 可用）
devecocli run --device "Pura 90" --skip-build --uninstall   # 改代码后仅重装
devecocli log --device "Pura 90" --bundle-name com.example.networkcompare --from 2m --tail 50
```

> `devecocli build/run` 需写 `~/.hvigor`、`~/.ohpm`，**必须在本机非沙箱环境执行**。

## 架构约定：如何新增一个对比场景

两套框架的 runner 采用**镜像方法**结构：每个场景在 `NetKitScenarios.ets` 与
`RcpScenarios.ets` 中各有一个同名 `static async` 方法，返回 `Promise<ScenarioResult>`，
UI 上一张卡片并排展示两者结果。

新增场景步骤：

1. **mock server**（`../mock-server/server.mjs`）：加端点 + 配套 `/stats` 计数端点。
2. **NetKitScenarios.ets**：加 `static async xxx()`，用 `http.createHttp()` +
   `req.request(url, options)`；`finally { req.destroy(); }`。
3. **RcpScenarios.ets**：加同名 `static async xxx()`，用 `rcp.createSession()` +
   `session.get/post/fetch(...)`；`finally { session.close(); }`（session 有数量上限，
   用完必须关）。
4. **pages/Index.ets**：在 `scenarios()` 数组加卡片，`key` 唯一，`netKit` / `rcp`
   指向上述方法（RCP 需要 `filesDir` 的场景用闭包 `() => RcpScenarios.xxx(this.filesDir)`）。
5. 构建 → 部署 → 模拟器点击验证（见"验证流程"）。

## 关键 API 事实（写代码前必读）

### ArkTS 严格限制（编译期强制，违反即编译失败）
- **禁止解构赋值**：`for (const [a, b] of ...)` 不合法 → 用对象数组 + 下标循环。
- **对象字面量必须对应显式声明的 interface/class**：`Array<{name: string}>` 不能作类型
  声明 → 在文件顶部声明 interface（如 `HeaderTarget`、`BaseTarget`、`EtagStats`）。
- **无 `any`**：JSON 解析统一 `JSON.parse(s) as Record<string, ...>`。
- `@State` 变量重新赋值才触发渲染：`Record`/数组用 `this.copyWith(...)` 生成新对象再
  赋值，不要原地改（`Index.ets` 已有该 helper）。

### API 24 (6.1.1) 能力边界
- Network Kit `RequestMethod.PATCH` **API 26 才有**；API 24 用
  `HttpRequestOptions.customMethod: 'PATCH'`（API 23+）。
- Network Kit `HttpRequestOptions.body`、`reuseConnections`、`inactivityMs` 是 API 26，
  API 24 用 `extraData`。
- Network Kit `connectionExtraInfo.networkProtocolName`（API 24）读实际协议
  （'HTTP/1.1' / 'HTTP/2' 等）；`isCacheHit` 看缓存命中。
- RCP `httpVersionSelectCallback`（强制协议版本）是 API 26；API 24 只能 ALPN 自动协商，
  用 `response.httpVersion` 观察。
- RCP `CookieRepository` API 23、`ResponseCache` API 20、`response.cacheInfo` API 20。

### HTTPS 自签名证书
- 证书 PEM 内嵌在 `AppConfig.MOCK_CA_PEM`（与 `mock-server/certs/cert.pem` 一致）。
- Network Kit：`HttpRequestOptions.caData = AppConfig.MOCK_CA_PEM`。
- RCP：`Configuration.security.remoteValidation = { content: AppConfig.MOCK_CA_PEM }`
  （`RcpScenarios.newSession()` 已封装）。
- ⚠️ **若 mock server 重新生成证书，必须同步更新 `MOCK_CA_PEM`**，否则 HTTPS 失败。

### 服务器可达性
- 模拟器访问宿主机：`10.0.2.2`（`AppConfig.host` 默认值，UI 顶部可改）。
- 真机：改为开发机局域网 IP。
- HarmonyOS 默认允许 HTTP 明文传输，无需网络安全配置。

## 验证流程（模拟器端到端，无头操作）

1. 启动 mock server：`cd mock-server && npm start`。
2. `devecocli build`（编译过 = ArkTS 严格检查过）。
3. `devecocli run --device "Pura 90"` 部署启动。
4. UI 自动化：
   ```bash
   hdc -t 127.0.0.1:5555 shell "uitest dumpLayout"     # 导出 UI 树（含 bounds）
   hdc -t 127.0.0.1:5555 file recv /data/local/tmp/layout_*.json /tmp/l.json
   # 用 python 解析 bounds 得到按钮中心坐标，然后：
   hdc -t 127.0.0.1:5555 shell "uitest uiInput click <x> <y>"
   hdc -t 127.0.0.1:5555 shell "uitest uiInput swipe 660 2400 660 800 400"  # 滚动
   ```
   ⚠️ **结果区出现后布局会下移**，按钮坐标会变，每轮点击前重新 dumpLayout 取最新坐标。
5. 结合 mock server 的 `[req] ...` 日志与计数端点（`/api/cache/stats`、
   `/api/cache/etag/stats`）验证客户端行为。

## 代码风格

- ArkTS：无 `any`、无解构、interface 在文件顶部声明。
- 场景方法返回 `ScenarioResult`：一句话摘要进 `summary`，多行详情进 `detail`。
- 场景描述与 UI 文案用中文。
