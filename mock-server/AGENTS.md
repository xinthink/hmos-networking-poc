# AGENTS.md — mock-server

Node.js Mock Server，为 `network-compare` App 提供 HTTP/1.1 与 HTTP/2 双协议测试端点。
**零运行时依赖**（仅用内置 `node:http` / `node:http2` / `node:crypto`），不要引入 npm
包（如 multipart 解析器）——解析逻辑手写在 `server.mjs` 的 `parseMultipart()`。

## 服务与端口

| 端口 | 传输 | 协议 |
|------|------|------|
| 8080 | 明文 `http://` | HTTP/1.1 only |
| 8443 | TLS/ALPN `https://`（自签名证书） | HTTP/2 或 HTTP/1.1（按客户端 ALPN 协商） |

同一 URL 走 8443 时，支持 h2 的客户端自动协商到 HTTP/2，否则回退 HTTP/1.1 —— 这正是
对比两套框架协议行为的核心手段。端口可用环境变量覆盖：`MOCK_HTTP1_PORT`、
`MOCK_HTTPS_PORT`、`MOCK_HOST`。

## 端点清单

| 方法 | 路径 | 用途 |
|------|------|------|
| GET | `/api/protocol` | 回显请求到达时的协议版本（h1/h2）与说明 |
| ANY | `/api/echo` | 回显 method / URL / query / headers / body |
| ANY | `/api/methods` | 报告客户端使用的 HTTP method（REST 覆盖测试） |
| GET | `/api/headers` | 回显收到的 header 名（h1 用 `rawHeaders` 保留大小写；h2 已小写） |
| GET | `/api/cookie/set` | 下发 `Set-Cookie` |
| GET | `/api/cookie/read` | 回显客户端回传的 `Cookie` header |
| GET | `/api/cache` | 可缓存响应（`Cache-Control: public, max-age=60` + ETag） |
| GET | `/api/cache/stats` | `/api/cache` 的网络命中计数 |
| GET | `/api/cache/etag` | `Cache-Control: no-cache` + ETag，匹配 `If-None-Match` 时回 304 |
| GET | `/api/cache/etag/stats` | ETag 重新验证计数（full200 / notModified304 / ifNoneMatchSeen） |
| POST | `/api/upload/multipart` | 解析 `multipart/form-data`，回显各 part 摘要 + sha256 |
| POST | `/api/upload/binary` | 接收 `application/octet-stream`，回显大小 + sha256 |
| GET | `/api/delay?ms=` | 延迟响应（超时测试） |

## 架构与新增端点

- 所有路由在 `server.mjs` 的 `route(req, res)` 中按 `pathname` 分发；`json(res, code, obj)`
  是统一 JSON 响应助手。
- 服务端状态（如 `cacheHits`、`etagState`）声明在文件顶部 `server-side state` 区块。
- **新增端点必须遵守"可观测计数"约定**：被测行为（缓存命中、条件请求、上传等）要有
  配套 `/stats` 计数端点，App 端通过计数 delta 客观判断客户端行为，而不是只看状态码。
- 请求日志：`route()` 开头已打印 `[req] <proto> <method> <path>`，新增端点自动获得日志。
- 304 响应不带 body（HTTP 规范），但要保留 `etag` 头便于客户端下次重新验证。

## 证书管理

- 证书：`certs/cert.pem` + `certs/key.pem`，由 `npm run certs`（`gen-certs.mjs`，openssl）
  生成，SAN 覆盖 `localhost`、`127.0.0.1`、`10.0.2.2`（模拟器访问宿主机的地址）。
- `key.pem` 已 gitignore，**禁止提交**。
- ⚠️ **重新生成证书后，必须把 `cert.pem` 内容同步到
  `network-compare/entry/src/main/ets/common/AppConfig.ets` 的 `MOCK_CA_PEM`**，
  否则 App 的 HTTPS 请求会因证书不受信任而失败。

## 验证

```bash
npm start                    # 启动（也可后台运行）
curl -s http://127.0.0.1:8080/api/protocol            # HTTP/1.1
curl -sk --http2 https://127.0.0.1:8443/api/protocol   # HTTP/2
curl -sk --http1.1 https://127.0.0.1:8443/api/protocol # HTTP/1.1 over TLS

# ETag 条件请求自测
curl -si http://127.0.0.1:8080/api/cache/etag | grep -iE '^HTTP|^etag'
curl -si http://127.0.0.1:8080/api/cache/etag -H 'If-None-Match: "etag-v1"' | grep -iE '^HTTP'
```

App 端联调前用 curl 自测端点，可快速隔离"服务端问题"与"客户端问题"。
