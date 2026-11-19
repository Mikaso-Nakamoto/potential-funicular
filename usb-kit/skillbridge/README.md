# skillbridge

MCP stdio-сервер, который делает из реестра скиллов формата skillware три стабильных
инструмента для любой MCP-совместимой модели (Pi подключает его через `config/mcp.json`).

## Зачем именно так

- **Контекст не раздувается.** Модель видит только три инструмента и каталог по запросу
  (`skills_list`); полный контракт подгружается через `skills_info` ровно тогда, когда
  навык выбран. Добавление сотни бандлов не добавляет hundred tools в системный промпт.
- **Типизированный контракт.** `manifest.yaml` описывает `parameters` (JSON Schema) и
  `outputs`; мост валидирует вход (`validate_params`) и нормализует выход в конверт
  `{"status": ...}`.
- **Детерминированное исполнение.** Код бандла (`skill.py`) выполняется здесь, а не
  импровизируется моделью; тяжёлые знания (`kb/`, `data/`) читает код, а не LLM.

## Ручной запуск и отладка

```bash
./venv/bin/skillbridge --root ./skills --selftest   # проверка реестра
SKILLS_ROOT=$PWD/skills ./venv/bin/skillbridge      # режим MCP stdio (использует Pi)
```

## Совместимость

- Работает с `mcp>=1.2,<3` (FastMCP v1 и MCPServer v2 — импорт выбирается сам).
- Skillware опционален: если установлен (`FULL=1 ./tools/bootstrap.sh`), классы на базе
  `BaseSkill` получают родную валидацию; без него действует duck-typing-контракт:
  класс в `skill.py` с методом `execute(params) -> dict`.

## Свой бандл

```
skills/<category>/<name>/
├── manifest.yaml     контракт: parameters/outputs/constitution/env_vars
├── skill.py          класс с execute(params)
├── instructions.md   директива для модели (возвращается в skills_info)
└── card.json         презентация (опционально)
```

Мост перечитывает реестр при каждом вызове — перезапуск Pi после правок не нужен.
