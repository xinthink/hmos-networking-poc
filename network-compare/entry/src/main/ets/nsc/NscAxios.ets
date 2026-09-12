/**
 * NSC verification — @ohos/axios column (second control).
 *
 * axios wraps `@ohos.net.http`, so it inherits Network Kit's NSC behaviour
 * (honours `trust-anchors`, subject to `component-config."Network Kit"`). It is
 * kept in the matrix because a "RCP vs Network Kit" conclusion is more credible
 * when the third-party wrapper on top of Network Kit agrees with the baseline.
 *
 * NOTE: this module deliberately does not import `AxiosScenarios` — the CA file
 * helper is duplicated here (same `${filesDir}/mock-ca.pem` path, identical
 * content) so the NSC suite stays self-contained and easy to move or delete.
 */
import axios, { AxiosError, AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import { http } from '@kit.NetworkKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

/** ArkTS forbids `any`/`unknown`, so axios needs all three type args spelled out. */
type NscAxiosResp = AxiosResponse<Record<string, string>, null>;
type NscAxiosErr = AxiosError<Record<string, string>, null>;

export class NscAxios {
  private static caFilePath: string = '';

  private static baseConfig(): AxiosRequestConfig {
    return {
      method: 'GET',
      readTimeout: 15000,
      connectTimeout: 15000,
      headers: { 'Accept': 'application/json' },
    };
  }

  /** Write the embedded mock CA PEM to filesDir once; axios only supports caPath. */
  private static async ensureCaFile(filesDir: string): Promise<string> {
    if (NscAxios.caFilePath.length > 0) {
      return NscAxios.caFilePath;
    }
    const p = `${filesDir}/mock-ca.pem`;
    const file = fs.openSync(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, AppConfig.MOCK_CA_PEM);
    } finally {
      fs.closeSync(file);
    }
    NscAxios.caFilePath = p;
    return p;
  }

  private static err(what: string, e: NscAxiosErr): ScenarioResult {
    const code = e.code ?? '';
    const msg = e.message ?? '';
    return new ScenarioResult(false, `${what} 失败: ${code} ${msg}`,
      `${what} 失败\ncode=${code}\nstatus=${e.response?.status ?? 0}\n${msg}`);
  }

  /** Trust probe #1 (control): no code-level CA — NSC trust-anchors must apply. */
  static async nscTrustAnchors(): Promise<ScenarioResult> {
    try {
      const config: AxiosRequestConfig = NscAxios.baseConfig();
      config.usingProtocol = http.HttpProtocol.HTTP2;
      const resp = await axios.get<Record<string, string>, NscAxiosResp, null>(
        `${AppConfig.httpsBase()}/api/protocol`, config);
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${resp.data['protocol']}\n` +
        `note        : no code-level caPath; trust comes from network_config.json base-config.trust-anchors`;
      return new ScenarioResult(resp.status === 200,
        resp.status === 200 ? 'system trust-anchors honored (HTTPS OK)' : 'system trust-anchors NOT honored',
        detail, resp.status);
    } catch (e) {
      return NscAxios.err('Axios nsc-trust-anchors', e as NscAxiosErr);
    }
  }

  /** Trust probe #3 (control): code-level `caPath` works independently of NSC. */
  static async nscTrustCa(filesDir: string): Promise<ScenarioResult> {
    try {
      const ca = await NscAxios.ensureCaFile(filesDir);
      const config: AxiosRequestConfig = NscAxios.baseConfig();
      config.usingProtocol = http.HttpProtocol.HTTP2;
      config.caPath = ca;
      const resp = await axios.get<Record<string, string>, NscAxiosResp, null>(
        `${AppConfig.httpsBase()}/api/protocol`, config);
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${resp.data['protocol']}\n` +
        `note        : caPath=${ca}（代码级信任，随 net.http 生效）`;
      return new ScenarioResult(resp.status === 200,
        resp.status === 200 ? '代码级 caPath 生效（HTTPS OK）' : '代码级 caPath 未生效', detail, resp.status);
    } catch (e) {
      return NscAxios.err('Axios nsc-trust-ca', e as NscAxiosErr);
    }
  }

  /** Cleartext probe (control): governed by `component-config."Network Kit"`. */
  static async nscCleartext(): Promise<ScenarioResult> {
    try {
      const resp = await axios.get<Record<string, string>, NscAxiosResp, null>(
        `${AppConfig.http1Base()}/api/protocol`, NscAxios.baseConfig());
      const detail =
        `HTTP status : ${resp.status}\n` +
        `server saw  : ${resp.data['protocol']}\n` +
        `note        : axios 底层走 net.http，明文受 component-config.'Network Kit' 约束。`;
      return new ScenarioResult(resp.status === 200,
        resp.status === 200 ? 'plaintext allowed' : 'plaintext blocked by system', detail, resp.status);
    } catch (e) {
      return NscAxios.err('Axios nsc-cleartext', e as NscAxiosErr);
    }
  }

  /**
   * N/A: axios (via net.http, API 24) has no "skip certificate validation"
   * option — RCP's `remoteValidation: 'skip'` has no counterpart here.
   */
  static async nscTrustSkip(): Promise<ScenarioResult> {
    return new ScenarioResult(true, 'N/A — 无对应能力',
      "axios 底层是 net.http（API 24），无跳过证书校验的选项；对应能力仅存在于 RCP 的 remoteValidation='skip'。");
  }

  /**
   * N/A: axios (via net.http, API 24) has no custom certificate validation
   * callback — RCP's `ValidationCallback` has no counterpart here.
   */
  static async nscTrustCallback(): Promise<ScenarioResult> {
    return new ScenarioResult(true, 'N/A — 无对应能力',
      'axios 底层是 net.http（API 24），无自定义证书校验回调；对应能力仅存在于 RCP 的 remoteValidation=ValidationCallback。');
  }
}
