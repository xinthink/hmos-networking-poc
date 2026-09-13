/**
 * NSC verification suite — single entry point.
 *
 * The whole "RCP security configuration × system NSC" verification lives in
 * this directory (`ets/nsc/`):
 *
 *   NscSuite.ets   ← you are here: card registry + headless self-test runner
 *   NscRcp.ets     RCP column (6 scenarios, all runtime-toggleable)
 *   NscNetKit.ets  Network Kit column (control + N/A placeholders)
 *   NscAxios.ets   axios column (control + N/A placeholders)
 *   NscEnv.ets     OS/API-level stamp so results survive version upgrades
 *
 * `Index.ets` only calls `NscSuite.cards()` / `NscSuite.runSelfTest()`; adding or
 * editing an NSC scenario means touching this directory alone.
 *
 * Results matrix, variant experiments and the manual procedure for re-running
 * this suite on a newer system version: `network-compare/NSC-VERIFICATION.md`.
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ScenarioDef, ScenarioRunner, ScenarioSink } from '../model/ScenarioDef';
import { ScenarioResult } from '../model/ScenarioResult';
import { NscRcp } from './NscRcp';
import { NscNetKit } from './NscNetKit';
import { NscAxios } from './NscAxios';
import { envTag, distributionTag } from './NscEnv';

const TAG = 'NetCompare';

export class NscSuite {
  /**
   * Scenario keys owned by this suite, in card order. `runSelfTest()` replays
   * every card in this list, so keep it in sync when adding a scenario.
   */
  static readonly KEYS: string[] = [
    'nscTrust',           // control: no code-level CA, trust from NSC only
    'nscCleartext',       // plaintext controlled by NSC component-config
    'nscTrustSystem',     // RCP explicit remoteValidation='system'
    'nscTrustCa',         // code-level CA overrides the 'system' default
    'nscTrustSkip',       // RCP-only: bypass every check
    'nscTrustCallback',   // RCP-only: custom ValidationCallback
    'pinSpki',            // pin == SPKI digest, trust OK
    'pinWrong',           // wrong pin, trust OK -> is pinning enforced?
    'pinCertHash',        // whole-cert digest probe (digest semantics)
    'pinBackup',          // [wrong, correct] -> whitelist semantics
    'pinSkipTrust',       // RCP-only: 'skip' + wrong pin
    'pinUntrustedTrust',  // RCP-only: 'system' + correct pin
  ];

  /** Cards contributed to the comparison UI (NSC group, appended last). */
  static cards(filesDir: string): ScenarioDef[] {
    return [
      {
        key: 'nscTrust',
        title: '网络安全配置: trust-anchors (应用级信任 CA)',
        desc: 'network_config.json base-config.trust-anchors 指向 resfile/mock-ca。本场景不带任何代码级 CA（Network Kit 无 caData，RCP 无 remoteValidation，axios 无 caPath），成功则证明系统级信任锚点对该框架生效。',
        netKit: NscNetKit.nscTrustAnchors,
        rcp: NscRcp.nscTrustAnchors,
        axios: NscAxios.nscTrustAnchors,
      },
      {
        key: 'nscCleartext',
        title: '网络安全配置: 明文权限 (component-config)',
        desc: 'network_config.json 的 cleartextTrafficPermitted 与 component-config 共同决定明文是否放行。语义是"该组件是否受系统明文禁令约束"：Network Kit 默认受控，RCP 默认不受控（API 23 起可配）。',
        netKit: NscNetKit.nscCleartext,
        rcp: NscRcp.nscCleartext,
        axios: NscAxios.nscCleartext,
      },
      {
        key: 'nscTrustSystem',
        title: 'NSC × RCP 信任优先级: remoteValidation=\'system\'',
        desc: 'RCP 显式指定 \'system\'（也是缺省值，= 设备系统 CA 库）；Network Kit/axios 不带代码级 CA（走 NSC trust-anchors）。NSC 已配 trust-anchor，对比三方是否采信——以此判定"两种 config 谁优先"。',
        netKit: NscNetKit.nscTrustAnchors,
        rcp: NscRcp.nscTrustSystem,
        axios: NscAxios.nscTrustAnchors,
      },
      {
        key: 'nscTrustCa',
        title: 'NSC × RCP 信任优先级: 代码级 CA 覆盖默认',
        desc: 'RCP remoteValidation={content} / Network Kit caData / axios caPath 显式信任 mock CA，验证代码级信任是否覆盖默认 system（也即是否独立于 NSC）。',
        netKit: NscNetKit.nscTrustCa,
        rcp: NscRcp.nscTrustCa,
        axios: () => NscAxios.nscTrustCa(filesDir),
      },
      {
        key: 'nscTrustSkip',
        title: 'NSC × RCP: remoteValidation=\'skip\' 绕过全部校验',
        desc: 'RCP 独有能力：跳过全部证书校验（自签证书直接通过）。Network Kit/axios 无对应选项（N/A）。',
        netKit: NscNetKit.nscTrustSkip,
        rcp: NscRcp.nscTrustSkip,
        axios: NscAxios.nscTrustSkip,
      },
      {
        key: 'nscTrustCallback',
        title: 'NSC × RCP: ValidationCallback 自定义校验',
        desc: 'RCP 独有能力：自定义证书校验回调完全替换默认信任逻辑。本例回调用 networkSecurity.certVerificationSync 只认系统 CA 库（自签证书将失败）——证明 callback 是 RCP 复刻 NSC 语义的唯一手段。Network Kit/axios 无对应选项（N/A）。',
        netKit: NscNetKit.nscTrustCallback,
        rcp: NscRcp.nscTrustCallback,
        axios: NscAxios.nscTrustCallback,
      },
      {
        key: 'pinSpki',
        title: '证书锁定: 正确 SPKI pin (信任正常)',
        desc: 'pin = 服务器公钥(SPKI)的 SHA-256 base64，同时信任正常（RCP remoteValidation={content} / caData / caPath）。用于确认 publicKeyHash 的摘要语义确实是公钥摘要。',
        netKit: NscNetKit.pinSpki,
        rcp: NscRcp.pinSpki,
        axios: () => NscAxios.pinSpki(filesDir),
      },
      {
        key: 'pinWrong',
        title: '证书锁定: 错误 pin (信任正常)',
        desc: '信任正常但 pin 为错误摘要。若失败 → pinning 在信任校验之外被强制执行（AND 语义）；若成功 → pinning 未生效。',
        netKit: NscNetKit.pinWrong,
        rcp: NscRcp.pinWrong,
        axios: () => NscAxios.pinWrong(filesDir),
      },
      {
        key: 'pinCertHash',
        title: '证书锁定: 整证书摘要 (语义探针)',
        desc: 'pin 用整张 DER 证书的 SHA-256（而非公钥摘要）。用于判定实现是按公钥取摘要还是按整证书取摘要——文档口径是公钥。',
        netKit: NscNetKit.pinCertHash,
        rcp: NscRcp.pinCertHash,
        axios: () => NscAxios.pinCertHash(filesDir),
      },
      {
        key: 'pinBackup',
        title: '证书锁定: pin 数组 [错误, 正确]',
        desc: 'pin 传数组且只有一项匹配。成功即白名单语义（任一命中即通过），这也是文档建议"始终配置至少一个备用公钥"的前提。',
        netKit: NscNetKit.pinBackup,
        rcp: NscRcp.pinBackup,
        axios: () => NscAxios.pinBackup(filesDir),
      },
      {
        key: 'pinSkipTrust',
        title: 'NSC × RCP 组合: remoteValidation=\'skip\' + 错误 pin',
        desc: 'RCP 独有组合：跳过信任校验但 pin 错误。若失败 → pinning 独立于信任判定（不受 skip 影响）；若成功 → pinning 从属于 remoteValidation。',
        netKit: NscNetKit.pinSkipTrust,
        rcp: NscRcp.pinSkipTrust,
        axios: NscAxios.pinSkipTrust,
      },
      {
        key: 'pinUntrustedTrust',
        title: 'NSC × RCP 组合: 不受信链 + 正确 pin',
        desc: 'RCP 独有组合：remoteValidation=\'system\'（自签 CA 不受信）但 pin 正确。若失败 → 信任校验与 pinning 是 AND 关系（pin 不能替代信任锚点）；若成功 → pin 可救不受信链。',
        netKit: NscNetKit.pinUntrustedTrust,
        rcp: NscRcp.pinUntrustedTrust,
        axios: NscAxios.pinUntrustedTrust,
      },
    ];
  }

  /**
   * Replay the whole suite and write one hilog line per (scenario, framework),
   * bracketed by ENV/DONE lines carrying the OS + API level.
   *
   * Headless reading:
   *   devecocli log --device "Pura 90" --bundle-name com.example.networkcompare \
   *     --keyword NSCTEST --from 5m --tail 200
   *
   * @param filesDir app files dir (axios needs it to materialise the CA PEM)
   * @param sink optional callback that mirrors results into the UI state
   */
  static async runSelfTest(filesDir: string, sink?: ScenarioSink): Promise<number> {
    const cards = NscSuite.cards(filesDir);
    hilog.info(0x0000, TAG, 'NSCTEST ENV %{public}s | distribution=%{public}s',
      envTag(), distributionTag());
    let okCount = 0;
    let ran = 0;
    for (let i = 0; i < cards.length; i++) {
      const card = cards[i];
      if (!NscSuite.KEYS.includes(card.key)) {
        continue;
      }
      const r1 = await NscSuite.runOne(card, 'netkit', card.netKit, sink);
      const r2 = await NscSuite.runOne(card, 'rcp', card.rcp, sink);
      const r3 = await NscSuite.runOne(card, 'axios', card.axios, sink);
      const all = [r1, r2, r3];
      for (let j = 0; j < all.length; j++) {
        ran++;
        if (all[j]) {
          okCount++;
        }
      }
    }
    hilog.info(0x0000, TAG, 'NSCTEST DONE %{public}s | ran=%{public}d pass=%{public}d',
      envTag(), ran, okCount);
    return ran;
  }

  /** Run one (scenario, framework) pair, log it, and push it to the UI. */
  private static async runOne(card: ScenarioDef, runner: ScenarioRunner,
                              fn: () => Promise<ScenarioResult>,
                              sink?: ScenarioSink): Promise<boolean> {
    let line: string = '';
    let ok = false;
    try {
      const r = await fn();
      ok = r.ok;
      line = `${r.ok ? 'OK' : 'FAIL'} status=${r.statusCode} | ${r.summary}`;
      const text = `${r.ok ? '[OK]' : '[FAIL]'} ${r.summary}\n${r.detail}`;
      if (sink) {
        sink(card.key, runner, text);
      }
    } catch (e) {
      const err = e as Error;
      line = `EXC | ${err.message ?? e}`;
    }
    hilog.info(0x0000, TAG, 'NSCTEST %{public}s %{public}s %{public}s', card.key, runner, line);
    return ok;
  }
}
