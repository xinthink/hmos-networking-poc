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
| **证书锁定 (pin)** | 三方各自机制；RCP 只认自己的 `certificatePinning`，且与 `remoteValidation` 是 **AND**；NSC 的静态 `pin-set` 对 RCP 同样**零作用** | 见 §6 |
| **用户安装的 CA（MITM 防护）** | RCP **默认信任**用户 CA，但 **遵守** NSC 的 `trust-global-user-ca` / `trust-current-user-ca = false` opt-out —— **这是 RCP 唯一遵守的 NSC 信任类开关** | 见 §6-G |

## 2. 模块地图

```
ets/
├── model/ScenarioDef.ets        # card interface + runner/sink types (shared by UI and suite)
├── nsc/                         # THIS SUITE: all RCP x NSC verification lives here
│   ├── NscSuite.ets             # card registry + headless self-test runner (entry point)
│   ├── NscRcp.ets               # RCP column: 6 scenarios + 5 session builders
│   ├── NscNetKit.ets            # Network Kit column: control + N/A placeholders
│   ├── NscAxios.ets             # axios column: control + N/A placeholders
│   ├── NscPins.ets              # pin digests of the mock cert (recompute: npm run pins)
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

证书锁定组（6 张）：

| # | key | 验证点 | 期望（提交版配置） |
|---|---|---|---|
| 7 | `pinSpki` | `publicKeyHash` 的摘要语义 = 公钥(SPKI) SHA-256 | 三方 200 |
| 8 | `pinWrong` | pinning 是否在信任之外强制执行 | 三方 FAIL（2300090 / 1007900090） |
| 9 | `pinCertHash` | 用整证书摘要作 pin（语义探针） | 三方 FAIL |
| 10 | `pinBackup` | pin 数组 = 白名单（任一命中即通过） | 三方 200 |
| 11 | `pinSkipTrust` | RCP：`'skip'` + 错误 pin | RCP **FAIL** → pinning 独立于信任判定 |
| 12 | `pinUntrustedTrust` | RCP：`'system'` + 正确 pin | RCP **FAIL(1007900060)** → pin 不能替代信任 |

用户 CA 组（2 张，见 §6-G）：

| # | key | 验证点 | 期望 |
|---|---|---|---|
| 13 | `userCaTrust` | 不带代码级 CA 访问 `:9443`（证书只由用户 CA 签发） | 用户 CA 已装且未 opt-out → 三方 200；opt-out 后 → 三方 FAIL |
| 14 | `userCaByCodeCa` | 同一端点、把用户 CA 作为代码级 CA（对照） | 三方 200（否则核心探针不可解） |

自检总计 **42 行** = 14 场景 × 3 框架（外加 ENV/DONE）。

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
| `nscCleartext` | 三方 | 见 §8 变体 | ✅ 三方 200（提交版配置） | |
| `pinSpki` | 三方 | 200 | ✅ 三方 200 | |
| `pinWrong` | 三方 | FAIL | ✅ FAIL（2300090 / 1007900090） | |
| `pinCertHash` | 三方 | FAIL | ✅ FAIL | |
| `pinBackup` | 三方 | 200 | ✅ 三方 200 | |
| `pinSkipTrust` | rcp | FAIL | ✅ FAIL 1007900090 | |
| `pinUntrustedTrust` | rcp | FAIL | ✅ FAIL 1007900060 | |

| `userCaTrust` | 三方 | 见 §6-G | ✅ 三方 200（**用户 CA 已装在设备上**）；未装时为三方 FAIL | |
| `userCaByCodeCa` | 三方 | 200 | ✅ 三方 200 | |

汇总：`ran=42 pass=31`（用户 CA 已装 + 提交版配置）；未装用户 CA 时为 `pass=28`。

## 6. 配置关系与优先级（证书锁定 / 用户 CA）

### A. RCP：`remoteValidation` × `certificatePinning`（运行时，无需重构建）

| 场景 | Network Kit | RCP | axios | 读出的规则 |
|---|---|---|---|---|
| `pinSpki`（正确 SPKI pin + 信任正常） | 200 | 200 | 200 | `publicKeyHash` = **公钥(SPKI) 的 SHA-256 base64** |
| `pinWrong`（错误 pin + 信任正常） | ❌ 2300090 | ❌ 1007900090 | ❌ 2300090 | pinning **在信任之外强制执行** |
| `pinCertHash`（整证书摘要作 pin） | ❌ 2300090 | ❌ 1007900090 | ❌ 2300090 | 摘要取**公钥**，不是整证书 |
| `pinBackup`（`[错误, 正确]`） | 200 | 200 | 200 | pin 数组 = **白名单**（任一命中即通过）→ 备用公钥可用 |
| `pinSkipTrust`（RCP `'skip'` + 错误 pin） | N/A | ❌ 1007900090 | N/A | **pinning 独立于信任判定**：`'skip'` 只关链校验，不关 pinning |
| `pinUntrustedTrust`（RCP `'system'` + 正确 pin） | N/A | ❌ 1007900060 | N/A | **pin 不能替代信任锚点**：信任与 pinning 是 **AND** |

结论（RCP）：`remoteValidation` 决定"链是否可信"，`certificatePinning` 决定"公钥是否为预期"，
**两者是 AND 关系**——任一方不通过即请求失败；且 `'skip'` 只放弃前者，放弃不了后者。
错误码：RCP `1007900090 SSL public key does not match pinned public key`；
Network Kit/axios `2300090 Specified pinned public key did not match`。

### B. NSC：`trust-anchors` × `pin-set`（静态，需 build-variant）

静态 `pin-set` 写在 `domain-config[]` 里（`pin[].digest-algorithm: "sha256"` + `digest`，
可选 `expiration`）。实测（变体见 §8）：

| 变体 | domain `trust-anchors` | `pin-set` | `nscTrust`（无代码级 CA） | 带正确 `caData` 的请求 |
|---|---|---|---|---|
| V3 | ✅ mock CA | ✅ 正确、未过期 | Network Kit/axios **200** | 200 |
| V4 | ✅ mock CA | ❌ 错误 | **FAIL 2300090**（pin 不匹配） | **FAIL 2300090**（caData 救不了） |
| V5 | ❌ 无 | ✅ 正确 | **FAIL 2300060**（链不受信） | pin 生效，动态 pin 被覆盖 |
| V6 | ✅ mock CA | ❌ 错误但 **expiration 已过期** | **200**（过期即不锁定） | 动态 pin 恢复生效 |

结论（NSC）：`trust-anchors`（链是否可信）与 `pin-set`（公钥是否匹配）**也是 AND**，
且 **`pin-set` 不能替代 `trust-anchors`**（V5：pin 正确但链不受信 → 仍失败，
且错误码是信任类 `2300060` 而非 pin 类 `2300090`）；
`expiration` 到期后 pinning **整体失效**（V6）——这正是官方文档提示的安全取舍。

### C. 静态 `pin-set` 与动态 `certificatePinning` 谁优先（新发现）

这是文档没有直说、靠变体实测才能确定的一条：**域级静态 `pin-set`（生效中）完全覆盖
请求级动态 `certificatePinning`**——动态 pin 根本不参与判定。

| 静态 `pin-set` | 请求级 `certificatePinning` | 实测结果 | 说明 |
|---|---|---|---|
| 无 | 正确 | 200 | 动态 pin 正常工作 |
| 无 | 错误 | FAIL 2300090 | 动态 pin 生效 |
| 正确、未过期 | **错误** | **200** | 静态 pin 命中 → 动态错误 pin 被忽略 |
| 错误、未过期 | **正确** | **FAIL 2300090** | 静态 pin 不匹配 → 动态正确 pin 也救不了 |
| 正确、未过期 | `[错误, 正确]` | 200 | 仍是静态 pin 的结论 |
| 错误、未过期 | `[错误, 正确]` | FAIL 2300090 | 同上 |
| 错误但已过期 | 正确 | 200 | 过期 → 静态视同不存在，动态恢复生效 |
| 错误但已过期 | 错误 | FAIL 2300090 | 同上 |

> 判定逻辑：**不是 AND、也不是 union**（AND 会让 V3 的动态错误 pin 失败；union 会让
> V4 的动态正确 pin 通过）。唯一与全部 8 行实测一致的模型是"**静态优先覆盖**"。

⚠️ 实践含义：一旦在 `network_config.json` 里配了 `pin-set`，代码里的
`certificatePinning` 对该域名**不再起作用**（排查"我明明配了 pin 为什么不生效"时先看这里）。

### D. RCP 对 NSC `pin-set` 的遵循程度

V3–V6 四个变体里，**RCP 列的结果与提交版基线逐行一致**（`pinSpki` 200、`pinWrong`
FAIL 1007900090、`nscTrust` FAIL 1007900060…）→ **RCP 完全忽略 NSC 的 `pin-set`**，
与它忽略 NSC `trust-anchors` 一致。

> ⚠️ **本节结论曾被过度概括，已修正**：早期把 RCP 的遵循度写成"只有明文开关生效"，
> 但 §6-G 的用户 CA 实验证明 **RCP 也遵守 `trust-*-user-ca` opt-out**。
> 准确的规律是：**RCP 遵守 NSC 中"收紧/限制性"的开关，不遵守"补充/放宽性"的配置**：
>
> | NSC 项 | 性质 | RCP 是否遵守 |
> |---|---|---|
> | `component-config` 明文开关 | 收紧（禁用明文） | ✅ 遵守 |
> | `trust-global/current-user-ca: false` | 收紧（不信任用户 CA） | ✅ **遵守**（§6-G） |
> | `trust-anchors`（app 级信任锚点） | 放宽（增加信任源） | ❌ 忽略 |
> | `pin-set`（静态证书锁定） | 放松链校验的替代约束 | ❌ 忽略 |

### E. pin 值怎么算（证书轮换后必须更新）

```bash
cd mock-server && npm run pins        # 打印 SPKI / 整证书两种摘要
# 把 SPKI pin 填进 network-compare/.../nsc/NscPins.ets
```

`digest` / `publicKeyHash` = `base64(sha256(SubjectPublicKeyInfo))`（**不是**整证书摘要）。
证书重新生成后不同步 `NscPins.ets` 与 `pin-set` 会直接导致全部 pin 场景失败。

### F. V7 同一构建自证：开关确实生效 × 遵守度（2026-09 复核）

§5.3-D 的结论（"RCP 忽略 NSC anchors/pin-set"）可能被质疑为"其实那个开关没生效"。
V7 用**一次构建**把两个观测放进同一个 NSC 文件里，消除这一辩解。

**V7 配置**（`base-config` 与 `domain-config` 都禁明文、都配 trust-anchors；
`component-config` 三项全 true；domain 加**错误**摘要的 pin-set）：

```json
{
  "network-security-config": {
    "base-config": {
      "cleartextTrafficPermitted": false,
      "trust-anchors": [
        { "certificates": "/data/storage/el1/bundle/entry/resources/resfile/mock-ca" }
      ]
    },
    "domain-config": [
      {
        "domains": [ { "include-subdomains": true, "name": "10.0.2.2" } ],
        "cleartextTrafficPermitted": false,
        "trust-anchors": [
          { "certificates": "/data/storage/el1/bundle/entry/resources/resfile/mock-ca" }
        ],
        "pin-set": {
          "expiration": "2035-12-31",
          "pin": [
            { "digest-algorithm": "sha256",
              "digest": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=" }
          ]
        }
      }
    ],
    "component-config": { "Request": true, "Network Kit": true, "Remote Communication Kit": true }
  }
}
```

**V7 实测**（`ran=36 pass=12`；同一构建、同一份 NSC）：

| 观测 | Network Kit / axios | RCP | 读出的规则 |
|---|---|---|---|
| `nscCleartext` | ❌ 2300997 `Cleartext traffic not permitted` | ❌ **1007900201** `Plaintext transmission is forbidden` | **开关确实生效**（RCP 被全局明文禁令拦下） |
| `nscTrust` | ❌ 2300090（被静态 pin 拦） | ❌ **1007900060** | 开关生效的同时，RCP 仍不读 NSC trust-anchors |
| `nscTrustSystem` | ❌ 2300090 | ❌ 1007900060 | 同上（显式 `'system'`） |
| `nscTrustCa` | ❌ 2300090（静态 pin 覆盖其 `caData`） | ✅ **200** | RCP 只认自己的代码级 CA |
| `pinSpki`（NSC 静态 pin **错误**、动态 pin 正确） | ❌ 2300090 | ✅ **200** | **NSC pin-set 对 RCP 无约束** |
| `pinBackup` | ❌ 2300090 | ✅ 200 | 同上 |
| `pinWrong` | ❌ 2300090 | ❌ 1007900090 | RCP 自己的动态 pin 仍生效 |
| `pinSkipTrust` | N/A | ❌ 1007900090 | `'skip'` 不关 pinning |
| `pinUntrustedTrust` | N/A | ❌ 1007900060 | pin 不替代信任锚点 |

**分析**

1. **同一构建内自证**：这份 NSC 明确压住了 Network Kit/axios（明文被拦 + 静态 pin 覆盖其动态
   pin），说明 NSC 在本构建中**确实是生效的**；就在同一构建里，RCP 的 anchors 与 pin-set
   观测结果与"完全没有这些配置"的基线**逐行一致**（仅明文一项变化，且原因就是明文禁令本身）。
2. 因此"RCP 不遵守 NSC anchors/pin-set"不能用"开关没打开/NSC 没生效"解释。
3. RCP 对 NSC 的遵循度可精确表述为：**只有 `component-config` 明文开关这一项生效**；
   `trust-anchors`、`pin-set` 均不生效（对 RCP 而言等于不存在）。
4. 与官方文档的冲突仍然存在（文档称 RCP 也可通过 `network_config.json` 配置 CA），
   待验证事项见 §10。

### G. 用户安装的 CA 与 MITM 防护（RCP **遵守** opt-out）

**威胁模型**：用户/代理工具（Charles、Fiddler、企业 MDM）把一张 CA 装进设备的
**用户 CA 库**，然后用它签发服务器证书——这正是 HTTPS 中间人抓包的常规做法
（官方文档原话：用户安装的 CA "可信度较低，可能被用于中间人攻击"）。
NSC 提供顶层开关 `"trust-global-user-ca": false` / `"trust-current-user-ca": false`
让应用拒绝这类 CA。

**实验构造**：`npm run user-ca` 生成一张独立 CA（`nsc-user-ca`）与由它签发的服务器
证书，跑在第三个监听 `:9443`。该链**不在** app trust-anchors、**也不在**系统库中
（已验证：`openssl verify -CAfile certs/cert.pem user-server.pem` 失败），
**只有**设备用户 CA 库能救它。三阶段实测（同一台模拟器、同一份 NSC）：

| 阶段 | 用户 CA 已装 | `trust-*-user-ca` | Network Kit | axios | **RCP** |
|---|---|---|---|---|---|
| ① 阴性对照 | ❌ | 缺省 | ❌ 2300060 | ❌ 2300060 | ❌ 1007900060 |
| ② 判据 | ✅ | 缺省（= 信任用户 CA） | ✅ **200** | ✅ **200** | ✅ **200** ← **RCP 默认也信任用户 CA** |
| ③ opt-out | ✅ | 两者 `false` | ❌ 2300060 | ❌ 2300060 | ❌ **1007900060** ← **RCP 同样拒绝** |

**结论**

1. **RCP 默认信任用户安装的 CA**（与 Network Kit 相同）→ 不配 opt-out 时，
   装了代理 CA 的设备上 **RCP 流量同样可被中间人解密**。
2. **RCP 遵守 `trust-global-user-ca` / `trust-current-user-ca = false`**：
   阶段 ③ 里 RCP 从 200 变为 `1007900060`，而 ②→③ 的唯一变化就是这两个顶层 key
   （同一 App、同一设备、同一张已安装的 CA）→ 因果成立。
   → **NSC 的这项配置可以保护 RCP 免受"用户 CA 型中间人"攻击。**
3. 这是 RCP **唯一**遵守的 NSC 信任类开关（`trust-anchors`、`pin-set` 均忽略，见 §6-B/D）。
   规律是"**收紧性开关遵守、补充性配置忽略**"。

**假设的机制**（未验证）：`trust-*-user-ca` 改变的是**设备级 CA 集合的组装**，
任何 TLS 栈（含 RCP 内部的实现）都会读到；而 `trust-anchors` / `pin-set` 是
**应用级策略**，由 netstack 自身实施，RCP 不经过它。

**对照有效性说明**（为什么这个结论站得住）

- ① 与 ② 之间只差"装没装 CA"，NK/axios 由 FAIL 翻 200 → 证明"200 的来源确实是用户 CA"；
- ② 与 ③ 之间只差那两个 key → 证明失败由 opt-out 引起；
- ③ 里 `nscCleartext`（三方 200）、`nscTrustCa`（三方 200）、`pinSpki`（三方 200）、
  `nscTrust netkit`（200）全部正常 → 证明该 NSC **解析正常、其余策略仍生效**，
  不是"配置写坏导致全盘拒绝"。

**如何装用户 CA（本环境实测可行的路径）**

⚠️ 应用侧 API `certificateManagerDialog.openInstallCertificateDialog` 在**本模拟器返回
`29700004 - The API is not supported on this device`**（"deviceType is not support"），
尽管 syscap `Security.CertificateManagerDialog=true` 且 `com.ohos.certmanager` 与
`cert_manager_se` 都存在。可用的替代路径是**走证书管理 UI**：

```bash
# 1) 把 CA 推到设备文档目录（shell 属于 file_manager 组，可写）
hdc file send mock-server/certs/user-ca.pem \
  /storage/media/100/local/files/Docs/Download/nsc-user-ca.crt

# 2) 直接拉起证书管理界面（它的 MainAbility 不是 launcher 入口，只能这样起）
hdc shell "aa start -b com.ohos.certmanager -a MainAbility"

# 3) UI 路径（点坐标来自 uitest dumpLayout，本机 1280x2848）
#    Install from storage → CA certificates → 选文件
#      (Browse → Downloads/Received → Download Manager → nsc-user-ca.crt → Done)
#    → Install → 出现 "Installed successfully"
```

卸载：同一界面的 "Delete all certificates and credentials"，或 CA 列表里删除。

**复现实验的完整步骤**

1. `cd mock-server && npm run user-ca`（生成 CA/服务器证书；`npm start` 会自动监听 `:9443`）
2. 按上面的 UI 路径把 `user-ca.pem` 装成用户 CA
3. 点 App 顶部**「自检 NSC × RCP 组」** → 看 `userCaTrust` / `userCaByCodeCa` 两行
   （阶段 ② 对应"提交版配置"；阶段 ③ 对应在 `network_config.json` **顶层**加
   `"trust-global-user-ca": false` 与 `"trust-current-user-ca": false` 后重新构建）
4. ⚠️ 阶段 ① 必须在**装 CA 之前**跑，或先卸载 CA——否则拿不到阴性对照

**设备当前状态提醒**：本机模拟器上 **`nsc-user-ca` 仍然装着**，所以提交版基线下
`userCaTrust` 三方都是 200（`pass=31` 而非 28）。要回到"未装"状态需在证书管理 UI 里删除。

## 7. 跨版本复验（手工，系统升级后做一次）

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

## 8. 变体实验（build-variant：明文 + 证书锁定 + 用户 CA）

明文的优先级无法在运行时切换——`network_config.json` 随 HAP 打包，必须改配置重构建。

| 变体 | `cleartextTrafficPermitted`(base+domain) | `component-config."Remote Communication Kit"` | 6.1.1(24) 实测 |
|---|---|---|---|
| 提交版 | `true` | `true` | 三方明文 200 |
| V1 | `false` | `false` | 仅 RCP 200；netkit/axios 报 **2300997** |
| V2 | `false` | `true` | 三方全拦；RCP 报 **1007900201** |

**证书锁定变体**（`domain-config` 内加 `pin-set`，digest 用 `npm run pins` 的值）：

| 变体 | domain `trust-anchors` | `pin-set` | 结果 |
|---|---|---|---|
| V3 | mock CA | 正确，`expiration: 2035-12-31` | `nscTrust` 200；**动态错误 pin 被覆盖为 200** |
| V4 | mock CA | 错误 | `nscTrust`/`nscTrustCa`/`pinSpki`/`pinBackup` 全 FAIL 2300090 |
| V5 | **移除** | 正确 | `nscTrust` FAIL 2300060（pin 救不了不受信链） |
| V6 | mock CA | 错误但 `expiration: 2020-01-01`（已过期） | `nscTrust` 200；动态 pin 恢复生效 |

**用户 CA（MITM 防护）**：

| 变体 | 用户 CA | 顶层 `trust-global-user-ca` / `trust-current-user-ca` | 实测结果 |
|---|---|---|---|
| U1（提交版） | 已装 | 未配置（= 信任） | 三方 `userCaTrust` **200** |
| U2 | 已装 | 都 `false` | 三方 **FAIL**（NK/axios 2300060、**RCP 1007900060**） |

流程：改 JSON → `devecocli build` → `run --skip-build --uninstall` → 点自检 →
读 `nscCleartext` / `nscTrust` / `pin*` / `userCa*` 行 → **`git checkout -- <config>` 还原并重建**
（别忘了还原）。

## 9. 已知坑

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
6. **pin 值随证书失效**：mock 证书重新生成后，`NscPins.ets` 与任何 `pin-set` 都必须
   用 `cd mock-server && npm run pins` 重算，否则 pin 场景全红。
7. **`pin-set` 会静默压制代码里的 `certificatePinning`**（生效中的域级静态 pin 优先，
   见 §6-C）：排查 pin 不生效时先确认 NSC 里有没有配 `pin-set`。
8. **应用侧装用户 CA 的 API 在本模拟器不可用**：`openInstallCertificateDialog` 返回
   `29700004`（deviceType 不支持），必须走证书管理 UI（§6-G 有完整路径）。
9. **`trust-*-user-ca` 是 `network-security-config` 的兄弟节点**（顶层 key），
   写进 `network-security-config` 内部很可能被静默忽略。

## 10. 待验证事项（Pending，已知未做）

以下三项**尚未验证**，按预期价值排序；记录在此以免被误当作已证实结论：

| # | 待验证 | 为什么要做 | 怎么判定 |
|---|---|---|---|
| 1 | **真机复测**（商用 HarmonyOS 真机，非模拟器） | 现有全部结论来自 `OpenHarmony-6.1.1.125` 模拟器镜像；RCP 属 hms 协作能力域、SDK 里 `librcp_c.so` 只是空 stub、真实实现由设备提供 —— 模拟器镜像的 RCP 很可能未接 NSC 集成。这是"文档称 RCP 也读 `network_config.json`，实测却不读"这一矛盾的**首要候选解释** | 真机上跑同一份自检，对比 `nscTrust`/`pinSpki` 等 RCP 列 |
| 2 | **域名（主机名）而非 IP 的 domain 匹配** | 我们的 `domain-config.domains.name` 用的是 IP `10.0.2.2`。Network Kit 按 IP 匹配成功，但 RCP 的实现可能只按**主机名**匹配 domain-config | 把 mock server 用主机名访问（如 `localhost` / 自定义 hosts 名）重跑 `nscTrust` |
| 3 | **真实 MITM 代理演示**（用户已明确留待以后） | 本套件只做了机制验证：由用户 CA 直接给测试服务器签证书。要证明"攻击确实成功/被挡住"，还需要一个 TLS 终止 + 用用户 CA 现场签发伪造证书的代理进程，并处理代理配置（实测 RCP 日志为 `proxyType:none`，它默认不走系统代理） | 加 MITM 代理后重跑 `userCaTrust` |
| 4 | **CA 目录形态** | 我们的 `trust-anchors.certificates` 目录里同时放 `cert.pem` 与 `openssl x509 -hash` 命名的 `<hash>.0`。Network Kit 接受，RCP 的加载器可能只认其中一种 | 分别只放 `<hash>.0` / 只放 `cert.pem` 各跑一轮 |

> 结论口径：在上述三项完成前，本套件的 RCP 遵循度结论应表述为
> "**在 OpenHarmony 6.1.1(24) 模拟器镜像、IP 域匹配、当前 CA 目录形态下**，
> RCP 不遵守 NSC 的 `trust-anchors` 与 `pin-set`"。

