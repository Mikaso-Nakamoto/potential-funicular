#!/usr/bin/env python3
"""Статическая проверка PowerShell-скриптов набора LibreWolf-USB.

Зачем: на Linux нет ни Windows PowerShell 5.1, ни pwsh (в песочнице, где шёл аудит,
ассеты GitHub недоступны), поэтому «просто запустить» нельзя. Этот линтер закрывает
ту часть, которую можно проверить без исполнения:

  1. синтаксис — настоящая грамматика PowerShell (tree-sitter), а не счётчик скобок;
  2. известные грамматике-дыры (`--tlsv1.2`, числовые суффиксы `1MB`) отсеиваются,
     чтобы не выдавать ложных срабатываний;
  3. правило STR-01: внутри двойных кавычек `$var.имя` — это доступ к свойству,
     а не «переменная и точка». `"$Cfg.bak.json"` даёт пустую строку + ".json",
     то есть файл с именем `.json`. Именно этот баг был найден в наборе (F-15);
  4. правило JSON-01: `ConvertTo-Json` без `-Depth` в PS 5.1 обрезает вложенность
     на втором уровне — конфиг Xray при этом становится нерабочим, но валидным JSON;
  5. правило IWR-01: `Invoke-WebRequest` без `-UseBasicParsing` падает на PS 5.1,
     если в системе не настроен IE.

Установка (нужен только для этой проверки):

    python3 -m venv /tmp/psvenv
    /tmp/psvenv/bin/pip install tree_sitter tree-sitter-powershell

Запуск:

    /tmp/psvenv/bin/python review/netkit/tests/ps-lint.py inbox/LibreWolf-USB/app/*.ps1

Код возврата: 0 — чисто, 1 — есть настоящие находки, 2 — нет зависимости.
"""

import re
import sys

try:
    import tree_sitter
    import tree_sitter_powershell
    from tree_sitter import Language, Parser
except ImportError:
    print("нужен tree_sitter + tree-sitter-powershell (см. docstring)", file=sys.stderr)
    sys.exit(2)

LANG = Language(tree_sitter_powershell.language())
PARSER = Parser(LANG)

# дыры грамматики tree-sitter-powershell, а не ошибки в коде
GRAMMAR_GAPS = [
    # `--tlsv1.2` парсится как bareword + число, грамматика вставляет пустой `>`
    re.compile(r"^--\w*v?\d+\.\d"),
    # числовые суффиксы PS: 1MB, 512KB — в грамматике не поддержаны
    re.compile(r"^\d+(KB|MB|GB|TB|PB)$"),
]


def walk(node):
    yield node
    for child in node.children:
        yield from walk(child)


def is_grammar_gap(src: bytes, node) -> bool:
    if node.is_missing and node.type in (">", "<", ">>"):
        line_start = src.rfind(b"\n", 0, node.start_byte) + 1
        line = src[line_start:src.find(b"\n", node.end_byte) if src.find(b"\n", node.end_byte) != -1 else len(src)]
        return b"tlsv1." in line or b"tls1." in line
    if node.type == "ERROR":
        text = src[node.start_byte:node.end_byte].decode("utf-8", "replace")
        # `1MB`: грамматика видит только хвост "MB", цифра остаётся в предыдущем токене
        if text in ("KB", "MB", "GB", "TB", "PB") and node.start_byte > 0 and chr(src[node.start_byte - 1]).isdigit():
            return True
        return any(g.match(text) for g in GRAMMAR_GAPS)
    return False


def check_syntax(path, src):
    tree = PARSER.parse(src)
    problems = []
    for node in walk(tree.root_node):
        if node.type != "ERROR" and not node.is_missing:
            continue
        if is_grammar_gap(src, node):
            continue
        line, col = node.start_point[0] + 1, node.start_point[1] + 1
        text = src[node.start_byte:node.end_byte][:60].decode("utf-8", "replace")
        problems.append((line, col, "SYNTAX", f"{node.type}: {text!r}"))
    return tree, problems


def check_string_interpolation(tree, src):
    """STR-01: `$var.имя` внутри двойных кавычек = доступ к свойству."""
    problems = []
    for node in walk(tree.root_node):
        if node.type != "expandable_string_literal":
            continue
        # только прямые дети: `$($x.Prop)` — законный доступ к свойству внутри подвыражения
        for sub in node.children:
            if sub.type != "variable":
                continue
            tail = src[sub.end_byte:sub.end_byte + 32].decode("utf-8", "replace")
            m = re.match(r"\.([A-Za-z_][A-Za-z0-9_]*)", tail)
            if m:
                line = sub.start_point[0] + 1
                problems.append((line, sub.start_point[1] + 1, "STR-01",
                                 f'"$...{tail[:len(m.group(0)) + 6]}" — .{m.group(1)} ищется как свойство; нужна конкатенация'))
    return problems


def check_text_rules(path, text):
    problems = []
    for n, line in enumerate(text.splitlines(), 1):
        code = line.split("#", 1)[0]  # комментарии не считаем
        if "ConvertTo-Json" in code and "-Depth" not in code:
            problems.append((n, 1, "JSON-01", "ConvertTo-Json без -Depth: в PS 5.1 вложенность обрежется"))
        if "Invoke-WebRequest" in code and "-UseBasicParsing" not in code:
            problems.append((n, 1, "IWR-01", "Invoke-WebRequest без -UseBasicParsing: на PS 5.1 упадёт без IE"))
    return problems


def main(paths):
    real = 0
    for path in paths:
        src = open(path, "rb").read()
        text = src.decode("utf-8-sig", "replace")
        tree, problems = check_syntax(path, src)
        problems += check_string_interpolation(tree, src)
        problems += check_text_rules(path, text)
        if problems:
            real += len(problems)
            print(f"### {path}")
            for line, col, code, msg in sorted(problems):
                print(f"  {line}:{col}  {code}  {msg}")
        else:
            print(f"ok  {path}")
    print(f"\nвсего находок: {real}")
    return 1 if real else 0


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))
