import { randomBytes } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname } from 'node:path';

const EMPTY = () => ({ source: { connected: false, lastSynced: null }, shares: [] });

/** JSON-file persistence for the single demo patient (decision.md D9). */
export class Store {
  constructor(dataFile) {
    this.file = dataFile;
    this.state = existsSync(dataFile) ? JSON.parse(readFileSync(dataFile, 'utf8')) : EMPTY();
  }

  #save() {
    mkdirSync(dirname(this.file), { recursive: true });
    writeFileSync(this.file, JSON.stringify(this.state, null, 2));
  }

  getState() { return this.state; }

  connectSource() {
    this.state.source = { connected: true, lastSynced: new Date().toISOString() };
    this.#save();
    return this.state.source;
  }

  createShare({ categories, durationHours, label }) {
    const now = Date.now();
    const share = {
      token: randomBytes(16).toString('base64url'),
      label: label ?? '',
      categories,
      createdAt: new Date(now).toISOString(),
      expiresAt: new Date(now + durationHours * 3.6e6).toISOString(),
      revokedAt: null,
      views: [],
    };
    this.state.shares.push(share);
    this.#save();
    return share;
  }

  listShares() { return [...this.state.shares].reverse(); }

  getShare(token) { return this.state.shares.find((s) => s.token === token) ?? null; }

  /** Idempotent: a second revoke keeps the original revokedAt. */
  revoke(token) {
    const s = this.getShare(token);
    if (!s) return null;
    if (!s.revokedAt) { s.revokedAt = new Date().toISOString(); this.#save(); }
    return s;
  }

  logView(token, userAgent) {
    const s = this.getShare(token);
    if (!s) return;
    s.views.push({ at: new Date().toISOString(), userAgent: userAgent ?? '' });
    this.#save();
  }

  /** Test/admin hook: set a share's expiry. */
  setExpiry(token, iso) { const s = this.getShare(token); if (s) { s.expiresAt = iso; this.#save(); } }

  status(share, now = Date.now()) {
    if (share.revokedAt) return 'revoked';
    if (now >= Date.parse(share.expiresAt)) return 'expired';
    return 'active';
  }
}
