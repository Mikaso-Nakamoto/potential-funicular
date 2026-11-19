#!/bin/sh
# Точка входа POSIX: запускает Pi целиком из этой папки, куда бы её ни примонтировали.
set -eu

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=usb-kit/bin/env.sh
. "$BIN_DIR/env.sh"
stick_dirs

PI_SHIM="$PI_STICK_ROOT/npm-global/bin/pi"
PI_CLI="$PI_STICK_ROOT/npm-global/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js"

if [ ! -x "$PI_SHIM" ] && [ ! -f "$PI_CLI" ]; then
  echo "Стек ещё не собран или pi не найден. Выполните: $PI_STICK_ROOT/tools/bootstrap.sh" >&2
  exit 1
fi

# Зачистка временных кэшей при любом выходе (данные сессий в sessions/ не трогаем)
cleanup_tmp() {
  rm -rf "$PI_STICK_ROOT/tmp" 2>/dev/null || true
}
trap cleanup_tmp EXIT INT TERM

if [ -x "$PI_SHIM" ]; then
  exec "$PI_SHIM" "$@"
fi
exec "$PI_STICK_ROOT/node/bin/node" "$PI_CLI" "$@"
