import { networkInterfaces } from 'node:os';

/** First non-internal IPv4 (prefers en0 = Wi-Fi on Macs), so QR links work from a phone. */
export function lanIp() {
  const ifs = networkInterfaces();
  const order = ['en0', 'en1', ...Object.keys(ifs)];
  for (const name of order) {
    for (const a of ifs[name] ?? []) {
      if (a.family === 'IPv4' && !a.internal) return a.address;
    }
  }
  return '127.0.0.1';
}
