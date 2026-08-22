/**
 * Generate a self-signed TLS certificate for the mock server.
 * The SANs cover the hostnames/IPs a HarmonyOS emulator or real device
 * may use to reach this machine (10.0.2.2 is the emulator's host loopback).
 */
import { execFileSync } from 'node:child_process';
import { mkdirSync, existsSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const certDir = join(here, 'certs');
mkdirSync(certDir, { recursive: true });

const keyPath = join(certDir, 'key.pem');
const certPath = join(certDir, 'cert.pem');

if (existsSync(keyPath) && existsSync(certPath)) {
  console.log('Certificates already exist:', certPath, keyPath);
  process.exit(0);
}

const subj = '/CN=netkit-rcp-mock';
const san = 'subjectAltName=DNS:localhost,IP:127.0.0.1,IP:10.0.2.2,IP:192.168.0.0';
const args = [
  'req', '-x509', '-newkey', 'rsa:2048',
  '-keyout', keyPath,
  '-out', certPath,
  '-days', '3650',
  '-nodes',
  '-subj', subj,
  '-addext', san,
];

console.log('Running:', 'openssl ' + args.join(' '));
execFileSync('openssl', args, { stdio: 'inherit' });
console.log('Generated TLS certificate:');
console.log('  cert:', certPath);
console.log('  key :', keyPath);
