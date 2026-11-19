#!/bin/sh
# Точка входа: запускает Pi целикомом из этой папки, куда бы её ни примонтировали.
set -eu

BIN_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=usb-kit/bin/env.sh
. "$BIN_DIR/env.sh"
stick_dirs

if [ ! -x "$PI_STICK_ROOT/node/bin/node" ] && [ ! -x "$PI_STICK_ROOT/node/bin/pi" ]; then
  echo "Стек ещё не собран. Выполните: $PI_STICK_ROOT/tools/bootstrap.sh" >&2
  exit 1
fi

# Зачистка временных кэшей при любом выходе (данные сессий в sessions/ не трогаем)
cleanup_tmp() {
  rm -rf "$PI_STICK_ROOT/tmp" 2>/dev/null || true
}
trap cleanup_tmp EXIT INT TERM

exec "$PI_STICK_ROOT/node/bin/pi" "$@"
