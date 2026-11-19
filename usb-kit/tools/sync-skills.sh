#!/usr/bin/env bash
# Копирует категории маркдаун-скиллов из ../agent-skills (или $SKILLS_SRC) в config/skills.
# Категории — аргументы; по умолчанию набор для сетевой безопасности и крипто.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="${SKILLS_SRC:-$(cd "$ROOT/../agent-skills" 2>/dev/null && pwd || true)}"
DST="$ROOT/config/skills"

if [ -z "$SRC" ] || [ ! -d "$SRC" ]; then
  echo "agent-skills не найден рядом с usb-kit — синк пропущен." >&2
  echo "Укажите SKILLS_SRC=/путь/к/agent-skills, если навыки лежат отдельно." >&2
  exit 0
fi
mkdir -p "$DST"

DEFAULT_CATS=(network-security security-crypto crypto-engineering ai-integration)
CATS=("$@"); [ ${#CATS[@]} -gt 0 ] || CATS=("${DEFAULT_CATS[@]}")

for cat in "${CATS[@]}"; do
  if [ -d "$SRC/$cat" ]; then
    cp -R "$SRC/$cat" "$DST/"
    n=$(find "$DST/$cat" -name SKILL.md | wc -l | tr -d ' ')
    echo "  + $cat ($n скиллов)"
  else
    echo "  ? категория не найдена: $cat" >&2
  fi
done
echo "Назначение: $DST  (Pi подхватит при старте или /reload)"
