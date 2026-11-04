import { test } from 'node:test';
import assert from 'node:assert/strict';
import { start, post, makeShare, tempDataFile } from './helpers.js';

const CATS = ['medications', 'allergies', 'conditions', 'labs', 'immunizations'];

test('connect then record lists 5 categories', async () => {
  const s = await start();
  try {
    const before = await (await fetch(`${s.base}/api/record`)).json();
    assert.equal(before.source.connected, false);
    assert.deepEqual(before.categories, {});

    const c = await (await post(`${s.base}/api/source/connect`)).json();
    assert.equal(c.source.name, 'Thameside General Hospital');
    assert.equal(c.counts.labs, 5);

    const rec = await (await fetch(`${s.base}/api/record`)).json();
    assert.deepEqual(Object.keys(rec.categories).sort(), [...CATS].sort());
    assert.equal(rec.patient.name, 'Noah Dixon');
    assert.equal(rec.patient.homeCountry, 'United Kingdom');
    const hba1c = rec.categories.labs.find((i) => i.title.includes('HbA1c'));
    assert.equal(hba1c.usValue, 6.5);
  } finally { await s.close(); }
});

test('creates share with url and status active', async () => {
  const s = await start();
  try {
    const { res, json } = await makeShare(s.base);
    assert.equal(res.status, 201);
    assert.match(json.share.url, /^http:\/\/test\.local:3000\/s\/[A-Za-z0-9_-]{22}$/);
    assert.equal(json.share.status, 'active');
    assert.deepEqual(json.share.categories, ['allergies', 'labs']);
    assert.equal(json.walletAvailable, false);
    const hours = (Date.parse(json.share.expiresAt) - Date.parse(json.share.createdAt)) / 3.6e6;
    assert.equal(Math.round(hours), 24);
  } finally { await s.close(); }
});

test('rejects invalid share requests', async () => {
  const s = await start();
  try {
    await post(`${s.base}/api/source/connect`);
    for (const body of [
      { categories: [], durationHours: 24 },
      { categories: ['xrays'], durationHours: 24 },
      { categories: ['labs'], durationHours: 5 },
      { durationHours: 24 },
    ]) {
      const r = await post(`${s.base}/api/shares`, body);
      assert.equal(r.status, 400, JSON.stringify(body));
    }
    const list = await (await fetch(`${s.base}/api/shares`)).json();
    assert.deepEqual(list, []);
  } finally { await s.close(); }
});

test('share before connecting → 409', async () => {
  const s = await start();
  try {
    const r = await post(`${s.base}/api/shares`, { categories: ['labs'], durationHours: 24 });
    assert.equal(r.status, 409);
  } finally { await s.close(); }
});

test('revoke is idempotent', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base);
    const t = json.share.token;
    const a = await post(`${s.base}/api/shares/${t}/revoke`);
    assert.equal(a.status, 200);
    const first = await a.json();
    assert.equal(first.status, 'revoked');
    const b = await post(`${s.base}/api/shares/${t}/revoke`);
    assert.equal(b.status, 200);
    assert.equal((await b.json()).revokedAt, first.revokedAt);
  } finally { await s.close(); }
});

test('revoke unknown → 404', async () => {
  const s = await start();
  try {
    const r = await post(`${s.base}/api/shares/nope/revoke`);
    assert.equal(r.status, 404);
  } finally { await s.close(); }
});

test('shares persist across app instances', async () => {
  const dataFile = tempDataFile();
  const a = await start({ dataFile });
  const { json } = await makeShare(a.base);
  await a.close();
  const b = await start({ dataFile });
  try {
    const list = await (await fetch(`${b.base}/api/shares`)).json();
    assert.equal(list.length, 1);
    assert.equal(list[0].token, json.share.token);
    const rec = await (await fetch(`${b.base}/api/record`)).json();
    assert.equal(rec.source.connected, true);
  } finally { await b.close(); }
});
