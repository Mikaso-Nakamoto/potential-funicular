# Аудит portable-комплекта (Windows)

Здесь лежит бриф и инструменты для проверки набора «PowerShell + Xray/VLESS + LibreWolf», который запускается с флешки на чужих/недоверенных ПК.

```text
review/netkit/
  AUDIT-BRIEF.md          # что проверяем, по каким блокам, формат отчёта
  inbox/                  # сюда положить скрипты и конфиги (в git не попадают)
  tests/Invoke-LeakCheck.ps1   # проверка утечек IPv4/IPv6/DNS/прокси/листенеров
```

## Быстрый старт

1. Скопировать `*.bat`, `*.ps1`, `*.py`, обезличенные `config.json` и `sub.txt`, `user.js` в `inbox/`.
2. Прогнать проверку утечек на своей машине:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-LeakCheck.ps1
# и отдельно, с остановкой туннеля (только на своей машине):
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Invoke-LeakCheck.ps1 -KillTest
```

3. Отчёт сохраняется рядом: `tests/leak-report.md`.

## Безопасность самих файлов

- `inbox/` и `evidence/` исключены из git: реальные UUID, ссылки на подписку и скриншоты туда можно класть без риска закоммитить.
- Всё равно лучше присылать обезличенные копии: `00000000-0000-0000-0000-000000000000` вместо UUID и `https://example.com/sub/TOKEN` вместо ссылки.
- Скрипт проверки только читает состояние системы. Единственное действие — с флагом `-KillTest` останавливает процесс туннеля, чтобы увидеть, утекает ли трафик.

## Граница

Проверка делается для владельца комплекта и на его ПК. Скрывать активность от владельца машины, обходить EDR/корпоративный контроль и «улучшать» чистку журналов этот аудит не будет — см. §6 в `AUDIT-BRIEF.md`.

## Результат

- Отчёт: `AUDIT-REPORT.md` (F-01…F-19 по первому кругу + F-20…F-32 по второму разбору из 12 пунктов).
- Исправленный комплект собран отдельно от git (код автора в репозиторий не кладём):
  `inbox/dist/LibreWolf-USB-fixed.zip`, 66 647 байт, md5 `69a57d655d0e44251acef989fdd6276d`.
- Копия для скачивания: https://drive.google.com/file/d/1gZ2n2o_XMpg3DPvNw0UmH9BgZmrNICCo/view
- Что проверено статически и что требует живой машины — в §«Чего не проверял» отчёта.
- В комплекте есть `ПРОВЕРКА.bat` → `app/self-check.ps1`: офлайн-прогон конвертера
  и сборки JSON на 6 тестовых ключах (без сети, без Xray) — 46 проверок, включая
  отбрасывание `security=none` и линтер конфига `Test-ConfigSafe`.
- Сквозные прогоны исполнением: `tests/e2e-update-sub.sh` (8 сценариев) и
  `tests/e2e-start.sh` (4 сценария — запуск `start.ps1` с поддельными `xray.exe`,
  `LibreWolf.exe`, `curl.exe`, `netstat.exe`), `tests/bat-lint.py` (5 файлов `.bat`:
  конвейер и спецсимволы в `echo`, наличие `pause`).

## Проверка синтаксиса PowerShell без Windows

`tests/ps-lint.py` разбирает `.ps1` настоящей грамматикой (tree-sitter-powershell)
и дополнительно ловит три класса ошибок, которых парсер не видит: `$var.имя`
внутри двойных кавычек (класс F-15), `ConvertTo-Json` без `-Depth`,
`Invoke-WebRequest` без `-UseBasicParsing`.

```bash
python3 -m venv /tmp/psvenv
/tmp/psvenv/bin/pip install tree_sitter tree-sitter-powershell
/tmp/psvenv/bin/python review/netkit/tests/ps-lint.py review/netkit/inbox/LibreWolf-USB/app/*.ps1
```

На исправленном комплекте — 0 находок; на исходном архиве — те самые 6 мест из F-15.

## Прогон под настоящим PowerShell

`pwsh` 7.7 (Linux x64) в песочницу принёс пользователь: релизы GitHub отдают бинарник
с закрытого хоста. Как только он появился, код проверен исполнением, а не только
чтением:

- штатный парсер PowerShell — 0 ошибок в 7 файлах;
- `app/self-check.ps1` — 36/36 проверок;
- `tests/e2e-update-sub.sh` — 7/7 сценариев (локальный HTTPS + подмена `curl.exe`);
- `tests/Dump-Config.ps1` против `update-sub.py` — структурно идентичный конфиг,
  0 расхождений.

Сам прогон нашёл два дефекта, которые статикой не видны: `Generic.List[object]` + `@()`
роняли `ConvertTo-Nodes` (обновление подписки не работало) и base64-тело подписки
не разбиралось вне `Get-SubBody`. Оба закрыты — см. F-16 и F-17 в отчёте.

## Сборка архива

`tests/build-zip.py` — единственный правильный способ собрать zip для Windows:
`zip` из Linux не ставит флаг «имена в UTF-8», и кириллические `.bat` распаковываются
как `РџРѕРґРіРѕС‚РѕРІРєР°…`. Скрипт проверяет флаг 0x800 у каждого не-ASCII имени
и падает, если его нет (см. F-18).
