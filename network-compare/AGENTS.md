# AGENTS.md — network-compare

HarmonyOS App（bundle `com.example.networkcompare`，targetSdk `6.1.1(24)` / API 24），
对比 UI + 三框架 runner（Network Kit / RCP / Axios）。改动前先读本文件，并读仓库根
`../AGENTS.md` 的"跨工程约定"与"已实测结论"。

## 目录结构（entry/src/main/ets/）

```
ets/
├── pages/Index.ets               # comparison UI: 9 regular cards + NscSuite cards + self-test button
├── common/AppConfig.ets          # server host/port + embedded CA PEM (MOCK_CA_PEM)
├── model/ScenarioResult.ets      # scenario result model (ok/summary/detail/statusCode)
├── model/ScenarioDef.ets         # card interface + runner/sink types (shared by UI and suites)
├── netkit/NetKitScenarios.ets    # Network Kit scenarios, NSC excluded
├── rcp/RcpScenarios.ets          # RCP scenarios, NSC excluded
├── axios/AxiosScenarios.ets      # @ohos/axios scenarios, NSC excluded (see Axios notes below)
└── nsc/                          # NSC verification suite, self-contained
    ├── NscSuite.ets              # card registry + headless self-test runner (single entry point)
    ├── NscRcp.ets                # RCP column: 14 scenarios + session builders
    ├── NscNetKit.ets             # Network Kit column: control + N/A placeholders
    ├── NscAxios.ets              # axios column: control + N/A placeholders
    ├── NscPins.ets               # pin digests of the mock cert (npm run pins to recompute)
    └── NscEnv.ets                # OS/API-level stamp for cross-version comparison
```

> **NSC 验证已独立成模块**（`ets/nsc/`）：改 RCP × NSC 的验证只需动这个目录，
> `Index.ets` 只调用 `NscSuite.cards()` / `NscSuite.runSelfTest()`。套件说明、结果矩阵、
> **跨系统版本手工复验流程**：见 [`NSC-VERIFICATION.md`](NSC-VERIFICATION.md)。

## 常用命令（在 network-compare/ 下执行）

```bash
devecocli build                                  # 编译（ArkTS 严格检查）
devecocli run --device "Pura 90"                 # 构建+安装+启动（无签名，debug 可用）
devecocli run --device "Pura 90" --skip-build --uninstall   # 改代码后仅重装
devecocli log --device "Pura 90" --bundle-name com.example.networkcompare --from 2m --tail 50
```

> `devecocli build/run` 需写 `~/.hvigor`、`~/.ohpm`，**必须在本机非沙箱环境执行**。

## 架构约定：如何新增一个对比场景

三套框架的 runner 采用**镜像方法**结构：每个场景在 `NetKitScenarios.ets`、
`RcpScenarios.ets` 与 `AxiosScenarios.ets` 中各有一个同名 `static async` 方法，
返回 `Promise<ScenarioResult>`，UI 上一张卡片并排展示三者结果。

新增场景步骤：

1. **mock server**（`../mock-server/server.mjs`）：加端点 + 配套 `/stats` 计数端点。
2. **NetKitScenarios.ets**：加 `static async xxx()`，用 `http.createHttp()` +
   `req.request(url, options)`；`finally { req.destroy(); }`。
3. **RcpScenarios.ets**：加同名 `static async xxx()`，用 `rcp.createSession()` +
   `session.get/post/fetch(...)`；`finally { session.close(); }`（session 有数量上限，
   用完必须关）。
4. **AxiosScenarios.ets**：加同名 `static async xxx()`，用 `axios.get/post/...` +
   `AxiosRequestConfig`。⚠️ ArkTS 严格模式要求 axios 泛型**必须写全三个类型参数**
   （T/R/D，默认值是 `any`/`unknown` 会被编译拒绝），文件顶部已定义
   `AxiosJsonResp` / `AxiosObjResp` / `AxiosJsonErr` 别名；PATCH 用
   `axios.request({ method: 'PATCH' })`（2.2.13 的 .d.ts 漏了 `patch` 方法）。
5. **pages/Index.ets**：在 `scenarios()` 的 `cards` 数组加卡片，`key` 唯一，
   `netKit` / `rcp` / `axios` 指向上述方法（需要 `filesDir` 的场景用闭包
   `() => XxxScenarios.xxx(this.filesDir)`）。
6. 构建 → 部署 → 模拟器点击验证（见"验证流程"）。

> **例外：安全配置（NSC）相关场景不要加进上面三个 runner**，加到 `ets/nsc/` 套件里：
> 在 `NscRcp.ets` / `NscNetKit.ets` / `NscAxios.ets` 加同名方法 → 在 `NscSuite.cards()`
> 注册卡片 → 把 key 加进 `NscSuite.KEYS`（自检会跑它）。若该能力只存在于 RCP，
> 另两列返回 `ScenarioResult(true, 'N/A — 无对应能力', ...)` 占位。
> 详见 [`NSC-VERIFICATION.md`](NSC-VERIFICATION.md)。

## 关键 API 事实（写代码前必读）

### ArkTS 严格限制（编译期强制，违反即编译失败）
- **禁止解构赋值**：`for (const [a, b] of ...)` 不合法 → 用对象数组 + 下标循环。
- **对象字面量必须对应显式声明的 interface/class**：`Array<{name: string}>` 不能作类型
  声明 → 在文件顶部声明 interface（如 `HeaderTarget`、`BaseTarget`、`EtagStats`）。
- **无 `any`**：JSON 解析统一 `JSON.parse(s) as Record<string, ...>`。
- `@State` 变量重新赋值才触发渲染：`Record`/数组用 `this.copyWith(...)` 生成新对象再
  赋值，不要原地改（`Index.ets` 已有该 helper）。
- **helper 返回值赋给局部变量时要显式标注类型**：`const config: AxiosRequestConfig =
  X.baseConfig();`。省略标注会触发 `arkts-no-any-unknown`（推断穿不过 helper 返回值），
  本仓库在 `NscAxios.ets` 踩过。

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
- **Axios：没有 `caData`，只有 `caPath`** —— 需先把 PEM 写到文件再传路径
  （`AxiosScenarios.ensureCaFile(filesDir)` 已封装，写到 `${filesDir}/mock-ca.pem`）。
- ⚠️ **若 mock server 重新生成证书，必须同步更新 `MOCK_CA_PEM`**，否则 HTTPS 失败。

### Axios（@ohos/axios 2.2.13）特有事实（写代码前必读）
- **底层是 Network Kit**：`@ohos/axios` 适配器内部调用 `@ohos.net.http` 的
  `httpRequest.request(...)`，因此网络行为（h1 header 小写化、明文管控、trust-anchors
  等）默认跟随 Network Kit，差异来自 axios 层自身。
- **响应字段被裁剪**：适配器只映射 `result/responseCode/header/performanceTiming`，
  `response.cookies`、`connectionExtraInfo`（协议版本、`isCacheHit`）都拿不到。
- **泛型必须写全**：`axios.get<T, R, D>(url, config)` 三个类型参数都要显式给出
  （默认 `any`/`unknown` 触发 `arkts-no-any-unknown`）；文件顶部别名
  `AxiosJsonResp`/`AxiosObjResp`/`AxiosJsonErr` 可复用。
- **.d.ts 缺 `patch`**：2.2.13 的类型定义漏了 `AxiosInstance.patch`（运行时存在），
  用 `axios.request({ url, method: 'PATCH', data })` 代替（见 `patchRequest()`）。
- **默认自动 JSON 解析**：不设 `responseType` 时（`expectDataType` 未设置 →
  net.http 默认 STRING），`transformResponse` 会把 JSON 字符串解析成对象
  （`forcedJSONParsing=true`）；设 `responseType: 'string'` 则返回原始字符串。
- **无缓存/ETag 层**：`config.cache` 只对 HttpClient 适配器生效；axios 从不设置
  `usingCache`（net.http 默认值生效，与 Network Kit 行为一致）。
- **默认拒绝 304**：`validateStatus` 默认 `200 <= status < 300`，服务端回 304 时
  promise 会 reject（`AxiosError`，`err.response.status === 304`）；要消费 304 必须
  自定义 `validateStatus`。
- **Cookie 手动**：无 cookie jar；`response.cookies` 不透出，需从
  `resp.headers.get('set-cookie')` 手动解析再回填 `Cookie` header。
- **Multipart**：用 `axios.FormData`（`form.append(name, value, { filename, type })`），
  适配器识别 FormData 后走 `requestInStream` + `multiFormDataList`。
- **ArkTS 编译约束**：`@ohos/axios` 的 `.d.ts` 里有大量 `any`（库自身），我们代码里
  不能出现；所有 `as AxiosError` 断言用 `as AxiosJsonErr`。

### 网络安全配置（network_config.json）
- 配置文件：`entry/src/main/resources/base/profile/network_config.json`；证书目录：
  `entry/src/main/resources/resfile/mock-ca/`（含 `cert.pem` 与 `openssl x509 -hash`
  命名的 `<hash>.0` 副本）。
- 实测结论（详见 `../COMPARISON.md`「RCP SecurityConfiguration × 系统 NSC」）：
  - **trust-anchors**：Network Kit / axios 遵循（须 base-config **与** domain-config
    都配置，否则被 domain 覆盖）；**RCP 完全不遵循**应用级 trust-anchors——缺省与
    显式 `remoteValidation: 'system'` 都失败（`1007900060`），必须用代码级
    `remoteValidation`（`{content|filePath|folderPath}` / `'skip'` / `ValidationCallback`）。
  - **component-config 明文控制**：语义是"该组件**是否受**系统明文禁令约束"。
    `"Network Kit"` 默认 true；`"Remote Communication Kit"` 默认 **false**（API 23 起可配）
    → 全局 `cleartextTrafficPermitted: false` **只拦 Network Kit/axios**，RCP 不受影响；
    置 true 后 RCP 才被拦（`1007900201 Plaintext transmission is forbidden`）。
  - **用户 CA opt-out**：RCP **默认信任用户安装的 CA**（与 NetKit 同），但**遵守**
    顶层 `trust-global-user-ca` / `trust-current-user-ca = false`（拒绝后 1007900060）
    → NSC 此项**能**保护 RCP 免于"用户 CA 型中间人"（详见 `NSC-VERIFICATION.md` §6-G）。
  - **遵循度规律**：**遵守收紧性开关**（明文组件开关、用户 CA opt-out），
    **忽略补充性配置**（`trust-anchors`、`pin-set`）——不要笼统说"RCP 完全不遵守 NSC"。
  - **证书锁定**：RCP 的 `remoteValidation` 与 `certificatePinning` 是 **AND**，
    且 `'skip'` 只放弃链校验、**不放弃 pinning**；NSC 的 `trust-anchors` 与 `pin-set`
    也是 **AND**，且**生效中的静态 `pin-set` 覆盖请求级 `certificatePinning`**；
    RCP 同样**忽略** NSC 的 `pin-set`（详见 `NSC-VERIFICATION.md` §6）。
  - ⚠️ **pin 值随证书失效**：证书重新生成后必须 `cd ../mock-server && npm run pins`
    重算并更新 `ets/nsc/NscPins.ets` 及任何 `pin-set`（与 `MOCK_CA_PEM` 同级要求）。
  - ⚠️ 配置随 HAP 打包，**改动必须重新 build + 重装**（见下方"明文变体实验"）。
- ⚠️ `NscRcp.newCallbackSession()` 用 `networkSecurity.certVerificationSync`
  校验链——它对自签/不受信证书**抛异常**而非返回非 0，因此该处必须 try/catch 并映射为
  "拒绝"，否则异常会穿透 RCP 的校验回调。

### 无头验证：自检按钮 + NSCTEST 日志（推荐，别硬拖 UI）
UI 顶部有一个 **「自检 NSC × RCP 组（结果写 hilog）」** 按钮：一次点击顺序跑完
`NscSuite.KEYS`（信任/明文 6 个 + 证书锁定 6 个 + 用户 CA 2 个：`nscTrust`、`nscCleartext`、
`nscTrustSystem`、`nscTrustCa`、`nscTrustSkip`、`nscTrustCallback`、`pinSpki`、`pinWrong`、
`pinCertHash`、`pinBackup`、`pinSkipTrust`、`pinUntrustedTrust`、`userCaTrust`、
`userCaByCodeCa`）× 三框架
（`NscSuite.runSelfTest()`，在 `ets/nsc/` 内），并把每行结果写 hilog；结果同时回填 UI 三列：

```bash
hdc -t 127.0.0.1:5555 shell "hilog -r"
hdc -t 127.0.0.1:5555 shell "uitest uiInput click 660 652"     # 自检按钮中心（顶部固定位置）
sleep 20
devecocli log --device "Pura 90" --bundle-name com.example.networkcompare \
  --keyword NSCTEST --from 5m --tail 100 | grep NSCTEST
```

输出形如 `NSCTEST nscTrustSystem rcp FAIL status=1007900060 | 'system' rejected: ...`，
首尾另有 `NSCTEST ENV/DONE ...` 行**携带系统版本**（`osFullName` + `api=` + `deviceType`
+ `displayVersion`），所以日志自带版本标签，跨系统版本对比时不需要另做记录。

自检共 **42 行** = 14 场景 × 3 框架（外加 ENV/DONE）。

**为什么要有这个按钮**：`uitest dumpLayout` 在本 App 上一次往返约 2–5 秒，23 张卡片的
列表需要反复滚动+重定位，逐卡点击极慢且会被"结果区下移"打乱坐标；自检按钮把
"点 42 次 + 反复滚动"压缩成"点 1 次 + 读日志"。

⚠️ **不要并行执行 hdc/uitest**：两个 `uitest` 会话会互相阻塞，导致双方都超时
（本仓库踩过：驱动脚本与手工 dump 并行时全部任务报 CARD NOT FOUND）。

### 变体实验（build-variant，因为 NSC 随 HAP 打包）

**明文**：

| 变体 | `cleartextTrafficPermitted`(base+domain) | `component-config."Remote Communication Kit"` | 实测结果 |
|---|---|---|---|
| 提交版 | true | true | 三方明文都 200 |
| V1 | false | false | 只有 RCP 200；Network Kit/axios 报 2300997 |
| V2 | false | true | 三方全拦；RCP 报 1007900201 |

**证书锁定**（`domain-config` 加 `pin-set`，digest 取 `npm run pins` 的 SPKI 值）：

| 变体 | domain `trust-anchors` | `pin-set` | 实测结果 |
|---|---|---|---|
| V3 | 有 | 正确，未过期 | `nscTrust` 200；**动态错误 pin 被覆盖为 200** |
| V4 | 有 | 错误 | `nscTrust`/`nscTrustCa`/`pinSpki`/`pinBackup` 全 FAIL 2300090 |
| V5 | **无** | 正确 | `nscTrust` FAIL 2300060（pin 不能替代信任锚点） |
| V6 | 有 | 错误但 `expiration` 已过期 | `nscTrust` 200；动态 pin 恢复生效 |
| **V7** | 有 | 错误 + `cleartext=false` + RCP 开关 true | **同构建自证**：RCP 明文被拦（1007900201）证明开关生效，而 anchors/pin-set 仍被忽略（见 `NSC-VERIFICATION.md` §6-F） |

**用户安装的 CA（MITM 防护，见 `NSC-VERIFICATION.md` §6-G）**：

| 变体 | 用户 CA | 顶层 `trust-global-user-ca` / `trust-current-user-ca` | 实测 |
|---|---|---|---|
| U1（提交版） | 已装 | 未配置（= 信任） | 三方 `userCaTrust` 200 |
| U2 | 已装 | 都 `false` | 三方 FAIL（NK/axios 2300060、RCP 1007900060） |

> 装用户 CA 的路径：应用侧 `openInstallCertificateDialog` 在**本模拟器返回 29700004**，
> 必须走证书管理 UI —— `aa start -b com.ohos.certmanager -a MainAbility` →
> Install from storage → CA certificates → Browse → Downloads/Received → Download Manager
> → 选 `nsc-user-ca.crt` → Done → Install。文件先用
> `hdc file send certs/user-ca.pem /storage/media/100/local/files/Docs/Download/nsc-user-ca.crt` 推上去。
> ⚠️ 本机模拟器**当前仍装着**该 CA，所以基线里 `userCaTrust` 是 200（`pass=31`）。

> 结论：NSC 的 trust-anchors 与 pin-set 是 **AND**；**生效中的域级 `pin-set` 完全覆盖
> 请求级 `certificatePinning`**（动态 pin 不参与判定）；RCP 对两者都**忽略**。

流程：改 JSON → `devecocli build` → `devecocli run --device "Pura 90" --skip-build --uninstall`
→ 点自检 → 读 NSCTEST → **实验结束后 `git checkout -- <config>` 还原并重建**。

### 待验证事项（未做，勿当结论）
`NSC-VERIFICATION.md` §10 列了四项待验证：**真机复测**（现有结论全部来自 OpenHarmony 模拟器镜像）、
**主机名域匹配**（我们用的是 IP `10.0.2.2`）、**真实 MITM 代理演示**（用户已明确留待以后）、
**CA 目录形态**（同时放 `cert.pem` 与 `<hash>.0`）。
在这些完成前，RCP 遵循度结论的环境口径应写成"OpenHarmony 6.1.1(24) 模拟器 + IP 域匹配 + 当前目录形态下"。

### 跨系统版本复验（系统升级后手工做一次）
完整流程与结果矩阵见 [`NSC-VERIFICATION.md`](NSC-VERIFICATION.md) §5/§7：
跑一次自检 → 记下 `ENV` 行版本 → 与矩阵逐行比对（重点看 RCP 的信任/明文行为与错误码
`1007900060` / `1007900201` 是否变化）→ 把结果填进矩阵并在 `../COMPARISON.md` 补差异说明。

### 场景卡片说明：NSC 组（14 张，全部来自 `ets/nsc/`）
信任/明文 6 张：`nscTrust`（纯靠 NSC trust-anchors）、`nscCleartext`、
`nscTrustSystem`（显式 `'system'`）、`nscTrustCa`（代码级 CA 覆盖默认）、
`nscTrustSkip`、`nscTrustCallback`。
证书锁定 6 张：`pinSpki`、`pinWrong`、`pinCertHash`、`pinBackup`、
`pinSkipTrust`、`pinUntrustedTrust`（后两张为 RCP 独有组合）。
用户 CA 2 张：`userCaTrust`（不带代码级 CA 访问 `:9443`，测用户 CA 是否被信任）、
`userCaByCodeCa`（同一端点的代码级 CA 对照，必须 200）。
RCP 独有能力的卡片，Network Kit/axios 列返回
`ScenarioResult(true, 'N/A — 无对应能力', ...)` 占位（不复用 `error()`，避免 UI 显示 [FAIL]）。
卡片顺序由 `NscSuite.cards()` 决定，UI 里排在 9 张常规卡片之后。

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
