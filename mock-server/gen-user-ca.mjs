/**
 * Generate the "user-installed CA" test material for the NSC user-CA experiment.
 *
 * Mechanism under test: a CA that lives ONLY in the device's user CA store
 * (`/data/certificates/user_cacerts/...`) — i.e. what Charles/Fiddler-style proxy
 * tooling installs. NSC can be told to ignore such CAs via
 * `"trust-global-user-ca": false` / `"trust-current-user-ca": false`.
 *
 * Produces (public certs are committed, keys are gitignored):
 *   certs/user-ca.pem        CA certificate  -> installed into the device user CA store
 *   certs/user-ca.key        CA private key  (never committed)
 *   certs/user-server.pem    server cert for 10.0.2.2 etc., signed by user-ca
 *   certs/user-server.key    server private key (never committed)
 *
 * The server cert is served on a THIRD listener (default :9443) so that the
 * existing :8443 listener (self-signed mock CA) stays untouched.
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const certDir = join(here, 'certs');
mkdirSync(certDir, { recursive: true });

const caKey = join(certDir, 'user-ca.key');
const caCert = join(certDir, 'user-ca.pem');
const srvKey = join(certDir, 'user-server.key');
const srvCsr = join(certDir, 'user-server.csr');
const srvCert = join(certDir, 'user-server.pem');

const force = process.argv.includes('--force');
const present = [caKey, caCert, srvKey, srvCert].every((p) => existsSync(p));

if (present && !force) {
  console.log('User-CA material already exists:', caCert, srvCert);
} else {
  // Same SANs as the main cert so the app can reach it the same way.
  const san = 'subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2,IP:192.168.0.0';
  const run = (args) => execFileSync('openssl', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });

  // 1) A real CA (basicConstraints CA:TRUE) — this is the "user CA".
  run([
    'req', '-x509', '-newkey', 'rsa:2048', '-sha256', '-days', '3650', '-nodes',
    '-keyout', caKey, '-out', caCert,
    '-subj', '/CN=nsc-user-ca',
    '-addext', 'basicConstraints=critical,CA:TRUE,pathlen:0',
    '-addext', 'keyUsage=critical,keyCertSign,cRLSign',
  ]);

  // 2) Server key + CSR carrying the SANs.
  run([
    'req', '-new', '-newkey', 'rsa:2048', '-sha256', '-nodes',
    '-keyout', srvKey, '-out', srvCsr,
    '-subj', '/CN=netkit-rcp-mock',
    '-addext', san,
  ]);

  // 3) Sign the server cert with the user CA, copying the CSR extensions (SAN).
  run([
    'x509', '-req', '-in', srvCsr, '-sha256', '-days', '3650',
    '-CA', caCert, '-CAkey', caKey, '-CAcreateserial',
    '-copy_extensions', 'copy',
    '-out', srvCert,
  ]);

  rmSync(srvCsr, { force: true });
  console.log('Generated:', caCert, srvCert);
}

const caPem = readFileSync(caCert, 'utf8').trim();
const srvPem = readFileSync(srvCert, 'utf8');
const asTsString = (pem) => {
  const lines = pem.split('\n').filter((l) => l.length > 0);
  return lines.map((l) => `    '${l}\\n'`).join(' +\n') + ';';
};

console.log();
console.log('Paste into network-compare/entry/src/main/ets/common/AppConfig.ets (USER_CA_PEM):');
console.log('  /** CA installed into the device USER CA store (for the NSC user-CA experiment). */');
console.log('  static readonly USER_CA_PEM: string =');
console.log(asTsString(caPem));
console.log();
console.log('Fingerprint of the user CA (should NOT match the app trust-anchors / system store):');
console.log(' ', execFileSync('openssl', ['x509', '-in', caCert, '-noout', '-fingerprint', '-sha256'], { encoding: 'utf8' }).trim());
writeFileSync(join(certDir, '.user-ca-info.txt'),
  `subject: ${execFileSync('openssl', ['x509', '-in', caCert, '-noout', '-subject'], { encoding: 'utf8' }).trim()}\n` +
  `server : ${execFileSync('openssl', ['x509', '-in', srvCert, '-noout', '-subject', '-issuer'], { encoding: 'utf8' }).trim()}\n`, 'utf8');
