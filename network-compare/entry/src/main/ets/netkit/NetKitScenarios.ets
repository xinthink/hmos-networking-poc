/**
 * Scenario runner using Network Kit (@kit.NetworkKit, formerly @ohos.net.http).
 *
 * Each method executes one comparison scenario and returns a ScenarioResult.
 * All methods hit the mock server (see mock-server/server.mjs).
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

interface EchoBody {
  protocol: string;
  method: string;
  query: Record<string, string>;
  body?: Object;
}

/** One REST-method case for the method-coverage scenario. */
interface MethodCase {
  name: string;
  method: http.RequestMethod;
  custom?: string;
}

/** One target (protocol + base URL) for the header-normalization scenario. */
interface HeaderTarget {
  label: string;
  base: string;
  protocol: http.HttpProtocol;
}

/** Server-side ETag revalidation counters (mirrors mock-server etagState). */
interface EtagStats {
  full200: number;
  notModified304: number;
  ifNoneMatchSeen: number;
}

export class NetKitScenarios {
  /** GET /api/protocol over HTTP/1.1 (explicit usingProtocol). */
  static async protocolHttp1(): Promise<ScenarioResult> {
    return NetKitScenarios.getProtocol(http.HttpProtocol.HTTP1_1, AppConfig.http1Base());
  }

  /** GET /api/protocol over HTTPS; force HTTP/2 via usingProtocol. */
  static async protocolHttp2(): Promise<ScenarioResult> {
    return NetKitScenarios.getProtocol(http.HttpProtocol.HTTP2, AppConfig.httpsBase());
  }

  /** GET /api/protocol with protocol left to system auto-negotiation. */
  static async protocolAuto(): Promise<ScenarioResult> {
    return NetKitScenarios.getProtocol(undefined, AppConfig.httpsBase());
  }

  private static async getProtocol(protocol: http.HttpProtocol | undefined, base: string): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingProtocol: protocol,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: { 'Accept': 'application/json' },
        caData: AppConfig.MOCK_CA_PEM, // trust the mock server's self-signed cert
      };
      const resp = await req.request(`${base}/api/protocol`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, string>;
      const conn = resp.connectionExtraInfo;
      const clientProtocol = conn?.networkProtocolName ?? '(n/a)';
      const detail =
        `HTTP status : ${resp.responseCode}\n` +
        `server saw  : ${body['protocol']} (httpVersion ${body['httpVersion']})\n` +
        `client saw  : ${clientProtocol}\n` +
        `note        : ${body['note']}`;
      return new ScenarioResult(resp.responseCode === 200,
        `server saw ${body['protocol']}, client protocol "${clientProtocol}"`, detail, resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error(`NetworkKit /api/protocol (${protocol ?? 'auto'})`, err as Error);
    } finally {
      req.destroy();
    }
  }

  /**
   * REST method coverage: GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS -> /api/methods.
   * Note: RequestMethod.PATCH only exists since API 26, so PATCH uses customMethod (API 23+).
   */
  static async methods(): Promise<ScenarioResult> {
    const cases: MethodCase[] = [
      { name: 'GET', method: http.RequestMethod.GET },
      { name: 'POST', method: http.RequestMethod.POST },
      { name: 'PUT', method: http.RequestMethod.PUT },
      { name: 'PATCH', method: http.RequestMethod.GET, custom: 'PATCH' },
      { name: 'DELETE', method: http.RequestMethod.DELETE },
      { name: 'HEAD', method: http.RequestMethod.HEAD },
      { name: 'OPTIONS', method: http.RequestMethod.OPTIONS },
    ];
    const lines: string[] = [];
    let allOk = true;
    for (let i = 0; i < cases.length; i++) {
      const c = cases[i];
      const req = http.createHttp();
      try {
        const options: http.HttpRequestOptions = {
          method: c.method,
          customMethod: c.custom,
          expectDataType: http.HttpDataType.STRING,
          readTimeout: 15000,
          connectTimeout: 15000,
          header: { 'Content-Type': 'application/json' },
          caData: AppConfig.MOCK_CA_PEM,
        };
        const resp = await req.request(`${AppConfig.http1Base()}/api/methods`, options);
        let echoed = '';
        try {
          echoed = (JSON.parse(String(resp.result)) as Record<string, string>)['method'] ?? '(no body)';
        } catch {
          echoed = '(no body)';
        }
        const ok = resp.responseCode === 200;
        allOk = allOk && ok;
        lines.push(`${c.name.padEnd(8)} -> ${resp.responseCode}  server echoed: ${echoed}`);
      } catch (e) {
        const err = e as BusinessError;
        allOk = false;
        lines.push(`${c.name.padEnd(8)} -> ERROR ${err.code}: ${err.message}`);
      } finally {
        req.destroy();
      }
    }
    return new ScenarioResult(allOk, allOk ? 'all 7 methods OK' : 'some methods failed', lines.join('\n'));
  }

  /**
   * Header normalization: send a mixed-case header, ask the server what case it received.
   * HTTP/1.1 preserves case on the wire; HTTP/2 requires lowercase names.
   */
  static async headerCase(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      // Run twice: once over HTTP/1.1, once over HTTP/2 (TLS).
      const targets: HeaderTarget[] = [
        { label: 'HTTP/1.1', base: AppConfig.http1Base(), protocol: http.HttpProtocol.HTTP1_1 },
        { label: 'HTTP/2', base: AppConfig.httpsBase(), protocol: http.HttpProtocol.HTTP2 },
      ];
      const results: string[] = [];
      for (let i = 0; i < targets.length; i++) {
        const t = targets[i];
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingProtocol: t.protocol,
          readTimeout: 15000,
          connectTimeout: 15000,
          caData: AppConfig.MOCK_CA_PEM,
          header: {
            'Accept': 'application/json',
            'X-MiXeD-CaSe-Hdr': 'MixedCaseValue',
            'x-lowercase-hdr': 'lower',
            'X-ALLCAPS-HDR': 'upper',
          },
        };
        const resp = await req.request(`${t.base}/api/headers`, options);
        const body = JSON.parse(String(resp.result)) as Record<string, Object>;
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
      const ok = results.length === 2;
      return new ScenarioResult(ok, ok ? 'see detail (h1 case vs h2 lowercase)' : 'failed', results.join('\n'));
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit /api/headers', err as Error);
    } finally {
      req.destroy();
    }
  }

  /**
   * Cookie round-trip (manual, as Network Kit has no cookie jar):
   * 1) GET /api/cookie/set -> read Set-Cookie from response
   * 2) GET /api/cookie/read with the cookie echoed back in the Cookie header
   */
  static async cookies(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const setOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: { 'Accept': 'application/json' },
        caData: AppConfig.MOCK_CA_PEM,
      };
      const setResp = await req.request(`${AppConfig.http1Base()}/api/cookie/set`, setOptions);
      const rawCookies: string = setResp.cookies ?? '';
      // Network Kit returns cookies in Netscape cookie-file format, e.g.
      //   "#HttpOnly_10.0.2.2\tFALSE\t/\tFALSE\t0\tmock_session\tabc123-...\n10.0.2.2\tFALSE\t/\tFALSE\t1787419490\tmock_pref\tdark_123"
      // Each line is tab-separated; the name is the 6th field and the value the 7th.
      // Also tolerate simple "name=value; name=value" input.
      const cookieHeader = NetKitScenarios.extractCookieHeader(rawCookies);

      const readOptions: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: { 'Cookie': cookieHeader },
        caData: AppConfig.MOCK_CA_PEM,
      };
      const readResp = await req.request(`${AppConfig.http1Base()}/api/cookie/read`, readOptions);
      const readBody = JSON.parse(String(readResp.result)) as Record<string, string>;
      const detail =
        `Set-Cookie (raw)  : ${rawCookies}\n` +
        `sent back (Cookie): ${readBody['cookieHeader'] ?? '(empty)'}`;
      const ok = readResp.responseCode === 200 && (readBody['cookieHeader'] ?? '').length > 0;
      return new ScenarioResult(ok, ok ? 'cookie round-trip OK (manual)' : 'cookie round-trip failed', detail,
        readResp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit cookies', err as Error);
    } finally {
      req.destroy();
    }
  }

  /** Cache: GET /api/cache twice with the SAME URL (usingCache true); check server hit counter delta. */
  static async cache(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const statsBefore = await NetKitScenarios.getStats(req);
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingCache: true,
          readTimeout: 15000,
          connectTimeout: 15000,
          header: { 'Accept': 'application/json' },
          caData: AppConfig.MOCK_CA_PEM,
        };
        const resp = await req.request(`${AppConfig.http1Base()}/api/cache`, options);
        const isHit = resp.connectionExtraInfo?.isCacheHit ?? false;
        hitLines.push(`req #${i}: status=${resp.responseCode} clientCacheHit=${isHit}`);
      }
      // server-side counter: +1 => 2nd request hit the network; +0 => served from client cache
      const statsAfter = await NetKitScenarios.getStats(req);
      const delta = statsAfter - statsBefore;
      const detail = `${hitLines.join('\n')}\n` +
        `server network hits: before=${statsBefore} after=${statsAfter} delta=${delta}\n` +
        `(delta=0 => 2nd request served from client cache; delta=1 => both hit the network)`;
      const cached = delta === 0;
      return new ScenarioResult(true, cached ? '2nd request served from cache' : 'cache not used (delta=1)', detail);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit cache', err as Error);
    } finally {
      req.destroy();
    }
  }

  private static async getStats(req: http.HttpRequest): Promise<number> {
    const statsResp = await req.request(`${AppConfig.http1Base()}/api/cache/stats`, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 15000,
      connectTimeout: 15000,
      header: { 'Accept': 'application/json' },
      caData: AppConfig.MOCK_CA_PEM,
    });
    const stats = JSON.parse(String(statsResp.result)) as Record<string, number>;
    return Number(stats['networkHits'] ?? 0);
  }

  /**
   * ETag conditional-request test: GET /api/cache/etag twice (no-cache forces
   * revalidation). A spec-compliant cache sends If-None-Match on request #2 and
   * consumes the 304 (server counters: notModified304 / ifNoneMatchSeen delta).
   */
  static async etag(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const before = await NetKitScenarios.getEtagStats(req);
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const options: http.HttpRequestOptions = {
          method: http.RequestMethod.GET,
          expectDataType: http.HttpDataType.STRING,
          usingCache: true,
          readTimeout: 15000,
          connectTimeout: 15000,
          header: { 'Accept': 'application/json' },
          caData: AppConfig.MOCK_CA_PEM,
        };
        const resp = await req.request(`${AppConfig.http1Base()}/api/cache/etag`, options);
        const isHit = resp.connectionExtraInfo?.isCacheHit ?? false;
        const respEtag = NetKitScenarios.readHeader(resp, 'etag');
        hitLines.push(`req #${i}: status=${resp.responseCode} clientCacheHit=${isHit} respEtag=${respEtag}`);
      }
      const after = await NetKitScenarios.getEtagStats(req);
      const d304 = after.notModified304 - before.notModified304;
      const dInm = after.ifNoneMatchSeen - before.ifNoneMatchSeen;
      const detail = `${hitLines.join('\n')}\n` +
        `server stats: before=${NetKitScenarios.fmt(before)} after=${NetKitScenarios.fmt(after)}\n` +
        `delta: ifNoneMatchSeen=${dInm} notModified304=${d304}\n` +
        `(dInm>0 => client sent If-None-Match; d304>0 => server answered 304 and client consumed it)`;
      const etagSupported = dInm > 0 && d304 > 0;
      return new ScenarioResult(true,
        etagSupported ? 'ETag 条件请求生效 (If-None-Match -> 304)' : 'ETag 未生效（未发送 If-None-Match）', detail);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit etag', err as Error);
    } finally {
      req.destroy();
    }
  }

  private static async getEtagStats(req: http.HttpRequest): Promise<EtagStats> {
    const statsResp = await req.request(`${AppConfig.http1Base()}/api/cache/etag/stats`, {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      readTimeout: 15000,
      connectTimeout: 15000,
      header: { 'Accept': 'application/json' },
      caData: AppConfig.MOCK_CA_PEM,
    });
    const s = JSON.parse(String(statsResp.result)) as Record<string, number>;
    return {
      full200: Number(s['full200'] ?? 0),
      notModified304: Number(s['notModified304'] ?? 0),
      ifNoneMatchSeen: Number(s['ifNoneMatchSeen'] ?? 0),
    };
  }

  private static readHeader(resp: http.HttpResponse, key: string): string {
    const h = resp.header as Record<string, string>;
    if (h === undefined || h === null) {
      return '';
    }
    const v = h[key] ?? h[key.toLowerCase()];
    return v === undefined ? '' : String(v);
  }

  private static fmt(s: EtagStats): string {
    return `200=${s.full200},304=${s.notModified304},inm=${s.ifNoneMatchSeen}`;
  }

  /**
   * Multipart/form-data upload using Network Kit's native multiFormDataList (API 11+).
   * Uploads one text field and one binary file part.
   */
  static async multipartUpload(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const bin = new Uint8Array(256);
      for (let i = 0; i < bin.length; i++) {
        bin[i] = i;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
        header: { 'Content-Type': 'multipart/form-data' },
        caData: AppConfig.MOCK_CA_PEM,
        multiFormDataList: [
          { name: 'field1', contentType: 'text/plain', data: 'hello-from-netkit' },
          {
            name: 'file1',
            contentType: 'application/octet-stream',
            data: bin.buffer,
            remoteFileName: 'netkit.bin',
          },
        ],
      };
      const resp = await req.request(`${AppConfig.http1Base()}/api/upload/multipart`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, Object>;
      const parts = body['parts'] as Array<Record<string, Object>>;
      const lines: string[] = [`partCount=${body['partCount']} totalBytes=${body['totalBytes']}`];
      for (const p of parts) {
        const name = String(p['name'] ?? '(unnamed)');
        const fn = String(p['filename'] ?? '');
        lines.push(`  part name=${name} filename=${fn} size=${p['size']} type=${p['contentType']}`);
      }
      const ok = resp.responseCode === 200 && parts.length >= 2;
      return new ScenarioResult(ok, ok ? `multipart OK, ${parts.length} parts` : 'multipart failed',
        `${lines.join('\n')}\nboundary=${body['boundary']}`, resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit multipart', err as Error);
    } finally {
      req.destroy();
    }
  }

  /** Binary upload: POST an ArrayBuffer with Content-Type application/octet-stream. */
  static async binaryUpload(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const payload = new Uint8Array(1024 * 4);
      for (let i = 0; i < payload.length; i++) {
        payload[i] = (i * 31) & 0xff;
      }
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 30000,
        connectTimeout: 15000,
        header: { 'Content-Type': 'application/octet-stream' },
        caData: AppConfig.MOCK_CA_PEM,
        extraData: payload.buffer,
      };
      const resp = await req.request(`${AppConfig.http1Base()}/api/upload/binary`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, Object>;
      const detail =
        `bytes=${body['bytes']} sha256=${body['sha256']}\n` +
        `content-type sent: application/octet-stream\n` +
        `server saw content-type: ${body['contentType']}`;
      const ok = resp.responseCode === 200 && Number(body['bytes']) === payload.length;
      return new ScenarioResult(ok, ok ? `binary upload OK (${payload.length} bytes)` : 'binary upload failed',
        detail, resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit binary upload', err as Error);
    } finally {
      req.destroy();
    }
  }

  /**
   * Parse the cookies string returned by Network Kit into a Cookie header value.
   * Network Kit returns cookies in Netscape cookie-file format (tab-separated,
   * name in column 6, value in column 7). Also tolerates "name=value; ..." input.
   */
  private static extractCookieHeader(raw: string): string {
    if (!raw || raw.length === 0) {
      return '';
    }
    const pairs: string[] = [];
    const lines = raw.split(/[\r\n]+/);
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        continue;
      }
      // Netscape cookie-file line: fields tab-separated; ignore "#HttpOnly_" prefix
      const fields = line.replace(/^#/, '').split('\t');
      if (fields.length >= 7) {
        const name = fields[5];
        const value = fields[6];
        if (name.length > 0) {
          pairs.push(`${name}=${value}`);
          continue;
        }
      }
      // fallback: "name=value" possibly with attributes after ';'
      const eq = line.indexOf('=');
      if (eq > 0) {
        const name = line.slice(0, eq).trim();
        const value = line.slice(eq + 1).split(';')[0].trim();
        if (name.length > 0) {
          pairs.push(`${name}=${value}`);
        }
      }
    }
    return pairs.join('; ');
  }

  /**
   * Network Security Configuration (network_config.json) — trust-anchors.
   * The app embeds the mock CA under resfile/mock-ca and references it via
   * base-config.trust-anchors in network_config.json. This scenario sends NO
   * code-level CA (no caData), so success proves the system-level trust-anchors
   * are honored by Network Kit.
   */
  static async nscTrustAnchors(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        usingProtocol: http.HttpProtocol.HTTP2,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: { 'Accept': 'application/json' },
        // NOTE: no caData / caPath — trust comes from network_config.json
      };
      const resp = await req.request(`${AppConfig.httpsBase()}/api/protocol`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, string>;
      const conn = resp.connectionExtraInfo;
      const detail =
        `HTTP status : ${resp.responseCode}\n` +
        `client saw  : ${conn?.networkProtocolName ?? '(n/a)'}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : no code-level caData; trust comes from network_config.json base-config.trust-anchors`;
      return new ScenarioResult(resp.responseCode === 200,
        resp.responseCode === 200 ? 'system trust-anchors honored (HTTPS OK)' : 'system trust-anchors NOT honored',
        detail, resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit nsc-trust-anchors', err as Error);
    } finally {
      req.destroy();
    }
  }

  /**
   * Network Security Configuration — component-config cleartext control.
   * network_config.json sets component-config."Network Kit" to true (cleartext
   * allowed). If set to false, system blocks Network Kit plaintext requests.
   * This probes the current effective permission.
   */
  static async nscCleartext(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING,
        readTimeout: 15000,
        connectTimeout: 15000,
        header: { 'Accept': 'application/json' },
        caData: AppConfig.MOCK_CA_PEM,
      };
      const resp = await req.request(`${AppConfig.http1Base()}/api/protocol`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, string>;
      const detail =
        `HTTP status : ${resp.responseCode}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : cleartextTrafficPermitted=true in network_config.json base-config;\n` +
        `              component-config.'Network Kit'=true allows plaintext for Network Kit.`;
      return new ScenarioResult(resp.responseCode === 200,
        resp.responseCode === 200 ? 'plaintext allowed (component-config true)' : 'plaintext blocked by system',
        detail, resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit nsc-cleartext', err as Error);
    } finally {
      req.destroy();
    }
  }
}
