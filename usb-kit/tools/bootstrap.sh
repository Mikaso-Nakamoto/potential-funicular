#!/usr/bin/env bash
# Одноразовая (идемпотентная) сборка стека внутри usb-kit.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=usb-kit/bin/env.sh
source "$ROOT/bin/env.sh"
stick_dirs

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# ---------------------------------------------------------------- Node.js ---
if [ ! -x "$ROOT/node/bin/node" ]; then
  log "Установка портативного Node.js"
  os=$(uname -s | tr '[:upper:]' '[:lower:]'); [ "$os" = darwin ] && os=darwin || os=linux
  case "$(uname -m)" in x86_64|amd64) arch=x64 ;; arm64|aarch64) arch=arm64 ;; *) echo "Неподдерживаемая архитектура: $(uname -m)" >&2; exit 1 ;; esac
  if [ -z "${NODE_VERSION:-}" ]; then
    NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json \
      | grep -o '"version":"v[0-9]*\.[0-9]*\.[0-9]*","date":"[^"]*","files":\[[^]]*\],"npm":"[^"]*","lts":"[A-Za-z]*"' \
      | grep '"lts":"[A-Z]' | head -1 | grep -o 'v[0-9]*\.[0-9]*\.[0-9]*' | head -1 || true)
    # запасной разбор без npm-поля
    if [ -z "${NODE_VERSION:-}" ]; then
      NODE_VERSION=$(curl -fsSL https://nodejs.org/dist/index.json | python3 -c 'import sys,json; print(next(e["version"] for e in json.load(sys.stdin) if e.get("lts")))' 2>/dev/null || true)
    fi
  fi
  [ -n "${NODE_VERSION:-}" ] || { echo "Не удалось определить LTS-версию Node. Задайте NODE_VERSION=vX.Y.Z вручную." >&2; exit 1; }
  url="https://nodejs.org/dist/${NODE_VERSION}/node-${NODE_VERSION}-${os}-${arch}.tar.xz"
  echo "Качаю $url"
  mkdir -p "$ROOT/node"
  curl -fL "$url" | tar -xJ --strip-components=1 -C "$ROOT/node"
fi
"$ROOT/node/bin/node" --version

# -------------------------------------------------------------------- Pi ----
log "Установка @earendil-works/pi-coding-agent (npm prefix=$NPM_CONFIG_PREFIX)"
npm install -g --ignore-scripts --no-fund --no-audit @earendil-works/pi-coding-agent

# ------------------------------------------------------- Python + мост ------
log "Сборка venv и установка skillbridge"
PYBIN=${PYTHON_BIN:-python3}
"$PYBIN" -m venv "$ROOT/venv"
"$VENV_BIN/pip" install --quiet --upgrade pip
"$VENV_BIN/pip" install --quiet -r "$ROOT/skillbridge/requirements.txt"
if [ "${FULL:-0}" = "1" ]; then
  "$VENV_BIN/pip" install --quiet skillware   # полный режим: BaseSkill-валидация и каталог
fi
"$VENV_BIN/pip" install --quiet --force-reinstall --no-deps "$ROOT/skillbridge"
"$VENV_BIN/skillbridge" --root "$ROOT/skills" --selftest || echo "ВНИМАНИЕ: самотест моста неуспешен" >&2

# ------------------------------------------------------------ Скиллы Pi -----
log "Синхронизация маркдаун-скиллов из agent-skills/"
bash "$ROOT/tools/sync-skills.sh" "${@:1}"

log "Готово. Подключите модель: $ROOT/bin/run-pi.sh auth login <provider> --api-key"
