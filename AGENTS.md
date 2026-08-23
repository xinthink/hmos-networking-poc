# AGENTS.md（仓库根）

本仓库是一个 **多工程工作区**。开始改动前：先读本文件，再读你要改动的那个
子项目的 `AGENTS.md`（见下），以及 `README.md`、`COMPARISON.md`。

## 工程目标

验证 **Remote Communication Kit (RCP, `@kit.RemoteCommunicationKit`)** 是否可以取代
**Network Kit 的 HTTP 能力 (`@ohos.net.http` / `@kit.NetworkKit`)**。做法：同一套 HTTP
场景分别用两套框架实现，在模拟器上端到端实测，量化对比协议覆盖、Header 正规化、
Cookie、Cache（含 ETag）、Multipart、二进制上传等差异。

## 子工程一览（后续会新增其他工程）

| 子工程 | 角色 | 专属指南 | 关键文档 |
|--------|------|----------|----------|
| `mock-server/` | Node.js Mock Server：`:8080` 明文 HTTP/1.1 + `:8443` TLS/ALPN（h2+h1），零依赖 | [`mock-server/AGENTS.md`](mock-server/AGENTS.md) | `mock-server/README.md` |
| `network-compare/` | HarmonyOS App（bundle `com.example.networkcompare`，API 24）：对比 UI + 双框架 runner | [`network-compare/AGENTS.md`](network-compare/AGENTS.md) | [`network-compare/README.md`](network-compare/README.md) |

> 两个子工程是**独立工程**：`network-compare/` 可被 DevEco 单独打开，`mock-server/`
> 是纯 Node 工程。跨工程协作点见下文"跨工程约定"。

## 新增子工程的标准流程（强制约定）

**每新增一个子工程/模块，必须同时创建分层的 `README.md` 与 `AGENTS.md`，并更新本文件
（root AGENTS.md）**。这是仓库的固定规范，任何代理在新建子工程时都必须执行，不允许
只建代码不建文档。

步骤：

1. **创建子工程代码**：目录放仓库根下，命名 `kebab-case`（如 `mock-server/`、
   `network-compare/`）。子工程必须是**独立工程**（可单独构建/打开），不依赖其他
   子工程的构建产物（跨工程只通过运行时接口协作：HTTP 端点、端口、证书等）。
2. **创建 `README.md`**（面向使用者，写清"是什么 + 怎么跑"）：
   - 一句话定位（该工程在本仓库中的角色）
   - 快速开始：安装/生成证书、启动、构建、运行命令
   - 关键配置（端口、地址、环境变量）与对外接口（如 mock server 的端点表）
   - 与其他子工程的协作关系（谁调用谁、端口/证书如何同步）
3. **创建 `AGENTS.md`**（面向代理，写清"改代码要知道什么"，参考现有两个子工程的
   AGENTS.md）：
   - 角色定位 + 目录结构（只列本工程相关文件）
   - 常用命令（在本工程目录下执行的）
   - 架构约定：如何新增功能/场景（本工程特有的模式）
   - 关键约束与踩坑清单（语言限制、SDK/API 边界、证书、路径等）
   - 验证流程（本工程如何自测/联调）
   - 代码风格
   - 至少包含：`改动前先读仓库根 ../AGENTS.md` 的说明。
4. **更新 root `AGENTS.md`**：
   - 在"子工程一览"表新增一行（角色 + AGENTS.md/README 链接）。
   - 如该子工程引入新的跨工程协作点（端口、证书、协议、数据格式），在"跨工程约定"
     中补充；共享的实测/经验结论在"已实测结论"或合适章节更新。
5. **同步 `.gitignore`**：子工程的构建产物、密钥、本地配置按需加入
   `.gitignore`（参考现有条目：`mock-server/certs/key.pem`、`network-compare/**/build/`
   等）。

> 已有子工程即本规范的最佳范例：`mock-server/README.md` + `mock-server/AGENTS.md`、
> `network-compare/README.md` + `network-compare/AGENTS.md`，均按本流程分层维护。

## 工程级 Skills（DSH 识别机制）

本仓库使用 devecocli 安装 ArkTS/ArkUI 相关 skills（已装于 `.agents/skills/`）：
`hmos-arkts-knowledge-retriever`、`hmos-arkts-syntax-checker`、
`hmos-arkts-deprecated-interface-checker`、`hmos-arkui-develop-skill`、
`hmos-arkui-knowledge-retriever`、`hmos-arkui-statemgt-migration`、
`deveco-studio-codelinter`。另有本地安装的 `cangjie-coding`（仓颉语言知识库，
来源：`/ws/lrn/HMOS/CangjieSkills`，直接复制其 `.agents/skills/cangjie-coding`）。

⚠️ **`cangjie-coding` 的脚本要求 Python 3.10+**（`str | None` 注解），系统默认
`python3`（3.9）会报错，必须用 `python3.11`（或更高）调用
`scripts/search_docs.py` / `scripts/setup_stdx.py`。

**DSH 只扫描以下技能根目录**（源码见 skill-filesystem `roots()`）：

| 目录 | 来源 |
|------|------|
| `<projectRoot>/.dsh/skills` | project-dsh |
| `<projectRoot>/.agents/skills` | project-agents（本项目使用） |
| `~/.dsh/skills` | user-dsh |
| `~/.agents/skills` | user-agents |

⚠️ **安装命令注意**：
- `devecocli skills add --skill <name> --project .` 会把技能装到
  `.<agentName>/skills`（如 `.claude-code/skills`、`.opencode/skills`、
  `.codex/skills`）——这些目录 **DSH 不识别**，只对对应 agent 工具有效。
- 要让 DSH 在工程内识别，必须用：
  ```bash
  devecocli skills add --skill <name> --path "$PWD/.agents/skills"
  ```
  （`--path` 与 `--project`/`--agent` 互斥；`--path` 要求目录已存在。）

## 常用命令（速查）

```bash
# Mock Server（必须先于 App 运行；在 mock-server/ 下）
npm run certs   # 首次/证书丢失：生成自签名证书
npm start       # :8080 (HTTP/1.1) + :8443 (HTTP/2/HTTP/1.1)

# App（在 network-compare/ 下）
devecocli build                                    # 编译（ArkTS 严格检查）
devecocli run --device "Pura 90"                   # 构建+安装+启动
devecocli run --device "Pura 90" --skip-build --uninstall   # 改代码后重装
devecocli emulator list / start "Pura 90"
```

> `devecocli build/run` 需要写 `~/.hvigor`、`~/.ohpm`，**必须在本机非沙箱环境执行**；
> 在受控环境运行前先确认写权限。

## 跨工程约定（改代码时保持同步）

1. **端口固定**：8080（h1 明文）/ 8443（h2 TLS）。改端口须同步
   `mock-server/server.mjs` 与 `network-compare/.../common/AppConfig.ets`。
2. **证书同步（两处）**：`npm run certs` 重新生成 `mock-server/certs/cert.pem` 后，
   **必须**同步两处：
   - `network-compare/.../common/AppConfig.ets` 的 `MOCK_CA_PEM`（代码级信任）；
   - `network-compare/entry/src/main/resources/resfile/mock-ca/` 下的 `cert.pem` 与
     `openssl x509 -hash` 命名的 `<hash>.0` 副本（network_config.json 系统级信任锚点）。
3. **场景镜像**：每个对比场景在 App 两侧 runner 中同名成对实现（
   `NetKitScenarios.xxx` ↔ `RcpScenarios.xxx`），并对应 mock server 的一个或多个端点。
   新增场景的完整步骤见各子项目 AGENTS.md。
4. **服务端可观测计数**：mock server 每个被测端点尽量附带 `/stats` 计数端点
   （如 `/api/cache/stats`、`/api/cache/etag/stats`），App 端通过计数 delta 客观判断
   客户端行为（是否命中缓存、是否发送 If-None-Match）。新增实验保持这个模式。

## 已实测结论（全仓库共享，改动相关代码前必读）

| 场景 | Network Kit | RCP |
|------|-------------|-----|
| HTTP/1.1 / HTTP/2 (ALPN) | ✅ 显式 `usingProtocol` | ✅ 自动协商 |
| Header 大小写 (h1) | ⚠️ 发送时统一转小写 | ✅ 保留原大小写 |
| Header 大小写 (h2) | 全小写（RFC 7540） | 全小写 |
| Cookie | 手动；`response.cookies` 是 **Netscape cookie-file 格式**（tab 分隔） | `CookieRepository` 自动 |
| Cache (max-age) | ❌ 默认 `usingCache: true` 实测未命中 | ✅ `ResponseCache` 命中 |
| Cache + ETag (304) | ❌ 未发送 If-None-Match | ✅ If-None-Match → 304 → 复用缓存 |
| Multipart / 二进制上传 | ✅ | ✅ |
| 网络安全配置: trust-anchors | ✅ 遵循 network_config.json 应用级信任锚点（base+domain 都需配置） | ❌ 不遵循；须代码级 `remoteValidation` |
| 网络安全配置: 明文控制 | ✅ 受 component-config 约束（默认 true=受控） | ✅ 同样受约束，但 `"Remote Communication Kit"` 默认 **false=不受控**（API 23 起可置 true） |

> ⚠️ 不要因为"看起来奇怪"就擅自"修复"上述差异 —— 它们是本工程要记录和对比的
> **实测事实**（详见 `COMPARISON.md`）。若要改变实验条件（如给 Network Kit 配置
> `http.createHttpResponseCache()` 后再测缓存），先确认这是新的实验维度，并更新文档。

## 端到端验证流程

1. 启动 mock server：`cd mock-server && npm start`（可用 `curl` 自测端点）。
2. `cd network-compare && devecocli build`。
3. `devecocli run --device "Pura 90"` 部署启动。
4. UI 自动化验证（无头操作）：用 `hdc` 的 `uitest dumpLayout` 取按钮 bounds →
   `uitest uiInput click <x> <y>` 点击 → `uitest uiInput swipe ...` 滚动。
   ⚠️ 结果区出现后**布局会下移**，按钮坐标会变，需重新 dumpLayout 取最新坐标
   （完整命令见 `network-compare/AGENTS.md`）。
5. 结合 mock server 的 `[req] ...` 请求日志与服务端计数端点验证客户端行为。

## 代码风格（全仓库）

- ArkTS 文件：无 `any`、无解构、interface 在文件顶部声明。
- 场景方法返回 `ScenarioResult`（`ok`/`summary`/`detail`/`statusCode`）。
- mock server：零依赖（仅 `node:http` / `node:http2`），新端点附可观测计数。
- 中文注释与 UI 文案。
