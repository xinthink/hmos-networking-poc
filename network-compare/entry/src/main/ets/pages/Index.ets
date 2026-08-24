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
import { AxiosScenarios } from '../axios/AxiosScenarios';

const TAG = 'NetCompare';

interface ScenarioDef {
  key: string;
  title: string;
  desc: string;
  netKit: () => Promise<ScenarioResult>;
  rcp: () => Promise<ScenarioResult>;
  axios: () => Promise<ScenarioResult>;
}

@Entry
@Component
struct Index {
  @State host: string = AppConfig.host;
  @State netKitResults: Record<string, string> = {};
  @State rcpResults: Record<string, string> = {};
  @State axiosResults: Record<string, string> = {};
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
        desc: 'GET /api/protocol — 明文 8080 走 HTTP/1.1；TLS 8443 通过 ALPN 协商 h2。对比三方框架在客户端/服务端看到的协议版本（axios 不暴露客户端连接信息）。',
        netKit: NetKitScenarios.protocolHttp1,
        rcp: RcpScenarios.protocolHttp1,
        axios: AxiosScenarios.protocolHttp1,
      },
      {
        key: 'protocol2',
        title: 'HTTP/2 (TLS/ALPN)',
        desc: 'GET /api/protocol over https://…:8443。Network Kit 用 usingProtocol=HTTP2；RCP 无显式开关（API 26 前）；axios 同 Network Kit 可传 usingProtocol。',
        netKit: NetKitScenarios.protocolHttp2,
        rcp: RcpScenarios.protocolHttp2,
        axios: () => AxiosScenarios.protocolHttp2(this.filesDir),
      },
      {
        key: 'methods',
        title: 'REST 方法覆盖 (GET/POST/PUT/PATCH/DELETE/HEAD/OPTIONS)',
        desc: '依次请求 /api/methods，服务端回显收到的 method 与状态码。',
        netKit: NetKitScenarios.methods,
        rcp: RcpScenarios.methods,
        axios: AxiosScenarios.methods,
      },
      {
        key: 'headers',
        title: 'Header 正规化 (大小写)',
        desc: '发送 X-MiXeD-CaSe-Hdr / x-lowercase-hdr / X-ALLCAPS-HDR，服务端回显实际收到的 header 名。HTTP/1.1 保留大小写；HTTP/2 要求全小写。axios 的 AxiosHeaders 保留传入大小写，交给底层 net.http。',
        netKit: NetKitScenarios.headerCase,
        rcp: RcpScenarios.headerCase,
        axios: () => AxiosScenarios.headerCase(this.filesDir),
      },
      {
        key: 'cookies',
        title: 'Cookie',
        desc: '/api/cookie/set 下发 Set-Cookie，随后 /api/cookie/read 回显收到的 Cookie header。Network Kit 需手动解析 response.cookies；RCP 用 CookieRepository (API 23) 自动存取；axios 不透出 cookies 字段，需手动解析 set-cookie 响应头。',
        netKit: NetKitScenarios.cookies,
        rcp: RcpScenarios.cookies,
        axios: AxiosScenarios.cookies,
      },
      {
        key: 'cache',
        title: 'Cache',
        desc: '连续两次 GET /api/cache（Cache-Control: max-age=60），再查服务端命中计数。Network Kit usingCache 默认开启；RCP 需显式配置 ResponseCache (API 20)；axios 无缓存 API（config.cache 仅 HttpClient 适配器生效）。',
        netKit: NetKitScenarios.cache,
        rcp: () => RcpScenarios.cache(this.filesDir),
        axios: AxiosScenarios.cache,
      },
      {
        key: 'etag',
        title: 'Cache + ETag (条件请求 / 304)',
        desc: '连续两次 GET /api/cache/etag（Cache-Control: no-cache + ETag，强制重新验证）。符合规范的缓存会在第 2 次请求携带 If-None-Match，服务端回 304，客户端复用缓存。服务端统计 full200 / notModified304 / ifNoneMatchSeen。axios 无自动缓存，且默认 validateStatus 拒绝 304。',
        netKit: NetKitScenarios.etag,
        rcp: () => RcpScenarios.etag(this.filesDir),
        axios: AxiosScenarios.etag,
      },
      {
        key: 'multipart',
        title: 'Multipart/form-data 上传',
        desc: 'POST /api/upload/multipart：1 个文本字段 + 1 个二进制文件部分。Network Kit 用 multiFormDataList (API 11)；RCP 用 rcp.MultipartForm；axios 用自带 FormData（内部转 multiFormDataList）。',
        netKit: NetKitScenarios.multipartUpload,
        rcp: RcpScenarios.multipartUpload,
        axios: AxiosScenarios.multipartUpload,
      },
      {
        key: 'binary',
        title: '二进制上传 (application/octet-stream)',
        desc: 'POST 4KB ArrayBuffer。Network Kit 用 extraData:ArrayBuffer；RCP 用 ArrayBuffer 请求体；axios 用 data:ArrayBuffer。服务端回显字节数与 sha256。',
        netKit: NetKitScenarios.binaryUpload,
        rcp: RcpScenarios.binaryUpload,
        axios: AxiosScenarios.binaryUpload,
      },
      {
        key: 'nscTrust',
        title: '网络安全配置: trust-anchors (应用级信任 CA)',
        desc: 'network_config.json base-config.trust-anchors 指向 resfile/mock-ca。本场景不带任何代码级 CA（Network Kit 无 caData，RCP 无 remoteValidation，axios 无 caPath），成功则证明系统级信任锚点对该框架生效。',
        netKit: NetKitScenarios.nscTrustAnchors,
        rcp: RcpScenarios.nscTrustAnchors,
        axios: AxiosScenarios.nscTrustAnchors,
      },
      {
        key: 'nscCleartext',
        title: '网络安全配置: 明文权限 (component-config)',
        desc: 'network_config.json 配置 cleartextTrafficPermitted=true 且 component-config 按框架开启明文。axios 底层走 net.http，受 "Network Kit" 组件配置约束。此处探测当前明文权限是否生效。',
        netKit: NetKitScenarios.nscCleartext,
        rcp: RcpScenarios.nscCleartext,
        axios: AxiosScenarios.nscCleartext,
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

  private async runAxios(key: string, fn: () => Promise<ScenarioResult>): Promise<void> {
    this.busy = this.copyWith(this.busy, `axios_${key}`, true);
    try {
      const r = await fn();
      const text = `${r.ok ? '[OK]' : '[FAIL]'} ${r.summary}\n${r.detail}`;
      this.axiosResults = this.copyWith(this.axiosResults, key, text);
    } catch (e) {
      const err = e as Error;
      this.axiosResults = this.copyWith(this.axiosResults, key, `[EXC] ${err.message ?? e}`);
    } finally {
      this.busy = this.copyWith(this.busy, `axios_${key}`, false);
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
      Text('Network Kit vs RCP vs Axios 对比').fontSize(20).fontWeight(FontWeight.Bold)
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
                Button(`Axios${this.busy[`axios_${s.key}`] ? ' …' : ''}`)
                  .backgroundColor('#7C4DFF')
                  .enabled(!this.busy[`axios_${s.key}`])
                  .onClick(() => {
                    this.runAxios(s.key, s.axios);
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
              if (this.axiosResults[s.key] !== undefined) {
                Text(`Axios:\n${this.axiosResults[s.key]}`)
                  .fontSize(11)
                  .fontColor('#5A29E4')
                  .backgroundColor('#F1EDFF')
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
