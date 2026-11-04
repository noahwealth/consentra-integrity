import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, writeFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { start, post, makeShare, CERTS } from './helpers.js';
import { certInfo } from '../src/pass.js';

const haveCerts = ['pass.pem', 'pass.key', 'wwdr.pem'].every((f) => existsSync(join(CERTS, f)));

test('certInfo reads ids from cert', { skip: !haveCerts && 'no certs' }, () => {
  assert.deepEqual(certInfo(CERTS), { passTypeIdentifier: 'pass.com.aliabdullah.consentra', teamIdentifier: 'YRL45Q79LJ' });
});

test('certInfo → null without certs', () => {
  assert.equal(certInfo('/nonexistent'), null);
});

test('pkpass is a zip with signature', { skip: !haveCerts && 'no certs' }, async () => {
  const s = await start({ certsDir: CERTS });
  try {
    const { json } = await makeShare(s.base);
    assert.equal(json.walletAvailable, true);
    const r = await fetch(`${s.base}/api/shares/${json.share.token}/pass.pkpass`);
    assert.equal(r.status, 200);
    assert.equal(r.headers.get('content-type'), 'application/vnd.apple.pkpass');
    const buf = Buffer.from(await r.arrayBuffer());
    assert.equal(buf.subarray(0, 2).toString(), 'PK');
    const dir = mkdtempSync(join(tmpdir(), 'pkpass-'));
    const file = join(dir, 'p.pkpass');
    writeFileSync(file, buf);
    const listing = execFileSync('unzip', ['-l', file]).toString();
    for (const f of ['pass.json', 'manifest.json', 'signature', 'icon.png']) assert.match(listing, new RegExp(f));
    const passJson = JSON.parse(execFileSync('unzip', ['-p', file, 'pass.json']).toString());
    assert.equal(passJson.serialNumber, json.share.token);
    assert.equal(passJson.barcodes[0].message, json.share.url);
    assert.equal(passJson.passTypeIdentifier, 'pass.com.aliabdullah.consentra');
    assert.equal(passJson.teamIdentifier, 'YRL45Q79LJ');
    assert.equal(Date.parse(passJson.expirationDate), Date.parse(json.share.expiresAt));
  } finally { await s.close(); }
});

test('revoked share pass → 410', async () => {
  const s = await start({ certsDir: CERTS });
  try {
    const { json } = await makeShare(s.base);
    await post(`${s.base}/api/shares/${json.share.token}/revoke`);
    const r = await fetch(`${s.base}/api/shares/${json.share.token}/pass.pkpass`);
    assert.equal(r.status, 410);
  } finally { await s.close(); }
});

test('record reports walletAvailable', async () => {
  const without = await start();
  try {
    assert.equal((await (await fetch(`${without.base}/api/record`)).json()).walletAvailable, false);
  } finally { await without.close(); }
  if (!haveCerts) return;
  const withCerts = await start({ certsDir: CERTS });
  try {
    assert.equal((await (await fetch(`${withCerts.base}/api/record`)).json()).walletAvailable, true);
  } finally { await withCerts.close(); }
});

test('pass without certs → 503', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base);
    assert.equal(json.walletAvailable, false);
    const r = await fetch(`${s.base}/api/shares/${json.share.token}/pass.pkpass`);
    assert.equal(r.status, 503);
  } finally { await s.close(); }
});
