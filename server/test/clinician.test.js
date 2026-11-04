import { test } from 'node:test';
import assert from 'node:assert/strict';
import { start, post, makeShare } from './helpers.js';

const CATEGORY_TITLES = ['Medications', 'Allergies', 'Conditions', 'Lab results', 'Immunizations'];

test('clinician page omits unshared categories', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base); // allergies + labs
    const r = await fetch(`${s.base}/s/${json.share.token}`);
    assert.equal(r.status, 200);
    const html = await r.text();
    assert.match(html, /Penicillin/);
    assert.match(html, /6\.5\s*%/);
    assert.match(html, /48 mmol\/mol/);
    assert.match(html, /Noah Dixon/);
    for (const leak of ['Ramipril', 'Medications', 'Type 2 diabetes', 'Comirnaty', 'Immunizations']) {
      assert.doesNotMatch(html, new RegExp(leak), `leaked ${leak}`);
    }
  } finally { await s.close(); }
});

test('unknown token → 410 access ended', async () => {
  const s = await start();
  try {
    const r = await fetch(`${s.base}/s/not-a-real-token`);
    assert.equal(r.status, 410);
    const html = await r.text();
    assert.match(html, /Access ended/);
    for (const t of CATEGORY_TITLES) assert.doesNotMatch(html, new RegExp(t));
    const st = await fetch(`${s.base}/s/not-a-real-token/status`);
    assert.equal(st.status, 410);
    assert.deepEqual(await st.json(), { active: false });
  } finally { await s.close(); }
});

test('expired share → 410', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base);
    s.app.locals.store.setExpiry(json.share.token, new Date(Date.now() - 1000).toISOString());
    const r = await fetch(`${s.base}/s/${json.share.token}`);
    assert.equal(r.status, 410);
    assert.doesNotMatch(await r.text(), /Penicillin/);
  } finally { await s.close(); }
});

test('view is logged', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base);
    await fetch(`${s.base}/s/${json.share.token}`, { headers: { 'user-agent': 'TestBrowser/1.0' } });
    const list = await (await fetch(`${s.base}/api/shares`)).json();
    assert.equal(list[0].views.length, 1);
    assert.equal(list[0].views[0].userAgent, 'TestBrowser/1.0');
  } finally { await s.close(); }
});

test('revoked → status inactive', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base);
    const t = json.share.token;
    const before = await fetch(`${s.base}/s/${t}/status`);
    assert.equal(before.status, 200);
    assert.deepEqual(await before.json(), { active: true });
    await post(`${s.base}/api/shares/${t}/revoke`);
    const after = await fetch(`${s.base}/s/${t}/status`);
    assert.equal(after.status, 410);
    const page = await fetch(`${s.base}/s/${t}`);
    assert.equal(page.status, 410);
    assert.doesNotMatch(await page.text(), /Penicillin/);
  } finally { await s.close(); }
});

test('patient-entered label is HTML-escaped', async () => {
  const s = await start();
  try {
    const { json } = await makeShare(s.base, { categories: ['labs'], durationHours: 1, label: '<script>alert(1)</script>' });
    const html = await (await fetch(`${s.base}/s/${json.share.token}`)).text();
    assert.doesNotMatch(html, /<script>alert\(1\)<\/script>/);
    assert.match(html, /&lt;script&gt;/);
  } finally { await s.close(); }
});

test('malformed token → 410 access ended, no stack trace', async () => {
  const s = await start();
  try {
    const page = await fetch(`${s.base}/s/%E0%A4%A`);
    assert.equal(page.status, 410);
    const html = await page.text();
    assert.match(html, /Access ended/);
    assert.doesNotMatch(html, /node_modules|URIError|at /);
    const st = await fetch(`${s.base}/s/%E0%A4%A/status`);
    assert.equal(st.status, 410);
    assert.deepEqual(await st.json(), { active: false });
  } finally { await s.close(); }
});

test('malformed API input → JSON 400, no stack trace', async () => {
  const s = await start();
  try {
    const rv = await fetch(`${s.base}/api/shares/%E0%A4%A/revoke`, { method: 'POST' });
    assert.equal(rv.status, 400);
    assert.ok((await rv.json()).error);
    const bad = await fetch(`${s.base}/api/shares`, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{not json' });
    assert.equal(bad.status, 400);
    const body = await bad.text();
    assert.doesNotMatch(body, /node_modules|SyntaxError/);
    assert.ok(JSON.parse(body).error);
  } finally { await s.close(); }
});
