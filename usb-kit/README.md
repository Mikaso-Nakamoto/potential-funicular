# usb-kit — переносной агентный стек на флешке

Самодостаточная сборка: **Pi** (клиент под облачную модель) + **навыки из репозитория** +
**skillbridge** (MCP-мост к скиллам формата skillware). Всё ставится ВНУТРЬ этой папки и
не оставляет обязательных следов в системе: ни реестр, ни домашний каталог не используются.
Пути вычисляются от места запуска, поэтому буква диска / точка монтирования могут быть любыми.

## Быстрый старт (Windows, одна кнопка)

1. Распаковать папку `usb-kit` в **корень флешки** → должно быть `F:\usb-kit\SETUP.bat`.
2. Двойной клик по **`SETUP.bat`**. Он сам скачает Node.js, поставит Pi, соберёт venv с
   мостом, прогонит самотест и предложит сразу запустить агента.
3. Один раз подключить модель: `F:\usb-kit\bin\run-pi.bat auth login anthropic --api-key`.

`SETUP.bat` — только ASCII-обёртка (чтобы не зависеть от кодовой страницы консоли),
весь русский интерфейс и логика лежат в `tools/setup.ps1`, который он вызывает.

## Раскладка

```
usb-kit/
├── SETUP.bat       ← двойной клик на Windows: всё сам (обёртка над tools/setup.ps1)
├── bin/            запускаторы + общее окружение (env.sh)
│   ├── run-pi.sh       Linux/macOS/Git Bash
│   └── run-pi.bat      Windows (cmd)
├── tools/          одноразовая сборка
│   ├── setup.ps1       русский интерфейс установщика + автозапуск bootstrap.ps1
│   ├── bootstrap.sh    POSIX: Node + Pi + venv + мост + синк скиллов
│   ├── bootstrap.ps1   Windows-эквивалент
│   ├── sync-skills.sh  копирование категорий из ../agent-skills в config/skills
│   └── wipe-temp.*     ручная зачистка кэшей (обычно не нужна)
├── config/         ← PI_CODING_AGENT_DIR (аналог ~/.pi/agent)
│   ├── settings.json   предпочтения Pi
│   ├── mcp.json        MCP-серверы (skillbridge включён, ida — заглушка Phase 2)
│   └── skills/         скиллы Pi (заполняется sync-skills)
├── skillbridge/    исходники MCP-моста (ставится в venv при бутстрапе)
├── skills/         реестр скиллов skillware-формата для моста
│   └── netsec/nmap_scan/   показательный бандл (типизированный контракт)
├── node/           портативный Node.js          (создаёт bootstrap)
├── venv/           портативный Python venv      (создаёт bootstrap)
├── npm-global/     префикс npm для pi и серверов(создаёт bootstrap)
├── tmp/            ВСЕ кэши и временные файлы   (создаётся на лету, чистится при выходе)
└── sessions/       журнал сессий Pi             (ваши данные — остаётся)
```

## Сборка (один раз, на своей машине с интернетом)

Linux / macOS / WSL / Git Bash:

```bash
cd usb-kit
./tools/bootstrap.sh            # скачает Node LTS, поставит Pi, соберёт venv с мостом
```

Windows (PowerShell):

```powershell
cd usb-kit
powershell -ExecutionPolicy Bypass -File tools\bootstrap.ps1
```

Бутстрап идемпотентен: повторный запуск обновляет зависимости и пересинкивает скиллы.
Версию Node можно зафиксировать: `NODE_VERSION=v22.21.1 ./tools/bootstrap.sh`.

Что нужно от хоста сборки: Node скачивается сам, а вот **Python 3.10+** должен быть в системе.
`bootstrap.ps1` перебирает интерпретаторы в порядке `py -3.12` → `py -3.13` → `py -3` → `python`
и печатает выбранную версию; свой вариант задаётся переменной `PYTHON` (`PYTHON_BIN` на Linux).
Если pip падает на сборке колёс (pydantic/Rust) — Python слишком свежий:
`winget install -e --id Python.Python.3.12`, удалить папку `venv/` и повторить.

## Подключение облачной модели

Ключи, а не браузерный OAuth — они переносимы файлом:

```bash
./bin/run-pi.sh auth login anthropic --api-key   # или openai/google/openrouter...
```

После первого входа `config/auth.json` лежит на флешке. Для фиксации модели по умолчанию
добавьте в `config/settings.json`:

```json
{ "defaultProvider": "anthropic", "defaultModel": "claude-sonnet-5-0" }
```

## Запуск где угодно

```bash
<любой путь>/usb-kit/bin/run-pi.sh        # интерактивный TUI
<любой путь>/usb-kit/bin/run-pi.sh -p "..."  # print-режим для автоматизации
```

При старте экспортятся: `PI_STICK_ROOT`, `PI_CODING_AGENT_DIR`, `PI_CODING_AGENT_SESSION_DIR`,
`NPM_CONFIG_PREFIX/CACHE`, `TMPDIR/TEMP/TMP`, `XDG_*` — все внутрь флешки.
При выходе `tmp/` уничтожается автоматически (trap в run-pi.sh).

## Навыки: два слоя

1. **Маркдаун-скиллы Pi** (`config/skills/`) — инструкции; Pi показывает модели только
   имя+описание, полный текст грузится по совпадению задачи. Синкаются из `agent-skills/`
   скриптом (категории задаются аргументами; по умолчанию network-security + security-crypto + crypto-engineering).
2. **Типизированные бандлы skillware** (`skills/`) — через MCP-мост `skillbridge`:
   модель видит три инструмента (`skills_list`, `skills_info`, `skills_invoke`) и работает
   со строгими контрактами ввода-вывода; детерминированный код исполняется в Python,
   тяжёлые знания (kb/, data/) в контекст не попадают. См. `skillbridge/README.md`.

Добавить свой бандл = положить папку с `manifest.yaml` + `skill.py` в `skills/<category>/<name>/`.
Ничего перезапускать не надо: мост читает реестр при каждом вызове.

## IDA Pro 9.5 и Awesome-REA — Phase 2

В `config/mcp.json` есть выключенная запись `ida` под будущий мост к IDA (idalib/MCP),
а материалы Awesome-REA уже лежат в корне репозитория. Когда дойдём руки: отдельный
мост `idabridge` тем же шаблоном, что skillbridge, плюс конвертация RE-навыков в бандлы.

## Гигиена следов

Гарантируется на уровне приложений: всё пишется только сюда, `tmp/` сносится на выходе,
браузерные профили не трогаются. Форензик-чистота на чужой ОС недостижима без своей
загрузочной среды (Prefetch/журналы NTFS/pagefile) — если она нужна, используйте Tails
на отдельном носителе. Дополнительно рекомендуется:

- весь носитель — в контейнер VeraCrypt/LUKS (внутри теперь ключи модели и токены);
- трафик Pi и мостов — через ваш VPN-туннель (иначе провайдер модели видит реальный IP);
- `config/auth.json` и секреты — права 600, в git НЕ коммитятся (см. .gitignore).
