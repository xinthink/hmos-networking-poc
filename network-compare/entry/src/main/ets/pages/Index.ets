/*
 * Network Kit vs Remote Communication Kit (RCP) — comparison UI.
 *
 * Runs the same scenario set through both frameworks and shows the results
 * side by side. The mock server must be running (see mock-server/README).
 */
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppConfig } from '../common/AppConfig';
import { ScenarioResult } from '../model/ScenarioResult';
import { NetKitScenarios } from '../netkit/NetKitScenarios';
import { RcpScenarios } from '../rcp/RcpScenarios';

const TAG = 'NetCompare';

interface ScenarioDef {
  key: string;
  title: string;
  desc: string;
  netKit: () => Promise<ScenarioResult>;
  rcp: () => Promise<ScenarioResult>;
}

@Entry
@Component
struct Index {
  @State host: string = AppConfig.host;
  @State netKitResults: Record<string, string> = {};
  @State rcpResults: Record<string, string> = {};
  @State busy: Record<string, boolean> = {};
  private filesDir: string = '';

  aboutToAppear(): void {
    const ctx = getContext(this) as common.UIAbilityContext;
    this.filesDir = ctx.filesDir;
    hilog.info(0x0000, TAG, 'filesDir=%{public}s', this.filesDir);
  }

  private applyHost(): void {
    AppConfig.host = this.host;
    hilog.info(0x0000, TAG, 'host set to %{public}s', this.host);
  }

  private scenarios(): ScenarioDef[] {
    return [
      {
        key: 'protocol',
        title: '协议协商 (HTTP/1.1 vs HTTP/2)',
        desc: 'GET /api/protocol — 明文 8080 走 HTTP/1.1；TLS 8443 通过 ALPN 协商 h2。对比双方框架在客户端/服务端看到的协议版本。',
        netKit: NetKitScenarios.protocolHttp1,
        rcp: RcpScenarios.protocolHttp1,
      },
      {
        key: 'protocol2',
        title: 'HTTP/2 (TLS/ALPN)',
        desc: 'GET /api/protocol over https://…:8443。Network Kit 用 usingProtocol=HTTP2；RCP 无显式开关（API 26 前），由系统协商。',
        netKit: NetKitScenarios.protocolHttp2,
        rcp: RcpScenarios.protocolHttp2,
      },
      {
        key: 'methods',
        title: 'REST 方法覆盖 (GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS)',
        desc: '依次请求 /api/methods，服务端回显收到的 method 与状态码。',
        netKit: NetKitScenarios.methods,
        rcp: RcpScenarios.methods,
      },
      {
        key: 'headers',
        title: 'Header 正规化 (大小写)',
        desc: '发送 X-MiXeD-CaSe-Hdr / x-lowercase-hdr / X-ALLCAPS-HDR，服务端回显实际收到的 header 名。HTTP/1.1 保留大小写；HTTP/2 要求全小写。',
        netKit: NetKitScenarios.headerCase,
        rcp: RcpScenarios.headerCase,
      },
      {
        key: 'cookies',
        title: 'Cookie',
        desc: '/api/cookie/set 下发 Set-Cookie，随后 /api/cookie/read 回显收到的 Cookie header。Network Kit 需手动携带；RCP 可用 CookieRepository (API 23) 自动存取。',
        netKit: NetKitScenarios.cookies,
        rcp: RcpScenarios.cookies,
      },
      {
        key: 'cache',
        title: 'Cache',
        desc: '连续两次 GET /api/cache（Cache-Control: max-age=60），再查服务端命中计数。Network Kit usingCache 默认开启；RCP 需显式配置 ResponseCache (API 20)。',
        netKit: NetKitScenarios.cache,
        rcp: () => RcpScenarios.cache(this.filesDir),
      },
      {
        key: 'etag',
        title: 'Cache + ETag (条件请求 / 304)',
        desc: '连续两次 GET /api/cache/etag（Cache-Control: no-cache + ETag，强制重新验证）。符合规范的缓存会在第 2 次请求携带 If-None-Match，服务端回 304，客户端复用缓存。服务端统计 full200 / notModified304 / ifNoneMatchSeen。',
        netKit: NetKitScenarios.etag,
        rcp: () => RcpScenarios.etag(this.filesDir),
      },
      {
        key: 'multipart',
        title: 'Multipart/form-data 上传',
        desc: 'POST /api/upload/multipart：1 个文本字段 + 1 个二进制文件部分。Network Kit 用 multiFormDataList (API 11)；RCP 用 rcp.MultipartForm。',
        netKit: NetKitScenarios.multipartUpload,
        rcp: RcpScenarios.multipartUpload,
      },
      {
        key: 'binary',
        title: '二进制上传 (application/octet-stream)',
        desc: 'POST 4KB ArrayBuffer。Network Kit 用 extraData:ArrayBuffer；RCP 用 ArrayBuffer 请求体。服务端回显字节数与 sha256。',
        netKit: NetKitScenarios.binaryUpload,
        rcp: RcpScenarios.binaryUpload,
      },
      {
        key: 'nscTrust',
        title: '网络安全配置: trust-anchors (应用级信任 CA)',
        desc: 'network_config.json base-config.trust-anchors 指向 resfile/mock-ca。本场景不带任何代码级 CA（Network Kit 无 caData，RCP 无 remoteValidation），成功则证明系统级信任锚点对该框架生效。',
        netKit: NetKitScenarios.nscTrustAnchors,
        rcp: RcpScenarios.nscTrustAnchors,
      },
      {
        key: 'nscCleartext',
        title: '网络安全配置: 明文权限 (component-config)',
        desc: 'network_config.json 配置 cleartextTrafficPermitted=true 且 component-config 按框架开启明文（Network Kit / Remote Communication Kit 均可分别控制，API 23+ 支持 RCP）。此处探测当前明文权限是否生效。',
        netKit: NetKitScenarios.nscCleartext,
        rcp: RcpScenarios.nscCleartext,
      },
    ];
  }

  private async runNetKit(key: string, fn: () => Promise<ScenarioResult>): Promise<void> {
    this.busy = this.copyWith(this.busy, key, true);
    try {
      const r = await fn();
      const text = `${r.ok ? '[OK]' : '[FAIL]'} ${r.summary}\n${r.detail}`;
      this.netKitResults = this.copyWith(this.netKitResults, key, text);
    } catch (e) {
      const err = e as Error;
      this.netKitResults = this.copyWith(this.netKitResults, key, `[EXC] ${err.message ?? e}`);
    } finally {
      this.busy = this.copyWith(this.busy, key, false);
    }
  }

  private async runRcp(key: string, fn: () => Promise<ScenarioResult>): Promise<void> {
    this.busy = this.copyWith(this.busy, `rcp_${key}`, true);
    try {
      const r = await fn();
      const text = `${r.ok ? '[OK]' : '[FAIL]'} ${r.summary}\n${r.detail}`;
      this.rcpResults = this.copyWith(this.rcpResults, key, text);
    } catch (e) {
      const err = e as Error;
      this.rcpResults = this.copyWith(this.rcpResults, key, `[EXC] ${err.message ?? e}`);
    } finally {
      this.busy = this.copyWith(this.busy, `rcp_${key}`, false);
    }
  }

  /** Immutable-style update: returns a new record so @State re-renders. */
  private copyWith<T>(src: Record<string, T>, key: string, value: T): Record<string, T> {
    const next: Record<string, T> = {};
    const keys = Object.keys(src);
    for (let i = 0; i < keys.length; i++) {
      next[keys[i]] = src[keys[i]];
    }
    next[key] = value;
    return next;
  }

  build() {
    Column({ space: 8 }) {
      // Header
      Text('Network Kit vs RCP 对比').fontSize(20).fontWeight(FontWeight.Bold)
      Text(`Mock Server: http://${AppConfig.host}:8080 (h1) / https://${AppConfig.host}:8443 (h2)`).fontSize(12)
        .fontColor('#888888')

      // Host input
      Row({ space: 8 }) {
        TextInput({ text: this.host, placeholder: 'server host (10.0.2.2)' })
          .layoutWeight(1)
          .onChange((v: string) => {
            this.host = v;
          })
        Button('应用').onClick(() => this.applyHost())
      }
      .width('100%')

      // Scenario cards
      List({ space: 12 }) {
        ForEach(this.scenarios(), (s: ScenarioDef) => {
          ListItem() {
            Column({ space: 6 }) {
              Text(s.title).fontSize(15).fontWeight(FontWeight.Medium)
              Text(s.desc).fontSize(11).fontColor('#777777')
              Row({ space: 8 }) {
                Button(`Network Kit${this.busy[s.key] ? ' …' : ''}`)
                  .backgroundColor('#0A59F7')
                  .enabled(!this.busy[s.key])
                  .onClick(() => {
                    this.runNetKit(s.key, s.netKit);
                  })
                Button(`RCP${this.busy[`rcp_${s.key}`] ? ' …' : ''}`)
                  .backgroundColor('#00B96B')
                  .enabled(!this.busy[`rcp_${s.key}`])
                  .onClick(() => {
                    this.runRcp(s.key, s.rcp);
                  })
              }
              if (this.netKitResults[s.key] !== undefined) {
                Text(`Network Kit:\n${this.netKitResults[s.key]}`)
                  .fontSize(11)
                  .fontColor('#0A59F7')
                  .backgroundColor('#EEF3FE')
                  .borderRadius(6)
                  .padding(8)
                  .width('100%')
              }
              if (this.rcpResults[s.key] !== undefined) {
                Text(`RCP:\n${this.rcpResults[s.key]}`)
                  .fontSize(11)
                  .fontColor('#00875A')
                  .backgroundColor('#E9F9F0')
                  .borderRadius(6)
                  .padding(8)
                  .width('100%')
              }
            }
            .alignItems(HorizontalAlign.Start)
            .padding(12)
            .borderRadius(10)
            .backgroundColor('#FFFFFF')
            .width('100%')
          }
        }, (s: ScenarioDef) => s.key)
      }
      .layoutWeight(1)
      .width('100%')
      .scrollBar(BarState.Auto)
    }
    .padding(12)
    .backgroundColor('#F1F3F5')
    .height('100%')
    .width('100%')
  }
}
