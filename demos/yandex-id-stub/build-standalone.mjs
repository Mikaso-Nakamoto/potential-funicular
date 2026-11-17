/**
 * Собирает самостоятельный HTML-файл: фото, QR, флаги и библиотека номеров
 * зашиваются внутрь, внешних зависимостей нет.
 *
 *   node demos/yandex-id-stub/build-standalone.mjs
 *   → demos/yandex-id-stub/yandex-id-stub.html
 */
import { readFile, writeFile } from 'node:fs/promises';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const read = (p) => readFileSync(path.join(dir, p));

const MIME = { '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml' };
const dataUri = (file) => {
  const buf = read(file);
  const ext = path.extname(file);
  if (ext === '.svg') {
    // SVG лучше в URL-encoded виде: короче, чем base64
    const min = buf.toString('utf8')
      .replace(/<\?xml[^>]*>/g, '')
      .replace(/<!--[\s\S]*?-->/g, '')
      .replace(/\sid="[^"]*"/g, '')
      .replace(/>\s+</g, '><')
      .trim();
    return 'data:image/svg+xml,' + encodeURIComponent(min).replace(/'/g, '%27').replace(/"/g, '%22');
  }
  return `data:${MIME[ext] || 'application/octet-stream'};base64,` + buf.toString('base64');
};

const assets = {};
for (const file of readdirSync(path.join(dir, 'assets/flags-all')).filter((f) => f.endsWith('.svg'))) {
  assets['flags/' + file] = dataUri('assets/flags-all/' + file);
}
assets['qr.png'] = dataUri('assets/qr.png');

let html = await readFile(path.join(dir, 'index.html'), 'utf8');

// замены делаем функциями: в минифицированной библиотеке есть «$&», «$1» и т.п.,
// которые String.replace иначе трактует как спец-шаблоны
html = html
  .replace('src="assets/landscape-ai.jpg"', () => `src="${dataUri('assets/landscape-ai.jpg')}"`)
  .replace('src="assets/landscape-alt.jpg"', () => `src="${dataUri('assets/landscape-alt.jpg')}"`)
  .replace('src="assets/qr.png"', () => `src="${assets['qr.png']}"`)
  .replace(
    '<script src="assets/libphonenumber.js" defer></script>',
    () => `<script>window.__ASSETS = ${JSON.stringify(assets)};</script>\n<script>\n${read('assets/libphonenumber.js').toString()}\n</script>`
  );

await writeFile(path.join(dir, 'yandex-id-stub.html'), html);
console.log('OK → demos/yandex-id-stub/yandex-id-stub.html', (Buffer.byteLength(html) / 1024 / 1024).toFixed(2) + ' MB');
