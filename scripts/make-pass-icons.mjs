#!/usr/bin/env node
// Writes the Wallet pass images (icon/logo at 1x/2x/3x) with no dependencies:
// a gradient rounded square with a white open ring, the Consentra mark. Run once; output is committed.
import { writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync, crc32 } from 'node:zlib';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const OUT = join(dirname(fileURLToPath(import.meta.url)), '../server/pass-model/consentra.pass');
mkdirSync(OUT, { recursive: true });

const STOPS = [[0x5a, 0xc8, 0xfa], [0x58, 0x56, 0xd6], [0xaf, 0x52, 0xde]];
const lerp = (a, b, t) => a + (b - a) * t;
const grad = (t) => {
  const [a, b, u] = t < 0.55 ? [STOPS[0], STOPS[1], t / 0.55] : [STOPS[1], STOPS[2], (t - 0.55) / 0.45];
  return a.map((v, i) => Math.round(lerp(v, b[i], u)));
};

function mark(size, opaque = false) {
  const px = Buffer.alloc(size * size * 4);
  const r = opaque ? 0 : size * 0.225, c = size / 2;
  const ro = size * 0.30, ri = size * 0.19;
  const SS = 4; // supersampling for smooth edges
  for (let y = 0; y < size; y++) for (let x = 0; x < size; x++) {
    let cover = 0, white = 0;
    for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
      const fx = x + (sx + 0.5) / SS, fy = y + (sy + 0.5) / SS;
      const dx = Math.max(r - fx, 0, fx - (size - r)), dy = Math.max(r - fy, 0, fy - (size - r));
      if (dx * dx + dy * dy > r * r) continue;
      cover++;
      const d = Math.hypot(fx - c, fy - c), ang = Math.abs(Math.atan2(fy - c, fx - c));
      if (d <= ro && d >= ri && ang > 0.75) white++;
    }
    const n = SS * SS, i = (y * size + x) * 4;
    const [gr, gg, gb] = grad((x + y) / (2 * size));
    const w = cover ? white / cover : 0;
    px[i] = Math.round(lerp(gr, 255, w)); px[i + 1] = Math.round(lerp(gg, 255, w)); px[i + 2] = Math.round(lerp(gb, 255, w));
    px[i + 3] = Math.round((cover / n) * 255);
  }
  return png(size, size, px);
}

function png(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) rgba.copy(raw, y * (w * 4 + 1) + 1, y * w * 4, (y + 1) * w * 4);
  const chunk = (type, data) => {
    const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
    const td = Buffer.concat([Buffer.from(type), data]);
    const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
    return Buffer.concat([len, td, crc]);
  };
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4); ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk('IHDR', ihdr), chunk('IDAT', deflateSync(raw)), chunk('IEND', Buffer.alloc(0))]);
}

for (const [name, size] of [['icon.png', 29], ['icon@2x.png', 58], ['icon@3x.png', 87], ['logo.png', 50], ['logo@2x.png', 100], ['logo@3x.png', 150]]) {
  writeFileSync(join(OUT, name), mark(size));
}
console.log('wrote pass images to', OUT);

// iOS app icon (opaque, single 1024 size; Xcode 15 generates the rest).
const ICON = join(dirname(fileURLToPath(import.meta.url)), '../ios/Consentra/Assets.xcassets/AppIcon.appiconset');
mkdirSync(ICON, { recursive: true });
writeFileSync(join(ICON, 'icon-1024.png'), mark(1024, true));
writeFileSync(join(ICON, 'Contents.json'), JSON.stringify({ images: [{ filename: 'icon-1024.png', idiom: 'universal', platform: 'ios', size: '1024x1024' }], info: { author: 'xcode', version: 1 } }, null, 2));
const ACC = join(ICON, '../AccentColor.colorset');
mkdirSync(ACC, { recursive: true });
writeFileSync(join(ACC, 'Contents.json'), JSON.stringify({ colors: [{ color: { 'color-space': 'srgb', components: { red: '0.345', green: '0.337', blue: '0.839', alpha: '1.000' } }, idiom: 'universal' }], info: { author: 'xcode', version: 1 } }, null, 2));
writeFileSync(join(ICON, '../Contents.json'), JSON.stringify({ info: { author: 'xcode', version: 1 } }, null, 2));
console.log('wrote app icon to', ICON);
