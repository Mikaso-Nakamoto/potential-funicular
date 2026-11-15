#!/usr/bin/env python3
"""build-zip.py — сборка архива комплекта с корректными кириллическими именами.

Зачем свой сборщик вместо `zip`: Info-ZIP в локали без UTF-8 кладёт имена как
«сырые байты» и НЕ ставит general-purpose bit 11 (UTF-8). Windows Explorer тогда
читает кириллицу как CP1251 и показывает «РџРѕРґРіРѕС‚РѕРІРєР°-Р”РћРњРђ.bat».
Python zipfile кодирует имена в UTF-8 и выставляет флаг сам — но мы это ещё и
проверяем, чтобы баг не вернулся.

    python3 review/netkit/tests/build-zip.py

Печатает список записей и флагов, падает, если у имени с не-ASCII нет бита 0x800.
"""

import os
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
KIT = os.path.join(HERE, '..', 'inbox', 'LibreWolf-USB')
OUT = os.path.join(HERE, '..', 'inbox', 'dist', 'LibreWolf-USB-fixed.zip')

SKIP_DIRS = {'__pycache__'}
SKIP_FILES = {'.DS_Store', 'Thumbs.db'}


def main():
    kit = os.path.abspath(KIT)
    out = os.path.abspath(OUT)
    if not os.path.isdir(kit):
        print('нет каталога комплекта: %s' % kit, file=sys.stderr)
        return 2
    os.makedirs(os.path.dirname(out), exist_ok=True)

    entries = []
    for root, dirs, files in os.walk(kit):
        dirs[:] = sorted(d for d in dirs if d not in SKIP_DIRS and not d.startswith('.'))
        rel_root = os.path.relpath(root, kit)
        if rel_root != '.':
            entries.append((rel_root.replace(os.sep, '/') + '/', None))
        for name in sorted(files):
            if name in SKIP_FILES or name.startswith('.'):
                continue
            full = os.path.join(root, name)
            arc = os.path.relpath(full, kit).replace(os.sep, '/')
            entries.append((arc, full))

    with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arc, full in entries:
            if full is None:
                info = zipfile.ZipInfo(arc)
                info.external_attr = (0o40755 << 16) | 0x10
                z.writestr(info, b'')
            else:
                info = zipfile.ZipInfo(arc, date_time=_mtime(full))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o100644 << 16
                with open(full, 'rb') as fh:
                    z.writestr(info, fh.read())

    bad = []
    with zipfile.ZipFile(out) as z:
        print('%-40s %-8s %s' % ('запись', 'размер', 'UTF-8 флаг'))
        for info in z.infolist():
            flag = 'да' if (info.flag_bits & 0x800) else ('— (ASCII)' if info.filename.isascii() else 'НЕТ')
            print('%-40s %-8d %s' % (info.filename, info.file_size, flag))
            if not info.filename.isascii() and not (info.flag_bits & 0x800):
                bad.append(info.filename)
        names = [i.filename for i in z.infolist()]
        if len(names) != len(set(names)):
            print('дубликаты имён в архиве!', file=sys.stderr)
            return 1

    print('\nфайл: %s (%d байт, записей: %d)' % (out, os.path.getsize(out), len(entries)))
    if bad:
        print('имена без UTF-8 флага: %s' % bad, file=sys.stderr)
        return 1
    print('проверка UTF-8 флага: OK')
    return 0


def _mtime(path):
    import time
    t = time.localtime(os.path.getmtime(path))
    return (t.tm_year, t.tm_mon, t.tm_mday, t.tm_hour, t.tm_min, t.tm_sec)


if __name__ == '__main__':
    sys.exit(main())
