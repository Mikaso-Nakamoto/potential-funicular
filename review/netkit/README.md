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

- Отчёт: `AUDIT-REPORT.md` (14 находок + F-15, найденная при исправлении; в начале — таблица статуса).
- Исправленный комплект собран отдельно от git (код автора в репозиторий не кладём):
  `inbox/dist/LibreWolf-USB-fixed.zip`, md5 `cd598869f2875642385704559d9bd5dd`.
- Копия для скачивания: https://drive.google.com/file/d/182MKc8bINdMAG5gBcpQG5VIv2Nm7iRUL/view
- Что проверено статически и что требует живой машины — в §«Чего не проверял» отчёта.
- В комплекте есть `ПРОВЕРКА.bat` → `app/self-check.ps1`: офлайн-прогон конвертера
  и сборки JSON на 6 тестовых ключах (без сети, без Xray) — эту часть выполняет сам пользователь на Windows.

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
