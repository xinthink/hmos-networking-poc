/**
 * NSC verification — Network Kit column (the control).
 *
 * Network Kit is the baseline that DOES honour the system NSC: its HTTPS
 * requests succeed with no code-level `caData` because `network_config.json`
 * declares the mock CA under `trust-anchors`, and its plaintext traffic is
 * governed by `component-config."Network Kit"` (default true = controlled).
 */
import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

export class NscNetKit {
  /** Base request options; `caData` added only where the scenario needs it. */
  private static baseOptions(): http.HttpRequestOptions {
    return {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      usingProtocol: http.HttpProtocol.HTTP2,
      readTimeout: 15000,
      connectTimeout: 15000,
      header: { 'Accept': 'application/json' },
    };
  }

  /**
   * Trust probe #1 (control): NO code-level CA — trust must come from the NSC
   * `trust-anchors` in network_config.json. Expected: 200.
   */
  static async nscTrustAnchors(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const resp = await req.request(`${AppConfig.httpsBase()}/api/protocol`, NscNetKit.baseOptions());
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
   * Trust probe #3 (control): code-level `caData` works independently of NSC.
   * Expected: 200.
   */
  static async nscTrustCa(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const options = NscNetKit.baseOptions();
      options.caData = AppConfig.MOCK_CA_PEM;
      const resp = await req.request(`${AppConfig.httpsBase()}/api/protocol`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, string>;
      const detail =
        `HTTP status : ${resp.responseCode}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : caData=MOCK_CA_PEM（代码级信任）`;
      return new ScenarioResult(resp.responseCode === 200,
        resp.responseCode === 200 ? '代码级 caData 生效（HTTPS OK）' : '代码级 caData 未生效', detail,
        resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return ScenarioResult.error('NetworkKit nsc-trust-ca', err as Error);
    } finally {
      req.destroy();
    }
  }

  /**
   * Cleartext probe (control). Verdict is decided by
   * `component-config."Network Kit"` (default true) plus the global
   * `cleartextTrafficPermitted`. Blocked runs surface as 2300997.
   */
  static async nscCleartext(): Promise<ScenarioResult> {
    const req = http.createHttp();
    try {
      const options = NscNetKit.baseOptions();
      const resp = await req.request(`${AppConfig.http1Base()}/api/protocol`, options);
      const body = JSON.parse(String(resp.result)) as Record<string, string>;
      const detail =
        `HTTP status : ${resp.responseCode}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : 明文由 NSC component-config.'Network Kit' + cleartextTrafficPermitted 决定。`;
      return new ScenarioResult(resp.responseCode === 200,
        resp.responseCode === 200 ? 'plaintext allowed' : 'plaintext blocked by system', detail,
        resp.responseCode);
    } catch (e) {
      const err = e as BusinessError;
      return new ScenarioResult(false,
        'plaintext blocked by system (Cleartext traffic not permitted)',
        `NetworkKit nsc-cleartext 失败\ncode=${err.code}\n${err.message}\n` +
          `note        : 2300997 = Cleartext traffic not permitted`,
        err.code);
    } finally {
      req.destroy();
    }
  }

  /**
   * N/A: Network Kit (API 24) has no "skip certificate validation" option —
   * RCP's `remoteValidation: 'skip'` has no counterpart here.
   */
  static async nscTrustSkip(): Promise<ScenarioResult> {
    return new ScenarioResult(true, 'N/A — 无对应能力',
      'Network Kit (API 24) 无跳过证书校验的选项；信任来源只有 caData/caPath + network_config.json trust-anchors。');
  }

  /**
   * N/A: Network Kit (API 24) has no custom certificate validation callback —
   * RCP's `ValidationCallback` has no counterpart here.
   */
  static async nscTrustCallback(): Promise<ScenarioResult> {
    return new ScenarioResult(true, 'N/A — 无对应能力',
      'Network Kit (API 24) 无自定义证书校验回调；对应能力仅存在于 RCP 的 remoteValidation=ValidationCallback。');
  }
}
