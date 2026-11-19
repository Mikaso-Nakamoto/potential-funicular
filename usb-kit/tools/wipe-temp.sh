#!/bin/sh
# Ручная зачистка всех кэшей стека (сессии и конфиг не трогаются).
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
rm -rf "$ROOT/tmp" "$ROOT/npm-global/.cache" 2>/dev/null || true
echo "tmp/ очищен."
