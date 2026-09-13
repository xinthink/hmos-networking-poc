/**
 * Certificate-pin digests of the mock server certificate (base64 SHA-256).
 *
 * Both the static NSC `pin-set` (`digest`) and the dynamic
 * `certificatePinning.publicKeyHash` of Network Kit / RCP / axios take the same
 * kind of value, so these constants are shared by the whole suite.
 *
 * Recompute after ANY certificate change (`cd mock-server && npm run pins`):
 *
 *   SPKI : openssl x509 -in mock-server/certs/cert.pem -pubkey -noout \
 *            | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64
 *   CERT : openssl x509 -in mock-server/certs/cert.pem -outform der \
 *            | openssl dgst -sha256 -binary | openssl base64
 */
export class NscPins {
  /**
   * SHA-256 over the SubjectPublicKeyInfo — the documented "public key hash"
   * (a.k.a. SPKI pin / HPKP style).
   */
  static readonly SPKI_SHA256: string = 'QLc8TBmkuxFAQ/h8rKcWtRuCN4R0Zflysb5gNCnQse8=';

  /**
   * SHA-256 over the whole DER certificate. Not the documented semantics, used
   * as a probe: if pinning accepted THIS instead of SPKI, the implementation
   * hashes the certificate rather than the public key.
   */
  static readonly CERT_SHA256: string = 'WcHQ6kF8ohL3zaPwpNWbs2OYmjvI9AiWI7j74UwCGQc=';

  /** Deliberately wrong digest (correct length/format) — must always be rejected. */
  static readonly WRONG: string = 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=';
}
