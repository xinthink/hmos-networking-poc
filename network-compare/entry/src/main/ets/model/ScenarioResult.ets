/**
 * Shared model for scenario execution results.
 * Each scenario runner method returns one of these, and the UI
 * renders `summary` + `detail` side by side for both frameworks.
 */
export class ScenarioResult {
  /** Whether the scenario ran to completion (HTTP 2xx) without framework error. */
  ok: boolean = false;
  /** One-line headline, e.g. "HTTP/2 negotiated, server saw h2". */
  summary: string = '';
  /** Multi-line detail: status, headers observed, protocol, body, etc. */
  detail: string = '';
  /** Optional raw HTTP status code. */
  statusCode: number = 0;

  constructor(ok: boolean, summary: string, detail: string, statusCode: number = 0) {
    this.ok = ok;
    this.summary = summary;
    this.detail = detail;
    this.statusCode = statusCode;
  }

  /** Render a compact error result. */
  static error(what: string, err: Error): ScenarioResult {
    let msg = String(err?.message ?? err);
    return new ScenarioResult(false, `${what} 失败: ${msg}`, `${what} 失败\n${msg}`);
  }
}
