# shellcheck shell=sh
# Общее окружение стека. Все пути — от корня usb-kit, вычисляемого динамически.
# Используется: launchers, bootstrap, sync-skills. Не рассчитано на прямой запуск.

# ROOT можно задать извне; иначе — родитель каталога этого файла.
if [ -z "${PI_STICK_ROOT:-}" ]; then
  ENV_SH_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd) || return 1
  PI_STICK_ROOT=$(CDPATH= cd -- "$ENV_SH_DIR/.." && pwd) || return 1
fi
export PI_STICK_ROOT

# Исполняемые слои флешки первыми в PATH
case "$(uname -s 2>/dev/null)" in
  MSYS*|MINGW*|CYGWIN*)
    VENV_BIN="$PI_STICK_ROOT/venv/Scripts"
    ;;
  *)
    VENV_BIN="$PI_STICK_ROOT/venv/bin"
    ;;
esac
export PATH="$PI_STICK_ROOT/node/bin:$PI_STICK_ROOT/npm-global/bin:$VENV_BIN:$PATH"

# npm — префикс и кэш на флешке
export NPM_CONFIG_PREFIX="$PI_STICK_ROOT/npm-global"
export NPM_CONFIG_CACHE="$PI_STICK_ROOT/tmp/npm-cache"
export NODE_REPL_HISTORY="$PI_STICK_ROOT/tmp/node_repl_history"

# Pi — конфиг и сессии на флешке
export PI_CODING_AGENT_DIR="$PI_STICK_ROOT/config"
export PI_CODING_AGENT_SESSION_DIR="$PI_STICK_ROOT/sessions"

# Временные файлы — только на флешку
export TMPDIR="$PI_STICK_ROOT/tmp"
export TEMP="$PI_STICK_ROOT/tmp"
export TMP="$PI_STICK_ROOT/tmp"
export XDG_CACHE_HOME="$PI_STICK_ROOT/tmp/xdg-cache"
export XDG_CONFIG_HOME="$PI_STICK_ROOT/tmp/xdg-config"
export XDG_STATE_HOME="$PI_STICK_ROOT/tmp/xdg-state"

stick_dirs() {
  mkdir -p "$PI_STICK_ROOT/tmp" "$PI_STICK_ROOT/sessions" \
           "$PI_STICK_ROOT/config/skills" "$PI_STICK_ROOT/npm-global/bin"
}
