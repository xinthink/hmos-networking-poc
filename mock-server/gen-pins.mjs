/**
 * Print the certificate-pin digests of the mock server certificate.
 *
 * Both the static NSC `pin-set` (`digest`) and the dynamic
 * `certificatePinning.publicKeyHash` (Network Kit / RCP / axios) use these
 * values, so they must be refreshed in the app whenever the certificate is
 * regenerated — same rule as `MOCK_CA_PEM`.
 *
 *   SPKI : base64(sha256(SubjectPublicKeyInfo))  <- the documented "public key hash"
 *   CERT : base64(sha256(whole DER certificate)) <- different value, NOT the pin semantics
 *
 * Values are consumed by `network-compare/entry/src/main/ets/nsc/NscPins.ets`.
 */
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const certPath = join(here, 'certs', 'cert.pem');

if (!existsSync(certPath)) {
  console.error('Missing', certPath, '— run `npm run certs` first.');
  process.exit(1);
}

/** Run `openssl` with a Buffer in/out (never decode binary as utf8). */
function opensslBuffer(args, input) {
  return execFileSync('openssl', args, { input, encoding: null });
}

/** Run `openssl` expecting text output. */
function opensslText(args) {
  return execFileSync('openssl', args, { encoding: 'utf8' });
}

/** base64(sha256(der)) — the pin format both static and dynamic pinning expect. */
function pinOfDer(der) {
  return opensslBuffer(['dgst', '-sha256', '-binary'], der).toString('base64');
}

const spkiPem = opensslText(['x509', '-in', certPath, '-pubkey', '-noout']);
const spkiDer = opensslBuffer(['pkey', '-pubin', '-outform', 'der'], spkiPem);
const certDer = opensslBuffer(['x509', '-in', certPath, '-outform', 'der']);

const spkiPin = pinOfDer(spkiDer);
const certPin = pinOfDer(certDer);

console.log('certificate :', certPath);
console.log('SPKI pin    :', spkiPin, '  <- use this (publicKeyHash / pin-set digest)');
console.log('CERT pin    :', certPin, '  <- whole-cert digest, different value');
console.log();
console.log('Paste into network-compare/entry/src/main/ets/nsc/NscPins.ets:');
console.log(`  static readonly SPKI_SHA256: string = '${spkiPin}';`);
console.log(`  static readonly CERT_SHA256: string = '${certPin}';`);
