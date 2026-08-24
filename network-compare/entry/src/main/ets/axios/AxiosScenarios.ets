/**
 * Scenario runner using @ohos/axios (OpenHarmony port of Axios v1.3.4).
 *
 * Mirrors NetKitScenarios / RcpScenarios one-to-one so the same scenarios can
 * be compared across the three frameworks side by side.
 *
 * IMPORTANT (why this runner is interesting): @ohos/axios wraps @ohos.net.http
 * under the hood — every request is a Network Kit request with Axios sugar on
 * top (Promise API, interceptors, auto JSON parsing, AxiosHeaders,
 * validateStatus). Differences observed here therefore come from the Axios
 * layer itself:
 *   - response does NOT expose connectionExtraInfo / httpVersion / cookies
 *     (the adapter only maps result/responseCode/header/performanceTiming)
 *   - no `caData` option — only `caPath`, so the embedded CA PEM must be
 *     written to a file first
 *   - no cache / ETag layer: `config.cache` only works with the HttpClient
 *     adapter, and `usingCache` is never set on the underlying net.http call
 *     (net.http default applies, same as Network Kit)
 *   - 304 is REJECTED by the default validateStatus (status >= 200 && < 300)
 *   - default (responseType unset) auto-parses JSON responses into objects
 */
import axios, { AxiosError, AxiosHeaders, AxiosRequestConfig, AxiosResponse, FormData } from '@ohos/axios';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

/** One target (label + base URL + forced protocol + CA path) for header normalization. */
interface HeaderTargetAxios {
  label: string;
  base: string;
  protocol: http.HttpProtocol;
  ca: string;
}

/** Server-side ETag revalidation counters (mirrors mock-server etagState). */
interface EtagStatsAxios {
  full200: number;
  notModified304: number;
  ifNoneMatchSeen: number;
}

/**
 * ArkTS strict mode forbids `any`/`unknown`, and @ohos/axios type parameters
 * default to them — so every axios call must spell out all three type args.
 * These aliases keep the call sites readable.
 */
type AxiosJsonResp = AxiosResponse<Record<string, string>, null>;
type AxiosObjResp = AxiosResponse<Record<string, Object>, null>;
type AxiosJsonErr = AxiosError<Record<string, string>, null>;

export class AxiosScenarios {
  private static caFilePath: string = '';

  // ---- protocol negotiation -------------------------------------------------

  /** GET /api/protocol over HTTP/1.1 (explicit usingProtocol). */
  static async protocolHttp1(): Promise<ScenarioResult> {
    return AxiosScenarios.getProtocol(AppConfig.http1Base(), http.HttpProtocol.HTTP1_1, '');
  }

  /** GET /api/protocol over HTTPS; force HTTP/2 via usingProtocol. */
  static async protocolHttp2(filesDir: string): Promise<ScenarioResult> {
    const ca = await AxiosScenarios.ensureCaFile(filesDir);
    return AxiosScenarios.getProtocol(AppConfig.httpsBase(), http.HttpProtocol.HTTP2, ca);
  }

  private static async getProtocol(base: string, protocol: http.HttpProtocol, caPath: string): Promise<ScenarioResult> {
    try {
      const config: AxiosRequestConfig = {
        method: 'GET',
        usingProtocol: protocol,
        readTimeout: 15000,
        connectTimeout: 15000,
        headers: { 'Accept': 'application/json' },
        caPath: caPath.length > 0 ? caPath : undefined,
      };
      const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${base}/api/protocol`, config);
      const body = resp.data;
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${body['protocol']} (httpVersion ${body['httpVersion']})\n` +
        `client saw  : (axios 不暴露 connectionExtraInfo / httpVersion，无法从客户端读协议版本)\n` +
        `note        : ${body['note']}`;
      return new ScenarioResult(resp.status === 200,
        `server saw ${body['protocol']}, client 侧无协议观测字段`, detail, resp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err(`Axios /api/protocol (${base})`, err);
    }
  }

  // ---- REST method coverage -------------------------------------------------

  /** REST method coverage via axios verbs (get/post/put/patch/delete/head/options). */
  static async methods(): Promise<ScenarioResult> {
    const lines: string[] = [];
    let allOk = true;
    const run = async (name: string, p: Promise<AxiosJsonResp>): Promise<void> => {
      try {
        const resp = await p;
        const echoed = AxiosScenarios.echoedMethod(resp);
        const ok = resp.status === 200;
        allOk = allOk && ok;
        lines.push(`${name.padEnd(8)} -> ${resp.status}  server echoed: ${echoed}`);
      } catch (e) {
        const err = e as AxiosJsonErr;
        allOk = false;
        lines.push(`${name.padEnd(8)} -> ERROR ${err.code ?? ''} ${err.message ?? ''}`);
      }
    };
    const base = `${AppConfig.http1Base()}/api/methods`;
    await run('GET', axios.get<Record<string, string>, AxiosJsonResp, null>(base, AxiosScenarios.baseConfig()));
    await run('POST', axios.post<Record<string, string>>(base, { a: '1' }, AxiosScenarios.baseConfig()));
    await run('PUT', axios.put<Record<string, string>>(base, { a: '1' }, AxiosScenarios.baseConfig()));
    await run('PATCH', AxiosScenarios.patchRequest(base));
    await run('DELETE', axios.delete<Record<string, string>, AxiosJsonResp, null>(base, AxiosScenarios.baseConfig()));
    await run('HEAD', axios.head<Record<string, string>, AxiosJsonResp, null>(base, AxiosScenarios.baseConfig()));
    await run('OPTIONS', axios.options<Record<string, string>, AxiosJsonResp, null>(base, AxiosScenarios.baseConfig()));
    return new ScenarioResult(allOk, allOk ? 'all 7 methods OK' : 'some methods failed', lines.join('\n'));
  }

  // ---- header normalization -------------------------------------------------

  /**
   * Header normalization: send mixed-case headers, ask the server what case it
   * received. Axios stores header names as given (AxiosHeaders preserves case)
   * and hands them to net.http, which lowercases h1 names on the wire — so the
   * expectation is the same observable behavior as Network Kit.
   */
  static async headerCase(filesDir: string): Promise<ScenarioResult> {
    const ca = await AxiosScenarios.ensureCaFile(filesDir);
    try {
      const results: string[] = [];
      const targets: HeaderTargetAxios[] = [
        { label: 'HTTP/1.1', base: AppConfig.http1Base(), protocol: http.HttpProtocol.HTTP1_1, ca: '' },
        { label: 'HTTP/2', base: AppConfig.httpsBase(), protocol: http.HttpProtocol.HTTP2, ca: ca },
      ];
      for (let i = 0; i < targets.length; i++) {
        const t = targets[i];
        const config: AxiosRequestConfig = {
          method: 'GET',
          usingProtocol: t.protocol,
          readTimeout: 15000,
          connectTimeout: 15000,
          caPath: t.ca.length > 0 ? t.ca : undefined,
          headers: {
            'Accept': 'application/json',
            'X-MiXeD-CaSe-Hdr': 'MixedCaseValue',
            'x-lowercase-hdr': 'lower',
            'X-ALLCAPS-HDR': 'upper',
          },
        };
        const resp = await axios.get<Record<string, Object>, AxiosObjResp, null>(`${t.base}/api/headers`, config);
        const body = resp.data;
        const wire = body['wireHeaders'] as Record<string, string>;
        const observed: string[] = [];
        const names = Object.keys(wire);
        for (let j = 0; j < names.length; j++) {
          const n = names[j];
          if (n.toLowerCase().startsWith('x-')) {
            observed.push(`${n} = ${wire[n]}`);
          }
        }
        results.push(`[${t.label}] server received header names:\n  ${observed.join('\n  ')}`);
      }
      return new ScenarioResult(results.length === 2, 'see detail (h1 case vs h2 lowercase)', results.join('\n'));
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios /api/headers', err);
    }
  }

  // ---- cookies --------------------------------------------------------------

  /**
   * Cookie round-trip (manual — axios has no cookie jar and does NOT expose
   * net.http's response.cookies): parse Set-Cookie from the response headers,
   * then send it back in the Cookie header.
   */
  static async cookies(): Promise<ScenarioResult> {
    try {
      const setResp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cookie/set`, AxiosScenarios.baseConfig());
      const rawCookies = AxiosScenarios.readSetCookies(setResp);
      const cookieHeader = AxiosScenarios.extractCookieHeader(rawCookies);

      const readCfg: AxiosRequestConfig = AxiosScenarios.baseConfig();
      readCfg.headers = { 'Accept': 'application/json', 'Cookie': cookieHeader };
      const readResp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cookie/read`, readCfg);
      const readBody = readResp.data;
      const detail =
        `set status      : ${setResp.status}\n` +
        `read status     : ${readResp.status}\n` +
        `set-cookie (raw): ${rawCookies.join(' | ')}\n` +
        `sent back       : ${readBody['cookieHeader'] ?? '(empty)'}\n` +
        `note            : axios 不透出 response.cookies，需手动解析 set-cookie 响应头（与 Network Kit 同为手动模式）`;
      const ok = readResp.status === 200 && (readBody['cookieHeader'] ?? '').length > 0;
      return new ScenarioResult(ok, ok ? 'cookie round-trip OK (手动解析 set-cookie)' : 'cookie round-trip failed', detail,
        readResp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios cookies', err);
    }
  }

  // ---- cache / ETag ---------------------------------------------------------

  /**
   * Cache: GET /api/cache twice with the SAME URL. axios has no cache API —
   * `config.cache` only applies to the HttpClient adapter, and `usingCache` is
   * never set on the underlying net.http request (its default applies, same as
   * Network Kit). Server hit counter delta is the ground truth.
   */
  static async cache(): Promise<ScenarioResult> {
    try {
      const before = await AxiosScenarios.getStats();
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cache`, AxiosScenarios.baseConfig());
        const cc = AxiosScenarios.readHeader(resp, 'cache-control');
        hitLines.push(`req #${i}: status=${resp.status} cache-control=${cc}`);
      }
      const after = await AxiosScenarios.getStats();
      const delta = after - before;
      const detail = `${hitLines.join('\n')}\n` +
        `server network hits: before=${before} after=${after} delta=${delta}\n` +
        `(delta=0 => 2nd request served from client cache; delta=1 => both hit the network)\n` +
        `note            : axios 无缓存 API（config.cache 仅 HttpClient 适配器生效），底层 usingCache 未显式设置`;
      const cached = delta === 0;
      return new ScenarioResult(true, cached ? '2nd request served from cache' : 'cache not used (delta=1)', detail);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios cache', err);
    }
  }

  /**
   * ETag conditional-request test (mirror of NetKitScenarios.etag).
   * Phase A: two plain GETs — axios has no ETag store, so no If-None-Match is
   * expected (like Network Kit). Phase B: manual conditional request — axios
   * CAN send If-None-Match if you manage the ETag yourself, but the default
   * validateStatus REJECTS the 304; you must widen validateStatus to consume it.
   */
  static async etag(): Promise<ScenarioResult> {
    try {
      const before = await AxiosScenarios.getEtagStats();
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cache/etag`, AxiosScenarios.baseConfig());
        const respEtag = AxiosScenarios.readHeader(resp, 'etag');
        hitLines.push(`req #${i}: status=${resp.status} respEtag=${respEtag}`);
      }
      const mid = await AxiosScenarios.getEtagStats();
      const autoInm = mid.ifNoneMatchSeen - before.ifNoneMatchSeen;
      const auto304 = mid.notModified304 - before.notModified304;

      // Phase B-1: manual If-None-Match with DEFAULT validateStatus -> 304 rejected?
      let manualDefault = '';
      try {
        const cfg304: AxiosRequestConfig = AxiosScenarios.baseConfig();
        cfg304.headers = { 'Accept': 'application/json', 'If-None-Match': '"etag-v1"' };
        await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cache/etag`, cfg304);
        manualDefault = 'manual If-None-Match -> 服务端未回 304（意外）';
      } catch (e) {
        const err = e as AxiosJsonErr;
        manualDefault = `manual If-None-Match -> 默认 validateStatus 拒绝 304: ${err.code ?? ''} ${err.message ?? ''}`;
      }

      // Phase B-2: manual If-None-Match + validateStatus accepting 304
      let manualOk = '';
      try {
        const cfgOk: AxiosRequestConfig = AxiosScenarios.baseConfig();
        cfgOk.headers = { 'Accept': 'application/json', 'If-None-Match': '"etag-v1"' };
        cfgOk.validateStatus = (s: number): boolean => (s >= 200 && s < 300) || s === 304;
        const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/cache/etag`, cfgOk);
        manualOk = `manual + validateStatus(含304) -> status=${resp.status}，304 可被消费`;
      } catch (e) {
        const err = e as AxiosJsonErr;
        manualOk = `manual + validateStatus(含304) -> ERROR ${err.code ?? ''} ${err.message ?? ''}`;
      }

      const after = await AxiosScenarios.getEtagStats();
      const manualInm = after.ifNoneMatchSeen - mid.ifNoneMatchSeen;
      const manual304 = after.notModified304 - mid.notModified304;
      const detail = `${hitLines.join('\n')}\n` +
        `${manualDefault}\n${manualOk}\n` +
        `server stats: before=${AxiosScenarios.fmt(before)} mid=${AxiosScenarios.fmt(mid)} after=${AxiosScenarios.fmt(after)}\n` +
        `auto delta (两次普通 GET): ifNoneMatchSeen=${autoInm} notModified304=${auto304}\n` +
        `manual delta (手动 If-None-Match): ifNoneMatchSeen=${manualInm} notModified304=${manual304}\n` +
        `(autoInm>0 => 自动携带 If-None-Match；manualInm>0 => 手动携带成功)`;
      const autoSupported = autoInm > 0 && auto304 > 0;
      return new ScenarioResult(true,
        autoSupported ? 'ETag 自动条件请求生效' : '无自动 ETag；手动 If-None-Match 可用但 304 默认被 validateStatus 拒绝',
        detail);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios etag', err);
    }
  }

  // ---- uploads --------------------------------------------------------------

  /**
   * Multipart/form-data upload using axios's own FormData class, which maps to
   * net.http's multiFormDataList (the adapter routes FormData POSTs through the
   * upload/streaming path).
   */
  static async multipartUpload(): Promise<ScenarioResult> {
    try {
      const bin = new Uint8Array(256);
      for (let i = 0; i < bin.length; i++) {
        bin[i] = i;
      }
      const form = new FormData();
      form.append('field1', 'hello-from-axios');
      form.append('file1', bin.buffer, { filename: 'axios.bin', type: 'application/octet-stream' });
      const config: AxiosRequestConfig = {
        method: 'POST',
        readTimeout: 30000,
        connectTimeout: 15000,
        headers: { 'Content-Type': 'multipart/form-data' },
      };
      const resp = await axios.post<Record<string, Object>, AxiosObjResp, FormData>(
        `${AppConfig.http1Base()}/api/upload/multipart`, form, config);
      const body = resp.data;
      const parts = body['parts'] as Array<Record<string, Object>>;
      const lines: string[] = [`partCount=${body['partCount']} totalBytes=${body['totalBytes']}`];
      for (let i = 0; i < parts.length; i++) {
        const p = parts[i];
        const name = String(p['name'] ?? '(unnamed)');
        const fn = String(p['filename'] ?? '');
        lines.push(`  part name=${name} filename=${fn} size=${p['size']} type=${p['contentType']}`);
      }
      const ok = resp.status === 200 && parts.length >= 2;
      return new ScenarioResult(ok, ok ? `multipart OK, ${parts.length} parts` : 'multipart failed',
        `${lines.join('\n')}\nboundary=${body['boundary']}`, resp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios multipart', err);
    }
  }

  /** Binary upload: ArrayBuffer body with Content-Type application/octet-stream. */
  static async binaryUpload(): Promise<ScenarioResult> {
    try {
      const payload = new Uint8Array(1024 * 4);
      for (let i = 0; i < payload.length; i++) {
        payload[i] = (i * 31) & 0xff;
      }
      const config: AxiosRequestConfig = {
        method: 'POST',
        readTimeout: 30000,
        connectTimeout: 15000,
        headers: { 'Content-Type': 'application/octet-stream' },
      };
      const resp = await axios.post<Record<string, Object>, AxiosObjResp, ArrayBuffer>(
        `${AppConfig.http1Base()}/api/upload/binary`, payload.buffer, config);
      const body = resp.data;
      const detail =
        `bytes=${body['bytes']} sha256=${body['sha256']}\n` +
        `content-type sent: application/octet-stream\n` +
        `server saw content-type: ${body['contentType']}`;
      const ok = resp.status === 200 && Number(body['bytes']) === payload.length;
      return new ScenarioResult(ok, ok ? `binary upload OK (${payload.length} bytes)` : 'binary upload failed', detail,
        resp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios binary upload', err);
    }
  }

  // ---- network security configuration ---------------------------------------

  /**
   * Network Security Configuration — trust-anchors. No code-level CA (no
   * caPath), so success proves the system-level trust-anchors in
   * network_config.json are honored. Since axios wraps net.http, the expected
   * behavior matches Network Kit.
   */
  static async nscTrustAnchors(): Promise<ScenarioResult> {
    try {
      const config: AxiosRequestConfig = {
        method: 'GET',
        usingProtocol: http.HttpProtocol.HTTP2,
        readTimeout: 15000,
        connectTimeout: 15000,
        headers: { 'Accept': 'application/json' },
        // NOTE: no caPath — trust comes from network_config.json
      };
      const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.httpsBase()}/api/protocol`, config);
      const body = resp.data;
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : no code-level caPath; trust comes from network_config.json base-config.trust-anchors`;
      return new ScenarioResult(resp.status === 200,
        resp.status === 200 ? 'system trust-anchors honored (HTTPS OK)' : 'system trust-anchors NOT honored', detail,
        resp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios nsc-trust-anchors', err);
    }
  }

  /**
   * Network Security Configuration — component-config cleartext control.
   * axios goes through net.http, so the "Network Kit" component-config applies.
   * This probes the current effective permission.
   */
  static async nscCleartext(): Promise<ScenarioResult> {
    try {
      const resp = await axios.get<Record<string, string>, AxiosJsonResp, null>(`${AppConfig.http1Base()}/api/protocol`, AxiosScenarios.baseConfig());
      const body = resp.data;
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : cleartextTrafficPermitted=true in network_config.json base-config;\n` +
        `              axios 底层走 net.http，受 component-config.'Network Kit'=true 约束，明文当前允许。`;
      return new ScenarioResult(resp.status === 200,
        resp.status === 200 ? 'plaintext allowed (component-config true)' : 'plaintext blocked by system', detail,
        resp.status);
    } catch (e) {
      const err = e as AxiosJsonErr;
      return AxiosScenarios.err('Axios nsc-cleartext', err);
    }
  }

  // ---- helpers --------------------------------------------------------------

  /** Common base config: GET, 15s timeouts, Accept JSON. */
  private static baseConfig(): AxiosRequestConfig {
    return {
      method: 'GET',
      readTimeout: 15000,
      connectTimeout: 15000,
      headers: { 'Accept': 'application/json' },
    };
  }

  /**
   * PATCH via axios.request — the @ohos/axios 2.2.13 .d.ts omits the `patch`
   * verb (it exists at runtime), so use request({ method: 'PATCH' }) instead.
   */
  private static patchRequest(base: string): Promise<AxiosJsonResp> {
    const config: AxiosRequestConfig = {
      url: base,
      method: 'PATCH',
      data: { a: '1' },
      readTimeout: 15000,
      connectTimeout: 15000,
      headers: { 'Accept': 'application/json' },
    };
    return axios.request<Record<string, string>, AxiosJsonResp, Record<string, string>>(config);
  }

  /**
   * Write the embedded mock CA PEM to filesDir once and return the file path.
   * axios only supports `caPath` (no caData), so the PEM must live in a file.
   */
  private static async ensureCaFile(filesDir: string): Promise<string> {
    if (AxiosScenarios.caFilePath.length > 0) {
      return AxiosScenarios.caFilePath;
    }
    const p = `${filesDir}/mock-ca.pem`;
    const file = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, AppConfig.MOCK_CA_PEM);
    } finally {
      fs.closeSync(file);
    }
    AxiosScenarios.caFilePath = p;
    return p;
  }

  private static async getStats(): Promise<number> {
    const resp = await axios.get<Record<string, number>, AxiosResponse<Record<string, number>, null>, null>(
      `${AppConfig.http1Base()}/api/cache/stats`, AxiosScenarios.baseConfig());
    return Number(resp.data['networkHits'] ?? 0);
  }

  private static async getEtagStats(): Promise<EtagStatsAxios> {
    const resp = await axios.get<Record<string, number>, AxiosResponse<Record<string, number>, null>, null>(
      `${AppConfig.http1Base()}/api/cache/etag/stats`, AxiosScenarios.baseConfig());
    const s = resp.data;
    return {
      full200: Number(s['full200'] ?? 0),
      notModified304: Number(s['notModified304'] ?? 0),
      ifNoneMatchSeen: Number(s['ifNoneMatchSeen'] ?? 0),
    };
  }

  /** Read a single response header value via AxiosHeaders. */
  private static readHeader(resp: AxiosJsonResp, key: string): string {
    const h = resp.headers as AxiosHeaders;
    const v = h.get(key);
    if (v === undefined || v === null) {
      return '';
    }
    if (Array.isArray(v)) {
      return v.join(',');
    }
    return String(v);
  }

  /** Read Set-Cookie values (string or array) from the response headers. */
  private static readSetCookies(resp: AxiosJsonResp): string[] {
    const h = resp.headers as AxiosHeaders;
    const v = h.get('set-cookie');
    if (v === undefined || v === null) {
      return [];
    }
    if (Array.isArray(v)) {
      const out: string[] = [];
      for (let i = 0; i < v.length; i++) {
        out.push(String(v[i]));
      }
      return out;
    }
    return [String(v)];
  }

  /**
   * Parse Set-Cookie values into a Cookie header string ("a=1; b=2").
   * Tolerates both comma-joined values and per-cookie entries.
   */
  private static extractCookieHeader(cookies: string[]): string {
    const pairs: string[] = [];
    for (let i = 0; i < cookies.length; i++) {
      const segs = cookies[i].split(',');
      for (let j = 0; j < segs.length; j++) {
        const seg = segs[j].trim();
        if (seg.length === 0) {
          continue;
        }
        const semi = seg.indexOf(';');
        const pair = semi > 0 ? seg.slice(0, semi).trim() : seg;
        const eq = pair.indexOf('=');
        if (eq > 0) {
          pairs.push(pair);
        }
      }
    }
    return pairs.join('; ');
  }

  /** Extract the echoed method from a /api/methods response (auto-parsed or raw). */
  private static echoedMethod(resp: AxiosJsonResp): string {
    const d = resp.data;
    if (d === undefined || d === null) {
      return '(no body)';
    }
    if (typeof d === 'object') {
      const m = d['method'];
      return m === undefined ? '(no body)' : String(m);
    }
    const s = String(d);
    if (s.length === 0) {
      return '(no body)';
    }
    try {
      const o = JSON.parse(s) as Record<string, string>;
      return o['method'] ?? '(no body)';
    } catch (e) {
      return '(no body)';
    }
  }

  private static fmt(s: EtagStatsAxios): string {
    return `200=${s.full200},304=${s.notModified304},inm=${s.ifNoneMatchSeen}`;
  }

  /** Render an axios error result with code/status/message. */
  private static err(what: string, err: AxiosJsonErr): ScenarioResult {
    const code = err.code ?? '';
    const msg = err.message ?? '';
    const status = err.response?.status ?? 0;
    return new ScenarioResult(false, `${what} 失败: ${code} ${msg}`,
      `${what} 失败\ncode=${code}\nstatus=${status}\n${msg}`);
  }
}
