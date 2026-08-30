# AGENTS.md — cj-network-compare

纯 Cangjie HarmonyOS App（bundle `com.example.myapplication`，targetSdk `6.1.1(24)` /
API 24），用于验证 **Cangjie 语言下 Network Kit 的 HTTP 能力**。改动前先读本文件，
并读仓库根 `../AGENTS.md` 的"跨工程约定"与"已实测结论"，以及 `../COMPARISON.md` 的
"Cangjie 语言视角"章节。

> 本工程**没有 RCP 也没有 Axios**：RCP 无 Cangjie 绑定（`kit.RemoteCommunicationKit`
> 不存在），Axios 是 ArkTS/JS 库。Cangjie 侧网络只能用 Network Kit
> （`import kit.NetworkKit.*`）。

## 目录结构（entry/src/main/）

```
cangjie/
├── index.cj                    # 全部 11 个 Network Kit 场景 + 11 个 stdx 场景 + UI（EntryView）
├── main_ability.cj             # MainAbility（loadContent("EntryView")）
└── ability_*.cj / module_entry_entry.cj   # 模板生成的 ability/stage 文件
resources/
├── base/profile/network_config.json   # 网络安全配置（trust-anchors + component-config）
└── resfile/mock-ca/            # 自签 CA：cert.pem + <hash>.0（caPath 指向这里）
```

工程根：
```
hvigor/cangjie-build-support-6.1.280.tgz   # DevEco cangjie schema 扩展（从 DevEco 插件提取，构建必需）
vendor/cangjie_stdx/                       # stdx 源码（git submodule，pin v1.1.3.1，免 patch）
scripts/build-stdx.sh                      # stdx 交叉编译脚本（其他机器可复现）
entry/libs/arm64-v8a/*.so                  # stdx 运行时库（gitignored，脚本产物）
```

## stdx.net.http 集成（对比组 S1–S11）

stdx（Cangjie 扩展标准库）以 **git submodule** 管理（`vendor/cangjie_stdx`，pin
`v1.1.3.1`），**其他机器 `git clone --recursive` 后跑脚本即可复现**：

1. **stdx 源码（submodule）**：`git submodule update --init --recursive` 拉取
   `vendor/cangjie_stdx`（v1.1.3.1，官方 tag，**无需本地 patch**——RPATH 已修复，
   静态初始化问题 v1.1.3.1 未触发）。
2. **交叉编译**：`./scripts/build-stdx.sh`（自动：构造 CANGJIE_HOME、探测 OpenSSL
   头文件、`build.py build/install`、复制 package.json 与 .so 到 entry/libs）。环境变量
   `CANGJIE_SDK_HOME` / `DEVECO_OH_NATIVE_HOME` / `OPENSSL_INCLUDE` 可覆盖。
3. **cjpm.toml**：`[target.aarch64-linux-ohos.bin-dependencies]` 的 `path-option` 用
   **相对路径** `../vendor/cangjie_stdx/target/linux_ohos_aarch64_cjnative/dynamic/stdx`
   （相对 entry/，`package.json` 由脚本复制进该目录）。
4. **cangjie schema 扩展**（DevEco 6.1 bug 修复）：hvigor-config.json5 声明
   `"@ohos/cangjie-build-support": "file:cangjie-build-support-6.1.280.tgz"`（从 DevEco
   插件 `~/Library/Application Support/Huawei/DevEcoStudio6.1/plugins/devecostudio-cangjie-plugin-mac-arm-6.1.1.280/lib/hvigor/cangjie-build-support`
   打包，去掉 postinstall）。**devecocli build 必须带 `DEVECO_CANGJIE_PATH=$CANGJIE_SDK`**
   （否则 cangjie 插件走 deleteSchema 分支，build-profile 校验报 cangjieOptions 非法）。

**submodule 日常操作（其他机器/版本升级）**：
- 首次拉取：`git clone --recursive <repo>`，或已有克隆执行
  `git submodule update --init --recursive`。
- 日常更新：`git pull` → `git submodule update --recursive` → 若 submodule 有变化
  重跑 `./scripts/build-stdx.sh`。
- 升级 stdx 版本：`cd vendor/cangjie_stdx && git fetch origin --tags && git checkout
  <新tag>`（先确认与 cjc 1.1.3 兼容）→ 回仓库根 `git add vendor/cangjie_stdx` 记录
  新 pin → commit/push。submodule URL 在 `.gitmodules`
  （`https://gitcode.com/Cangjie/cangjie_stdx.git`）。

> ⚠️ **hvigor 卡死排查**：本机 node 若切换版本管理（nodenv→mise 等），hvigor daemon
> 缓存与 node 版本不匹配会**构建卡死**（无输出超时）。解决：删 `~/.hvigor/daemon`、
> `~/.hvigor/project_caches` 后重建。

> **cjpm 源码依赖替代方案（已验证，受 cjpm 1.1.3 限制）**：`[dependencies] stdx = {
> path/git, output-type = "dynamic" }` 可触发 stdx 的 build.cj pre-build 自动交叉编译
> native（OpenSSL 头需 patch PrepareOpenSSL 或官方 sysroot 方案），但组合时卡
> `profile.build.combined` 实验性限制（拒绝非 root 包名）。当前落地仍用官方
> **bin-dependencies**。token 配置在 `~/.cjpm/cangjie-repo.toml`（`[repository.home]` +
> registry + token）；详见 `COMPARISON.md`「cjpm 源码依赖实测」。

## 常用命令（在 cj-network-compare/ 下执行）

```bash
DEVECO_CANGJIE_PATH=/Users/ywu/.cangjie-sdk/6.1/cangjie devecocli build     # 编译（cjc 1.1.3）
DEVECO_CANGJIE_PATH=/Users/ywu/.cangjie-sdk/6.1/cangjie devecocli run --device "Pura 90" --skip-build --uninstall   # 重装启动
```

> ⚠️ **构建必须带 `DEVECO_CANGJIE_PATH`**（指向含 oh-uni-package.json 的 cangjie SDK），
> 否则 hvigor 的 cangjie schema 扩展不生效。

> `devecocli build/run` 需写 `~/.hvigor`、`~/.ohpm`，必须在本机非沙箱环境执行。

## 架构约定：如何新增/修改场景

所有场景集中在 `cangjie/index.cj`（单文件、无分包）。模式：

1. **场景函数**：`func runXxx(done: (String) -> Unit)`，异步回调风格——内部构造
   `HttpRequestOptions` + `asyncRequest(url, opt, fmt, onDone)`，最终调用 `done(text)`。
2. **`asyncRequest` 是核心壳**：`createHttp()` → `req.request(url, opt) { err, resp =>
   ... }` → `onDone(text)`。**纯回调，无阻塞原语（无 Monitor/spawn）**；回调在后台
   线程执行，`onDone` 由 `runScenario` 传入，内部用 `launch()` 调度回主线程。
3. **多请求串行**（methods 6 连发、cache/etag 各 4 连发）：用嵌套回调（
   `getCacheStats { before => ... }`）或方法递归（`MethodRunner.next()`，Cangjie 禁止
   捕获 var 的 lambda 作为参数传递，递归闭包不行，用类方法递归）。
4. **mock server 端点是共享的**：`../mock-server/server.mjs`（:8080 h1 / :8443 h2），
   新增场景先加端点，再在 `index.cj` 加 `runXxx` + UI 按钮（`runScenario(label, fn)`）。
5. **JSON 解析**：用 `index.cj` 里的极简提取器（`jStr`/`jInt`/`jObjEntries`/
   `jArrLen`/`jArrElemStr`/`jArrElemInt`），只支持扁平对象 + 单层对象/数组值，无转义。
   mock server 的响应满足该约束；解析更复杂的 JSON 前先评估手写成本。

## 关键约束与踩坑清单（写代码前必读）

1. **@State 只能在 UI 主线程修改**：Network Kit 回调在后台线程，回调里直接写
   `this.status = ...` 会崩（`[MTHRD1433]` / `null assertThread`）。正确模式：
   场景函数是异步回调风格（`done(text)`），`runScenario` 传入的 done 内部用
   `launch({ ... })`（`ohos.base` 顶层函数，"Submit the task to the main thread"，
   `import kit.ArkUI.*` 可用）调度回主线程后再更新 `@State`。**全程无阻塞原语、
   无 Monitor、无 spawn**，UI 不阻塞。
2. **lambda 捕获 var 后不能作为参数传递**（编译错误 "lambda capturing mutable
   variables needs to be called directly"）：需要跨回调修改的状态放进类字段
   （如 `MethodRunner` 的 `idx`/`sb`），闭包只捕获 `this`（let 引用）。
3. **RequestMethod 无 Patch**，且 `HttpRequestOptions` 无 `customMethod`：methods
   场景只能覆盖 Get/Post/Put/Delete/Head/Options（+Trace/Connect 枚举存在）。
4. **`HttpResponse` 无 `connectionExtraInfo`**：协议版本、缓存命中拿不到，只能靠
   mock server 回显（`/api/protocol`）与服务端计数（`/api/cache/stats`、
   `/api/cache/etag/stats`）客观判断。
5. **HTTPS 自签证书**：Cangjie 只有 `caPath`（文件路径），无 `caData`（内存 PEM）。
   `CA_PATH = /data/storage/el1/bundle/entry/resources/resfile/mock-ca/cert.pem`
   （bundle 只读路径，证书必须随 `resfile/mock-ca/` 打包，见跨工程约定 2）。
6. **multipart 必须显式设 `Content-Type: multipart/form-data` header**，否则 Network
   Kit 不进入 multipart 模式（server 收到 partCount=0）。
7. **Cangjie 语法**：`Byte` 就是 `UInt8`（typealias）；数值转换用类型构造函数
   `UInt8(x)`/`Int64(x)`，没有 `.toUInt8()` 方法；命名参数必须带前缀
   （`wait(timeout: x)`、`String.join(arr, delimiter: "; ")`）；`String` 无
   `substring`，用字节切片 `s.toArray().slice(start, len)` + `String.fromUtf8`。
8. **Cangjie 无 JSON 库**：不要假设有 `JSON.parse`；用工程内极简提取器。
9. **UI 自动化读文本会被截断**：`uitest dumpLayout` 导出的 `text` 字段对长文本只截
   断 ~100 字符（多行 Text 的 `bounds` 高度仍是真实渲染高度，可据此判断完整性）；
   关键数据验证以 mock server 日志/计数为准。

## 验证流程（模拟器端到端，无头操作）

1. 启动 mock server：`cd mock-server && npm start`。
2. `devecocli build` → `devecocli run --device "Pura 90" --skip-build --uninstall`。
3. UI 自动化：`hdc shell uitest dumpLayout` → 解析按钮 bounds → `uitest uiInput click
   <x> <y>`（结果区在按钮上方，每次点击后布局变化，须重新 dumpLayout 取最新坐标）。
4. 与 mock server 的 `[req] ...` 日志 + 计数端点对照验证客户端行为。

## 代码风格

- 单文件 `index.cj`：工具函数（桥/JSON/请求壳）在上，场景函数居中，`EntryView` 在底部。
- 中文注释与 UI 文案；场景函数返回可读文本（多行用 `StringBuilder` 累积）。
- 常量（`HTTP1_BASE`/`HTTPS_BASE`/`CA_PATH`）在文件顶部集中声明。
