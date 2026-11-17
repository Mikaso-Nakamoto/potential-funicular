/**
 * Собирает один самостоятельный HTML: флаги и фото фона зашиваются как data URI.
 * Запуск:  node demos/yandex-id-stub/build-standalone.mjs
 * Результат: demos/yandex-id-stub/yandex-id-stub.html
 */
import { readFile, writeFile } from 'node:fs/promises';
import { readdirSync, readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = path.dirname(fileURLToPath(import.meta.url));
const mime = { '.svg': 'image/svg+xml', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.png': 'image/png' };
const dataUri = (file) =>
  `data:${mime[path.extname(file)]};base64,` + readFileSync(file).toString('base64');

const flagsDir = path.join(dir, 'assets', 'flags');
const flagData = {};
for (const file of readdirSync(flagsDir).filter((f) => f.endsWith('.svg'))) {
  flagData[path.basename(file, '.svg')] = dataUri(path.join(flagsDir, file));
}

let html = await readFile(path.join(dir, 'index.html'), 'utf8');
const photo = dataUri(path.join(dir, 'assets', 'landscape-ai.jpg'));

html = html
  .replace('src="assets/landscape-ai.jpg"', `src="${photo}"`)
  // данные флагов вставляем перед основным скриптом
  .replace(/(<script>\s*\n\s*\(\(\) => \{)/, `<script>window.__FLAG_DATA = ${JSON.stringify(flagData)};</script>\n$1`);

await writeFile(path.join(dir, 'yandex-id-stub.html'), html);
console.log('OK → demos/yandex-id-stub/yandex-id-stub.html', (html.length / 1024).toFixed(0) + ' KB');
