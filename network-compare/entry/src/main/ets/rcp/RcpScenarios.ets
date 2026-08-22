/**
 * Scenario runner using Remote Communication Kit (@kit.RemoteCommunicationKit).
 *
 * Mirrors NetKitScenarios: same endpoints, same comparison scenarios, so the
 * results can be compared side by side. RCP auto-negotiates the HTTP version
 * (ALPN); there is no explicit protocol switch below API 26.
 */
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

/** One target (base URL + label) for the header-normalization scenario. */
interface BaseTarget {
  label: string;
  base: string;
}

/** Server-side ETag revalidation counters (mirrors mock-server etagState). */
interface EtagStatsRcp {
  full200: number;
  notModified304: number;
  ifNoneMatchSeen: number;
}

export class RcpScenarios {
  /** GET /api/protocol over cleartext HTTP/1.1. */
  static async protocolHttp1(): Promise<ScenarioResult> {
    return RcpScenarios.getProtocol(AppConfig.http1Base());
  }

  /** GET /api/protocol over TLS (ALPN negotiates h2 when possible). */
  static async protocolHttp2(): Promise<ScenarioResult> {
    return RcpScenarios.getProtocol(AppConfig.httpsBase());
  }

  private static async getProtocol(base: string): Promise<ScenarioResult> {
    const session = RcpScenarios.newSession();
    try {
      const resp = await session.get(`${base}/api/protocol`);
      const body = JSON.parse(resp.toString() ?? '{}') as Record<string, string>;
      const detail =
        `HTTP status : ${resp.statusCode}\n` +
        `client saw  : HTTP/${resp.httpVersion}\n` +
        `server saw  : ${body['protocol']} (httpVersion ${body['httpVersion']})\n` +
        `note        : ${body['note']}`;
      return new ScenarioResult(resp.statusCode === 200,
        `client HTTP/${resp.httpVersion}, server saw ${body['protocol']}`, detail, resp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error(`RCP /api/protocol (${base})`, err as Error);
    } finally {
      session.close();
    }
  }

  /** REST method coverage via RCP (get/post/put/patch/delete/head/options). */
  static async methods(): Promise<ScenarioResult> {
    const session = RcpScenarios.newSession();
    try {
      const lines: string[] = [];
      let allOk = true;
      const run = async (name: string, p: Promise<rcp.Response>): Promise<void> => {
        try {
          const resp = await p;
          const echoed = (JSON.parse(resp.toString() ?? '{}') as Record<string, string>)['method'] ?? '(no body)';
          const ok = resp.statusCode === 200;
          allOk = allOk && ok;
          lines.push(`${name.padEnd(8)} -> ${resp.statusCode}  server echoed: ${echoed}`);
        } catch (e) {
          const err = e as BusinessError;
          allOk = false;
          lines.push(`${name.padEnd(8)} -> ERROR ${err.code}: ${err.message}`);
        }
      };
      await run('GET', session.get(`${AppConfig.http1Base()}/api/methods`));
      await run('POST', session.post(`${AppConfig.http1Base()}/api/methods`, new rcp.Form({ a: '1' })));
      await run('PUT', session.put(`${AppConfig.http1Base()}/api/methods`, new rcp.Form({ a: '1' })));
      await run('PATCH', RcpScenarios.fetchMethod(session, 'PATCH'));
      await run('DELETE', session.delete(`${AppConfig.http1Base()}/api/methods`));
      await run('HEAD', session.head(`${AppConfig.http1Base()}/api/methods`));
      await run('OPTIONS', RcpScenarios.fetchMethod(session, 'OPTIONS'));
      return new ScenarioResult(allOk, allOk ? 'all 7 methods OK' : 'some methods failed', lines.join('\n'));
    } finally {
      session.close();
    }
  }

  /** Header normalization: send mixed-case headers, server reports what it received. */
  static async headerCase(): Promise<ScenarioResult> {
    const session = RcpScenarios.newSession();
    try {
      const results: string[] = [];
      const targets: BaseTarget[] = [
        { label: 'HTTP/1.1', base: AppConfig.http1Base() },
        { label: 'HTTP/2', base: AppConfig.httpsBase() },
      ];
      for (let i = 0; i < targets.length; i++) {
        const t = targets[i];
        const headers: rcp.RequestHeaders = {
          'accept': 'application/json',
          'X-MiXeD-CaSe-Hdr': 'MixedCaseValue',
          'x-lowercase-hdr': 'lower',
          'X-ALLCAPS-HDR': 'upper',
        };
        const req = new rcp.Request(`${t.base}/api/headers`, 'GET', headers);
        const resp = await session.fetch(req);
        const body = JSON.parse(resp.toString() ?? '{}') as Record<string, Object>;
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
      const err = e as BusinessError;
      return ScenarioResult.error('RCP /api/headers', err as Error);
    } finally {
      session.close();
    }
  }

  /**
   * Cookie round-trip using RCP's CookieRepository (API 23): Set-Cookie from
   * /api/cookie/set is stored automatically and attached to /api/cookie/read.
   */
  static async cookies(): Promise<ScenarioResult> {
    const repo = rcp.CookieRepository.create();
    const session = rcp.createSession({ cookieRepository: repo });
    try {
      const setResp = await session.get(`${AppConfig.http1Base()}/api/cookie/set`);
      const readResp = await session.get(`${AppConfig.http1Base()}/api/cookie/read`);
      const readBody = JSON.parse(readResp.toString() ?? '{}') as Record<string, string>;
      const detail =
        `set status     : ${setResp.statusCode}\n` +
        `read status    : ${readResp.statusCode}\n` +
        `cookies stored : ${setResp.cookies?.length ?? 0}\n` +
        `server received Cookie header: ${readBody['cookieHeader'] ?? '(empty)'}`;
      const ok = readResp.statusCode === 200 && (readBody['cookieHeader'] ?? '').length > 0;
      return new ScenarioResult(ok, ok ? 'cookie round-trip OK (CookieRepository)' : 'cookie round-trip failed',
        detail, readResp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('RCP cookies', err as Error);
    } finally {
      session.close();
    }
  }

  /**
   * Cache: session configured with an rcp.ResponseCache (API 20).
   * GET the SAME /api/cache URL twice; response.cacheInfo is set when served
   * from cache, and the server hit counter delta confirms it.
   */
  static async cache(filesDir: string): Promise<ScenarioResult> {
    const cache = new rcp.ResponseCache({
      persistent: { kind: 'file-system', pathToFolder: filesDir },
    });
    const session = rcp.createSession({
      requestConfiguration: { cache: cache },
    });
    try {
      const before = await RcpScenarios.getStats(session);
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const resp = await session.get(`${AppConfig.http1Base()}/api/cache`);
        const fromCache = resp.cacheInfo !== undefined;
        hitLines.push(`req #${i}: status=${resp.statusCode} servedFromCache=${fromCache}`);
      }
      const after = await RcpScenarios.getStats(session);
      const delta = after - before;
      const detail = `${hitLines.join('\n')}\n` +
        `server network hits: before=${before} after=${after} delta=${delta}\n` +
        `(delta=0 => 2nd request served from client cache; delta=1 => both hit the network)`;
      const cached = delta === 0;
      return new ScenarioResult(true, cached ? '2nd request served from cache' : 'cache not used (delta=1)', detail);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('RCP cache', err as Error);
    } finally {
      session.close();
    }
  }

  private static async getStats(session: rcp.Session): Promise<number> {
    const statsResp = await session.get(`${AppConfig.http1Base()}/api/cache/stats`);
    const stats = JSON.parse(statsResp.toString() ?? '{}') as Record<string, number>;
    return Number(stats['networkHits'] ?? 0);
  }

  /**
   * ETag conditional-request test (mirror of NetKitScenarios.etag).
   * GET /api/cache/etag twice with a ResponseCache session; no-cache forces
   * revalidation, so a spec-compliant cache sends If-None-Match on request #2
   * and consumes the 304.
   */
  static async etag(filesDir: string): Promise<ScenarioResult> {
    const cache = new rcp.ResponseCache({
      persistent: { kind: 'file-system', pathToFolder: filesDir },
    });
    const session = rcp.createSession({
      requestConfiguration: { cache: cache },
    });
    try {
      const before = await RcpScenarios.getEtagStats(session);
      const hitLines: string[] = [];
      for (let i = 1; i <= 2; i++) {
        const resp = await session.get(`${AppConfig.http1Base()}/api/cache/etag`);
        const fromCache = resp.cacheInfo !== undefined;
        const respEtag = RcpScenarios.readHeader(resp, 'etag');
        hitLines.push(`req #${i}: status=${resp.statusCode} servedFromCache=${fromCache} respEtag=${respEtag}`);
      }
      const after = await RcpScenarios.getEtagStats(session);
      const d304 = after.notModified304 - before.notModified304;
      const dInm = after.ifNoneMatchSeen - before.ifNoneMatchSeen;
      const detail = `${hitLines.join('\n')}\n` +
        `server stats: before=${RcpScenarios.fmt(before)} after=${RcpScenarios.fmt(after)}\n` +
        `delta: ifNoneMatchSeen=${dInm} notModified304=${d304}\n` +
        `(dInm>0 => client sent If-None-Match; d304>0 => server answered 304 and client consumed it)`;
      const etagSupported = dInm > 0 && d304 > 0;
      return new ScenarioResult(true,
        etagSupported ? 'ETag 条件请求生效 (If-None-Match -> 304)' : 'ETag 未生效（未发送 If-None-Match）', detail);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('RCP etag', err as Error);
    } finally {
      session.close();
    }
  }

  private static async getEtagStats(session: rcp.Session): Promise<EtagStatsRcp> {
    const statsResp = await session.get(`${AppConfig.http1Base()}/api/cache/etag/stats`);
    const s = JSON.parse(statsResp.toString() ?? '{}') as Record<string, number>;
    return {
      full200: Number(s['full200'] ?? 0),
      notModified304: Number(s['notModified304'] ?? 0),
      ifNoneMatchSeen: Number(s['ifNoneMatchSeen'] ?? 0),
    };
  }

  private static readHeader(resp: rcp.Response, key: string): string {
    const h = resp.headers as Record<string, string | string[] | undefined>;
    if (h === undefined || h === null) {
      return '';
    }
    const v = h[key] ?? h[key.toLowerCase()];
    if (v === undefined) {
      return '';
    }
    if (Array.isArray(v)) {
      return v.join(',');
    }
    return String(v);
  }

  private static fmt(s: EtagStatsRcp): string {
    return `200=${s.full200},304=${s.notModified304},inm=${s.ifNoneMatchSeen}`;
  }

  /** Multipart/form-data upload using rcp.MultipartForm (native). */
  static async multipartUpload(): Promise<ScenarioResult> {
    const session = RcpScenarios.newSession();
    try {
      const bin = new Uint8Array(256);
      for (let i = 0; i < bin.length; i++) {
        bin[i] = i;
      }
      const form = new rcp.MultipartForm({
        field1: 'hello-from-rcp',
        file1: {
          contentType: 'application/octet-stream',
          remoteFileName: 'rcp.bin',
          contentOrPath: { content: bin.buffer },
        },
      });
      const resp = await session.post(`${AppConfig.http1Base()}/api/upload/multipart`, form);
      const body = JSON.parse(resp.toString() ?? '{}') as Record<string, Object>;
      const parts = body['parts'] as Array<Record<string, Object>>;
      const lines: string[] = [`partCount=${body['partCount']} totalBytes=${body['totalBytes']}`];
      for (const p of parts) {
        const name = String(p['name'] ?? '(unnamed)');
        const fn = String(p['filename'] ?? '');
        lines.push(`  part name=${name} filename=${fn} size=${p['size']} type=${p['contentType']}`);
      }
      const ok = resp.statusCode === 200 && parts.length >= 2;
      return new ScenarioResult(ok, ok ? `multipart OK, ${parts.length} parts` : 'multipart failed',
        `${lines.join('\n')}\nboundary=${body['boundary']}`, resp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('RCP multipart', err as Error);
    } finally {
      session.close();
    }
  }

  /** Binary upload: ArrayBuffer body with Content-Type application/octet-stream. */
  static async binaryUpload(): Promise<ScenarioResult> {
    const session = RcpScenarios.newSession();
    try {
      const payload = new Uint8Array(1024 * 4);
      for (let i = 0; i < payload.length; i++) {
        payload[i] = (i * 31) & 0xff;
      }
      const headers: rcp.RequestHeaders = { 'content-type': 'application/octet-stream' };
      const req = new rcp.Request(`${AppConfig.http1Base()}/api/upload/binary`, 'POST', headers, payload.buffer);
      const resp = await session.fetch(req);
      const body = JSON.parse(resp.toString() ?? '{}') as Record<string, Object>;
      const detail =
        `bytes=${body['bytes']} sha256=${body['sha256']}\n` +
        `content-type sent: application/octet-stream\n` +
        `server saw content-type: ${body['contentType']}`;
      const ok = resp.statusCode === 200 && Number(body['bytes']) === payload.length;
      return new ScenarioResult(ok, ok ? `binary upload OK (${payload.length} bytes)` : 'binary upload failed',
        detail, resp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('RCP binary upload', err as Error);
    } finally {
      session.close();
    }
  }

  // ---- helpers -------------------------------------------------------------

  /** Session trusting the mock server's self-signed CA. */
  private static newSession(): rcp.Session {
    const security: rcp.SecurityConfiguration = {
      remoteValidation: { content: AppConfig.MOCK_CA_PEM },
    };
    const config: rcp.Configuration = { security: security };
    return rcp.createSession({ requestConfiguration: config });
  }

  private static async fetchMethod(session: rcp.Session, method: string): Promise<rcp.Response> {
    const req = new rcp.Request(`${AppConfig.http1Base()}/api/methods`, method);
    return session.fetch(req);
  }
}
