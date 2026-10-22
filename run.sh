#!/usr/bin/env bash
# Быстрый запуск бота без systemd (для проверки руками).
# Постоянная работа — через systemd: docs/DEPLOY.md
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f config.toml ]; then
  echo "Нет config.toml — копирую из примера:"
  echo "  cp config.example.toml config.toml"
  echo "и заполняю его под себя."
  exit 1
fi
if [ ! -f .env ]; then
  echo "Нет .env — скопируйте .env.example и впишите ключ сообщества:"
  echo "  cp .env.example .env && nano .env"
  exit 1
fi

exec python3 -m bot.main "$@"
