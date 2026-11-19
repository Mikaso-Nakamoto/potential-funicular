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
log "Проверка Python и сборка venv"
PYBIN=${PYTHON_BIN:-python3}
command -v "$PYBIN" >/dev/null 2>&1 || {
  echo "Python 3 не найден. Debian/Ubuntu: sudo apt install python3 python3-venv; Fedora: sudo dnf install python3" >&2; exit 1; }
pyver=$("$PYBIN" -c 'import sys;print("%d.%d" % sys.version_info[:2])' 2>/dev/null || echo 0.0)
if ! "$PYBIN" -c 'import sys;raise SystemExit(0 if sys.version_info[:2] >= (3,10) else 1)'; then
  echo "Нужен Python >= 3.10, найден $pyver. Задайте PYTHON_BIN=/путь/к/python3.12" >&2; exit 1
fi
echo "  Python $pyver ($PYBIN)"

if [ -x "$VENV_BIN/python" ]; then
  echo "  venv уже есть — переиспользую"
else
  "$PYBIN" -m venv "$ROOT/venv" || {
    echo "Не удалось создать venv. Debian/Ubuntu: sudo apt install python3-venv" >&2; exit 1; }
fi
"$VENV_BIN/pip" install --quiet --upgrade pip
"$VENV_BIN/pip" install --quiet -r "$ROOT/skillbridge/requirements.txt" || {
  echo "pip не поставил зависимости (mcp, PyYAML) — проверьте сеть/прокси." >&2; exit 1; }
if [ "${FULL:-0}" = "1" ]; then
  "$VENV_BIN/pip" install --quiet skillware   # полный режим: BaseSkill-валидация и каталог
fi
"$VENV_BIN/pip" install --quiet --force-reinstall --no-deps "$ROOT/skillbridge"
"$VENV_BIN/skillbridge" --root "$ROOT/skills" --selftest || echo "ВНИМАНИЕ: самотест моста неуспешен" >&2

# ------------------------------------------------------------ Скиллы Pi -----
log "Синхронизация маркдаун-скиллов из agent-skills/"
bash "$ROOT/tools/sync-skills.sh" "${@:1}"

log "Готово. Подключите модель: $ROOT/bin/run-pi.sh auth login <provider> --api-key"
