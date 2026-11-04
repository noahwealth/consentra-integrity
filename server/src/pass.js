// Apple Wallet pass per share, signed on the server (decision.md D4, D5).
import { X509Certificate } from 'node:crypto';
import { existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { PKPass } from 'passkit-generator';
import { CATEGORY_TITLES } from './source/display.js';

const MODEL = fileURLToPath(new URL('../pass-model/consentra.pass', import.meta.url));
const FILES = { cert: 'pass.pem', key: 'pass.key', wwdr: 'wwdr.pem' };

/** Reads Pass Type ID (subject UID) and Team ID (subject OU) from the signing cert; null if certs are missing. */
export function certInfo(certsDir) {
  try {
    if (!Object.values(FILES).every((f) => existsSync(join(certsDir, f)))) return null;
    const subject = new X509Certificate(readFileSync(join(certsDir, FILES.cert))).subject;
    const field = (k) => subject.split('\n').find((l) => l.startsWith(`${k}=`))?.slice(k.length + 1);
    const passTypeIdentifier = field('UID'), teamIdentifier = field('OU');
    return passTypeIdentifier && teamIdentifier ? { passTypeIdentifier, teamIdentifier } : null;
  } catch {
    return null;
  }
}

/** @returns {Promise<Buffer>} a signed .pkpass */
export async function buildPass({ share, patient, source, certsDir }) {
  const ids = certInfo(certsDir);
  if (!ids) throw new Error('Wallet signing certificates not found');
  const read = (f) => readFileSync(join(certsDir, f));

  const pass = await PKPass.from(
    { model: MODEL, certificates: { wwdr: read(FILES.wwdr), signerCert: read(FILES.cert), signerKey: read(FILES.key) } },
    { ...ids, serialNumber: share.token },
  );

  pass.setBarcodes({ format: 'PKBarcodeFormatQR', message: share.url, messageEncoding: 'iso-8859-1', altText: 'Scan to view shared record' });
  pass.setExpirationDate(new Date(share.expiresAt));

  const titles = share.categories.map((c) => CATEGORY_TITLES[c]);
  pass.headerFields.push({ key: 'expires', label: 'EXPIRES', value: share.expiresAt, dateStyle: 'PKDateStyleShort', timeStyle: 'PKDateStyleShort' });
  pass.primaryFields.push({ key: 'patient', label: 'HEALTH PASSPORT', value: patient.name });
  pass.secondaryFields.push({ key: 'sharing', label: 'SHARING', value: titles.join(', ') });
  pass.auxiliaryFields.push(
    { key: 'for', label: 'FOR', value: share.label || 'Any clinician' },
    { key: 'source', label: 'SOURCE', value: `${source.name}, ${source.city}` },
  );
  pass.backFields.push(
    { key: 'how', label: 'How it works', value: 'Show this QR code to your clinician. They open your shared record in any browser. Nothing to install.' },
    { key: 'revoke', label: 'Your control', value: 'Revoke access anytime in the Consentra app. The link stops working immediately, even if this pass is still in Wallet.' },
    { key: 'home', label: 'Home country', value: patient.homeCountry },
  );
  return pass.getAsBuffer();
}
