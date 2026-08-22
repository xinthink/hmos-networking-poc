/**
 * Mock server for the Network Kit vs Remote Communication Kit (RCP) comparison.
 *
 * Two listeners:
 *   - HTTP/1.1 (cleartext) on  :8080
 *   - TLS with ALPN on        :8443  -> negotiates HTTP/2 (h2) when the client
 *     supports it, otherwise falls back to HTTP/1.1 over TLS.
 *
 * Endpoints:
 *   GET  /api/protocol          -> which protocol version the request arrived on
 *   ANY  /api/echo              -> echo method/url/query/headers(body for non-GET)
 *   GET  /api/headers           -> header case as received on the wire
 *   ANY  /api/methods           -> which HTTP method was received (REST method coverage)
 *   GET  /api/cookie/set        -> sets a cookie
 *   GET  /api/cookie/read       -> echoes the received Cookie header
 *   GET  /api/cache             -> Cache-Control: max-age=60, counts network hits
 *   GET  /api/cache/stats       -> server-side counter for /api/cache
 *   GET  /api/cache/etag        -> Cache-Control: no-cache + ETag; honors If-None-Match (304)
 *   GET  /api/cache/etag/stats  -> ETag revalidation counters (200/304/If-None-Match seen)
 *   POST /api/upload/multipart  -> multipart/form-data; echoes part summary
 *   POST /api/upload/binary     -> application/octet-stream; echoes size + sha256
 *   GET  /api/delay?ms=...      -> delayed response (timeout tests)
 *
 * Run:  node server.mjs   (or `npm start`)
 */
import http from 'node:http';
import http2 from 'node:http2';
import fs from 'node:fs';
import crypto from 'node:crypto';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const HTTP1_PORT = Number(process.env.MOCK_HTTP1_PORT ?? 8080);
const HTTPS_PORT = Number(process.env.MOCK_HTTPS_PORT ?? 8443);
const HOST = process.env.MOCK_HOST ?? '0.0.0.0';

const certPath = path.join(__dirname, 'certs', 'cert.pem');
const keyPath = path.join(__dirname, 'certs', 'key.pem');

// ---- server-side state -----------------------------------------------------
const cacheHits = { network: 0 };
// ETag conditional-request counters
const etagState = {
  full200: 0,          // full 200 responses (no valid If-None-Match)
  notModified304: 0,   // 304 responses (If-None-Match matched)
  ifNoneMatchSeen: 0,  // requests that carried an If-None-Match header
};

// ---- helpers ---------------------------------------------------------------

/** Read the whole request body into a Buffer. */
function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on('data', (c) => chunks.push(c));
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

/**
 * Header case on the wire:
 *  - HTTP/1.1: Node exposes `rawHeaders` preserving the exact case the client sent.
 *  - HTTP/2:   RFC 7540 requires lowercase names; Node already lowercases them,
 *              and there is no rawHeaders. We list what we actually received.
 */
function wireHeaders(req) {
  if (Array.isArray(req.rawHeaders)) {
    const out = {};
    for (let i = 0; i < req.rawHeaders.length; i += 2) {
      const k = req.rawHeaders[i];
      out[k] = out[k] !== undefined ? [].concat(out[k], req.rawHeaders[i + 1]) : req.rawHeaders[i + 1];
    }
    return out;
  }
  return { ...req.headers };
}

function protocolName(req) {
  if (req.httpVersionMajor === 2) return 'HTTP/2';
  if (req.httpVersionMajor === 1) return `HTTP/${req.httpVersion}`;
  return req.httpVersion;
}

/** Minimal multipart/form-data parser (no external deps). */
function parseMultipart(body, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType ?? '');
  if (!m) return { error: 'no boundary in Content-Type', parts: [] };
  const boundary = (m[1] ?? m[2]).trim();
  const delimiter = Buffer.from(`--${boundary}`);
  const parts = [];
  let idx = 0;
  while (true) {
    const start = body.indexOf(delimiter, idx);
    if (start === -1) break;
    let end = body.indexOf(Buffer.from(`\r\n--${boundary}`), start + delimiter.length);
    if (end === -1) end = body.length;
    const raw = body.subarray(start + delimiter.length + 2, end); // skip CRLF after delimiter
    if (raw.length === 0) break; // closing delimiter
    const headerEnd = raw.indexOf('\r\n\r\n');
    const headerText = raw.subarray(0, headerEnd).toString('utf8');
    const data = raw.subarray(headerEnd + 4);
    // strip trailing CRLF that belongs to the delimiter
    const endsWithCrlf = data.length >= 2 && data[data.length - 2] === 13 && data[data.length - 1] === 10;
    const bodyData = endsWithCrlf ? data.subarray(0, data.length - 2) : data;
    const h = {};
    for (const line of headerText.split('\r\n')) {
      const ci = line.indexOf(':');
      if (ci > 0) h[line.slice(0, ci).trim().toLowerCase()] = line.slice(ci + 1).trim();
    }
    const disp = h['content-disposition'] ?? '';
    const nameM = /name="([^"]*)"/.exec(disp);
    const fileM = /filename="([^"]*)"/.exec(disp);
    // Skip the closing delimiter's empty remainder (no name => not a real part)
    if (!nameM && !fileM && bodyData.length === 0) {
      idx = end;
      continue;
    }
    parts.push({
      name: nameM ? nameM[1] : undefined,
      filename: fileM ? fileM[1] : undefined,
      contentType: h['content-type'],
      size: bodyData.length,
      text: bodyData.length < 4096 ? bodyData.toString('utf8') : undefined,
      sha256: crypto.createHash('sha256').update(bodyData).digest('hex'),
    });
    idx = end;
  }
  return { boundary, parts };
}

function json(res, code, obj) {
  const body = JSON.stringify(obj, null, 2);
  res.writeHead(code, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(body),
  });
  res.end(body);
}

// ---- request router --------------------------------------------------------

async function route(req, res) {
  const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`);
  const method = req.method.toUpperCase();
  const proto = protocolName(req);
  const pathname = url.pathname;

  console.log(`[req] ${proto} ${method} ${pathname}${url.search} from ${req.socket?.remoteAddress ?? '?'}`);

  // CORS (not needed by native clients, harmless for browser-based debugging)
  res.setHeader('access-control-allow-origin', '*');

  // --- /api/protocol : which HTTP version did this request arrive on?
  if (pathname === '/api/protocol') {
    return json(res, 200, {
      protocol: proto,
      httpVersion: req.httpVersion,
      alpn: req.alpnProtocol ?? undefined,
      note: proto === 'HTTP/2'
        ? 'Request arrived over HTTP/2 (h2). Header names are required to be lowercase.'
        : 'Request arrived over HTTP/1.x. Header names are case-insensitive on the wire.',
    });
  }

  // --- /api/headers : exact header case as received
  if (pathname === '/api/headers') {
    return json(res, 200, {
      protocol: proto,
      wireHeaders: wireHeaders(req),
      lowercased: { ...req.headers },
      rawHeadersAvailable: Array.isArray(req.rawHeaders),
      note: proto === 'HTTP/2'
        ? 'HTTP/2: server received lowercased header names (RFC 7540 requires it).'
        : 'HTTP/1.1: server received header names with the exact case the client sent (rawHeaders).',
    });
  }

  // --- /api/echo : echo everything back
  if (pathname === '/api/echo') {
    const body = method === 'GET' || method === 'HEAD' ? Buffer.alloc(0) : await readBody(req);
    let parsedBody;
    let parseError;
    try {
      parsedBody = JSON.parse(body.toString('utf8'));
    } catch {
      parsedBody = body.toString('utf8');
      if (!parsedBody) parsedBody = undefined;
    }
    const result = {
      protocol: proto,
      method,
      url: req.url,
      path: pathname,
      query: Object.fromEntries(url.searchParams),
      headers: { ...req.headers },
      wireHeaders: wireHeaders(req),
      body: parsedBody,
      bodyBytes: body.length,
      timestamp: new Date().toISOString(),
    };
    return json(res, 200, result);
  }

  // --- /api/methods : which method did the client use? (REST coverage)
  if (pathname === '/api/methods') {
    return json(res, 200, { protocol: proto, method, supported: true });
  }

  // --- /api/cookie/set : issue cookies
  if (pathname === '/api/cookie/set') {
    const ts = Date.now();
    res.setHeader('set-cookie', [
      `mock_session=abc123-${ts}; Path=/; HttpOnly`,
      `mock_pref=dark_${ts % 1000}; Path=/; Max-Age=3600`,
    ]);
    return json(res, 200, { protocol: proto, setCookies: [`mock_session=abc123-${ts}`, `mock_pref=dark_${ts % 1000}`] });
  }

  // --- /api/cookie/read : show what cookies came back
  if (pathname === '/api/cookie/read') {
    return json(res, 200, {
      protocol: proto,
      cookieHeader: req.headers.cookie ?? null,
      allHeaders: { ...req.headers },
    });
  }

  // --- /api/cache : cacheable response (max-age=60)
  if (pathname === '/api/cache') {
    cacheHits.network += 1;
    const body = JSON.stringify({ protocol: proto, hit: 'network', count: cacheHits.network, ts: Date.now() });
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'public, max-age=60',
      etag: '"v1"',
      'content-length': Buffer.byteLength(body),
    });
    return res.end(body);
  }

  // --- /api/cache/stats : how many times did the server actually get hit?
  if (pathname === '/api/cache/stats') {
    return json(res, 200, { networkHits: cacheHits.network, note: 'If the 2nd /api/cache request is served from client cache, this counter stays at 1.' });
  }

  // --- /api/cache/etag : ETag conditional-request probe.
  // Cache-Control: no-cache forces revalidation every time; the client should
  // send If-None-Match on the 2nd request and accept a 304 without a body.
  if (pathname === '/api/cache/etag') {
    const ifNoneMatch = req.headers['if-none-match'];
    const body = JSON.stringify({
      protocol: proto,
      etag: '"etag-v1"',
      ts: Date.now(),
      note: 'Cache-Control: no-cache forces revalidation; 2nd request should carry If-None-Match and get 304.',
    });
    if (ifNoneMatch !== undefined && ifNoneMatch !== null) {
      etagState.ifNoneMatchSeen += 1;
      if (ifNoneMatch.includes('etag-v1')) {
        etagState.notModified304 += 1;
        // 304: no body, keep the ETag so the client can revalidate next time
        res.writeHead(304, {
          'cache-control': 'no-cache',
          etag: '"etag-v1"',
        });
        return res.end();
      }
    }
    etagState.full200 += 1;
    res.writeHead(200, {
      'content-type': 'application/json; charset=utf-8',
      'cache-control': 'no-cache',
      etag: '"etag-v1"',
      'content-length': Buffer.byteLength(body),
    });
    return res.end(body);
  }

  // --- /api/cache/etag/stats : ETag revalidation counters
  if (pathname === '/api/cache/etag/stats') {
    return json(res, 200, {
      ...etagState,
      note: 'full200: full responses | notModified304: 304 sent for a matching If-None-Match | ifNoneMatchSeen: requests that carried If-None-Match',
    });
  }

  // --- /api/upload/multipart
  if (pathname === '/api/upload/multipart' && method === 'POST') {
    const body = await readBody(req);
    const parsed = parseMultipart(body, req.headers['content-type']);
    return json(res, 200, {
      protocol: proto,
      contentType: req.headers['content-type'],
      totalBytes: body.length,
      partCount: parsed.parts.length,
      boundary: parsed.boundary,
      parts: parsed.parts,
    });
  }

  // --- /api/upload/binary
  if (pathname === '/api/upload/binary' && method === 'POST') {
    const body = await readBody(req);
    const sha = crypto.createHash('sha256').update(body).digest('hex');
    return json(res, 200, {
      protocol: proto,
      contentType: req.headers['content-type'],
      bytes: body.length,
      sha256: sha,
    });
  }

  // --- /api/delay : delayed response
  if (pathname === '/api/delay') {
    const ms = Math.min(Number(url.searchParams.get('ms') ?? 1000) || 1000, 30000);
    await new Promise((r) => setTimeout(r, ms));
    return json(res, 200, { protocol: proto, delayedMs: ms, ts: Date.now() });
  }

  return json(res, 404, { error: 'not found', protocol: proto, path: pathname });
}

// ---- servers ---------------------------------------------------------------

// HTTP/1.1 cleartext
const h1 = http.createServer((req, res) => {
  route(req, res).catch((err) => {
    console.error('[h1] error', err);
    json(res, 500, { error: String(err?.message ?? err) });
  });
});

h1.listen(HTTP1_PORT, HOST, () => {
  console.log(`[HTTP/1.1] listening on http://${HOST}:${HTTP1_PORT}`);
});

// TLS + ALPN (HTTP/2 with HTTP/1.1 fallback)
if (!fs.existsSync(certPath) || !fs.existsSync(keyPath)) {
  console.error('Missing TLS certs. Run: node gen-certs.mjs');
  process.exit(1);
}

const tls = http2.createSecureServer(
  {
    key: fs.readFileSync(keyPath),
    cert: fs.readFileSync(certPath),
    allowHTTP1: true,
    // ALPN: advertise h2 and http/1.1; the client picks.
    ALPNProtocols: ['h2', 'http/1.1'],
  },
  (req, res) => {
    route(req, res).catch((err) => {
      console.error('[tls] error', err);
      json(res, 500, { error: String(err?.message ?? err) });
    });
  },
);

tls.listen(HTTPS_PORT, HOST, () => {
  console.log(`[TLS/ALPN] listening on https://${HOST}:${HTTPS_PORT} (HTTP/2 + HTTP/1.1)`);
});

process.on('SIGINT', () => process.exit(0));
