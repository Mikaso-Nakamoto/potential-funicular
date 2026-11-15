#!/usr/bin/env bash
# e2e-start.sh — прогон app/start.ps1 под настоящим pwsh (Linux), без Windows.
#
# Зачем: start.ps1 — единственный скрипт, который поднимает xray, проверяет порт и
# запускает браузер. Под Linux его можно выполнить целиком, если подменить три вещи:
#   vpn\xray.exe          — слушатель SOCKS на порту из конфига (python)
#   app\LibreWolf\...exe  — процесс, который живёт 3 секунды и выходит
#   curl.exe / netstat    — обёртки, отдающие предсказуемый IP и вывод netstat -ano
# Сам скрипт комплекта при этом не меняется, кроме одной строки: на Linux
# Start-Process не знает -WindowStyle Hidden, поэтому в тестовой копии этот
# параметр вырезается.
#
# Требуется: pwsh 7 (Linux), python3, curl.
#   PWSH=/tmp/pwsh/pwsh review/netkit/tests/e2e-start.sh
#
# Выход: 0 — все сценарии дали ожидаемый результат, 1 — что-то не так.

set -u
PWSH="${PWSH:-pwsh}"
HERE="$(cd "$(dirname "$0")" && pwd)"
KIT="$(cd "$HERE/../inbox/LibreWolf-USB" && pwd)"
WORK="$(mktemp -d)"
FAILED=0

say() { printf '\n=== %s ===\n' "$1"; }
ok()  { printf '  [OK]   %s\n' "$1"; }
bad() { printf '  [FAIL] %s\n' "$1"; FAILED=$((FAILED+1)); }

cleanup() {
  pkill -f "$WORK/kit/vpn/xray.exe" 2>/dev/null
  pkill -f "$WORK/listen.py" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

[ -d "$KIT/app" ] || { echo "не найден комплект: $KIT"; exit 1; }
command -v "$PWSH" >/dev/null 2>&1 || { echo "не найден pwsh ($PWSH)"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "не найден python3"; exit 1; }

# ---------------------------------------------------------------- окружение
mkdir -p "$WORK/kit/app/LibreWolf" "$WORK/kit/vpn" "$WORK/kit/profile" "$WORK/bin"
cp "$KIT"/app/*.ps1 "$WORK/kit/app/"
cp "$KIT"/app/user.js "$WORK/kit/app/"
# -WindowStyle Hidden на Linux не поддерживается — вырезаем только из тестовой копии
sed -i 's/ -WindowStyle Hidden//' "$WORK/kit/app/start.ps1"

# curl.exe: прямой IP и IP «через прокси» — разные, иначе сработает детектор утечки
cat > "$WORK/bin/curl.exe" <<'SH'
#!/bin/sh
case "$*" in
  *--socks5-hostname*) printf '203.0.113.7' ;;
  *)                   printf '198.51.100.9' ;;
esac
SH
chmod +x "$WORK/bin/curl.exe"

# netstat -ano в формате Windows — запасной путь Get-ListenerPid, когда нет CIM
cat > "$WORK/bin/netstat.exe" <<SH
#!/bin/sh
# формат Windows:  TCP  127.0.0.1:PORT  0.0.0.0:0  LISTENING  PID
ss -ltnp 2>/dev/null | tail -n +2 | while read -r _ recv send local peer rest; do
  port="\${local##*:}"
  pid="\$(printf '%s' "\$rest" | sed -n 's/.*pid=\\([0-9]*\\).*/\\1/p')"
  [ -n "\$pid" ] || pid=0
  printf '  TCP    127.0.0.1:%s        0.0.0.0:0              LISTENING       %s\\n' "\$port" "\$pid"
done
SH
chmod +x "$WORK/bin/netstat.exe"

# фальшивый xray: слушает порт из конфига, который ему передали через -c
cat > "$WORK/listen.py" <<'PY'
import json, socket, sys
cfg = open(sys.argv[1], encoding='utf-8').read()
port = json.loads(cfg)['inbounds'][0]['port']
s = socket.socket()
s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', port))
s.listen(8)
print('fake-xray listening %d' % port, flush=True)
while True:
    try:
        c, _ = s.accept(); c.close()
    except OSError:
        break
PY
cat > "$WORK/kit/vpn/xray.exe" <<SH
#!/bin/sh
cfg="\$(printf '%s' "\$2" | tr -d '\"')"
printf '%s\\n' "\$cfg" >> "$WORK/xray-config-used.txt"
exec python3 "$WORK/listen.py" "\$cfg"
SH
chmod +x "$WORK/kit/vpn/xray.exe"

# фальшивый браузер: живёт 3 секунды — сессия должна корректно завершиться
printf '#!/bin/sh\nsleep 3\n' > "$WORK/kit/app/LibreWolf/LibreWolf.exe"
chmod +x "$WORK/kit/app/LibreWolf/LibreWolf.exe"

# конфиг собираем тем же кодом, что и в комплекте
"$PWSH" -NoProfile -Command "
. '$WORK/kit/app/vless-lib.ps1'
\$u = '11111111-1111-1111-1111-111111111111'
\$n = @(ConvertFrom-VlessLink ('vless://' + \$u + '@r.example.com:443?type=tcp&security=reality&pbk=K&sni=r.example.com#r'))
[IO.File]::WriteAllText('$WORK/kit/vpn/config.json', (New-ConfigJson \$n), (New-Object System.Text.UTF8Encoding \$false))
" >/dev/null 2>&1
[ -s "$WORK/kit/vpn/config.json" ] || { echo 'не удалось собрать config.json для теста'; exit 1; }
CFG_MD5="$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)"

export PATH="$WORK/bin:$PATH"
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"

run_start() {
  ( cd "$WORK/kit" && "$PWSH" -NoProfile -ExecutionPolicy Bypass -File "$WORK/kit/app/start.ps1" "$@" 2>&1 )
}

# ------------------------------------------------------------------- сценарий 1
say '1. обычный запуск: случайный порт, конфиг в %TEMP%, уборка после выхода'
OUT="$(run_start)"; RC=$?
[ "$RC" -eq 0 ] || { echo '--- вывод start.ps1 ---'; echo "$OUT" | tail -18; }
PORT_USED="$(sed -n 's/.*SOCKS-порт сессии: \([0-9]*\).*/\1/p' <<<"$OUT" | head -1)"
if [ "$RC" -eq 0 ]; then ok "код возврата 0"; else bad "код возврата $RC"; fi
if [ -n "$PORT_USED" ] && [ "$PORT_USED" != "10808" ]; then
  ok "SOCKS-порт выбран случайно: $PORT_USED"
else
  bad "порт не случайный: '$PORT_USED'"
fi
USED_CFG="$(head -1 "$WORK/xray-config-used.txt" 2>/dev/null)"
case "$USED_CFG" in
  */config.session.json) ok 'xray запущен с сессионным конфигом из %TEMP%' ;;
  *) bad "xray получил не тот конфиг: '$USED_CFG'" ;;
esac
[ -f "$USED_CFG" ] && bad 'сессионный конфиг не удалён после выхода' || ok 'сессионный конфиг удалён из %TEMP%'
if [ "$(md5sum "$WORK/kit/vpn/config.json" | cut -d' ' -f1)" = "$CFG_MD5" ]; then
  ok 'config.json на «флешке» не тронут'
else
  bad 'config.json переписан запуском'
fi
if grep -q "user_pref(\"network.proxy.socks_port\", $PORT_USED)" "$WORK/kit/profile/user.js"; then
  ok 'порт прокси записан в профиль браузера'
else
  bad 'порт прокси не попал в профиль'
fi
if grep -q 'kill-switch активен' <<<"$OUT"; then ok 'watchdog запущен'; else bad 'watchdog не запустился'; fi
if grep -q 'браузер закрыт пользователем' <<<"$OUT"; then ok 'сессия завершилась штатно'; else bad 'нет штатного завершения'; fi
sleep 1
if ss -ltn 2>/dev/null | grep -q ":$PORT_USED "; then bad 'порт остался занят (xray пережил скрипт)'; else ok 'xray остановлен вместе со скриптом'; fi
if grep -q 'старт сессии' "$WORK/kit/vpn/logs/"*.log 2>/dev/null; then
  ok 'лог сессии записан'
else
  bad "лог сессии пуст (файлов в vpn/logs: $(ls "$WORK/kit/vpn/logs/" 2>/dev/null | wc -l))"
fi
if grep -qi '198.51.100.9' "$WORK/kit/vpn/logs/"*.log 2>/dev/null; then
  bad 'в лог попал настоящий IP'
else
  ok 'настоящий IP в лог не попал'
fi

# ------------------------------------------------------------------- сценарий 2
say '2. xray не поднял SOCKS — запуск браузера должен быть отменён'
cat > "$WORK/kit/vpn/xray.exe" <<'SH'
#!/bin/sh
exit 9
SH
chmod +x "$WORK/kit/vpn/xray.exe"
OUT="$(run_start)"; RC=$?
if [ "$RC" -ne 0 ]; then ok "код возврата $RC (ненулевой)"; else bad 'скрипт вернул 0 при мёртвом xray'; fi
if grep -q 'Xray завершился' <<<"$OUT"; then ok 'отказ с понятным сообщением'; else bad 'сообщение об отказе не найдено'; fi
if grep -q 'Браузер запущен' <<<"$OUT"; then bad 'браузер всё-таки запущен'; else ok 'браузер не запускался'; fi
[ -f "$WORK/kit/profile/user.js" ] && rm -f "$WORK/kit/profile/user.js"

# ------------------------------------------------------------------- сценарий 3
say '3. владельца порта определить нельзя — fail-closed'
cat > "$WORK/kit/vpn/xray.exe" <<SH
#!/bin/sh
cfg="\$(printf '%s' "\$2" | tr -d '\"')"
exec python3 "$WORK/listen.py" "\$cfg"
SH
chmod +x "$WORK/kit/vpn/xray.exe"
# netstat-заглушку убираем: Get-NetTCPConnection на Linux нет, значит владелец неизвестен
mkdir -p "$WORK/bin2"
cp "$WORK/bin/curl.exe" "$WORK/bin2/"
OUT="$(PATH="$WORK/bin2:/usr/bin:/bin" run_start)"; RC=$?
if grep -q 'Не удалось определить владельца порта' <<<"$OUT"; then
  ok 'отказ по неизвестному владельцу порта'
else
  bad 'fail-closed не сработал'; echo "$OUT" | tail -5
fi
if [ "$RC" -ne 0 ]; then ok "код возврата $RC"; else bad 'код возврата 0'; fi

# ------------------------------------------------------------------- сценарий 4
say '4. чужой процесс на 10808 не мешает: порт сессии другой'
python3 - <<'PY' &
import socket, time
s = socket.socket(); s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
s.bind(('127.0.0.1', 10808)); s.listen(1); time.sleep(12)
PY
FOREIGN=$!
sleep 1
cat > "$WORK/kit/vpn/xray.exe" <<SH
#!/bin/sh
cfg="\$(printf '%s' "\$2" | tr -d '\"')"
exec python3 "$WORK/listen.py" "\$cfg"
SH
chmod +x "$WORK/kit/vpn/xray.exe"
OUT="$(run_start)"; RC=$?
if [ "$RC" -eq 0 ]; then ok 'запуск не зависит от занятости 10808'; else bad "код возврата $RC"; fi
if ! grep -q 'занят чужим процессом' <<<"$OUT"; then
  ok 'занятость 10808 не влияет: порт сессии выбирается отдельно'
else
  bad 'старт упёрся в фиксированный порт 10808'
fi
kill "$FOREIGN" 2>/dev/null

# ------------------------------------------------------------------- сценарий 5
say '5. лончер LibreWolf.exe: настоящий процесс переживает лончер, сессия не должна закрываться'
# Реальный баг с продакшена: librewolf.exe в корне — лончер, он запускает
# настоящий процесс и сразу завершается. Если следить за PID от Start-Process,
# скрипт решает «браузер закрыт», гасит xray, а браузер открывается позже без VPN.
python3 - "$WORK" <<'PYEOF'
import os, sys
w = sys.argv[1]
core = os.path.join(w, 'kit/app/LibreWolf/core')
os.makedirs(core, exist_ok=True)
real = os.path.join(core, 'lw-real.exe')
with open(real, 'w') as f:
    f.write('#!/bin/sh\nsleep 6\n')
os.chmod(real, 0o755)
launcher = os.path.join(w, 'kit/app/LibreWolf/LibreWolf.exe')
with open(launcher, 'w') as f:
    f.write('#!/bin/sh\n"$(dirname "$0")/core/lw-real.exe" &\nsleep 0.2\nexit 0\n')
os.chmod(launcher, 0o755)
PYEOF
cat > "$WORK/kit/vpn/xray.exe" <<SH
#!/bin/sh
cfg="\$(printf '%s' "\$2" | tr -d '\"')"
exec python3 "$WORK/listen.py" "\$cfg"
SH
chmod +x "$WORK/kit/vpn/xray.exe"
T0="$(date +%s)"
OUT="$(run_start)"; RC=$?
T1="$(date +%s)"
DUR=$((T1 - T0))
if [ "$RC" -eq 0 ]; then ok 'код возврата 0'; else bad "код возврата $RC"; echo "$OUT" | tail -6; fi
if [ "$DUR" -ge 5 ]; then ok "сессия ждала настоящий процесс ($DUR с), а не лончер"; else bad "сессия закрылась через $DUR с — снова следит за лончером"; fi
if grep -q 'браузер закрыт пользователем' <<<"$OUT"; then ok 'штатное завершение после реального закрытия'; else bad 'нет штатного завершения'; fi

say 'итог'
if [ "$FAILED" -eq 0 ]; then echo 'ВСЁ ХОРОШО: все сценарии прошли'; exit 0; fi
echo "ПРОВАЛОВ: $FAILED"; exit 1
