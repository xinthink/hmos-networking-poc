/**
 * NSC verification — Remote Communication Kit column.
 *
 * Answers two questions about how RCP's own security configuration relates to
 * the system Network Security Configuration (`network_config.json`):
 *
 *   1. trust   — RCP reads ONLY its own `SecurityConfiguration.remoteValidation`.
 *                The default is `'system'` (device CA store) and the app-level NSC
 *                `trust-anchors` are never consulted, so NSC has zero effect.
 *   2. cleartext — `SecurityConfiguration` has no plaintext field at all, so the
 *                NSC `component-config` flag is the only lever (and it outranks
 *                the global `cleartextTrafficPermitted` switch).
 *
 * All six scenarios below are runtime-toggleable (no rebuild needed); the
 * cleartext *variant* matrix is a build-time experiment, see
 * `network-compare/NSC-VERIFICATION.md`.
 */
import { rcp } from '@kit.RemoteCommunicationKit';
import { networkSecurity } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';

/** Endpoint used by every TLS probe in this suite. */
function httpsProtocolUrl(): string {
  return `${AppConfig.httpsBase()}/api/protocol`;
}

export class NscRcp {
  // ---- sessions (one per remoteValidation variant) ---------------------------

  /** No security configuration at all: remoteValidation keeps its default. */
  private static newDefaultSession(): rcp.Session {
    return rcp.createSession();
  }

  /** Code-level CA: `remoteValidation = { content: <PEM> }`. */
  private static newCaSession(): rcp.Session {
    const security: rcp.SecurityConfiguration = {
      remoteValidation: { content: AppConfig.MOCK_CA_PEM },
    };
    const config: rcp.Configuration = { security: security };
    return rcp.createSession({ requestConfiguration: config });
  }

  /**
   * Explicit `remoteValidation: 'system'`. This is also the documented default
   * ("Default is 'system'" in @hms.collaboration.rcp.d.ts), so making it
   * explicit removes any doubt that we compare the real default behaviour
   * rather than a missing-configuration quirk.
   */
  private static newSystemExplicitSession(): rcp.Session {
    const security: rcp.SecurityConfiguration = { remoteValidation: 'system' };
    const config: rcp.Configuration = { security: security };
    return rcp.createSession({ requestConfiguration: config });
  }

  /** `remoteValidation: 'skip'` — bypasses every certificate check. */
  private static newSkipSession(): rcp.Session {
    const security: rcp.SecurityConfiguration = { remoteValidation: 'skip' };
    const config: rcp.Configuration = { security: security };
    return rcp.createSession({ requestConfiguration: config });
  }

  /**
   * Custom `ValidationCallback` that mimics "system CA store only": it checks
   * the presented chain with `networkSecurity.certVerificationSync` (which does
   * NOT look at app-level NSC trust-anchors) and rejects otherwise. This is the
   * only way to re-implement NSC-like semantics inside RCP.
   */
  private static newCallbackSession(): rcp.Session {
    const cb: rcp.ValidationCallback = (context: rcp.ValidationContext): boolean => {
      if (context.pemCerts.length === 0) {
        return false;
      }
      const last: number = context.pemCerts.length - 1;
      const blob: networkSecurity.CertBlob = {
        type: networkSecurity.CertType.CERT_TYPE_PEM,
        data: context.pemCerts[last],
      };
      try {
        // Second arg omitted -> verify against the system CA store only.
        // NOTE: for a self-signed / untrusted cert this THROWS (e.g. 2305018
        // "Self-signed certificate") instead of returning non-zero, so the
        // exception must be caught and mapped to "reject".
        return networkSecurity.certVerificationSync(blob) === 0;
      } catch (e) {
        return false;
      }
    };
    const security: rcp.SecurityConfiguration = { remoteValidation: cb };
    const config: rcp.Configuration = { security: security };
    return rcp.createSession({ requestConfiguration: config });
  }

  // ---- shared body -----------------------------------------------------------

  /** GET /api/protocol over TLS and render the outcome. */
  private static async probe(session: rcp.Session, okSummary: string, failSummary: string,
                             note: string): Promise<ScenarioResult> {
    try {
      const resp = await session.get(httpsProtocolUrl());
      const body = JSON.parse(resp.toString() ?? '{}') as Record<string, string>;
      const detail =
        `HTTP status : ${resp.statusCode}\n` +
        `client HTTP : ${resp.httpVersion}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : ${note}`;
      const ok = resp.statusCode === 200;
      return new ScenarioResult(ok, ok ? okSummary : failSummary, detail, resp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return new ScenarioResult(false, failSummary,
        `失败\ncode=${err.code}\n${err.message}\nnote        : ${note}`, err.code);
    } finally {
      session.close();
    }
  }

  // ---- scenarios -------------------------------------------------------------

  /**
   * Trust probe #1: no code-level CA at all. network_config.json declares the
   * mock CA as a trust-anchor; if RCP consulted the app-level NSC this would
   * succeed. Expected: FAIL.
   */
  static async nscTrustAnchors(): Promise<ScenarioResult> {
    return NscRcp.probe(NscRcp.newDefaultSession(),
      'system trust-anchors honored (HTTPS OK)',
      'NSC trust-anchors 被忽略：RCP 缺省配置不读应用级信任锚点',
      'no code-level remoteValidation; trust expected from network_config.json base-config.trust-anchors');
  }

  /**
   * Trust probe #2: `remoteValidation: 'system'` explicitly. Same verdict as the
   * default proves `'system'` == device CA store, unrelated to app-level NSC.
   * Expected: FAIL (code 1007900060).
   */
  static async nscTrustSystem(): Promise<ScenarioResult> {
    return NscRcp.probe(NscRcp.newSystemExplicitSession(),
      "'system' accepted (unexpected)",
      "'system' rejected: RCP 只认自身配置，NSC trust-anchors 被忽略",
      "remoteValidation='system' (explicit, also the documented default); NSC trust-anchors NOT consulted");
  }

  /**
   * Trust probe #3: code-level CA overrides the `'system'` default — and thereby
   * also overrides any NSC expectation. Expected: 200.
   */
  static async nscTrustCa(): Promise<ScenarioResult> {
    return NscRcp.probe(NscRcp.newCaSession(),
      '代码级 CA 生效（覆盖默认 system）',
      '代码级 CA 未生效',
      'remoteValidation={content:MOCK_CA_PEM} 覆盖默认 system');
  }

  /**
   * RCP-only capability: `'skip'` bypasses every trust check, so the self-signed
   * mock CA passes even though it is in no trust store. Expected: 200.
   */
  static async nscTrustSkip(): Promise<ScenarioResult> {
    return NscRcp.probe(NscRcp.newSkipSession(),
      "'skip' 绕过全部校验（HTTPS OK）",
      "'skip' 仍被拦截（意外）",
      "remoteValidation='skip' —— 不查系统 CA、不查 NSC，全部放行（生产慎用）");
  }

  /**
   * RCP-only capability: a custom `ValidationCallback` completely replaces the
   * trust logic. The callback here accepts only what the system CA store knows,
   * so the self-signed mock certificate is rejected — the same verdict
   * `'system'` gives, but now enforced by app code. Returning `true`
   * unconditionally would instead mean the `'skip'` semantics.
   * Expected: FAIL (code 1007900060).
   */
  static async nscTrustCallback(): Promise<ScenarioResult> {
    return NscRcp.probe(NscRcp.newCallbackSession(),
      'callback 放行（意外）',
      "callback 按系统 CA 库拒绝：自签证书不在系统 CA 库（与 'system' 判定一致，但由应用代码执行）",
      'ValidationCallback 用 networkSecurity.certVerificationSync 只认系统 CA 库');
  }

  /**
   * Cleartext probe. The effective verdict is decided by NSC
   * `component-config."Remote Communication Kit"` (not by RCP itself, which has
   * no plaintext option).
   */
  static async nscCleartext(): Promise<ScenarioResult> {
    const session = rcp.createSession();
    try {
      const resp = await session.get(`${AppConfig.http1Base()}/api/protocol`);
      const body = JSON.parse(resp.toString() ?? '{}') as Record<string, string>;
      const detail =
        `HTTP status : ${resp.statusCode}\n` +
        `server saw  : ${body['protocol']}\n` +
        `note        : 明文由 NSC component-config.'Remote Communication Kit' 决定；\n` +
        `              全局 cleartextTrafficPermitted 对 RCP 无效（组件开关优先）。`;
      return new ScenarioResult(resp.statusCode === 200,
        resp.statusCode === 200 ? 'plaintext allowed (组件不受控或未禁明文)' : 'plaintext blocked by system',
        detail, resp.statusCode);
    } catch (e) {
      const err = e as BusinessError;
      return new ScenarioResult(false,
        `RCP 明文被系统拦截（code=${err.code}）`,
        `RCP nsc-cleartext 失败\ncode=${err.code}\n${err.message}\n` +
          `note        : 1007900201 = Plaintext transmission is forbidden（组件开关已置 true 并被全局禁令约束）`,
        err.code);
    } finally {
      session.close();
    }
  }
}
