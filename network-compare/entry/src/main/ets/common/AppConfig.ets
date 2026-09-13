/**
 * Global configuration for the Network Kit vs RCP comparison app.
 *
 * The mock server runs on the dev machine:
 *   - HTTP/1.1 (cleartext)  -> http://<host>:8080
 *   - TLS + ALPN (h2 + h1)  -> https://<host>:8443
 *
 * `host` defaults to 10.0.2.2, which is how the HarmonyOS emulator reaches
 * the host machine's loopback. Change it to the LAN IP of the dev machine
 * when running on a real device.
 */
export class AppConfig {
  /** Server host as seen from the app (emulator -> host loopback). */
  static host: string = '10.0.2.2';

  static http1Port: number = 8080;
  static httpsPort: number = 8443;
  /** Third listener: TLS cert signed by the "user-installed CA" (gen-user-ca.mjs). */
  static userCaPort: number = 9443;

  /** Base URL for plain HTTP/1.1 (no TLS). */
  static http1Base(): string {
    return `http://${AppConfig.host}:${AppConfig.http1Port}`;
  }

  /** Base URL for TLS with ALPN (HTTP/2 with HTTP/1.1 fallback). */
  static httpsBase(): string {
    return `https://${AppConfig.host}:${AppConfig.httpsPort}`;
  }

  /**
   * Base URL of the listener whose certificate is signed by the "user CA".
   * Trusted ONLY via the device user CA store (used by the NSC user-CA experiment).
   */
  static userCaBase(): string {
    return `https://${AppConfig.host}:${AppConfig.userCaPort}`;
  }

  /**
   * Self-signed CA certificate of the mock server, used for HTTPS.
   * Network Kit: `caData` (request option).
   * RCP: `remoteValidation: { content }` (security configuration).
   */
  static readonly MOCK_CA_PEM: string =
    '-----BEGIN CERTIFICATE-----\n' +
    'MIIDPTCCAiWgAwIBAgIUCfyXngcT96pOnp8llxi7EjZCl2AwDQYJKoZIhvcNAQEL\n' +
    'BQAwGjEYMBYGA1UEAwwPbmV0a2l0LXJjcC1tb2NrMB4XDTI2MDgyMjE2MDA0MFoX\n' +
    'DTM2MDgxOTE2MDA0MFowGjEYMBYGA1UEAwwPbmV0a2l0LXJjcC1tb2NrMIIBIjAN\n' +
    'BgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAtozJbDHwYrbGWyK3wGP7XmU+sh/n\n' +
    'QZLo0fF9NwVm0iyisum+xCbNbiGZ3RBIVMtqVvAJjVdxC6DPG7okWoYEheeFZNZT\n' +
    'M10CW8ZY1Hecegf3oY1qR+ordcJQSLGFCoXSbCrNlozem1gWhYl0lipOFaOhlklD\n' +
    '1dUzuLbpESmOLX4ITzjURywY2TmkLrRzurauDlPHwqeoMZYcs5hFf5m2RZkRILxe\n' +
    'PCf31Y6oGogaFP+FQ0Ne5q2ryQLvcjOlmjWTx+F31exHksE1lQI3sFmgBl3haMZh\n' +
    'TzHB2PTjIAfvNQBSyiCGTsjh+qhM328JaGLQEzWqiK5c9LGFN2Eu6mvY8QIDAQAB\n' +
    'o3sweTAdBgNVHQ4EFgQUiFyuhtA8zPHCt6muCZDO+jHY2MAwHwYDVR0jBBgwFoAU\n' +
    'iFyuhtA8zPHCt6muCZDO+jHY2MAwDwYDVR0TAQH/BAUwAwEB/zAmBgNVHREEHzAd\n' +
    'gglsb2NhbGhvc3SHBH8AAAGHBAoAAgKHBMCoAAAwDQYJKoZIhvcNAQELBQADggEB\n' +
    'ABgjYCfuL407fcJUE5mGzoan/4Iz4Vm3e321P7OBTUWRZIaRITjVdtxIsLmjr2za\n' +
    '2zm5ClZqFYvODC7ZFQ08G1KDm3tS1h3ctZw+wpukPpNdY6bpMw5U++1xSNvzhrj2\n' +
    '+5pjPiIu5n9SQlyZBw12PNQB9KIlsUujqvhTw9nhKUcDteMLtsbEgQENi9lTViEd\n' +
    'FGgLNJi7gwXsStkqrxmqs3T0NPWgI6iVShHBEQY7VM9YM1wAbhDSKF/lu6d0HNOu\n' +
    'diYzrPxf3zMIwYe6wZmKwBr9ojbHIccx8n5FSK7hBtyYxlSNahv6z2gveplDjeW+\n' +
    'Zm4ys7CADiwhGdJdOw2q/VI=\n' +
    '-----END CERTIFICATE-----';

  /**
   * The "user-installed CA" (certs/user-ca.pem), used for the NSC experiment:
   * RcpScenarios/NetKitScenarios install it into the DEVICE user CA store via
   * certificateManagerDialog, then probe AppConfig.userCaBase().
   * Regenerate with: cd mock-server && npm run user-ca
   */
  static readonly USER_CA_PEM: string =
    '-----BEGIN CERTIFICATE-----\n' +
    'MIIDIDCCAgigAwIBAgIUPSqaac1mG5PK+YaN8IJc75vSMuowDQYJKoZIhvcNAQEL\n' +
    'BQAwFjEUMBIGA1UEAwwLbnNjLXVzZXItY2EwHhcNMjYwOTEzMTAwMDExWhcNMzYw\n' +
    'OTEwMTAwMDExWjAWMRQwEgYDVQQDDAtuc2MtdXNlci1jYTCCASIwDQYJKoZIhvcN\n' +
    'AQEBBQADggEPADCCAQoCggEBAL39GKiGV4Nh66FAWAaiStHyW9vlyeZ0PRDVQzbM\n' +
    'deoJUTee9o0qt+ReWVqUbMQTT9ZF4wp3J1qlacrkJ1ULCZY2C7dGvKMMsGeYdKl9\n' +
    '1jN+6izBGWl89mxVn/nyE7p2I4gC5Ux7AR8Z6tjyrEboaQIWVUqhAO2k0anmNXfN\n' +
    'txdARfjGfHARMIgSRYSViqFSBTFhDgZiiFGkL5RLPIKL4hV+4e5UeL1EdQqT2FSq\n' +
    'p/9I+iT9jeMmHZHvhri/NKgCw25wvu64Xkwtzx0Tonp/AdPctauZmvAI3qwrwLDy\n' +
    'ENYCW05I1L5VZ56+vTMlzcGpbS4pPRWi41yFds6MUFx23BMCAwEAAaNmMGQwHQYD\n' +
    'VR0OBBYEFEQYK6rEzD2JaiED9ApTiuEmebnsMB8GA1UdIwQYMBaAFEQYK6rEzD2J\n' +
    'aiED9ApTiuEmebnsMBIGA1UdEwEB/wQIMAYBAf8CAQAwDgYDVR0PAQH/BAQDAgEG\n' +
    'MA0GCSqGSIb3DQEBCwUAA4IBAQBHsSyvdS3E3WprQNjyFGuf0p1QQ6BpLPeOTl0T\n' +
    'qd45VudHlEpZn2IbUkE3P40Fnp7GB/wrEbmoyiWwDr3JRwKZ0eMg8XVcu3Q73XsC\n' +
    '/DoXKabsaHIKtgbYQKulf11IyVX1zMrOSdDPLB/qoRbsPSyfT2DAevZkAvIq35LN\n' +
    'JalNoLC31hLZJf5wCkExzQaF/19TklVQ5DcV6tVk3VoJ3NLOpmuNSyV1dUAcaxlZ\n' +
    '8YNmUbyxDhGCn7p+dd3B0j2Pz1865tkcxsWIIbeq1542UZFWbzcol085nyfL/9b5\n' +
    'FrBdO1+ZNzVpH+3NBiU4rSs9IKDFZd9bEzV8YKmSXE16lHce\n' +
    '-----END CERTIFICATE-----\n';
}
