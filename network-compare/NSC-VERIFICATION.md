# NSC 验证套件（RCP SecurityConfiguration × 系统 NSC）

> 本文档描述 `entry/src/main/ets/nsc/` 这个**自包含验证模块**：它验证什么、如何运行、
> 各系统版本上的实测结果，以及**系统版本升级后如何手工复验**。
>
> 背景结论（业务视角）见 `../COMPARISON.md` 的「RCP SecurityConfiguration × 系统 NSC」；
> 四框架技术定位见 `../docs/harmonyos-network-libraries.md` §3.3。

## 1. 验证什么

RCP 自身的安全配置（`rcp.SecurityConfiguration`）与系统网络安全配置
（NSC = `entry/src/main/resources/base/profile/network_config.json`）各管什么、谁优先：

| 维度 | 结论 | 由谁生效 |
|---|---|---|
| **TLS 信任** | NSC 的 `trust-anchors` 对 RCP **零作用**；RCP 只认自己的 `remoteValidation` | RCP 自身配置 |
| **明文 HTTP** | RCP 无明文字段，明文**只能**由 NSC 决定；且 NSC 内部 **组件开关 > 全局开关** | NSC |

## 2. 模块地图

```
ets/
├── model/ScenarioDef.ets        # card interface + runner/sink types (shared by UI and suite)
├── nsc/                         # THIS SUITE: all RCP x NSC verification lives here
│   ├── NscSuite.ets             # card registry + headless self-test runner (entry point)
│   ├── NscRcp.ets               # RCP column: 6 scenarios + 5 session builders
│   ├── NscNetKit.ets            # Network Kit column: control + N/A placeholders
│   ├── NscAxios.ets             # axios column: control + N/A placeholders
│   └── NscEnv.ets               # OS/API-level stamp (results carry their own version)
├── netkit/NetKitScenarios.ets   # remaining scenarios (NSC excluded)
├── rcp/RcpScenarios.ets         # remaining scenarios (NSC excluded)
├── axios/AxiosScenarios.ets     # remaining scenarios (NSC excluded)
└── pages/Index.ets              # UI: 9 regular cards + NscSuite.cards() + self-test button
```

改这个套件只需要动 `ets/nsc/`：`Index.ets` 只调用
`NscSuite.cards(filesDir)` 和 `NscSuite.runSelfTest(filesDir, sink)`。

## 3. 场景清单

| # | key | 场景 | RCP 侧写法 | 期望 |
|---|---|---|---|---|
| 1 | `nscTrust` | 不带代码级 CA，纯靠 NSC | 缺省 session | RCP **FAIL**（对照组 200） |
| 2 | `nscCleartext` | 明文权限 | 缺省 session | 取决于 NSC 组件开关 |
| 3 | `nscTrustSystem` | 显式系统 CA 库 | `remoteValidation: 'system'` | RCP **FAIL** |
| 4 | `nscTrustCa` | 代码级 CA 覆盖默认 | `{ content: MOCK_CA_PEM }` | 三方 200 |
| 5 | `nscTrustSkip` | 绕过全部校验 | `'skip'` | RCP 200（其余 N/A） |
| 6 | `nscTrustCallback` | 自定义校验 | `ValidationCallback` | RCP **FAIL**（本例只认系统库） |

`nscTrustSkip` / `nscTrustCallback` 是 RCP 独有能力，Network Kit/axios 列返回
`N/A — 无对应能力`（用 `ScenarioResult(true, ...)` 占位，不是失败）。

## 4. 如何运行

### 4.1 无头自检（推荐）

```bash
cd network-compare
devecocli build
devecocli run --device "Pura 90" --skip-build --uninstall

# 点首页顶部「自检 NSC × RCP 组（结果写 hilog）」按钮（固定位置 y≈652）
hdc -t 127.0.0.1:5555 shell "hilog -r"
hdc -t 127.0.0.1:5555 shell "uitest uiInput click 660 652"
sleep 30

devecocli log --device "Pura 90" --bundle-name com.example.networkcompare \
  --keyword NSCTEST --from 5m --tail 200 | grep NSCTEST
```

输出（18 行 = 6 场景 × 3 框架，外加 ENV/DONE 两行）。下面是**真实日志片段**
（`summary` 里的中文是 App 自己的文案，属程序输出而非图内文字）：

```text
NSCTEST ENV OpenHarmony-6.1.1.125 api=24 phone (emulator 6.1.0.126(SP1DEVC00E120R4P11)) | distribution=6.1.0 api=24
NSCTEST nscTrust rcp FAIL status=1007900060 | NSC trust-anchors 被忽略：RCP 缺省配置不读应用级信任锚点
...
NSCTEST DONE OpenHarmony-6.1.1.125 api=24 phone (...) | ran=18 pass=15
```

- **ENV / DONE 行带系统版本**（`osFullName` + `api=` + `deviceType` + `displayVersion`），
  所以日志本身能区分是哪个版本跑的，跨版本对比不需要额外记录。
- `pass` 数量不是"越少越好"：**3 个 RCP FAIL 是期望值**（场景 1/3/6）。
  判读标准见 §6。

### 4.2 单张卡片

UI 上每张卡片三列按钮（Network Kit / RCP / axios）独立可点，用于交互式排查。
⚠️ 结果区出现后布局会下移，坐标需重新 `uitest dumpLayout` 获取。

## 5. 结果矩阵（按系统版本）

| 场景 | 列 | 期望 | HarmonyOS 6.1.1(24) 实测<br>（emulator 6.1.0.126） | 新版本待填 |
|---|---|---|---|---|
| `nscTrust` | netkit | 200 | ✅ 200 | |
| `nscTrust` | rcp | FAIL | ✅ FAIL 1007900060 | |
| `nscTrust` | axios | 200 | ✅ 200 | |
| `nscTrustSystem` | rcp | FAIL | ✅ FAIL 1007900060 | |
| `nscTrustCa` | 三方 | 200 | ✅ 三方 200 | |
| `nscTrustSkip` | rcp | 200 | ✅ 200 | |
| `nscTrustCallback` | rcp | FAIL | ✅ FAIL 1007900060 | |
| `nscCleartext` | 三方 | 见 §7 变体 | ✅ 三方 200（提交版配置） | |

汇总：`ran=18 pass=15`（3 个期望 FAIL）。

## 6. 跨版本复验（手工，系统升级后做一次）

**前置**：mock server 已启动（`cd mock-server && npm start`）；模拟器/真机已连通；
`AppConfig.host` 指向可达地址（模拟器默认 `10.0.2.2`）。

1. 记录环境：`devecocli device view` 或在自检日志的 `ENV` 行读取系统版本与 API level。
2. `devecocli build && devecocli run --device <name> --skip-build --uninstall`。
3. 按 §4.1 跑自检，拿到 18 行结果 + ENV/DONE。
4. 与上表逐行对比，关注三类变化：
   - **RCP 信任行为**：`nscTrust` / `nscTrustSystem` 是否从 FAIL 变 200
     （若变 200 → RCP 开始读应用级 NSC trust-anchors，属重大行为变更）。
   - **RCP 明文行为**：`nscCleartext` 是否被拦（配合 §7 变体一起看）。
   - **错误码**：`1007900060`（SSL 校验失败）/ `1007900201`（明文被禁）是否被替换。
5. 把结果填进 §5 表格的"新版本待填"列，并在
   `../COMPARISON.md`「RCP SecurityConfiguration × 系统 NSC」一节补一句差异说明。
6. 若某行与期望不符，先排除环境因素（证书是否重新生成 → `MOCK_CA_PEM` 是否同步、
   NSC 是否被改过），再判定为行为变更。

> ⚠️ 证书轮换會影响全部 HTTPS 场景：`mock-server` 重新生成证书后必须同步
> `AppConfig.MOCK_CA_PEM` 与 `resfile/mock-ca/`（见 `AGENTS.md`「HTTPS 自签名证书」）。

## 7. 明文变体实验（build-variant）

明文的优先级无法在运行时切换——`network_config.json` 随 HAP 打包，必须改配置重构建。

| 变体 | `cleartextTrafficPermitted`(base+domain) | `component-config."Remote Communication Kit"` | 6.1.1(24) 实测 |
|---|---|---|---|
| 提交版 | `true` | `true` | 三方明文 200 |
| V1 | `false` | `false` | 仅 RCP 200；netkit/axios 报 **2300997** |
| V2 | `false` | `true` | 三方全拦；RCP 报 **1007900201** |

流程：改 JSON → `devecocli build` → `run --skip-build --uninstall` → 点自检 →
读 `nscCleartext` 行 → **`git checkout -- <config>` 还原并重建**（别忘了还原）。

## 8. 已知坑

1. **不要并行执行 hdc/uitest**：两个 `uitest` 会话互相阻塞，双方都会超时
   （曾导致驱动脚本全部任务报 `CARD NOT FOUND`）。
2. **`uitest dumpLayout` 很慢**（本 App 单次 2–5 秒）：14 张卡片的列表逐卡点击极不划算，
   所以有自检按钮。UI 自动化仅用于交互式排查。
3. **`networkSecurity.certVerificationSync` 对自签/不受信证书抛异常**（如 2305018），
   不是返回非 0 —— `NscRcp.newCallbackSession()` 里已 try/catch 映射为"拒绝"。
4. **`remoteValidation` 缺省值就是 `'system'`**（见 `@hms.collaboration.rcp.d.ts`
   "Default is 'system'"），所以"缺省"与"显式 'system'"应当同结论；若不同，说明有 bug。
5. **ArkTS 类型推断**：把 helper 返回值赋给局部变量时需显式标注
   （`const config: AxiosRequestConfig = ...`），否则 `arkts-no-any-unknown` 编译失败。
