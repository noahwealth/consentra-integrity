import express from 'express';
import { Store } from './store.js';
import { lanIp } from './net.js';
import { SOURCE, patient, resources } from './source/thameside.js';
import { CATEGORIES, toDisplayItem } from './source/display.js';
import { renderShare, renderEnded } from './clinician.js';
import { certInfo, buildPass } from './pass.js';

const DURATIONS = new Set([1, 24, 168, 720]);

export function patientSummary() {
  const n = patient.name[0];
  return {
    name: `${n.given.join(' ')} ${n.family}`,
    birthDate: patient.birthDate,
    homeCountry: SOURCE.country,
    nhsNumber: patient.identifier[0].value,
  };
}

export function displayRecord(categories = CATEGORIES) {
  return Object.fromEntries(categories.map((c) => [c, resources[c].map((r) => toDisplayItem(c, r))]));
}

export function createApp({ dataFile, certsDir, baseUrl = `http://${lanIp()}:${process.env.PORT ?? 3000}` }) {
  const store = new Store(dataFile);
  const app = express();
  Object.assign(app.locals, { store, certsDir, baseUrl });
  app.use(express.json());
  app.use((req, res, next) => { res.set('Cache-Control', 'no-store'); next(); });

  const serialize = (s) => ({ ...s, status: store.status(s), url: `${baseUrl}/s/${s.token}` });
  const sourceInfo = () => ({ ...SOURCE, ...store.getState().source });

  app.post('/api/source/connect', (req, res) => {
    store.connectSource();
    const counts = Object.fromEntries(CATEGORIES.map((c) => [c, resources[c].length]));
    res.json({ source: sourceInfo(), counts });
  });

  app.get('/api/record', (req, res) => {
    const connected = store.getState().source.connected;
    res.json({ patient: patientSummary(), source: sourceInfo(), categories: connected ? displayRecord() : {}, walletAvailable: certInfo(certsDir) !== null });
  });

  app.post('/api/shares', (req, res) => {
    const { categories, durationHours, label } = req.body ?? {};
    const valid = Array.isArray(categories) && categories.length > 0
      && categories.every((c) => CATEGORIES.includes(c))
      && new Set(categories).size === categories.length
      && DURATIONS.has(durationHours)
      && (label === undefined || (typeof label === 'string' && label.length <= 80));
    if (!valid) return res.status(400).json({ error: 'categories must be a non-empty subset of ' + CATEGORIES.join(', ') + '; durationHours one of 1, 24, 168, 720' });
    if (!store.getState().source.connected) return res.status(409).json({ error: 'Connect a source first' });
    const ordered = CATEGORIES.filter((c) => categories.includes(c));
    const share = store.createShare({ categories: ordered, durationHours, label: label?.trim() });
    res.status(201).json({ share: serialize(share), walletAvailable: certInfo(certsDir) !== null });
  });

  app.get('/api/shares', (req, res) => res.json(store.listShares().map(serialize)));

  app.post('/api/shares/:token/revoke', (req, res) => {
    const s = store.revoke(req.params.token);
    if (!s) return res.status(404).json({ error: 'Unknown share' });
    res.json(serialize(s));
  });

  app.get('/api/shares/:token/pass.pkpass', async (req, res) => {
    const s = store.getShare(req.params.token);
    if (!s) return res.status(404).json({ error: 'Unknown share' });
    if (store.status(s) !== 'active') return res.status(410).json({ error: 'Share is no longer active' });
    if (!certInfo(certsDir)) return res.status(503).json({ error: 'Wallet signing certificates are not installed on the server' });
    try {
      const buf = await buildPass({ share: serialize(s), patient: patientSummary(), source: sourceInfo(), certsDir });
      res.type('application/vnd.apple.pkpass').set('Content-Disposition', 'attachment; filename="consentra.pkpass"').send(buf);
    } catch (e) {
      console.error('pass build failed', e);
      res.status(500).json({ error: 'Could not build Wallet pass' });
    }
  });

  // ---- Clinician (capability URL; decision.md D7) ----
  const activeShare = (token) => {
    const s = store.getShare(token);
    return s && store.status(s) === 'active' ? s : null;
  };

  app.get('/s/:token/status', (req, res) => {
    const s = activeShare(req.params.token);
    res.status(s ? 200 : 410).json({ active: Boolean(s) });
  });

  app.get('/s/:token', (req, res) => {
    const s = activeShare(req.params.token);
    if (!s) return res.status(410).type('html').send(renderEnded());
    store.logView(s.token, req.get('user-agent'));
    const record = { patient: patientSummary(), source: sourceInfo(), categories: displayRecord(s.categories) };
    res.type('html').send(renderShare(record, s));
  });

  // Malformed input (bad percent-escapes in a token, unparseable JSON) must never reach Express's
  // default handler, which prints a stack trace. Clinician links fail closed to the same page.
  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (req.path.startsWith('/s/')) {
      return req.path.endsWith('/status')
        ? res.status(410).json({ active: false })
        : res.status(410).type('html').send(renderEnded());
    }
    const status = err.status >= 400 && err.status < 500 ? err.status : (err instanceof URIError ? 400 : 500);
    if (status === 500) console.error(err);
    res.status(status).json({ error: status === 500 ? 'Server error' : 'Malformed request' });
  });

  return app;
}
