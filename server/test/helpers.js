import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createApp } from '../src/app.js';

export const CERTS = new URL('../certs', import.meta.url).pathname;

export function tempDataFile() {
  return join(mkdtempSync(join(tmpdir(), 'consentra-')), 'state.json');
}

/** Starts an app on an ephemeral port. Returns { base, app, close }. */
export async function start({ dataFile = tempDataFile(), certsDir = '/nonexistent' } = {}) {
  const app = createApp({ dataFile, certsDir, baseUrl: 'http://test.local:3000' });
  const server = await new Promise((r) => { const s = app.listen(0, '127.0.0.1', () => r(s)); });
  const base = `http://127.0.0.1:${server.address().port}`;
  return { base, app, dataFile, close: () => new Promise((r) => server.close(r)) };
}

export const post = (url, body) =>
  fetch(url, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify(body ?? {}) });

export async function makeShare(base, body = { categories: ['allergies', 'labs'], durationHours: 24, label: 'Dr. Test' }) {
  await post(`${base}/api/source/connect`);
  const res = await post(`${base}/api/shares`, body);
  return { res, json: await res.json() };
}
