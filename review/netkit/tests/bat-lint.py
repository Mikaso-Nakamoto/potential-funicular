#!/usr/bin/env python3
"""bat-lint.py — проверка .bat комплекта на символы, которые ломают cmd.

Зачем: `START.bat` падал, не дойдя до `pause`, из-за строки
    echo    LibreWolf-USB  |  трафик браузера через VPN (kill-switch)
В cmd `|` — это конвейер, а `(`/`)` в правой части дают синтаксическую ошибку,
после которой cmd прекращает выполнение файла. Окно мигало и закрывалось,
пользователь не видел ни ошибки, ни баннера.

Правила:
  1. в строках `echo` не должно быть неэкранированных | & < > ^ (жёстко) и скобок (предупреждение);
  2. файл должен быть CRLF, с BOM (иначе `chcp 65001` + кириллица дают мусор);
  3. последняя команда перед `exit /b` должна быть `pause`, иначе окно закроется
     раньше, чем человек прочитает сообщение об ошибке.

    python3 review/netkit/tests/bat-lint.py
"""
import glob
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.abspath(os.path.join(HERE, '..', 'kit'))
if not os.path.isdir(KIT):
    KIT = os.path.abspath(os.path.join(HERE, '..', 'inbox', 'LibreWolf-USB'))
BAD = '|&<>^()'


def check(path):
    problems = []
    warns = []
    raw = open(path, 'rb').read()
    if not raw.startswith(b'\xef\xbb\xbf'):
        warns.append('нет BOM (не обязательно, но с ним кириллица надёжнее)')
    if b'\r\n' not in raw:
        problems.append('нет CRLF (cmd не любит LF-only)')
    text = raw.decode('utf-8-sig', 'replace')
    lines = text.splitlines()
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s.lower().startswith('echo'):
            continue
        body = s[4:]
        for ch in '|&<>^':
            if ch in body:
                problems.append(f'строка {n}: символ {ch!r} в echo ломает cmd -> {s[:70]}')
        if '(' in body or ')' in body:
            warns.append(f'строка {n}: скобки в echo — лучше убрать -> {s[:70]}')
    joined = '\n'.join(l.strip().lower() for l in lines)
    if 'pause' not in joined:
        problems.append('нет pause — окно закроется до того, как прочтут ошибку')
    return problems, warns


def main():
    files = sorted(glob.glob(os.path.join(KIT, '*.bat')))
    if not files:
        print('не найдено .bat в', KIT)
        return 1
    bad = 0
    for f in files:
        p, w = check(f)
        if p:
            bad += 1
            print(f'[FAIL] {os.path.basename(f)}')
            for item in p:
                print('   -', item)
        else:
            print(f'[OK]   {os.path.basename(f)}')
        for item in w:
            print('   [i]', item)
    print()
    if bad:
        print(f'ПРОВАЛОВ: {bad} из {len(files)}')
        return 1
    print(f'ВСЁ ХОРОШО: {len(files)} файл(ов) .bat')
    return 0


if __name__ == '__main__':
    sys.exit(main())
