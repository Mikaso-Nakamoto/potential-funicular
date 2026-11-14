#!/usr/bin/env bash
# Собирает статику для GitHub Pages в docs/.
#
# GitHub Pages умеет публиковать только корень ветки или папку /docs,
# поэтому дашборд из projects/victoria-falls копируется в docs как есть.
# Источник правды — projects/victoria-falls/, docs/ генерируется.
#
#   ./scripts/build-pages.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/projects/victoria-falls"
OUT="$ROOT/docs"

[ -f "$SRC/index.html" ] || { echo "Не найден $SRC/index.html" >&2; exit 1; }

rm -rf "$OUT"
mkdir -p "$OUT"

cp "$SRC/index.html" "$OUT/index.html"
cp -R "$SRC/css" "$OUT/css"
cp -R "$SRC/js" "$OUT/js"
cp -R "$SRC/iconss" "$OUT/iconss"

# Отключаем Jekyll: иначе он пытается обработать разметку и ломает пути
touch "$OUT/.nojekyll"

# Небольшая памятка, что папка сгенерирована
cat > "$OUT/README.md" <<'NOTE'
# docs/

Сгенерированная копия `projects/victoria-falls/` для GitHub Pages.
Не редактируйте вручную — пересоберите: `./scripts/build-pages.sh`.
NOTE

echo "docs/ собрана: $(find "$OUT" -type f | wc -l | tr -d ' ') файлов, $(du -sh "$OUT" | cut -f1)"
