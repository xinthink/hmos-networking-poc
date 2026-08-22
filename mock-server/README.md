# Mock Server (HTTP/1.1 + HTTP/2)

Node.js mock server for the Network Kit vs RCP comparison. Zero runtime dependencies
(built-in `node:http` / `node:http2` only).

## What it serves

| Port  | Transport                                   | Protocol            |
|-------|---------------------------------------------|---------------------|
| 8080  | Cleartext `http://`                          | HTTP/1.1 only       |
| 8443  | TLS with ALPN `https://` (self-signed cert) | HTTP/2 or HTTP/1.1 (negotiated) |

Same URL on 8443 therefore yields HTTP/2 when the client supports it (h2 via ALPN)
and falls back to HTTP/1.1 otherwise — ideal for comparing both frameworks on the
same endpoint.

## Endpoints

| Method | Path                        | Purpose                                                        |
|--------|-----------------------------|----------------------------------------------------------------|
| GET    | `/api/protocol`             | Echo the protocol version the request arrived on               |
| ANY    | `/api/echo`                 | Echo method / URL / query / headers / body                     |
| ANY    | `/api/methods`              | Report which HTTP method the client used (REST coverage)       |
| GET    | `/api/headers`              | Echo header names exactly as received (`rawHeaders` for h1)    |
| GET    | `/api/cookie/set`           | Issue `Set-Cookie` headers                                     |
| GET    | `/api/cookie/read`          | Echo the `Cookie` header the client sent back                  |
| GET    | `/api/cache`                | Cacheable response (`Cache-Control: public, max-age=60`)       |
| GET    | `/api/cache/stats`          | Server-side counter of `/api/cache` network hits               |
| GET    | `/api/cache/etag`           | `Cache-Control: no-cache` + `ETag`; honors `If-None-Match` (304) |
| GET    | `/api/cache/etag/stats`     | ETag revalidation counters (full200 / notModified304 / ifNoneMatchSeen) |
| POST   | `/api/upload/multipart`     | Parse `multipart/form-data`, echo part summary + sha256        |
| POST   | `/api/upload/binary`        | Receive `application/octet-stream`, echo size + sha256         |
| GET    | `/api/delay?ms=1000`        | Delayed response (timeout tests)                               |

## Run

```bash
npm start            # or: node server.mjs
```

First run (or after deleting `certs/`):

```bash
npm run certs        # generates certs/key.pem + certs/cert.pem via openssl
```

## Connect from a device/emulator

- **Emulator**: `10.0.2.2` reaches the host machine's loopback → base URL
  `http://10.0.2.2:8080` / `https://10.0.2.2:8443`. This is the app default.
- **Real device**: use the dev machine's LAN IP, e.g. `http://192.168.x.y:8080`.
  Make sure macOS allows inbound connections (`sudo` not needed for node, but the
  macOS firewall may prompt).

The app trusts the self-signed cert by embedding `certs/cert.pem`
(`AppConfig.MOCK_CA_PEM`). If you regenerate certs, update the embedded PEM.

## Quick verification

```bash
curl -s  http://127.0.0.1:8080/api/protocol          # HTTP/1.1
curl -sk --http2 https://127.0.0.1:8443/api/protocol # HTTP/2
curl -sk --http1.1 https://127.0.0.1:8443/api/protocol # HTTP/1.1 over TLS
```
